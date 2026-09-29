/* ulanzi-au05-keepalive: keep both HID interfaces of the Ulanzi Vibe Key AU05
 * (fff1:00dd) open. With no process holding one of them the firmware reboots
 * its USB transceiver after ~4 s of host idle, so the input event node churns
 * through new numbers and the USB microphone keeps dropping out. The mic key
 * emits F9, which voxtype listens for, so this also keeps dictation reliable.
 *
 * Read-only: it never writes to the device and never grabs the input event
 * devices, so keys and the rotary wheel keep reaching the focused application
 * unchanged. The technique (and the idle-reboot diagnosis) comes from
 * kubja/ulanzi-vibekey; see docs/ulanzi-au05.md.
 *
 * Run it as a user service; the udev rule grants it uaccess on the hidraw
 * nodes.
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* HID_ID reads "0003:0000FFF1:000000DD" and HID_PHYS ends in "/input2" or
 * "/input3". Match the vendor:product pair, not the serial, so any AU05 works.
 * strcasestr makes the comparison case-insensitive. */
#define HIDRAW_DIR "/sys/class/hidraw"
#define AU05_ID "0000fff1:000000dd"

#define REOPEN_DELAY_S 1

/* Open the hidraw node whose parent interface is `suffix` ("/input2" or
 * "/input3"), or -1 when the device is not present. */
static int open_au05_interface(const char *suffix) {
  DIR *dir = opendir(HIDRAW_DIR);
  if (dir == NULL) {
    return -1;
  }

  int fd = -1;
  struct dirent *entry;
  while (fd < 0 && (entry = readdir(dir)) != NULL) {
    if (strncmp(entry->d_name, "hidraw", 6) != 0) {
      continue;
    }

    char path[512];
    snprintf(path, sizeof path, HIDRAW_DIR "/%s/device/uevent", entry->d_name);

    FILE *uevent = fopen(path, "r");
    if (uevent == NULL) {
      continue;
    }
    char text[1024];
    size_t len = fread(text, 1, sizeof text - 1, uevent);
    text[len] = '\0';
    fclose(uevent);

    if (strcasestr(text, AU05_ID) == NULL || strcasestr(text, suffix) == NULL) {
      continue;
    }

    char node[512];
    snprintf(node, sizeof node, "/dev/%s", entry->d_name);
    fd = open(node, O_RDONLY | O_NONBLOCK);
  }

  closedir(dir);
  return fd;
}

/* Read whatever is pending. Returns 1 while both interfaces are alive, 0 once
 * one of them signals EOF or an error (unplugged or re-enumerated). */
static int drain(int fd_input, int fd_vendor) {
  struct pollfd fds[2] = {
    { .fd = fd_input, .events = POLLIN },
    { .fd = fd_vendor, .events = POLLIN },
  };

  if (poll(fds, 2, -1) < 0) {
    return 0;
  }

  for (int i = 0; i < 2; i++) {
    if ((fds[i].revents & (POLLIN | POLLHUP | POLLERR)) == 0) {
      continue;
    }
    char discard[256];
    if (read(fds[i].fd, discard, sizeof discard) <= 0) {
      return 0;
    }
  }
  return 1;
}

int main(void) {
  for (;;) {
    int fd_input = open_au05_interface("/input2");
    int fd_vendor = open_au05_interface("/input3");

    if (fd_input >= 0 && fd_vendor >= 0) {
      while (drain(fd_input, fd_vendor)) {
      }
      close(fd_input);
      close(fd_vendor);
    } else {
      if (fd_input >= 0) {
        close(fd_input);
      }
      if (fd_vendor >= 0) {
        close(fd_vendor);
      }
    }

    sleep(REOPEN_DELAY_S);
  }
}
