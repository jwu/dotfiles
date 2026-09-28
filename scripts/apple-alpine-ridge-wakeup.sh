#!/bin/bash
# Cut the S3 wakeup sources that make 2016-2017 T1 MacBook Pros leave deep sleep
# every ~45s and eventually hang on resume. Runs as root from a oneshot at boot,
# because /proc/acpi/wakeup resets every boot. See docs/suspend.md.
set -eu

# Alpine Ridge Thunderbolt root ports and their xHCI controllers, plus the
# Wi-Fi PME. LID0 and SPIT are deliberately absent: they are what lets the lid
# and the keyboard wake the machine.
for dev in RP05 RP09 XHC2 XHC3 RP12; do
  if grep -Eq "^${dev}[[:space:]].*enabled" /proc/acpi/wakeup; then
    printf '%s\n' "$dev" > /proc/acpi/wakeup
  fi
done

# Same sources from the PCI side, so the setting applies without a reboot and
# without replaying every udev add rule on the bus.
for pci in /sys/bus/pci/devices/*; do
  [ -r "$pci/vendor" ] && [ -r "$pci/device" ] || continue
  [ "$(cat "$pci/vendor")" = 0x8086 ] || continue
  case "$(cat "$pci/device")" in
    0x15d2 | 0x15d4) printf 'disabled\n' > "$pci/power/wakeup" 2> /dev/null || true ;;
  esac
done

# Apple's NVMe controller is one of the devices that fails to come back on
# resume; the Omarchy fix for the same models sets this too.
nvme_d3cold=/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
if [ -w "$nvme_d3cold" ]; then
  printf '0\n' > "$nvme_d3cold"
fi
