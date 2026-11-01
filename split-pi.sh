#!/usr/bin/env bash
# Split mode, the other machine (the Pi, line 2 of secrets/nodes.conf): it runs rrolf-hc
# (hell creek) and rrolf-pvp, which connect to the master of the main machine over the LAN,
# and syncd in clone mode, which keeps its PostgreSQL a copy of the master's database. No
# master, no tunnel, and it never takes over by itself: the tunnel of the main machine
# sends the players to it (see ./split-mac.sh).
#
# Run from your own computer; it works on the machines over ssh (--local: on this machine).
# Order the first time: ./split-pi.sh, then ./split-mac.sh. Back to normal:
# ./split-pi.sh --off, then ./split-mac.sh --off.
#
# Usage: ./split-pi.sh [--off | --status | --tunnel-check] [--dry-run] [--no-apply]
#                      [--no-start] [--remote a,b] [--node NAME] [--key FILE] [--local]
#                      [--allow-old]
#   (default)       switch to split mode: stop the servers there, write the settings, build, start
#   --off           back to the normal full stack (a backup with its own master) on this machine
#   --status        what runs here, whether the master answers, the last lines of the database copy
#   --tunnel-check  read-only look at cloudflared there: credentials, clock, network, connectors
#   --remote a,b    the servers this machine runs (default rrolf-hc,rrolf-pvp)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/common/split-launch.sh"
split_launch pi "${BASH_SOURCE[0]}" "$@"
