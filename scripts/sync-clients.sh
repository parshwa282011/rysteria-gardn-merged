#!/usr/bin/env bash
# Copies the built web clients (the rrolf client and the whole gardn folder) from one
# machine to another, for a machine that cannot build them. The Raspberry Pi has no
# emscripten, so its build.sh runs with --skip-clients and would serve an old client
# and an old gardn the day it takes over the tunnel. Run this on your own computer
# after building on the machine that has emscripten:
#
#   scripts/sync-clients.sh c1 asdf [ssh-key]
#
# The names are the ones in secrets/nodes.conf (name os lan ssh repo). The clients are
# WebAssembly, so they run on any machine; node_modules and .env of gardn stay where
# they are. Restart gardn afterwards (stop.sh / run.sh on the target, or kill its
# gardn process and run run.sh) because gardn reads its files when it starts.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
from="${1:?usage: sync-clients.sh <from node> <to node> [ssh-key]}"
to="${2:?usage: sync-clients.sh <from node> <to node> [ssh-key]}"
key="${3:-}"
nodes="$here/secrets/nodes.conf"
[ -f "$nodes" ] || nodes="$here/dual-server-syncing/nodes.conf"

node_field() { # <node> <column 1-5>
    awk -v n="$1" -v c="$2" '$1 !~ /^#/ && $1 == n { print $c; exit }' "$nodes"
}
ssh_opts=(-o BatchMode=yes)
[ -n "$key" ] && ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)

src_ssh="$(node_field "$from" 4)"; src_repo="$(node_field "$from" 5)"
dst_ssh="$(node_field "$to" 4)"; dst_repo="$(node_field "$to" 5)"
for v in "$src_ssh" "$src_repo" "$dst_ssh" "$dst_repo"; do
    [ -n "$v" ] && [ "$v" != "-" ] || { echo "error: $from or $to is not in $nodes with an ssh target and a repo folder" >&2; exit 1; }
done

# builds/<os>-<arch> differs between machines
remote_build() { ssh "${ssh_opts[@]}" "$1" "ls -d $2/builds/*/rrolf-client 2>/dev/null | head -1 | xargs dirname"; }
src_build="$(remote_build "$src_ssh" "$src_repo")"
dst_build="$(remote_build "$dst_ssh" "$dst_repo")"
[ -n "$src_build" ] || { echo "error: nothing built on $from" >&2; exit 1; }
[ -n "$dst_build" ] || { echo "error: $to has no builds/ folder yet: build there first" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
rsh="ssh ${ssh_opts[*]}"
echo "==> $from:$src_build -> $to:$dst_build"
rsync -a -e "$rsh" "$src_ssh:$src_build/rrolf-client/" "$tmp/rrolf-client/"
rsync -a -e "$rsh" --exclude node_modules --exclude .env --exclude package.json --exclude package-lock.json \
    "$src_ssh:$src_build/gardn/" "$tmp/gardn/"
rsync -a -e "$rsh" "$tmp/rrolf-client/" "$dst_ssh:$dst_build/rrolf-client/"
rsync -a -e "$rsh" "$tmp/gardn/" "$dst_ssh:$dst_build/gardn/"
echo "==> done. Restart gardn on $to so that it loads the new files."
