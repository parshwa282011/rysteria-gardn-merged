#!/usr/bin/env bash
# Prints the version hash of a build of gardn. The client and the server of gardn refuse each
# other when it differs, so a client built somewhere else (the GitHub Action that builds the
# website, see scripts/build-web.sh) must get the same number as the servers on your machines.
# So it is the commit time of gardn, the same wherever the same commit is built. With changes in
# gardn that are not committed it is the time now, as it used to be (every build is its own version).
# Usage: build-hash.sh [repository root, default: two folders up]
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if [ -z "$(git -C "$root/gardn" status --porcelain 2>/dev/null)" ]; then
    git -C "$root/gardn" show -s --format=%ct HEAD 2>/dev/null && exit 0
fi
date +%s
