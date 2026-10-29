#!/usr/bin/env bash
# Starts everything that build.sh produced, detached, in this order:
#   master (waits for /health) -> rrolf game servers -> gardn -> edge
#   -> cloudflared, only if CLOUDFLARED_ENABLED=1 in ~/.rysteria-secrets/common.env
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

for kind in master rrolf gardn edge; do
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
        esac
    done
done

# ----------------------------------------------------------------- cloudflared
if [ "$(common_get CLOUDFLARED_ENABLED)" = 1 ]; then
    need cloudflared
    domain="$(common_get DOMAIN)"
    tunnel_name="$(common_get TUNNEL_NAME)"
    tunnel_yml="$RS_RUN/tunnel.yml"
    log "cloudflared tunnel $tunnel_name for $domain"
    if [ "$RS_DRY_RUN" != 1 ]; then
        {
            echo "tunnel: $tunnel_name"
            echo "credentials-file: $(common_get TUNNEL_CREDENTIALS)"
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
            echo "  - service: http_status:404"
        } >"$tunnel_yml"
    fi
    if is_running cloudflared; then
        log "cloudflared already running"
    elif [ "$RS_DRY_RUN" = 1 ]; then
        echo "[dry-run] nohup cloudflared tunnel --config $tunnel_yml run $tunnel_name"
    else
        (
            cd "$RS_RUN" || exit 1
            nohup cloudflared tunnel --config "$tunnel_yml" run "$tunnel_name" >>"$RS_RUN/cloudflared.log" 2>&1 &
            echo $! >"$(pid_file cloudflared)"
        )
    fi
fi

log "everything is up. logs: $RS_RUN/*.log   stop: scripts/$RS_OS/stop.sh"
