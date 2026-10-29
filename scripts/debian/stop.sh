#!/usr/bin/env bash
# Debian / Ubuntu / Raspberry Pi OS: stops what run started.
# The work is done by scripts/common/stop.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/stop.sh" "$@"
