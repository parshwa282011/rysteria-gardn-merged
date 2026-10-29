#!/usr/bin/env bash
# Debian / Ubuntu / Raspberry Pi OS: the whole thing in one go: setup, build, run.
# Usage: scripts/debian/up.sh [--dry-run] [--skip-clients]
# (setup is skipped on later runs with --no-setup)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -euo pipefail
args=()
setup=1
for a in "$@"; do
    case "$a" in
    --no-setup) setup=0 ;;
    *) args+=("$a") ;;
    esac
done
dry=()
for a in ${args[@]+"${args[@]}"}; do [ "$a" = --dry-run ] && dry=(--dry-run); done
[ "$setup" = 0 ] || "$here/setup.sh" ${dry[@]+"${dry[@]}"}
"$here/build.sh" ${args[@]+"${args[@]}"}
"$here/run.sh" ${dry[@]+"${dry[@]}"}
