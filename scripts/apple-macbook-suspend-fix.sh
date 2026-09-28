#!/bin/bash
# Install the Alpine Ridge S3 resume fix on 2016-2017 T1 MacBook Pros. Stops the
# resume hang, not the ~45s hardware wakeup. Root only, idempotent: bootstrap/arch.sh
# calls it during provisioning, and it can be re-run on a provisioned machine.
# See docs/suspend.md.
set -euo pipefail

product="$(cat /sys/class/dmi/id/product_name 2> /dev/null || true)"
case "$product" in
  MacBookPro13,1 | MacBookPro13,2 | MacBookPro13,3 | \
  MacBookPro14,1 | MacBookPro14,2 | MacBookPro14,3) ;;
  *)
    echo "    $product has no Alpine Ridge wakeup problem; nothing to do"
    exit 0
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "    this installer writes /etc and /boot/grub; run it with sudo" >&2
  exit 1
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -m 0755 "$here/apple-alpine-ridge-wakeup.sh" /usr/local/bin/apple-alpine-ridge-wakeup

# Waking the machine from S3 through PCI is a hotplug-shaped event, so the udev
# rule covers cards that appear after boot. The helper covers the ones already
# there.
cat > /etc/udev/rules.d/99-apple-alpine-ridge-wakeup.rules << 'EOF'
# Alpine Ridge NHI (8086:15d2) and xHCI (8086:15d4) must not wake S3: they emit
# PME every ~45s and pull the machine out of deep sleep with the lid still shut.
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d2", ATTR{power/wakeup}="disabled"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d4", ATTR{power/wakeup}="disabled"
EOF

cat > /etc/systemd/system/apple-alpine-ridge-wakeup.service << 'EOF'
[Unit]
Description=Disable Alpine Ridge wakeup sources from S3 (T1 MacBook Pro)
After=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/apple-alpine-ridge-wakeup

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now apple-alpine-ridge-wakeup.service
udevadm control --reload-rules

# Alpine Ridge ports never return from D3: each one costs its own ~1s timeout on
# resume. This is the one part that needs a reboot.
if ! grep -qE '(^| )pcie_port_pm=off( |$)' /proc/cmdline; then
  if [ ! -f /etc/default/grub ]; then
    echo "    /etc/default/grub is missing; add pcie_port_pm=off to the kernel cmdline by hand" >&2
  else
    grep -q 'pcie_port_pm=off' /etc/default/grub ||
      sed -i 's|^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"|\1 pcie_port_pm=off"|' /etc/default/grub
    if grep -q 'pcie_port_pm=off' /etc/default/grub; then
      grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
      echo "    pcie_port_pm=off is in the GRUB cmdline; reboot to pick it up"
    else
      echo "    GRUB_CMDLINE_LINUX_DEFAULT is not set in /etc/default/grub; add pcie_port_pm=off by hand" >&2
    fi
  fi
fi

echo "    wakeup:$(awk '/^(RP01|RP05|RP09|RP12|XHC1|XHC2|XHC3|ARPT|SPIT|LID0)[[:space:]]/ { printf " %s=%s", $1, $3 }' /proc/acpi/wakeup)"
