#!/usr/bin/env bash
# Brings the checkout up to date: git pull of the merged repository (rrolf and
# gardn are its submodules) and `git submodule update`.
# A checkout with uncommitted changes is NOT touched: the pull is skipped with a
# warning, so local work is never overwritten.
#
# Usage: scripts/common/sync-repo.sh [--dry-run]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

git -C "$RS_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "$RS_ROOT is not a git checkout; run scripts/bootstrap.sh to clone $RS_REPO_URL"

dirty="$(git -C "$RS_ROOT" status --porcelain --ignore-submodules=none 2>/dev/null || true)"
sub_dirty="$(git -C "$RS_ROOT" submodule foreach --quiet 'git status --porcelain' 2>/dev/null || true)"
if [ -n "$dirty$sub_dirty" ]; then
    warn "uncommitted changes in $RS_ROOT (or its submodules): skipping git pull"
    exit 0
fi

log "git pull ($RS_REPO_URL)"
run git -C "$RS_ROOT" pull --ff-only
run git -C "$RS_ROOT" submodule sync --recursive
run git -C "$RS_ROOT" submodule update --init --recursive
