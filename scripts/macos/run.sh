#!/usr/bin/env bash
# macOS: starts everything that was built (and cloudflared if enabled).
# The work is done by scripts/common/run.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/run.sh" "$@"
