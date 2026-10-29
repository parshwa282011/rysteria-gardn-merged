#!/usr/bin/env bash
# macOS: deletes builds/ so the next build starts clean.
# The work is done by scripts/common/clean-builds.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/clean-builds.sh" "$@"
