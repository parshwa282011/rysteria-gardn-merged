#!/usr/bin/env bash
# Debian / Ubuntu / Raspberry Pi OS: builds every server and client into builds/.
# The work is done by scripts/common/build.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/build.sh" "$@"
