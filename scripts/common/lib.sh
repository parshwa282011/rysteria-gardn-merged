#!/usr/bin/env bash
# Shared helpers for the deployment scripts. Sourced, never executed.
# Works with bash 3.2 (macOS) and newer.
#
# The one rule: nothing in here edits game or server source. Everything lands in
#   <repo>/builds/<os>-<arch>/      (disposable, see clean-builds.sh)
#   ~/.rysteria-secrets/            (kept; never touched by builds or cleans)

set -euo pipefail

RS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RS_ROOT="$(cd "$RS_COMMON_DIR/../.." && pwd)"
RS_REPO_URL="${RS_REPO_URL:-https://github.com/parshwa282011/rysteria-gardn-merged.git}"
RS_SECRETS_DIR="${SECRETS_DIR:-$HOME/.rysteria-secrets}"
RS_DRY_RUN="${RS_DRY_RUN:-0}"
RS_FORCE="${RS_FORCE:-0}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Runs a command, or only prints it with --dry-run.
run() {
    if [ "$RS_DRY_RUN" = 1 ]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# Handles the flags every script shares; leftovers are kept in RS_ARGS.
RS_ARGS=()
parse_common_flags() {
    RS_ARGS=()
    for arg in "$@"; do
        case "$arg" in
        --dry-run) RS_DRY_RUN=1 ;;
        --force) RS_FORCE=1 ;;
        *) RS_ARGS+=("$arg") ;;
        esac
    done
    # child scripts (sync-repo.sh ...) inherit the choice
    export RS_DRY_RUN RS_FORCE
}

# ---------------------------------------------------------------- platform

detect_platform() {
    local uname_s uname_m
    uname_s="$(uname -s)"
    uname_m="$(uname -m)"
    case "$uname_s" in
    Darwin) RS_OS=macos ;;
    Linux)
        # Debian family: Debian, Ubuntu, Raspberry Pi OS. WSL Ubuntu counts.
        if [ -r /etc/os-release ] && grep -qiE 'debian|ubuntu|raspbian' /etc/os-release; then
            RS_OS=debian
        else
            die "unsupported Linux (only Debian/Ubuntu/Raspberry Pi OS are supported)"
        fi
        ;;
    *) die "unsupported OS $uname_s (on Windows use scripts/windows/*.ps1)" ;;
    esac
    case "$uname_m" in
    arm64 | aarch64) RS_ARCH=arm64 ;;
    x86_64 | amd64) RS_ARCH=amd64 ;;
    armv7l | armv6l) RS_ARCH=armhf ;;
    *) RS_ARCH="$uname_m" ;;
    esac
    RS_IS_PI=0
    if [ -r /proc/device-tree/model ] && grep -qi 'raspberry' /proc/device-tree/model 2>/dev/null; then
        RS_IS_PI=1
    fi
    RS_TARGET="$RS_ROOT/builds/$RS_OS-$RS_ARCH"
    RS_WORK="$RS_ROOT/builds/.work/$RS_OS-$RS_ARCH"
    export RS_WORK
    RS_RUN="$RS_TARGET/run"

    if [ "$RS_OS" = macos ]; then
        RS_JOBS="$(sysctl -n hw.ncpu)"
    else
        RS_JOBS="$(nproc)"
    fi
    # a Pi runs out of memory long before it runs out of cores
    if [ "$RS_IS_PI" = 1 ] && [ "$RS_JOBS" -gt 2 ]; then
        RS_JOBS=2
    fi
}

# Homebrew's compilers do not look in /opt/homebrew by themselves
setup_build_env() {
    if [ "$RS_OS" = macos ] && command -v brew >/dev/null 2>&1; then
        local prefix
        prefix="$(brew --prefix)"
        export CPATH="$prefix/opt/curl/include:$prefix/include${CPATH:+:$CPATH}"
        export LIBRARY_PATH="$prefix/opt/curl/lib:$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
        local pc="$prefix/lib/pkgconfig"
        local keg
        for keg in libpq mongo-c-driver libsodium libwebsockets curl; do
            [ -d "$prefix/opt/$keg/lib/pkgconfig" ] && pc="$prefix/opt/$keg/lib/pkgconfig:$pc"
        done
        export PKG_CONFIG_PATH="$pc${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        # emscripten's closure compiler needs java
        command -v java >/dev/null 2>&1 || export PATH="$prefix/opt/openjdk/bin:$PATH"
    fi
    # emsdk installed by debian/setup.sh
    if [ -f "$HOME/emsdk/emsdk_env.sh" ] && ! command -v emcc >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        . "$HOME/emsdk/emsdk_env.sh" >/dev/null 2>&1 || true
    fi
}

need() {
    local missing=0 cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "missing command: $cmd"
            missing=1
        fi
    done
    [ "$missing" = 0 ] || die "run scripts/$RS_OS/setup.sh first"
}

# ----------------------------------------------------------------- servers

# parallel arrays filled from servers.conf
SV_NAME=()
SV_KIND=()
SV_ARG=()
SV_PORT=()
SV_HOST=()

load_servers() {
    SV_NAME=()
    SV_KIND=()
    SV_ARG=()
    SV_PORT=()
    SV_HOST=()
    local name kind arg port host
    while read -r name kind arg port host; do
        case "$name" in '' | '#'*) continue ;; esac
        SV_NAME+=("$name")
        SV_KIND+=("$kind")
        SV_ARG+=("$arg")
        SV_PORT+=("$port")
        SV_HOST+=("$host")
    done <"$RS_COMMON_DIR/servers.conf"
}

# value of KEY in a KEY=VALUE file (empty if absent)
env_get() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

# sets KEY=VALUE in a file (adds it when missing); keeps the rest as it is
env_set() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" -F= '
        $1 == k { print k "=" v; done = 1; next }
        { print }
        END { if (!done) print k "=" v }' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# -------------------------------------------------------------------- secrets
# One file per server plus common.env and master.env, all outside the repo.
# Existing files are never overwritten.

write_if_missing() {
    local file="$1"
    if [ -f "$file" ]; then
        return 0
    fi
    log "creating template $file"
    if [ "$RS_DRY_RUN" = 1 ]; then
        return 0
    fi
    cat >"$file"
    chmod 600 "$file"
}

# <repo>/secrets/*.env is where you edit the values (it is git-ignored). Every
# run copies those files into the real secrets directory (~/.rysteria-secrets,
# mode 700/600), which is what the builds read.
secrets_import() {
    local src="$RS_ROOT/secrets" f
    [ -d "$src" ] || return 0
    if [ "$RS_DRY_RUN" != 1 ]; then
        umask 077
        mkdir -p "$RS_SECRETS_DIR"
        chmod 700 "$RS_SECRETS_DIR"
    fi
    for f in "$src"/*.env; do
        [ -f "$f" ] || continue
        log "importing $(basename "$f") from $src"
        if [ "$RS_DRY_RUN" = 1 ]; then
            printf '[dry-run] cp %q %q\n' "$f" "$RS_SECRETS_DIR/"
        else
            cp -f "$f" "$RS_SECRETS_DIR/$(basename "$f")"
            chmod 600 "$RS_SECRETS_DIR/$(basename "$f")"
        fi
    done
}

secrets_init() {
    load_servers
    log "secrets directory $RS_SECRETS_DIR"
    if [ "$RS_DRY_RUN" = 1 ]; then
        printf '[dry-run] mkdir -p %q; chmod 700\n' "$RS_SECRETS_DIR"
    else
        umask 077
        mkdir -p "$RS_SECRETS_DIR"
        chmod 700 "$RS_SECRETS_DIR"
    fi
    secrets_import
    local domain="${DOMAIN:-parshwa.blog}"

    write_if_missing "$RS_SECRETS_DIR/common.env" <<EOF
# Deployment settings shared by the scripts (not given to any server as is).
DOMAIN=$domain
# 1 = run cloudflared after the servers are up (setup.sh installs it)
CLOUDFLARED_ENABLED=0
# 1 = run.sh also starts the mail server (the "email system" folder) and exposes
# its webmail through the tunnel. scripts/<os>/mail.sh setup turns this on.
MAIL_ENABLED=0
TUNNEL_NAME=rysteria
# the credentials json that "cloudflared tunnel create" wrote
TUNNEL_CREDENTIALS=$HOME/.cloudflared/rysteria.json
# how game servers and gardn reach the master from the same machine
MASTER_HOST=127.0.0.1
MASTER_PORT=55554
MASTER_TLS=0
# baked into the clients at build time
CLIENT_API_URL=https://api-game.$domain/
GARDN_WS_URL=wss://game.$domain/gardn/
EOF

    local master_example="$RS_ROOT/rrolf/MasterServer/c/.env.example"
    if [ ! -f "$RS_SECRETS_DIR/master.env" ] && [ "$RS_DRY_RUN" != 1 ]; then
        log "creating template $RS_SECRETS_DIR/master.env (secrets generated)"
        cat "$master_example" >"$RS_SECRETS_DIR/master.env"
        chmod 600 "$RS_SECRETS_DIR/master.env"
        env_set "$RS_SECRETS_DIR/master.env" SERVER_SECRET "$(random_secret)"
        env_set "$RS_SECRETS_DIR/master.env" TOKEN_SECRET_1 "$(random_secret)"
        env_set "$RS_SECRETS_DIR/master.env" TOKEN_SECRET_2 "$(random_secret)"
        env_set "$RS_SECRETS_DIR/master.env" OTP_PEPPER "$(random_secret)"
        env_set "$RS_SECRETS_DIR/master.env" ALLOWED_ORIGINS "https://game.$domain"
        env_set "$RS_SECRETS_DIR/master.env" CLIENT_URL "https://game.$domain/"
        env_set "$RS_SECRETS_DIR/master.env" DISCORD_REDIRECT_URI "https://api-game.$domain/oauth/discord/callback"
        warn "edit $RS_SECRETS_DIR/master.env: database URI and Discord keys"
    fi

    mail_secrets_init "$domain"

    local i name kind arg port
    for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
        name="${SV_NAME[$i]}"
        kind="${SV_KIND[$i]}"
        arg="${SV_ARG[$i]}"
        port="${SV_PORT[$i]}"
        case "$kind" in
        master) continue ;; # master.env is the whole file
        rrolf)
            write_if_missing "$RS_SECRETS_DIR/$name.env" <<EOF
# $name: values for this game server only. The mode and port ($port) are
# compiled in. SERVER_SECRET and the master address are added from master.env /
# common.env when the build copies this file to builds/.
EOF
            ;;
        gardn)
            write_if_missing "$RS_SECRETS_DIR/$name.env" <<EOF
# $name: server specific values only (the shared secret comes from master.env).
EOF
            ;;
        edge)
            write_if_missing "$RS_SECRETS_DIR/$name.env" <<EOF
# $name: public web server for the rrolf client and gardn.
EDGE_PORT=$port
EOF
            ;;
        esac
    done
}

# mail.env: settings for the mail server in "email system/". mail.sh copies the
# parts docker compose needs into "email system/.env".
mail_secrets_init() {
    local domain="$1"
    write_if_missing "$RS_SECRETS_DIR/mail.env" <<EOF
# Mail server. Fill this in, then run scripts/<os>/mail.sh setup
MAIL_DOMAIN=$domain
MAIL_HOSTNAME=mail.$domain
# blank = the public IPv4 address is detected automatically
SERVER_IP=
# Let's Encrypt writes here about certificate problems
CERT_EMAIL=
# Cloudflare API token with Zone > DNS > Edit for $domain (creates the DNS records)
CLOUDFLARE_API_TOKEN=
# webmail is served at https://<WEBMAIL_HOST>.$domain through the tunnel
WEBMAIL_HOST=webmail
WEBMAIL_PORT=8989
TZ=UTC
# mailboxes to create, space separated address:password, for example
# MAIL_ACCOUNTS=you@$domain:change-me noreply@$domain:change-me
MAIL_ACCOUNTS=
EOF
}

check_secrets_ready() {
    [ -d "$RS_SECRETS_DIR" ] || die "no $RS_SECRETS_DIR: run scripts/$RS_OS/setup.sh first"
    [ -f "$RS_SECRETS_DIR/master.env" ] || die "missing $RS_SECRETS_DIR/master.env"
    local db_type uri
    db_type="$(env_get "$RS_SECRETS_DIR/master.env" DB_TYPE)"
    case "$db_type" in
    postgres) uri="$(env_get "$RS_SECRETS_DIR/master.env" POSTGRES_URI)" ;;
    mongo) uri="$(env_get "$RS_SECRETS_DIR/master.env" MONGO_URI)" ;;
    *) die "DB_TYPE in master.env must be postgres or mongo" ;;
    esac
    case "$uri" in
    '' | *user:password*)
        [ "$RS_DRY_RUN" = 1 ] || die "set the $db_type connection string in $RS_SECRETS_DIR/master.env"
        ;;
    esac
}

common_get() { env_get "$RS_SECRETS_DIR/common.env" "$1"; }
mail_get() { env_get "$RS_SECRETS_DIR/mail.env" "$1"; }
mail_enabled() { [ "$(common_get MAIL_ENABLED)" = 1 ]; }

# Writes <dest>/.env for one server. Servers only receive what they need: game
# servers and gardn get the shared secret and the master address, never the
# database credentials, token secrets or Discord keys.
compose_env() {
    local name="$1" kind="$2" dest="$3"
    local env_file="$dest/.env"
    if [ "$RS_DRY_RUN" = 1 ]; then
        printf '[dry-run] compose %s/.env for %s\n' "$dest" "$name"
        return 0
    fi
    (
        umask 077
        case "$kind" in
        master)
            cat "$RS_SECRETS_DIR/master.env" >"$env_file"
            ;;
        rrolf)
            {
                echo "SERVER_SECRET=$(env_get "$RS_SECRETS_DIR/master.env" SERVER_SECRET)"
                echo "RR_API_HOST=$(common_get MASTER_HOST)"
                echo "RR_API_PORT=$(common_get MASTER_PORT)"
                echo "RR_API_TLS=$(common_get MASTER_TLS)"
                cat "$RS_SECRETS_DIR/$name.env"
            } >"$env_file"
            ;;
        gardn)
            local scheme=http
            [ "$(common_get MASTER_TLS)" = 1 ] && scheme=https
            {
                echo "SERVER_SECRET=$(env_get "$RS_SECRETS_DIR/master.env" SERVER_SECRET)"
                echo "MASTER_URL=$scheme://$(common_get MASTER_HOST):$(common_get MASTER_PORT)"
                cat "$RS_SECRETS_DIR/$name.env"
            } >"$env_file"
            ;;
        edge)
            {
                cat "$RS_SECRETS_DIR/$name.env"
                echo "CLIENT_DIR=$RS_TARGET/rrolf-client"
                echo "GARDN_PORT=$(server_port gardn)"
            } >"$env_file"
            ;;
        esac
    )
    chmod 600 "$env_file"
}

server_port() {
    local i
    for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
        if [ "${SV_KIND[$i]}" = "$1" ] || [ "${SV_NAME[$i]}" = "$1" ]; then
            echo "${SV_PORT[$i]}"
            return 0
        fi
    done
}

# ------------------------------------------------------------------ processes

pid_file() { echo "$RS_RUN/$1.pid"; }

is_running() {
    local file pid
    file="$(pid_file "$1")"
    [ -f "$file" ] || return 1
    pid="$(cat "$file" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

any_running() {
    [ -d "$RS_RUN" ] || return 1
    local f name
    for f in "$RS_RUN"/*.pid; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .pid)"
        is_running "$name" && return 0
    done
    return 1
}
