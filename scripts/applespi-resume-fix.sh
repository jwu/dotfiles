#!/bin/bash
# Install the applespi resume hook, so the Apple SPI touchpad does not stay dead
# until the next reboot. Root only, idempotent: bootstrap/arch.sh calls it during
# provisioning, and it can be re-run on a provisioned machine. See docs/suspend.md.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "    this installer writes /usr/local/bin and /usr/lib/systemd; run it with sudo" >&2
  exit 1
fi

# applespi drives the Apple SPI keyboard and touchpad only; elsewhere there is
# nothing to install.
if [ ! -d /sys/bus/spi/drivers/applespi ]; then
  echo "    applespi is not loaded; nothing to do"
  exit 0
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -m 0755 "$here/applespi-reset.sh" /usr/local/bin/applespi-reset

# systemd-sleep runs this after resume. The delay lets niri and the locker take
# input first: a rebind removes the built-in keyboard for a moment, and losing
# keystrokes on a password prompt is worse than losing the touchpad for two
# seconds.
cat > /usr/lib/systemd/system-sleep/applespi-reset << 'EOF'
#!/bin/bash
# Post-resume hook; see /usr/local/bin/applespi-reset and docs/suspend.md.
case "$1" in
  post) sleep 2; /usr/local/bin/applespi-reset ;;
esac
exit 0
EOF
chmod 0755 /usr/lib/systemd/system-sleep/applespi-reset

echo "    applespi resume hook installed"
