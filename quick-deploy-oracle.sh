#!/usr/bin/env bash
# Deploys what is in this folder (committed or not) to the Oracle Cloud machines, one at a time or
# all at once. Unlike quick-deploy.sh it needs no git push: the files are copied with rsync.
#
#   ./quick-deploy-oracle.sh game                  update + build + restart the game machine only
#   ./quick-deploy-oracle.sh db                    update the database machine only (copier service)
#   ./quick-deploy-oracle.sh all                   both (db first, then game)
#   ./quick-deploy-oracle.sh game --servers "rrolf-pvp gardn"
#                                                  only restart those game servers (names from
#                                                  scripts/common/servers.conf) after the update
#   ./quick-deploy-oracle.sh status                what runs on each machine, and the health of the game
#   ./quick-deploy-oracle.sh dns                   the Cloudflare DNS records the game machine needs
#   ./quick-deploy-oracle.sh tunnel [start|stop]   database tunnel 127.0.0.1:15432 -> the db machine,
#                                                  through the game machine (for running the master here)
#
# Options:
#   --no-build      copy the code, do not build (game)
#   --secrets       push secrets/*.env again (otherwise only when the machine has none)
#   --setup         run the machine's setup script first (done by itself on a machine that never had it)
#   --leave-off     update and build, but leave the game servers stopped
#   --dry-run       only print what would be done
#   --key FILE      ssh key (default ~/.ssh/id_c1)
#
# The machines are listed in secrets/oracle.conf:   name  role  ssh-target  jump-host-name-or-"-"
# (the db machine has no public address: it is reached through the game machine).
#
# First time on a new game machine:  ./quick-deploy-oracle.sh game   (sets it up, copies, builds, starts)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$ROOT/secrets/oracle.conf"
KEY="$HOME/.ssh/id_c1"
DRY=0; BUILD=1; PUSH_SECRETS=0; SETUP=0; OFF=0; SERVERS=""
TARGETS=""; CMD=""; ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
    game | db | all) TARGETS="$TARGETS $1" ;;
    status | dns | tunnel) CMD="$1"; if [ "$1" = tunnel ] && [ "${2:-}" != "" ] && [ "${2#-}" = "$2" ]; then ARG="$2"; shift; fi ;;
    --no-build) BUILD=0 ;;
    --secrets) PUSH_SECRETS=1 ;;
    --setup) SETUP=1 ;;
    --leave-off) OFF=1 ;;
    --dry-run) DRY=1 ;;
    --servers) shift; SERVERS="${1:?--servers needs names}" ;;
    --key) shift; KEY="${1:?--key needs a file}" ;;
    -h | --help) sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
[ -f "$CONF" ] || die "no $CONF (columns: name role ssh-target jump-host)"
[ -f "$KEY" ] || die "ssh key $KEY not found (--key FILE)"

# ------------------------------------------------------------------ machines
M_NAME=(); M_ROLE=(); M_SSH=(); M_JUMP=()
while read -r name role target jump _rest; do
    case "$name" in '' | '#'*) continue ;; esac
    M_NAME+=("$name"); M_ROLE+=("$role"); M_SSH+=("$target"); M_JUMP+=("${jump:--}")
done <"$CONF"
idx() { local i; for ((i = 0; i < ${#M_NAME[@]}; i++)); do [ "${M_NAME[$i]}" = "$1" ] && { echo "$i"; return; }; done; die "no machine \"$1\" in $CONF"; }

BASE_OPTS="-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -i $KEY -o IdentitiesOnly=yes"
# ssh options for machine i, with the jump host in front when it has one
opts_for() {
    local j="${M_JUMP[$1]}"
    if [ "$j" = "-" ]; then echo "$BASE_OPTS"; else
        local ji; ji="$(idx "$j")"
        echo "$BASE_OPTS -o ProxyCommand=\"ssh $BASE_OPTS -W %h:%p ${M_SSH[$ji]}\""
    fi
}
rsh() { local i=$1; shift; eval "ssh -n $(opts_for "$i") \"\${M_SSH[$i]}\" \"\$@\""; }       # one command
rsh_stdin() { local i=$1; shift; eval "ssh $(opts_for "$i") \"\${M_SSH[$i]}\" \"\$@\""; }   # script on stdin
act() { if [ "$DRY" = 1 ]; then echo "   [dry run] $*"; return 1; fi; echo "   $*"; return 0; }

# ssh as a command rsync can use
WRAP="$(mktemp -d)/ssh-wrapper"
trap 'rm -rf "$(dirname "$WRAP")"' EXIT
make_wrapper() { printf '#!/bin/bash\nexec ssh %s "$@"\n' "$(opts_for "$1")" >"$WRAP"; chmod +x "$WRAP"; }

# --------------------------------------------------------------- small commands
if [ "$CMD" = dns ]; then
    i="$(idx game)"; ip="${M_SSH[$i]#*@}"
    domain="$(awk -F= '$1=="DOMAIN" {print $2}' "$ROOT/secrets/common.env")"
    echo "Cloudflare dashboard > $domain > DNS > Records.  Delete the old CNAMEs to the tunnel first (they have the same names)."
    echo "Type  Name                 Content          Proxy status"
    awk -v d="$domain" -v ip="$ip" '$1 !~ /^#/ && NF >= 5 && $4 ~ /^[0-9]+$/ && $5 != "-" { n = split($5, h, ","); for (k = 1; k <= n; k++) printf "A     %-20s %-16s Proxied (orange)\n", h[k], ip }' "$ROOT/scripts/common/servers.conf"
    # the same records as a BIND zone file for Cloudflare's DNS > Records > Import and export > Import
    zone="$ROOT/cloudflare/$domain.zone"
    {
        echo "; Oracle game machine: import in Cloudflare DNS > Records > Import and export (delete the old tunnel CNAMEs of these names first)"
        echo "\$ORIGIN $domain."
        awk -v d="$domain" -v ip="$ip" '$1 !~ /^#/ && NF >= 5 && $4 ~ /^[0-9]+$/ && $5 != "-" { n = split($5, h, ","); for (k = 1; k <= n; k++) printf "%s.%s.\t1\tIN\tA\t%s ; cf_tags=cf-proxied:true\n", h[k], d, ip }' "$ROOT/scripts/common/servers.conf"
    } >"$zone"
    echo
    echo "Zone file for the import: $zone"
    echo
    echo "SSL/TLS > Overview: encryption mode = Full   (nginx has a self-signed certificate)"
    echo "           better: Full (strict) with an Origin certificate: SSL/TLS > Origin Server > Create Certificate"
    echo "           (hostnames *.$domain, $domain), then on the game machine:"
    echo "           sudo tee /etc/nginx/origin.pem, sudo tee /etc/nginx/origin.key, ./quick-deploy-oracle.sh game --no-build"
    echo "Network: WebSockets = On (default).  Only these hostnames are needed; no ssh.* record."
    exit 0
fi

if [ "$CMD" = tunnel ]; then
    i="$(idx game)"; d="$(idx db)"; dbhost="${M_SSH[$d]#*@}"; port=15432
    pidf="${TMPDIR:-/tmp}/oracle-db-tunnel.pid"
    case "${ARG:-start}" in
    stop)
        if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then kill "$(cat "$pidf")"; echo "tunnel stopped"; else echo "no tunnel running"; fi; rm -f "$pidf"; exit 0 ;;
    start)
        if nc -z 127.0.0.1 $port 2>/dev/null; then echo "127.0.0.1:$port is already in use (a tunnel is up?)"; exit 0; fi
        eval "ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=3 $(opts_for "$i") -L 127.0.0.1:$port:$dbhost:5432 \"${M_SSH[$i]}\""
        pgrep -f "127.0.0.1:$port:$dbhost:5432" | head -1 >"$pidf"
        echo "database tunnel up: postgresql://rysteria:<password>@127.0.0.1:$port/rysteria  (stop: $0 tunnel stop)" ;;
    *) die "tunnel start|stop" ;;
    esac
    exit 0
fi

if [ "$CMD" = status ]; then
    for ((i = 0; i < ${#M_NAME[@]}; i++)); do
        say "${M_NAME[$i]} (${M_ROLE[$i]}, ${M_SSH[$i]})"
        case "${M_ROLE[$i]}" in
        game) rsh "$i" 'uptime; echo "rysteria: $(XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active rysteria)  nginx: $(systemctl is-active nginx)"; echo "master: $(curl -s -m 5 http://127.0.0.1:55554/health)"; ps -eo pid,etime,args | grep -E "rrolf-server|rysteria-master|gardn-server|edge.js" | grep -v grep | cut -c1-90; cd ~/rysteria-gardn-merged 2>/dev/null && git log --oneline -1' || true ;;
        db) rsh "$i" 'uptime; free -m | sed -n 2p; echo "postgres: $(systemctl is-active postgresql)  sync: $(systemctl is-active rysteria-db-sync)"; export POSTGRES_URI="$(cat ~/.local-db-uri)"; python3 ~/rysteria-gardn-merged/scripts/common/remote-copy.py --status 2>&1 | tail -15' || true ;;
        esac
    done
    exit 0
fi

[ -n "$TARGETS" ] || { sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 2; }
case " $TARGETS " in *" all "*) TARGETS=" db game" ;; esac

# ------------------------------------------------------------------ helpers
# a command that survives the ssh connection: log in ~/.qdo-<label>.log, exit code in ~/.qdo-<label>.done
remote_bg() { # <machine> <label> <command>
    local i=$1 label=$2 cmd=$3 n=0 code line
    rsh "$i" "rm -f ~/.qdo-$label.done; nohup bash -lc '$cmd > ~/.qdo-$label.log 2>&1; echo \$? > ~/.qdo-$label.done' >/dev/null 2>&1 </dev/null &"
    while :; do
        sleep 15; n=$((n + 1))
        code="$(rsh "$i" "cat ~/.qdo-$label.done 2>/dev/null" || true)"
        if [ -n "$code" ]; then
            rsh "$i" "tail -n 25 ~/.qdo-$label.log" || true
            [ "$code" = 0 ] || die "$label on ${M_NAME[$i]} failed (exit $code), full log: ${M_NAME[$i]}:~/.qdo-$label.log"
            return 0
        fi
        line="$(rsh "$i" "tail -n 1 ~/.qdo-$label.log 2>/dev/null | cut -c1-110" || true)"
        [ $((n % 4)) != 0 ] || echo "   ${M_NAME[$i]} $label ($((n / 4)) min): $line"
        [ "$n" -lt 480 ] || die "$label on ${M_NAME[$i]} still running after 2 hours"
    done
}

push_secrets() { # <machine> [files...]
    local i=$1; shift
    local files=("$@")
    if [ ${#files[@]} -eq 0 ]; then
        files=("$ROOT"/secrets/*.env)
        local f; for f in "$ROOT"/secrets/*.p8 "$ROOT"/secrets/apple-domain.txt; do [ -f "$f" ] && files+=("$f"); done
    fi
    act "${M_NAME[$i]}: pushing $(printf '%s ' "${files[@]##*/}")" || return 0
    rsh "$i" 'umask 077; mkdir -p ~/.rysteria-secrets; chmod 700 ~/.rysteria-secrets'
    make_wrapper "$i"
    rsync -q -e "$WRAP" "${files[@]}" "${M_SSH[$i]}:.rysteria-secrets/"
    rsh "$i" 'chmod 600 ~/.rysteria-secrets/*'
}

has_secrets() { rsh "$1" 'test -f ~/.rysteria-secrets/master.env' 2>/dev/null; }

# the files of this repository as they are here now: tracked (submodules too) + new, minus what is deleted
file_list() {
    local out="$1"
    cd "$ROOT"
    { git ls-files --recurse-submodules; git ls-files -o --exclude-standard; } | sort -u | while IFS= read -r f; do
        [ -e "$f" ] && printf '%s\n' "$f"
    done | grep -v -E '^(secrets/|builds/)' >"$out"
}

# ------------------------------------------------------------------ the game machine
deploy_game() {
    local i; i="$(idx game)"
    say "game: ${M_SSH[$i]}"
    [ "$DRY" = 1 ] || rsh "$i" true || die "can't ssh to ${M_SSH[$i]} (is it up? is port 22 open in the security list?)"

    # 1. setup (once)
    if [ "$SETUP" = 1 ] || ! rsh "$i" 'test -f /var/log/rysteria-init.done && test -d ~/rysteria-gardn-merged/.git' 2>/dev/null; then
        if act "setup: installing the toolchain, nginx, emscripten, firewall (10-20 minutes)"; then
            make_wrapper "$i"
            rsync -q -e "$WRAP" "$ROOT/scripts/oracle-cloud-init-game.sh" "${M_SSH[$i]}:oracle-cloud-init-game.sh"
            remote_bg "$i" setup 'sudo bash ~/oracle-cloud-init-game.sh'
        fi
    fi

    # 2. code
    local list; list="$(mktemp)"
    file_list "$list"
    if act "copying $(wc -l <"$list" | tr -d ' ') files (rsync: only what differs)"; then
        make_wrapper "$i"
        (cd "$ROOT" && rsync -rlpzc --files-from="$list" -e "$WRAP" ./ "${M_SSH[$i]}:rysteria-gardn-merged/") || die "rsync failed"
    fi
    rm -f "$list"

    # 3. secrets
    if [ "$PUSH_SECRETS" = 1 ] || { [ "$DRY" = 0 ] && ! has_secrets "$i"; }; then push_secrets "$i"; else echo "   secrets: already on the machine (--secrets pushes them again)"; fi

    # 4. build, nginx, (re)start
    if [ -n "$SERVERS" ]; then
        if [ "$BUILD" = 1 ] && act "build"; then remote_bg "$i" build 'cd ~/rysteria-gardn-merged && scripts/debian/build.sh'; fi
        if act "restarting only: $SERVERS"; then
            rsh_stdin "$i" "SERVERS='$SERVERS' bash -l -s" <<'EOF'
set -e
cd ~/rysteria-gardn-merged
source scripts/common/lib.sh; detect_platform; load_servers
for n in $SERVERS; do
    if is_running "$n"; then
        pid="$(cat "$(pid_file "$n")")"; echo "   stopping $n ($pid)"; kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
        kill -KILL "$pid" 2>/dev/null || true
    fi
done
RS_ONLY="$SERVERS" scripts/debian/run.sh 2>&1 | tail -n 8
EOF
        fi
        return 0
    fi
    local flags=""
    [ "$BUILD" = 1 ] || flags="--no-build"
    [ "$OFF" = 0 ] || flags="$flags --no-start"
    if [ "$OFF" = 1 ] && act "stopping the game servers (--leave-off)"; then rsh "$i" 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user stop rysteria' || true; fi
    if act "nginx + build + restart (scripts/oracle-finish-game.sh $flags)"; then
        remote_bg "$i" finish "cd ~/rysteria-gardn-merged && scripts/oracle-finish-game.sh $flags"
    fi

    # 5. PDEV (the give-petals cheat) must never be in a build
    if [ "$DRY" = 0 ] && [ "$BUILD" = 1 ]; then
        if rsh "$i" 'cd ~/rysteria-gardn-merged && { ls builds/*/PDEV-BUILD 2>/dev/null; grep -l "^PDEV" builds/.work/*/*/CMakeCache.txt 2>/dev/null; } | head -3' | grep -q .; then
            die "PDEV is set in a build on the game machine"
        fi
        echo "   no PDEV in the build"
    fi
}

# ------------------------------------------------------------------ the database machine
deploy_db() {
    local i; i="$(idx db)"
    say "db: ${M_SSH[$i]} (through ${M_JUMP[$i]})"
    [ "$DRY" = 1 ] || rsh "$i" true || die "can't ssh to the db machine through the game machine (is the game machine up?)"
    if [ "$SETUP" = 1 ] && act "setup: PostgreSQL + sync service (oracle-cloud-init-db.sh)"; then
        make_wrapper "$i"
        rsync -q -e "$WRAP" "$ROOT/scripts/oracle-cloud-init-db.sh" "${M_SSH[$i]}:oracle-cloud-init-db.sh"
        remote_bg "$i" setup 'sudo bash ~/oracle-cloud-init-db.sh'
    fi
    if act "copying scripts/common/remote-copy.py"; then
        make_wrapper "$i"
        rsync -q -e "$WRAP" "$ROOT/scripts/common/remote-copy.py" "${M_SSH[$i]}:rysteria-gardn-merged/scripts/common/remote-copy.py"
    fi
    if [ "$PUSH_SECRETS" = 1 ]; then push_secrets "$i" "$ROOT/secrets/master.env" "$ROOT/secrets/common.env"; fi
    if [ "$OFF" = 1 ]; then act "stopping the copier (--leave-off)" && rsh "$i" 'sudo systemctl stop rysteria-db-sync' || true
    elif act "restarting the copier service"; then
        rsh "$i" 'sudo systemctl restart rysteria-db-sync; sleep 3; systemctl is-active rysteria-db-sync; systemctl is-active postgresql'
    fi
}

# ------------------------------------------------------------------ go
for t in $TARGETS; do
    case "$t" in
    db) deploy_db ;;
    game) deploy_game ;;
    esac
done

if [ "$DRY" = 0 ]; then
    say "done. ./quick-deploy-oracle.sh status shows what runs;  ./quick-deploy-oracle.sh dns the Cloudflare records"
fi
