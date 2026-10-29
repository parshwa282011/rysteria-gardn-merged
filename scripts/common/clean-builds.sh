#!/usr/bin/env bash
# Deletes the builds/ directory so the next build.sh starts from nothing.
# It removes ONLY <repo>/builds: never the secrets directory, never source.
# Refuses while any server from this build is still running.
#
# Usage: scripts/<os>/clean-builds.sh [--dry-run]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
detect_platform

builds="$RS_ROOT/builds"
# safety: it must be exactly <repo>/builds, a real directory (not a link)
[ "$(basename "$builds")" = builds ] || die "refusing to delete $builds"
[ ! -L "$builds" ] || die "$builds is a symlink, refusing"
if [ ! -d "$builds" ]; then
    log "nothing to delete ($builds does not exist)"
    exit 0
fi
case "$RS_SECRETS_DIR/" in
"$builds"/*) die "the secrets directory lives inside builds/, refusing" ;;
esac

# any build target may still have a running server
for pids in "$builds"/*/run; do
    [ -d "$pids" ] || continue
    for f in "$pids"/*.pid; do
        [ -e "$f" ] || continue
        pid="$(cat "$f" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            die "$(basename "$f" .pid) is still running (pid $pid): run scripts/$RS_OS/stop.sh first"
        fi
    done
done

log "deleting $builds (secrets in $RS_SECRETS_DIR are untouched)"
run rm -rf -- "$builds"
