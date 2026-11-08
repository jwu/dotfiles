#!/bin/bash
# Rebind applespi so its protocol state machine starts over. A resume can leave
# it reading the multitouch-init reply as touchpad data, after which every
# packet fails the length check and the touchpad goes dead. Root only; installed
# as /usr/local/bin/applespi-reset. See docs/suspend.md.
set -euo pipefail

driver=/sys/bus/spi/drivers/applespi
device=spi-APP000D:00

# No applespi on non-Apple machines.
if [ ! -e "$driver/$device" ]; then
  exit 0
fi

printf '%s\n' "$device" > "$driver/unbind"
sleep 1
printf '%s\n' "$device" > "$driver/bind"
