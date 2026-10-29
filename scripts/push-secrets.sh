#!/usr/bin/env bash
# Sends secrets/*.env straight into ~/.rysteria-secrets/ on a server (dir 700, files 600).
# Usage: scripts/push-secrets.sh user@host [ssh-key]
set -euo pipefail
target="${1:?usage: push-secrets.sh user@host [ssh-key]}"
key="${2:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ssh_opts=(-o BatchMode=yes)
[ -n "$key" ] && ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)
ssh "${ssh_opts[@]}" "$target" 'umask 077; mkdir -p ~/.rysteria-secrets; chmod 700 ~/.rysteria-secrets'
scp "${ssh_opts[@]}" "$here"/secrets/*.env "$target":.rysteria-secrets/
ssh "${ssh_opts[@]}" "$target" 'chmod 600 ~/.rysteria-secrets/*.env; ls -l ~/.rysteria-secrets'
