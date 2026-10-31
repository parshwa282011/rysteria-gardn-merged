#!/usr/bin/env bash
# Builds every server (and both clients) for this machine into
#   builds/<os>-<arch>/<server>/        one folder per server, each with its .env
# Intermediate files go to builds/.work/ and disappear with clean-builds.sh.
#
# Usage: scripts/<os>/build.sh [--skip-clients] [--dry-run] [--force]
#   --skip-clients   do not build the WASM clients / gardn (no emscripten needed)
# Source code is never modified.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

skip_clients=0
parse_common_flags "$@"
for arg in ${RS_ARGS[@]+"${RS_ARGS[@]}"}; do
    case "$arg" in
    --skip-clients) skip_clients=1 ;;
    *) die "unknown option $arg" ;;
    esac
done

detect_platform
setup_build_env
load_servers
secrets_import
check_secrets_ready

need cmake git
[ "$skip_clients" = 1 ] || need emcc node npm

log "building for $RS_OS-$RS_ARCH with $RS_JOBS jobs into $RS_TARGET"
run mkdir -p "$RS_TARGET" "$RS_WORK" "$RS_RUN"

# one version per build: gardn clients and servers of different builds refuse
# each other, so a stale browser tab reloads instead of misbehaving
BUILD_HASH="$(date +%s)"

has_kind() {
    local i
    for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
        [ "${SV_KIND[$i]}" = "$1" ] && return 0
    done
    return 1
}

cmake_build() { # <source dir> <work dir> <cmake args...>
    local src="$1" work="$2"
    shift 2
    run cmake -S "$src" -B "$work" "$@"
    run cmake --build "$work" -j "$RS_JOBS"
}

# ------------------------------------------------------------------- master
if has_kind master; then
    log "master server (C)"
    cmake_build "$RS_ROOT/rrolf/MasterServer/c" "$RS_WORK/master" -DCMAKE_BUILD_TYPE=Release
fi

# ------------------------------------------------------------- rrolf servers
# the mode (default / pvp / garden / ctf) is compiled in, so every rrolf server
# is its own build. PDEV (the give-petals PIN of the old scripts) is never enabled.
for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
    [ "${SV_KIND[$i]}" = rrolf ] || continue
    # several options in one column are separated by commas: -DPVP=1,-DPDEV=1
    extra=()
    [ "${SV_ARG[$i]}" = "-" ] || IFS=',' read -ra extra <<<"${SV_ARG[$i]}"
    log "${SV_NAME[$i]} (rrolf game server ${SV_ARG[$i]}, port ${SV_PORT[$i]})"
    cmake_build "$RS_ROOT/rrolf/Server" "$RS_WORK/${SV_NAME[$i]}" -DDEBUG_BUILD=0 ${extra[@]+"${extra[@]}"}
done

# ------------------------------------------------------------------- clients
CLIENT_API_URL="$(common_get CLIENT_API_URL)"
GARDN_WS_URL="$(common_get GARDN_WS_URL)"
if [ "$skip_clients" = 0 ]; then
    log "rrolf client (WASM), master at $CLIENT_API_URL"
    cmake_build "$RS_ROOT/rrolf/Client" "$RS_WORK/rrolf-client" \
        -DWASM_BUILD=1 -DDEBUG_BUILD=0 -DCMAKE_C_FLAGS=-DEMSCRIPTEN "-DRR_API_URL=$CLIENT_API_URL"

    if has_kind gardn; then
        log "gardn server (WebAssembly on Node)"
        cmake_build "$RS_ROOT/gardn/Server" "$RS_WORK/gardn-server" \
            -DDEBUG=0 -DWASM_SERVER=1 -DGENERAL_SPATIAL_HASH=1 -DUSE_CODEPOINT_LEN=1 \
            "-DVERSION_HASH=$BUILD_HASH" "-DSERVER_PORT=$(server_port gardn)"
        log "gardn client (WASM), websocket $GARDN_WS_URL"
        cmake_build "$RS_ROOT/gardn/Client" "$RS_WORK/gardn-client" \
            -DDEBUG=0 -DUSE_CODEPOINT_LEN=1 "-DWS_URL=$GARDN_WS_URL" "-DVERSION_HASH=$BUILD_HASH"
    fi
fi

# ------------------------------------------------------ assemble the folders
log "assembling server folders"
for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
    name="${SV_NAME[$i]}"
    kind="${SV_KIND[$i]}"
    dest="$RS_TARGET/$name"
    run mkdir -p "$dest"
    case "$kind" in
    master)
        run cp "$RS_WORK/master/rysteria-master" "$dest/"
        ;;
    rrolf)
        run cp "$RS_WORK/$name/rrolf-server" "$dest/"
        ;;
    gardn)
        if [ "$skip_clients" = 0 ]; then
            run cp "$RS_WORK/gardn-server/gardn-server.js" "$RS_WORK/gardn-server/gardn-server.wasm" "$dest/"
            run cp "$RS_WORK/gardn-client/gardn-client.js" "$RS_WORK/gardn-client/gardn-client.wasm" "$dest/"
            run cp "$RS_ROOT/gardn/Client/public/index.html" "$dest/index.html"
            if [ "$RS_DRY_RUN" != 1 ]; then
                # the page asks for the version it was built with
                sed "s/const versionHash = '0';/const versionHash = '$BUILD_HASH';/" \
                    "$dest/index.html" >"$dest/index.html.new" && mv "$dest/index.html.new" "$dest/index.html"
            fi
            # the host script needs the ws package
            if [ ! -d "$dest/node_modules/ws" ]; then
                if [ "$RS_DRY_RUN" = 1 ]; then
                    echo "[dry-run] npm install ws in $dest"
                else
                    (cd "$dest" && printf '{"name":"gardn-host","private":true}' >package.json &&
                        npm install --omit=dev --no-audit --no-fund ws@8)
                fi
            fi
        fi
        ;;
    edge)
        run cp "$RS_COMMON_DIR/edge.js" "$dest/edge.js"
        ;;
    sync)
        if sync_enabled; then
            need node npm
            for f in syncd.js store.js util.js package.json package-lock.json; do
                run cp "$RS_ROOT/dual-server-syncing/$f" "$dest/"
            done
            if [ "$RS_DRY_RUN" = 1 ]; then
                echo "[dry-run] npm install pg in $dest"
            elif [ ! -d "$dest/node_modules/pg" ]; then
                (cd "$dest" && npm install --omit=dev --no-audit --no-fund)
            fi
        fi
        ;;
    esac
done

if [ "$skip_clients" = 0 ]; then
    # the page, fonts, logo and platform.js come from Client/public; the built
    # rrolf-client.js / .wasm replace the copies that may sit there from old builds
    run mkdir -p "$RS_TARGET/rrolf-client"
    run cp -R "$RS_ROOT/rrolf/Client/public/." "$RS_TARGET/rrolf-client/"
    run cp "$RS_WORK/rrolf-client/rrolf-client.js" "$RS_WORK/rrolf-client/rrolf-client.wasm" "$RS_TARGET/rrolf-client/"
fi

# .env last: each file is composed from ~/.rysteria-secrets/ after its folder exists
log "writing .env files from $RS_SECRETS_DIR"
for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
    compose_env "${SV_NAME[$i]}" "${SV_KIND[$i]}" "$RS_TARGET/${SV_NAME[$i]}"
done

log "build complete: $RS_TARGET"
