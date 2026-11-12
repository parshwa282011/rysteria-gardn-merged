#!/usr/bin/env bash
# Builds the website of both games (the rrolf client, the gardn client and the pages) into one folder
# of static files, laid out the way scripts/common/edge.js serves them, for the Cloudflare Worker
# in cloudflare/. The GitHub Action .github/workflows/deploy-web.yml runs it, and so can you.
#
# Usage: scripts/build-web.sh [--out DIR] [--work DIR] [--no-icons]
#   --out DIR    where the site goes (default cloudflare/dist, emptied first)
#   --work DIR   cmake build folders (default .web-build)
#   --no-icons   do not make the petal pictures of the stats pages (they need Chrome)
# Needs: emscripten (emcc), cmake, node, git, and both submodules (git submodule update --init).
# Settings (environment, else secrets/common.env, else the defaults):
#   CLIENT_API_URL  the master the rrolf client asks     (https://api-game.<domain>/)
#   GARDN_WS_URL    where the gardn client connects      (wss://game.<domain>/gardn/)
#   DOMAIN          only for those two defaults          (parshwa.blog)
# The gardn version hash is the commit time of gardn (common/build-hash.sh), so this client
# talks to the servers that scripts/<os>/build.sh builds from the same commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/cloudflare/dist"
work="$root/.web-build"
icons=1
abs() { mkdir -p "$(dirname "$1")" && printf '%s/%s' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }
while [ $# -gt 0 ]; do
    case "$1" in
    --out) shift; out="$(abs "${1:?--out needs a folder}")" ;;
    --work) shift; work="$(abs "${1:?--work needs a folder}")" ;;
    --no-icons) icons=0 ;;
    -h | --help) sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
for tool in cmake emcc node git; do command -v "$tool" >/dev/null || die "$tool is not installed"; done
[ -f "$root/rrolf/Client/CMakeLists.txt" ] && [ -f "$root/gardn/Client/CMakeLists.txt" ] ||
    die "the submodules are empty: git submodule update --init --recursive"

env_get() { [ -f "$1" ] && { grep -E "^$2=" "$1" | head -n1 | cut -d= -f2- || true; } || true; }
common="$root/secrets/common.env"
[ -f "$common" ] || common="${SECRETS_DIR:-$HOME/.rysteria-secrets}/common.env"
domain="${DOMAIN:-$(env_get "$common" DOMAIN)}"; domain="${domain:-parshwa.blog}"
api_url="${CLIENT_API_URL:-$(env_get "$common" CLIENT_API_URL)}"; api_url="${api_url:-https://api-game.$domain/}"
ws_url="${GARDN_WS_URL:-$(env_get "$common" GARDN_WS_URL)}"; ws_url="${ws_url:-wss://game.$domain/gardn/}"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
hash="$("$root/scripts/common/build-hash.sh" "$root")"
echo "master $api_url, gardn websocket $ws_url, gardn version $hash"

say "rrolf client"
cmake -S "$root/rrolf/Client" -B "$work/rrolf-client" -UPDEV -DWASM_BUILD=1 -DDEBUG_BUILD=0 \
    -DCMAKE_C_FLAGS=-DEMSCRIPTEN "-DRR_API_URL=$api_url"
cmake --build "$work/rrolf-client" -j "$jobs"

say "gardn client"
cmake -S "$root/gardn/Client" -B "$work/gardn-client" -DDEBUG=0 -DUSE_CODEPOINT_LEN=1 \
    "-DWS_URL=$ws_url" "-DVERSION_HASH=$hash"
cmake --build "$work/gardn-client" -j "$jobs"

say "assembling $out"
rm -rf "$out"
mkdir -p "$out/gardn"
# the rrolf site: its page, fonts, logo, platform.js and the other pages, then the built files over them
cp -R "$root/rrolf/Client/public/." "$out/"
cp "$work/rrolf-client/rrolf-client.js" "$work/rrolf-client/rrolf-client.wasm" "$out/"
# gardn: its page asks for the version it was built with
cp "$root/gardn/Client/public/index.html" "$out/gardn/index.html"
cp "$work/gardn-client/gardn-client.js" "$work/gardn-client/gardn-client.wasm" "$out/gardn/"
sed -i.bak "s/const versionHash = '0';/const versionHash = '$hash';/" "$out/gardn/index.html" && rm -f "$out/gardn/index.html.bak"
grep -q "const versionHash = '$hash';" "$out/gardn/index.html" || die "the gardn page has no versionHash line to set"
# the extra names of edge.js's PAGES (the Worker serves /name from name.html)
cp "$out/login.html" "$out/signup.html"
cp "$out/stats.html" "$out/status.html"
cp "$out/privacy.html" "$out/privacy-policy.html"
cp "$out/terms.html" "$out/terms-of-service.html"
cp "$out/leaderboard.html" "$out/gardn/leaderboard.html"
cp "$out/gardn-stats.html" "$out/gardn/stats.html"

if [ "$icons" = 1 ]; then
    say "petal icons for the stats pages (needs Chrome; the pages show plain tiles without them)"
    node "$root/scripts/gen-icons.mjs" --rrolf "$out" --gardn "$out/gardn" --out "$out/icons" ||
        echo "warning: no petal icons this time"
fi

echo
du -sh "$out" | sed 's/\t/  /'
find "$out" -type f | wc -l | sed 's/^ *//; s/$/ files/'
