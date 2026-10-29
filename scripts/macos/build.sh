#!/usr/bin/env bash
# macOS: builds every server and client into builds/.
# The work is done by scripts/common/build.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/build.sh" "$@"
