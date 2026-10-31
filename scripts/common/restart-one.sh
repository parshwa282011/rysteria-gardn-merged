#!/usr/bin/env bash
# Starts ONE rrolf game server again. The master server runs this (RESTART_COMMAND
# in its .env, written by build.sh) when a game server dropped its connection
# without saying it was stopping, for example because it crashed. The master
# tries once and gives up if this fails or the server does not come back.
#
# Usage: scripts/common/restart-one.sh <name>      name as in servers.conf
# Exit status 0 = started, anything else = it could not be.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
name="${RS_ARGS[0]:-}"
[ -n "$name" ] || die "usage: restart-one.sh <name>"
detect_platform
load_servers

# stop.sh is running, or someone stopped everything on purpose
[ ! -e "$RS_RUN/stopping" ] || die "everything is being stopped: not restarting $name"

kind=""
for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
    [ "${SV_NAME[$i]}" = "$name" ] && kind="${SV_KIND[$i]}"
done
[ "$kind" = rrolf ] || die "$name is not an rrolf game server in servers.conf"
dir="$RS_TARGET/$name"
[ -x "$dir/rrolf-server" ] && [ -f "$dir/.env" ] || die "$dir has no built server: run build.sh"

# the process can still exist but be cut off from the master: stop it first
if is_running "$name"; then
    pid="$(cat "$(pid_file "$name")")"
    log "$name is still running (pid $pid) but not connected: stopping it"
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    kill -KILL "$pid" 2>/dev/null || true
    sleep 0.5
fi

run mkdir -p "$RS_RUN"
log "starting $name again"
(
    cd "$dir" || exit 1
    nohup ./rrolf-server >>"$RS_RUN/$name.log" 2>&1 &
    echo $! >"$(pid_file "$name")"
)
sleep 1
is_running "$name" || die "$name exited right away, see $RS_RUN/$name.log"
log "$name started (pid $(cat "$(pid_file "$name")"))"
