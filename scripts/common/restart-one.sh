#!/usr/bin/env bash
# Starts ONE rrolf game server (or gardn) again. The master server runs this
# (RESTART_COMMAND in its .env, written by build.sh) when a game server dropped its
# connection without saying it was stopping, for example because it crashed. The
# master tries once and gives up if this fails or the server does not come back.
# The edge (edge.js) runs it for gardn when gardn does not answer.
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

# split mode: a server of the other machine is started again there
for ((i = 0; i < ${#RM_NAME[@]}; i++)); do
    [ "${RM_NAME[$i]}" = "$name" ] || continue
    remote_ssh="$(split_get SPLIT_REMOTE_SSH)"
    remote_repo="$(split_get SPLIT_REMOTE_REPO)"
    key="$(split_get SPLIT_SSH_KEY)"
    key="${key/#\~/$HOME}"
    [ -n "$remote_ssh" ] && [ -n "$remote_repo" ] || die "$name runs on the other machine but split.env has no SPLIT_REMOTE_SSH / SPLIT_REMOTE_REPO"
    ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
    [ -z "$key" ] || ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)
    log "$name runs on $remote_ssh: starting it again there"
    exec ssh -n "${ssh_opts[@]}" "$remote_ssh" "bash -l -c 'cd \"$remote_repo\" && scripts/common/restart-one.sh \"$name\"'"
done

kind=""
for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
    [ "${SV_NAME[$i]}" = "$name" ] && kind="${SV_KIND[$i]}"
done
dir="$RS_TARGET/$name"
case "$kind" in
rrolf)
    [ -x "$dir/rrolf-server" ] && [ -f "$dir/.env" ] || die "$dir has no built server: run build.sh"
    server_cmd=(./rrolf-server)
    ;;
gardn)
    [ -f "$dir/gardn-server.js" ] && [ -f "$dir/.env" ] || die "$dir has no built gardn: run build.sh"
    server_cmd=(node gardn-server.js)
    ;;
*) die "$name is not an rrolf game server or gardn in servers.conf" ;;
esac

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
    nohup "${server_cmd[@]}" >>"$RS_RUN/$name.log" 2>&1 &
    echo $! >"$(pid_file "$name")"
)
sleep 1
is_running "$name" || die "$name exited right away, see $RS_RUN/$name.log"
log "$name started (pid $(cat "$(pid_file "$name")"))"
