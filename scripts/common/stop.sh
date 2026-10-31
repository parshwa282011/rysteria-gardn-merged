#!/usr/bin/env bash
# Stops what run.sh started, in reverse order (cloudflared first, master last)
# so players are saved while the master is still there. Servers get SIGTERM,
# which makes the master and gardn write everything they hold before exiting;
# anything still alive after 20 seconds is killed.
#
# Usage: scripts/<os>/stop.sh [--dry-run] [--keep-role]
#   --keep-role  a machine that is the primary stays the primary: the next run.sh
#                starts the tunnel again. syncd uses it to restart a primary.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
detect_platform
load_servers

stop_one() {
    local name="$1" file pid i
    file="$(pid_file "$name")"
    [ -f "$file" ] || return 0
    pid="$(cat "$file" 2>/dev/null || true)"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        run rm -f "$file"
        return 0
    fi
    log "stopping $name (pid $pid)"
    if [ "$RS_DRY_RUN" = 1 ]; then
        echo "[dry-run] kill -TERM $pid"
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    for i in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        warn "$name ignored SIGTERM, killing it"
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$file"
}

# the master starts a game server again when it drops without saying it stops
# (restart-one.sh). While this runs it must not
run mkdir -p "$RS_RUN"
run touch "$RS_RUN/stopping"

# syncd first: it must not see the servers go away and start them again
stop_one syncd
if [ "${RS_ARGS[0]:-}" = --keep-role ] && [ "$(cat "$RS_RUN/sync.role" 2>/dev/null)" = primary ]; then
    run touch "$RS_RUN/sync.keep-role"
else
    run rm -f "$RS_RUN/sync.role"
fi
stop_one cloudflared
for ((i = ${#SV_NAME[@]} - 1; i >= 0; i--)); do
    stop_one "${SV_NAME[$i]}"
done
if mail_enabled; then
    "$RS_COMMON_DIR/mail.sh" stop || warn "could not stop the mail server"
fi
log "stopped"
