#!/bin/sh
# Pin the one setting the subscription must not be allowed to change: the
# managed browser flags point at 7890, and mihomo has no command-line flag for
# mixed-port while config.yaml is replaced wholesale on every manual
# subscription refresh.
#
# Installed as /usr/local/bin/mihomo-overlay and run from ExecStartPre with a
# "+" prefix so it runs as root: the service itself is User=mihomo and cannot
# write its own root-owned config. See docs/design.md, the mihomo section.
set -eu

config=/etc/mihomo/config.yaml
[ -f "$config" ] || exit 0

if ! grep -qx 'mixed-port: 7890' "$config"; then
  sed -i 's/^mixed-port:.*/mixed-port: 7890/' "$config"
fi
