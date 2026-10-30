#!/usr/bin/env bash
# Debian / Ubuntu / Raspberry Pi OS: backup / failover between machines (init | status | promote).
# The work is done by scripts/common/sync.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/sync.sh" "$@"
