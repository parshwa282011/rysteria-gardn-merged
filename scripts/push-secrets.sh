#!/usr/bin/env bash
# Sends secrets/*.env (and *.p8) straight into ~/.rysteria-secrets/ on a server (dir 700, files 600).
# Usage: scripts/push-secrets.sh user@host [ssh-key]
set -euo pipefail
target="${1:?usage: push-secrets.sh user@host [ssh-key] [port]}"
key="${2:-}"
port="${3:-}"
scp_port=()
[ -n "$port" ] && scp_port=(-P "$port")
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ssh_opts=(-o BatchMode=yes)
[ -n "$key" ] && ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)
ssh_port=()
[ -n "$port" ] && ssh_port=(-p "$port")
ssh "${ssh_opts[@]}" ${ssh_port[@]+"${ssh_port[@]}"} "$target" 'umask 077; mkdir -p ~/.rysteria-secrets; chmod 700 ~/.rysteria-secrets'
# the .env files, and the Apple key (*.p8, apple-domain.txt) when there is one
files=("$here"/secrets/*.env)
for f in "$here"/secrets/*.p8 "$here"/secrets/apple-domain.txt; do [ -f "$f" ] && files+=("$f"); done
scp "${ssh_opts[@]}" ${scp_port[@]+"${scp_port[@]}"} "${files[@]}" "$target":.rysteria-secrets/
ssh "${ssh_opts[@]}" ${ssh_port[@]+"${ssh_port[@]}"} "$target" 'chmod 600 ~/.rysteria-secrets/*; ls -l ~/.rysteria-secrets'
