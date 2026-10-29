#!/usr/bin/env bash
# Debian / Ubuntu / Raspberry Pi OS (also WSL Ubuntu): installs the build
# dependencies with apt, Node.js LTS and emsdk when the system ones are too old,
# updates the checkout and creates ~/.rysteria-secrets/ with .env templates.
# Databases are not installed: PostgreSQL / MongoDB are yours to provide.
#
# Usage: scripts/debian/setup.sh [--dry-run] [--no-emscripten]
#   --no-emscripten   server-only machine: skip emsdk (build with --skip-clients)

source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
parse_common_flags "$@"
with_emscripten=1
for arg in ${RS_ARGS[@]+"${RS_ARGS[@]}"}; do
    case "$arg" in
    --no-emscripten) with_emscripten=0 ;;
    *) die "unknown option $arg" ;;
    esac
done
detect_platform
[ "$RS_OS" = debian ] || die "this is the Debian script, you are on $RS_OS"

SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

log "apt packages"
run $SUDO apt-get update
run $SUDO apt-get install -y build-essential clang cmake pkg-config git curl ca-certificates \
    python3 openssl default-jre-headless \
    libwebsockets-dev libcurl4-openssl-dev libsodium-dev libpq-dev libmongoc-dev

# the gardn host uses global fetch: Node 18 or newer
node_major=0
command -v node >/dev/null 2>&1 && node_major="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$node_major" -lt 18 ]; then
    log "Node.js LTS (NodeSource), the system one is too old"
    if [ "$RS_DRY_RUN" = 1 ]; then
        echo "[dry-run] curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO -E bash -; apt-get install -y nodejs"
    else
        curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO -E bash -
        $SUDO apt-get install -y nodejs
    fi
fi

if [ "$with_emscripten" = 1 ] && ! command -v emcc >/dev/null 2>&1 && [ ! -d "$HOME/emsdk" ]; then
    log "emsdk (WebAssembly compiler) into ~/emsdk"
    if [ "$RS_IS_PI" = 1 ]; then
        warn "building the clients on a Pi is slow; consider --no-emscripten and building them elsewhere"
    fi
    run git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
    run "$HOME/emsdk/emsdk" install latest
    run "$HOME/emsdk/emsdk" activate latest
fi

if [ "$(env_get "$RS_SECRETS_DIR/common.env" CLOUDFLARED_ENABLED)" = 1 ] && ! command -v cloudflared >/dev/null 2>&1; then
    log "cloudflared"
    case "$RS_ARCH" in
    amd64) deb=cloudflared-linux-amd64.deb ;;
    arm64) deb=cloudflared-linux-arm64.deb ;;
    armhf) deb=cloudflared-linux-arm.deb ;;
    *) die "no cloudflared package for $RS_ARCH" ;;
    esac
    if [ "$RS_DRY_RUN" = 1 ]; then
        echo "[dry-run] download $deb from github.com/cloudflare/cloudflared and dpkg -i"
    else
        tmp="$(mktemp -d)"
        curl -fsSL -o "$tmp/$deb" "https://github.com/cloudflare/cloudflared/releases/latest/download/$deb"
        $SUDO dpkg -i "$tmp/$deb"
        rm -rf "$tmp"
    fi
fi

"$RS_COMMON_DIR/sync-repo.sh"
secrets_init
log "setup done. Next: edit $RS_SECRETS_DIR/master.env, then scripts/debian/build.sh"
