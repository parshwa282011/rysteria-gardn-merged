#!/usr/bin/env bash
# Starts everything that build.sh produced, detached, in this order:
#   master (waits for /health) -> rrolf game servers -> gardn -> edge
#   -> syncd, only if SYNC_ENABLED=1 in ~/.rysteria-secrets/sync.env
#   -> cloudflared, only if CLOUDFLARED_ENABLED=1 in ~/.rysteria-secrets/common.env
#      (with SYNC_ENABLED=1 only on the primary machine, see dual-server-syncing/)
# Each process runs in its own builds/<os>-<arch>/<name>/ folder and reads the
# .env sitting there. Logs and pid files: builds/<os>-<arch>/run/
#
# Usage: scripts/<os>/run.sh [--dry-run]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
[ "${#RS_ARGS[@]}" = 0 ] || die "unknown option ${RS_ARGS[0]}"
detect_platform
load_servers
[ -d "$RS_TARGET" ] || die "nothing built yet: run scripts/$RS_OS/build.sh"
check_secrets_ready
run mkdir -p "$RS_RUN"
# stop.sh leaves this while it stops everything, so that nothing is restarted
run rm -f "$RS_RUN/stopping"

start() { # <name> <command...> ; runs inside the server's folder
    local name="$1"
    shift
    local dir="$RS_TARGET/$name"
    [ -d "$dir" ] || die "$dir does not exist: build first"
    [ -f "$dir/.env" ] || die "$dir/.env is missing: build.sh writes it"
    if is_running "$name"; then
        log "$name already running (pid $(cat "$(pid_file "$name")"))"
        return 0
    fi
    log "starting $name"
    if [ "$RS_DRY_RUN" = 1 ]; then
        printf '[dry-run] (cd %q && nohup' "$dir"
        printf ' %q' "$@"
        printf ' >> %q 2>&1 &)\n' "$RS_RUN/$name.log"
        return 0
    fi
    (
        cd "$dir" || exit 1
        nohup "$@" >>"$RS_RUN/$name.log" 2>&1 &
        echo $! >"$(pid_file "$name")"
    )
    sleep 0.5
    is_running "$name" || die "$name exited right away, see $RS_RUN/$name.log"
}

wait_for_master() {
    [ "$RS_DRY_RUN" = 1 ] && return 0
    local port i
    port="$(server_port master)"
    for i in $(seq 1 30); do
        if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            log "master is healthy"
            return 0
        fi
        sleep 1
    done
    die "master did not become healthy, see $RS_RUN/master.log"
}

ROLE_FILE="$RS_RUN/sync.role"

# With SYNC_ENABLED=1 only the primary gets the tunnel. syncd decides who that is
# and records it in $ROLE_FILE (it calls this script again after taking over).
is_primary_here() {
    ! sync_enabled || [ "$(cat "$ROLE_FILE" 2>/dev/null)" = primary ]
}

for kind in master rrolf gardn edge sync; do
    for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
        [ "${SV_KIND[$i]}" = "$kind" ] || continue
        name="${SV_NAME[$i]}"
        case "$kind" in
        master)
            start "$name" ./rysteria-master --env .env
            wait_for_master
            ;;
        rrolf) start "$name" ./rrolf-server ;;
        gardn) start "$name" node gardn-server.js ;;
        edge) start "$name" node edge.js ;;
        sync)
            sync_enabled || continue
            # a role left over from before a reboot or crash must not start the
            # tunnel, except after stop.sh --keep-role (a restart of the primary)
            if [ -e "$RS_RUN/sync.keep-role" ]; then
                run rm -f "$RS_RUN/sync.keep-role"
            else
                is_running "$name" || run rm -f "$ROLE_FILE"
            fi
            start "$name" node syncd.js
            ;;
        esac
    done
done

# ------------------------------------------------------------------ mail server
# "email system/" (docker). A failure here must not take the game servers down.
if mail_enabled && is_primary_here; then
    "$RS_COMMON_DIR/mail.sh" start || warn "mail server did not start (see: scripts/$RS_OS/mail.sh status)"
fi

# ----------------------------------------------------------------- cloudflared
if [ "$(common_get CLOUDFLARED_ENABLED)" = 1 ] && ! is_primary_here; then
    log "backup mode: no tunnel on this machine (syncd starts it if the primary fails). state: scripts/$RS_OS/sync.sh status"
elif [ "$(common_get CLOUDFLARED_ENABLED)" = 1 ]; then
    need cloudflared
    domain="$(common_get DOMAIN)"
    tunnel_name="$(common_get TUNNEL_NAME)"
    # the id, when known, is what cloudflared is least likely to get wrong
    tunnel_ref="$(common_get TUNNEL_ID)"
    [ -n "$tunnel_ref" ] || tunnel_ref="$tunnel_name"
    tunnel_yml="$RS_RUN/tunnel.yml"
    tunnel_creds="$(tunnel_credentials || true)"
    log "cloudflared tunnel $tunnel_name for $domain"
    if [ -z "$tunnel_creds" ] && [ "$RS_DRY_RUN" != 1 ]; then
        warn "no credentials file for the tunnel: TUNNEL_CREDENTIALS=$(common_get TUNNEL_CREDENTIALS) does not exist here, nor does ~/.cloudflared/$tunnel_name.json. Copy it from the machine that made the tunnel (cloudflared tunnel create). The game runs, but not through the tunnel"
    elif [ "$RS_DRY_RUN" != 1 ]; then
        {
            echo "tunnel: $tunnel_ref"
            echo "credentials-file: $tunnel_creds"
            echo "ingress:"
            for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
                [ "${SV_HOST[$i]}" = "-" ] && continue
                # several hostnames may share one server: "hc-game,default-game"
                IFS=',' read -ra hosts <<<"${SV_HOST[$i]}"
                for h in "${hosts[@]}"; do
                    echo "  - hostname: $h.$domain"
                    echo "    service: http://127.0.0.1:${SV_PORT[$i]}"
                done
            done
            # webmail for the mail server (SMTP/IMAP cannot go through a tunnel)
            if mail_enabled && [ -n "$(mail_get WEBMAIL_HOST)" ]; then
                echo "  - hostname: $(mail_get WEBMAIL_HOST).$domain"
                echo "    service: http://127.0.0.1:$(mail_get WEBMAIL_PORT)"
            fi
            echo "  - service: http_status:404"
        } >"$tunnel_yml"
    fi
    if is_running cloudflared; then
        log "cloudflared already running"
    elif [ "$RS_DRY_RUN" = 1 ]; then
        echo "[dry-run] nohup cloudflared tunnel --no-autoupdate --protocol http2 --config $tunnel_yml run $tunnel_ref"
    elif [ -n "$tunnel_creds" ]; then
        # TCP (http2) instead of QUIC: a network that drops UDP made the QUIC
        # connections time out every few minutes. Started up to three times, and
        # it has to register a connection with Cloudflare to count as started
        tunnel_up=0
        for attempt in 1 2 3; do
            seen=0
            [ ! -f "$RS_RUN/cloudflared.log" ] || seen=$(wc -l <"$RS_RUN/cloudflared.log")
            (
                cd "$RS_RUN" || exit 1
                nohup cloudflared tunnel --no-autoupdate --protocol http2 --config "$tunnel_yml" run "$tunnel_ref" >>"$RS_RUN/cloudflared.log" 2>&1 &
                echo $! >"$(pid_file cloudflared)"
            )
            for _ in $(seq 1 30); do
                sleep 1
                is_running cloudflared || break
                if tail -n +"$((seen + 1))" "$RS_RUN/cloudflared.log" 2>/dev/null | grep -q "Registered tunnel connection"; then
                    tunnel_up=1
                    break
                fi
            done
            [ "$tunnel_up" = 1 ] && break
            warn "cloudflared did not connect (try $attempt of 3), last lines of $RS_RUN/cloudflared.log:"
            tail -n 5 "$RS_RUN/cloudflared.log" >&2 || true
            if is_running cloudflared; then
                kill "$(cat "$(pid_file cloudflared)")" 2>/dev/null || true
            fi
            rm -f "$(pid_file cloudflared)"
            sleep 2
        done
        if [ "$tunnel_up" = 1 ]; then
            log "cloudflared is connected"
        else
            warn "cloudflared could not connect: the game runs here but not through the tunnel. syncd (or run.sh again) tries again"
        fi
    fi
fi

log "everything is up. logs: $RS_RUN/*.log   stop: scripts/$RS_OS/stop.sh"
