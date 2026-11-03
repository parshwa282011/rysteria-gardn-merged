#!/usr/bin/env bash
# Splits the game between two machines. Run it ON a machine, or from your own computer
# with ../../split-mac.sh and ../../split-pi.sh in the repository's top folder, which run
# it over ssh.
#
#   the "mac" machine (the one with the master and the database, c1)
#       master, PostgreSQL, gardn, the web edge, rrolf-garden and rrolf-minigames, and the
#       cloudflared tunnel for ALL hostnames. The ports of the servers that run on the
#       other machine (1234 and 1235) are forwarders (forward.js) to that machine, so the
#       tunnel keeps the routes it has: nothing in its configuration changes.
#   the "pi" machine
#       rrolf-hc (hell creek) and rrolf-pvp, which talk to the master over the LAN, and
#       syncd in clone mode, which keeps this machine's PostgreSQL a copy of the master's
#       database. No tunnel, no master, never takes over by itself.
#
# Usage: scripts/common/split.sh <command> [options]
#   mac       make this machine the "mac" side   --pi-addr IP  --pi-ssh user@host  --pi-repo DIR
#                                                [--pi-os debian] [--key FILE] [--remote a,b]
#   pi        make this machine the "pi" side    --mac-addr IP
#   off       back to the normal full stack on this machine (failover with syncd as before)
#   status    what runs here and whether the other side answers
#   tunnel-check   read-only look at cloudflared here: credentials, clock, network, who is connected
# Options for mac / pi / off:
#   --no-apply    only write split.env, do not stop, build and start anything
#   --no-start    stop and build, but leave the servers off
#   --no-start-pi (mac) do not start the other machine afterwards
#   --dry-run     print what would be done
#
# Order for the first time: pi (it builds and starts, waiting for the master), then mac
# (which starts the master and then the other machine's servers if they are not running).
# To go back: off on the pi first, then on the mac.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
detect_platform
cmd="${RS_ARGS[0]:-status}"
PI_ADDR=""; PI_SSH=""; PI_REPO=""; PI_OS=debian; KEY=""; MAC_ADDR=""
REMOTE="rrolf-hc,rrolf-pvp"; NO_APPLY=0; NO_START=0; NO_START_PI=0
args=(${RS_ARGS[@]+"${RS_ARGS[@]}"})
for ((n = 1; n < ${#args[@]}; n++)); do
    case "${args[$n]}" in
    --pi-addr) PI_ADDR="${args[$((++n))]:?--pi-addr needs an address}" ;;
    --pi-ssh) PI_SSH="${args[$((++n))]:?--pi-ssh needs user@host}" ;;
    --pi-repo) PI_REPO="${args[$((++n))]:?--pi-repo needs a folder}" ;;
    --pi-os) PI_OS="${args[$((++n))]:?--pi-os needs macos or debian}" ;;
    --key) KEY="${args[$((++n))]:?--key needs a file}" ;;
    --mac-addr) MAC_ADDR="${args[$((++n))]:?--mac-addr needs an address}" ;;
    --remote) REMOTE="${args[$((++n))]:?--remote needs names}" ;;
    --no-apply) NO_APPLY=1 ;;
    --no-start) NO_START=1 ;;
    --no-start-pi) NO_START_PI=1 ;;
    *) die "unknown option ${args[$n]}" ;;
    esac
done
SPLIT_FILE="$RS_SECRETS_DIR/split.env"

# ------------------------------------------------------------------ helpers
all_names() { awk '$1 !~ /^#/ && NF >= 5 { print $1 }' "$RS_COMMON_DIR/servers.conf"; }
list_has() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }
master_port() { common_get MASTER_PORT; }
master_uri() { env_get "$RS_SECRETS_DIR/master.env" POSTGRES_URI; }
probe_tcp() { # <host> <port>: can a connection be made
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 3 "$1" "$2" >/dev/null 2>&1
    else
        (exec 3<>"/dev/tcp/$1/$2") >/dev/null 2>&1
    fi
}
master_health() { curl -fsS -m 5 "http://$1:$(master_port)/health" 2>/dev/null; }
ssh_opts() {
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
    local key="${KEY/#\~/$HOME}"
    [ -z "$key" ] || SSH_OPTS+=(-i "$key" -o IdentitiesOnly=yes)
}

# PostgreSQL has to be up here: the master (mac) or the copy (pi) lives in it
ensure_postgres() {
    local uri
    uri="$(master_uri)"
    case "$uri" in '' | *user:password*) warn "POSTGRES_URI is not set in $RS_SECRETS_DIR/master.env"; return 0 ;; esac
    command -v psql >/dev/null 2>&1 || { warn "psql is not installed: cannot check PostgreSQL"; return 0; }
    if psql "$uri" -Atc 'select 1' >/dev/null 2>&1; then
        log "PostgreSQL answers"
        return 0
    fi
    if [ "$RS_OS" = macos ] && command -v brew >/dev/null 2>&1; then
        local formula
        formula="$(brew services list 2>/dev/null | awk '$1 ~ /^postgresql/ { print $1; exit }')"
        if [ -n "$formula" ]; then
            log "PostgreSQL does not answer: brew services start $formula"
            run brew services start "$formula" || true
            for _ in $(seq 1 20); do
                sleep 1
                psql "$uri" -Atc 'select 1' >/dev/null 2>&1 && { log "PostgreSQL answers"; return 0; }
            done
        fi
    fi
    [ "$RS_DRY_RUN" = 1 ] && return 0
    die "PostgreSQL does not answer with the POSTGRES_URI of master.env. Start it first"
}

# stop this machine's servers, build (the .env files change), start
apply() { # <start: 1|0>
    if [ "$NO_APPLY" = 1 ]; then
        log "split.env written, nothing applied (--no-apply). To use it: stop.sh, build.sh --skip-clients, run.sh"
        return 0
    fi
    log "building (writes the .env files again; the web clients are not rebuilt)"
    "$RS_ROOT/scripts/$RS_OS/build.sh" --skip-clients
    if [ "$1" = 1 ] && [ "$NO_START" = 0 ]; then
        "$RS_ROOT/scripts/$RS_OS/run.sh"
    else
        log "the servers stay off"
    fi
}
stop_here() {
    [ "$NO_APPLY" = 1 ] || { log "stopping the servers of this machine"; "$RS_ROOT/scripts/$RS_OS/stop.sh"; }
}

write_split() { # KEY=VALUE lines on stdin
    log "writing $SPLIT_FILE"
    if [ "$RS_DRY_RUN" = 1 ]; then cat | sed 's/^/[dry-run] /'; return 0; fi
    (umask 077; mkdir -p "$RS_SECRETS_DIR"; cat >"$SPLIT_FILE")
    chmod 600 "$SPLIT_FILE"
}

# ----------------------------------------------------------------- commands
case "$cmd" in
mac)
    [ -n "$PI_ADDR" ] || die "mac needs --pi-addr (the other machine's LAN address, for the forwarders)"
    [ -n "$PI_SSH" ] && [ -n "$PI_REPO" ] || die "mac needs --pi-ssh user@host and --pi-repo <folder> (to restart its servers and start them)"
    ssh_opts
    ensure_postgres
    if [ "$(sync_get SYNC_LAN_HEALTH)" = 0 ]; then
        warn "SYNC_LAN_HEALTH=0 in sync.env: the master would only listen on this machine, but the other machine's servers connect over the LAN. Split mode makes it listen on the LAN anyway"
    fi
    if [ "$RS_DRY_RUN" != 1 ]; then
        ssh -n "${SSH_OPTS[@]}" "$PI_SSH" "test -x '$PI_REPO/scripts/common/split.sh'" ||
            die "cannot reach $PI_SSH over ssh with a key, or $PI_REPO there has no scripts/common/split.sh (commit, push and update it first: ./quick-deploy.sh)"
    fi
    # what runs here: everything in servers.conf except what the other machine runs and syncd
    run_list=""
    for name in $(all_names); do
        list_has "$REMOTE" "$name" && continue
        [ "$name" = syncd ] && continue
        run_list="$run_list,$name"
    done
    run_list="${run_list#,}"
    stop_here
    write_split <<EOF
SPLIT_ROLE=mac
SPLIT_RUN=$run_list
SPLIT_REMOTE=$REMOTE
SPLIT_REMOTE_ADDR=$PI_ADDR
SPLIT_REMOTE_SSH=$PI_SSH
SPLIT_REMOTE_REPO=$PI_REPO
SPLIT_REMOTE_OS=$PI_OS
SPLIT_SSH_KEY=$KEY
EOF
    apply 1
    if [ "$NO_APPLY" = 0 ] && [ "$NO_START" = 0 ] && [ "$NO_START_PI" = 0 ]; then
        log "starting the servers on $PI_SSH"
        if [ "$RS_DRY_RUN" = 1 ]; then
            echo "[dry-run] ssh $PI_SSH \"cd $PI_REPO && scripts/$PI_OS/run.sh\""
        else
            ssh -n "${SSH_OPTS[@]}" "$PI_SSH" "bash -l -c 'cd \"$PI_REPO\" && scripts/$PI_OS/run.sh'" 2>&1 | tail -6 ||
                warn "could not start the other machine: run scripts/$PI_OS/run.sh there"
        fi
    fi
    log "split mode: this machine has the master, the database and the tunnel; $REMOTE run on $PI_ADDR"
    ;;
pi)
    if [ -z "$MAC_ADDR" ]; then
        # the lan column of the first line of nodes.conf is the main machine
        nodes="$RS_SECRETS_DIR/nodes.conf"; [ -f "$nodes" ] || nodes="$RS_ROOT/dual-server-syncing/nodes.conf"
        MAC_ADDR="$(awk '$1 !~ /^#/ && NF >= 5 { sub(/:.*/, "", $3); print $3; exit }' "$nodes" 2>/dev/null || true)"
        case "$MAC_ADDR" in '' | '-') MAC_ADDR="" ;; esac
    fi
    [ -n "$MAC_ADDR" ] || die "pi needs --mac-addr (the LAN address of the machine with the master)"
    ensure_postgres
    if h="$(master_health "$MAC_ADDR")"; then
        log "the master at $MAC_ADDR answers: $h"
    else
        warn "the master at $MAC_ADDR:$(master_port) does not answer yet. The servers here keep trying; run split.sh mac on the other machine"
    fi
    uri="$(master_uri)"
    if command -v psql >/dev/null 2>&1 && [ -n "$uri" ]; then
        triggers="$(psql "$uri" -Atc "select count(*) from pg_trigger where tgname = 'sync_capture'" 2>/dev/null || echo 0)"
        [ "${triggers:-0}" -gt 0 ] ||
            warn "this database has none of the master's tables yet, so the copy can not be applied. Run the master here once (scripts/$RS_OS/run.sh in normal mode) before switching to split mode"
    fi
    stop_here
    # what runs here is what the other side forwards (--remote, hell creek and pvp), plus the
    # database copy. The master is built (it knows the database's tables) but not started
    write_split <<EOF
SPLIT_ROLE=pi
SPLIT_RUN=$REMOTE,syncd
SPLIT_BUILD_ONLY=master
SPLIT_REMOTE=
SPLIT_MASTER_ADDR=$MAC_ADDR
EOF
    apply 1
    log "split mode: this machine runs the servers it was given and copies the database of $MAC_ADDR"
    ;;
off)
    stop_here
    if [ -f "$SPLIT_FILE" ]; then
        log "removing $SPLIT_FILE"
        run rm -f "$SPLIT_FILE"
    fi
    apply 1
    log "normal mode again on this machine. Do the same on the other one"
    ;;
status)
    role="$(split_role)"
    if [ -z "$role" ]; then
        log "split mode is off here"
    else
        log "split mode: role $role"
        grep -v '^SPLIT_SSH_KEY' "$SPLIT_FILE" | sed 's/^/   /'
    fi
    load_servers
    echo "running here:"
    for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
        ! split_has SPLIT_BUILD_ONLY "${SV_NAME[$i]}" || continue
        if is_running "${SV_NAME[$i]}"; then echo "   ${SV_NAME[$i]}: running"; else echo "   ${SV_NAME[$i]}: not running"; fi
    done
    for ((i = 0; i < ${#RM_NAME[@]}; i++)); do
        addr="$(split_get SPLIT_REMOTE_ADDR)"
        fwd=down; is_running "fwd-${RM_NAME[$i]}" && fwd=running
        if probe_tcp "$addr" "${RM_PORT[$i]}"; then far="$addr:${RM_PORT[$i]} answers"; else far="$addr:${RM_PORT[$i]} does NOT answer"; fi
        echo "   ${RM_NAME[$i]}: runs on the other machine; forwarder $fwd, $far"
    done
    if [ "$role" = pi ]; then
        if h="$(master_health "$(master_addr)")"; then echo "master at $(master_addr): $h"; else echo "master at $(master_addr): does NOT answer"; fi
        echo "database copy (syncd):"; tail -n 3 "$RS_RUN/syncd.log" 2>/dev/null | cut -c1-200 | sed 's/^/   /'
    elif [ -n "$role" ] || curl -fsS -m 3 "http://127.0.0.1:$(master_port)/health" >/dev/null 2>&1; then
        if h="$(master_health 127.0.0.1)"; then echo "master here: $h"; else echo "master here: does NOT answer"; fi
        if [ "$role" = mac ]; then
            if is_running cloudflared; then echo "tunnel: running"; else echo "tunnel: NOT running"; fi
        fi
    fi
    ;;
tunnel-check)
    # read-only: nothing is started or changed
    ok=1
    bad() { ok=0; printf '   PROBLEM: %s\n' "$*"; }
    log "cloudflared on this machine ($RS_OS-$RS_ARCH)"
    if command -v cloudflared >/dev/null 2>&1; then
        echo "   $(cloudflared --version 2>&1 | head -1)"
    else
        bad "cloudflared is not installed (scripts/$RS_OS/setup.sh installs it)"
    fi
    ref="$(common_get TUNNEL_ID)"; [ -n "$ref" ] || ref="$(common_get TUNNEL_NAME)"
    creds="$(tunnel_credentials || true)"
    if [ -n "$creds" ]; then echo "   credentials: $creds"; else bad "no credentials file: TUNNEL_CREDENTIALS=$(common_get TUNNEL_CREDENTIALS) is not here, nor ~/.cloudflared/$(common_get TUNNEL_NAME).json. Copy it from the machine that made the tunnel"; fi
    # a clock that is off breaks the TLS connection to Cloudflare: typical for a Pi after a power cut
    edge_date="$(curl -sI -m 8 https://www.cloudflare.com 2>/dev/null | awk 'tolower($1) == "date:" { sub(/^[^ ]+ /, ""); print; exit }' | tr -d '\r')"
    if [ -n "$edge_date" ]; then
        if [ "$RS_OS" = macos ]; then then_s="$(date -j -u -f '%a, %d %b %Y %H:%M:%S GMT' "$edge_date" +%s 2>/dev/null || echo 0)"
        else then_s="$(date -u -d "$edge_date" +%s 2>/dev/null || echo 0)"; fi
        now_s="$(date -u +%s)"
        if [ "$then_s" -gt 0 ]; then
            skew=$((now_s - then_s)); [ "$skew" -ge 0 ] || skew=$((-skew))
            if [ "$skew" -gt 60 ]; then bad "this machine's clock is $skew s away from Cloudflare's"; else echo "   clock: within $skew s of Cloudflare"; fi
        fi
    else
        bad "https://www.cloudflare.com does not answer: no internet?"
    fi
    for host in region1.v2.argotunnel.com region2.v2.argotunnel.com; do
        if probe_tcp "$host" 7844; then echo "   $host:7844 (tunnel connection) reachable"; else bad "$host:7844 is not reachable: a firewall or router blocks the tunnel's TCP port"; fi
    done
    load_servers
    tmp="$(mktemp)"
    write_tunnel_config "$tmp" "$ref" "${creds:-/none}"
    if command -v cloudflared >/dev/null 2>&1; then
        # (--config belongs to "tunnel", before "ingress": after it cloudflared only prints its help)
        validated="$(cloudflared tunnel --config "$tmp" ingress validate 2>&1 || true)"
        case "$validated" in
        *OK*) echo "   the routes this machine would give the tunnel are valid ($(grep -c hostname "$tmp") hostnames)" ;;
        *) bad "the generated routes are not valid: $(printf '%s' "$validated" | tail -2 | tr '\n' ' ')" ;;
        esac
        echo "   who is connected to the tunnel now:"
        info="$(cloudflared tunnel info "$ref" 2>&1 | grep -E '^(CONNECTOR|[0-9a-f]{8}-)' | cut -c1-110 | head -8 || true)"
        if [ -n "$info" ]; then
            printf '%s\n' "$info" | sed 's/^/      /'
        else
            echo "      (nobody, or this machine has no cert.pem to ask: ~/.cloudflared/cert.pem)"
        fi
    fi
    rm -f "$tmp"
    case "$(split_role)" in
    pi) echo "   split mode: this machine is meant to have NO tunnel, the other machine passes its servers' connections on" ;;
    mac) is_running cloudflared && echo "   cloudflared is running here" || echo "   cloudflared is not running here (run.sh starts it)" ;;
    esac
    [ "$ok" = 1 ] && log "nothing wrong found" || { log "see the problems above"; exit 1; }
    ;;
*) sed -n 2,/^source/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
