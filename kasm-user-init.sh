#!/usr/bin/env bash
set -euo pipefail

# Apply OS-account settings as root, then run the unchanged Kasm startup chain
# as the regular desktop user. KASM_USER_PASSWORD is supplied by Compose from
# the ignored .env file and is never written to logs.
/usr/sbin/usermod -aG sudo kasm-user
if [ -z "${KASM_USER_PASSWORD:-}" ]; then
  echo "KASM_USER_PASSWORD must be set in .env" >&2
  exit 1
fi
printf 'kasm-user:%s\n' "$KASM_USER_PASSWORD" | /usr/sbin/chpasswd
unset KASM_USER_PASSWORD

exec /usr/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
  /dockerstartup/kasm_default_profile.sh \
  /dockerstartup/vnc_startup.sh \
  /dockerstartup/kasm_startup.sh "$@"
