#!/usr/bin/env bash
# Split mode, the main machine (c1, line 1 of secrets/nodes.conf): it keeps the master, the
# PostgreSQL database, gardn, the web edge, rrolf-garden and rrolf-minigames and the whole
# cloudflared tunnel. Hell creek (rrolf-hc) and pvp (rrolf-pvp) move to the other machine
# (the Pi): their ports here become forwarders to it, so the tunnel's routes do not change.
# The other machine keeps a copy of the database (syncd in clone mode).
#
# Run from your own computer; it works on the machines over ssh (--local: on this machine).
# Order the first time: ./split-pi.sh, then ./split-mac.sh (this starts the Pi's servers
# too). Back to normal: ./split-pi.sh --off, then ./split-mac.sh --off.
#
# Usage: ./split-mac.sh [--off | --status | --tunnel-check] [--dry-run] [--no-apply]
#                       [--no-start] [--no-start-pi] [--remote a,b] [--node NAME]
#                       [--key FILE] [--local] [--allow-old]
#   (default)       switch to split mode: stop the servers there, write the settings, build, start
#   --off           back to the full stack on this machine
#   --status        what runs where, and whether the other machine answers
#   --tunnel-check  read-only look at cloudflared there: credentials, clock, network, connectors
#   --dry-run       print what would be done there    --no-apply  only write the settings
#   --remote a,b    the servers that go to the other machine (default rrolf-hc,rrolf-pvp)
#   --allow-old     use the machines even if they are not at this computer's commit
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/common/split-launch.sh"
split_launch mac "${BASH_SOURCE[0]}" "$@"
