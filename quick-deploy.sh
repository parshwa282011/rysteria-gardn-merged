#!/usr/bin/env bash
# Deploys what is committed here to every machine in secrets/nodes.conf, in the
# order that works, from this computer:
#
#   1. checks that nothing is uncommitted and pushes the commits (rrolf and gardn
#      first, then this repository, which points at them)
#   2. stops the backup machines (the Pi), so that their syncd can not take over
#      while the main one is restarted
#   3. on every machine: git fetch, reset --hard to origin/main (what was changed
#      there by hand is saved to ~/deploy-discarded-*.patch first) and the
#      submodules to the commits this repository points at
#   4. builds on every machine at the same time. The first machine in nodes.conf
#      builds everything (it has emscripten), the others with --skip-clients
#   5. refuses to go on if a build has PDEV in it (the give-petals cheat)
#   6. restarts the first machine (c1)
#   7. copies its web clients and gardn to the others (scripts/sync-clients.sh)
#      and starts them, one after another (the Pi)
#   8. checks the public pages and that every machine runs the same commit
#
# With --leave-off the main machine is stopped as well, nothing is started again (not
# even the Pi) and the pages are not checked: the machines end up updated, built and
# off, with the database still running.
#
# Usage: ./quick-deploy.sh [--dry-run] [--leave-off] [--allow-dirty] [--key FILE] [--no-push]
#   --dry-run      only print what would be done, change nothing
#   --leave-off    update and build everything, but leave every server stopped
#   --allow-dirty  deploy the commits even though files here are modified
#   --key FILE     ssh key for the machines (default ~/.ssh/id_c1 if it exists)
#   --no-push      do not push, but stop if something is not pushed yet
#
# The machines, their ssh targets and folders come from secrets/nodes.conf
# (name os lan ssh repo). DEPLOY_URLS (space separated) replaces the pages that
# step 8 checks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
ALLOW_DIRTY=0
PUSH=1
OFF=0
KEY=""
[ -f "$HOME/.ssh/id_c1" ] && KEY="$HOME/.ssh/id_c1"
while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) DRY=1 ;;
    --leave-off) OFF=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --no-push) PUSH=0 ;;
    --key) shift; KEY="${1:?--key needs a file}" ;;
    -h | --help) sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30)
[ -n "$KEY" ] && SSH_OPTS+=(-i "$KEY" -o IdentitiesOnly=yes)

# ------------------------------------------------------------------- machines
NODES="$ROOT/secrets/nodes.conf"
[ -f "$NODES" ] || NODES="$ROOT/dual-server-syncing/nodes.conf"
[ -f "$NODES" ] || die "no secrets/nodes.conf"
N=0
N_NAME=(); N_OS=(); N_SSH=(); N_REPO=()
while read -r name os _lan target repo _rest; do
    case "$name" in '' | '#'*) continue ;; esac
    [ "$target" = "-" ] && continue
    case "$os" in macos | debian) ;; *) die "$name: os \"$os\" can not be deployed from here (macos or debian)" ;; esac
    N_NAME[$N]="$name"; N_OS[$N]="$os"; N_SSH[$N]="$target"; N_REPO[$N]="$repo"
    N=$((N + 1))
done <"$NODES"
[ "$N" -ge 1 ] || die "$NODES lists no machine with an ssh target"

# one command on machine i
rsh() { local i=$1; shift; ssh "${SSH_OPTS[@]}" "${N_SSH[$i]}" "$@"; }
# a script on stdin on machine i, run by bash with REPO set (and OSDIR = macos or debian)
rscript() {
    local i=$1; shift
    # the script travels as an argument, so that what it starts can not read it
    # from stdin
    local b64
    b64="$(base64 | tr -d '\n')"
    ssh -n "${SSH_OPTS[@]}" "${N_SSH[$i]}" \
        "REPO='${N_REPO[$i]}' OSDIR='${N_OS[$i]}' $* bash -l -c \"\$(printf %s '$b64' | base64 -d)\""
}
# like rscript, but the script is only printed with --dry-run
act() { # <machine> <what it does> [VAR=value ...], script on stdin
    local i=$1 what=$2; shift 2
    if [ "$DRY" = 1 ]; then echo "   [dry run] ${N_NAME[$i]}: $what"; cat >/dev/null; return 0; fi
    echo "   ${N_NAME[$i]}: $what"
    rscript "$i" "$@"
}

# --------------------------------------------------------------- 1. local state
say "1. this computer"
cd "$ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = main ] || die "this repository is on \"$BRANCH\", the machines run main"
if [ "$ALLOW_DIRTY" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git status --short --untracked-files=no
    die "uncommitted changes (above). Commit them, or --allow-dirty to deploy only what is committed"
fi
ahead() { # <folder>: commits not pushed to its upstream
    git -C "$1" fetch -q 2>/dev/null || true
    git -C "$1" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?"
}
# the submodules first: the parent must not point at a commit nobody can fetch
for d in rrolf gardn .; do
    n="$(ahead "$d")"
    [ "$n" != "?" ] || die "$d has no upstream branch to push to"
    if [ "$n" != 0 ]; then
        if [ "$PUSH" = 0 ] || [ "$DRY" = 1 ]; then
            [ "$DRY" = 1 ] && echo "   [dry run] would push $n commit(s) of $d" ||
                die "$d has $n commit(s) that are not pushed (leave out --no-push)"
        else
            echo "   pushing $n commit(s) of $d"
            git -C "$d" push -q
        fi
    fi
done
WANT="$(git rev-parse HEAD)"
echo "   deploying $(git log --oneline -1)"
echo "   machines: $(for ((i = 0; i < N; i++)); do printf '%s ' "${N_NAME[$i]}"; done)(first = main one)"

# ----------------------------------------------------- 2. stop the backup machines
say "2. stopping the backup machines, so that none takes over"
for ((i = 1; i < N; i++)); do
    act "$i" "stop" <<'EOF'
cd "$REPO" && scripts/$OSDIR/stop.sh 2>&1 | tail -3 || true
EOF
done
[ "$N" -gt 1 ] || echo "   (only one machine)"
if [ "$OFF" = 1 ]; then
    act 0 "stop (--leave-off)" <<'EOF'
cd "$REPO" && scripts/$OSDIR/stop.sh 2>&1 | tail -3 || true
EOF
fi

# ---------------------------------------------------------------- 3. update
say "3. updating the code on every machine"
update_machine() {
    act "$1" "fetch, reset to origin/main, submodules" WANT="$WANT" <<'EOF'
set -euo pipefail
cd "$REPO"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    f="$HOME/deploy-discarded-$(date +%Y%m%d-%H%M%S).patch"
    { git diff; git submodule foreach --quiet 'git diff' || true; } >"$f"
    echo "   changes made by hand here were saved to $f"
fi
git fetch -q origin
git reset -q --hard origin/main
git submodule sync -q
git submodule update --init --force -q
have="$(git rev-parse HEAD)"
[ "$have" = "$WANT" ] || { echo "   this machine is at $have, not $WANT (is it pushed?)"; exit 1; }
git log --oneline -1
EOF
}
pids=(); rc=0
for ((i = 0; i < N; i++)); do
    update_machine "$i" >"${TMPDIR:-/tmp}/quick-deploy-update-$i.log" 2>&1 &
    pids[$i]=$!
done
for ((i = 0; i < N; i++)); do
    wait "${pids[$i]}" || rc=1
    cat "${TMPDIR:-/tmp}/quick-deploy-update-$i.log"
done
[ "$rc" = 0 ] || die "updating failed (the backups are stopped: scripts/<os>/run.sh on them starts them again)"

# ---------------------------------------------------------------- 4. build
say "4. building (the first machine everything, the others without the web clients)"
for ((i = 0; i < N; i++)); do
    flags="--skip-clients"; [ "$i" = 0 ] && flags=""
    act "$i" "build ${flags:-(everything)}" FLAGS="$flags" <<'EOF'
cd "$REPO"
rm -f /tmp/quick-deploy-build.done
nohup bash -c "scripts/$OSDIR/build.sh $FLAGS > /tmp/quick-deploy-build.log 2>&1; echo \$? > /tmp/quick-deploy-build.done" >/dev/null 2>&1 </dev/null &
EOF
done
if [ "$DRY" = 0 ]; then
    left=$N
    done_flag=()
    for ((i = 0; i < N; i++)); do done_flag[$i]=0; done
    while [ "$left" -gt 0 ]; do
        sleep 20
        for ((i = 0; i < N; i++)); do
            [ "${done_flag[$i]}" = 0 ] || continue
            code="$(rsh "$i" 'cat /tmp/quick-deploy-build.done 2>/dev/null' || true)"
            if [ -z "$code" ]; then
                echo "   ${N_NAME[$i]}: $(rsh "$i" 'tail -1 /tmp/quick-deploy-build.log' 2>/dev/null | cut -c1-100)"
                continue
            fi
            done_flag[$i]=1; left=$((left - 1))
            if [ "$code" != 0 ]; then
                rsh "$i" 'tail -30 /tmp/quick-deploy-build.log' || true
                die "the build on ${N_NAME[$i]} failed (exit $code), log: ${N_NAME[$i]}:/tmp/quick-deploy-build.log. Nothing was restarted"
            fi
            echo "   ${N_NAME[$i]}: build done"
        done
    done
fi

# ---------------------------------------------------------------- 5. PDEV
say "5. no PDEV in any build"
for ((i = 0; i < N; i++)); do
    act "$i" "look for PDEV in the cmake caches" <<'EOF'
cd "$REPO"
found="$(ls builds/*/PDEV-BUILD 2>/dev/null || true) $(grep -l '^PDEV' builds/.work/*/*/CMakeCache.txt 2>/dev/null || true)"
found="${found# }"; found="${found% }"
if [ -n "$found" ]; then echo "   PDEV is set in: $found"; exit 1; fi
echo "   none"
EOF
done

# ---------------------------------------------------------------- 6. restart the main machine
if [ "$OFF" = 0 ]; then
    say "6. restarting ${N_NAME[0]}"
    act 0 "stop, then run" <<'EOF'
cd "$REPO"
scripts/$OSDIR/stop.sh 2>&1 | tail -3
scripts/$OSDIR/run.sh 2>&1 | tail -4
EOF
else
    say "6. ${N_NAME[0]} stays off (--leave-off)"
fi

# ---------------------------------------------------------------- 7. the others
for ((i = 1; i < N; i++)); do
    say "7. ${N_NAME[$i]}: web clients and gardn from ${N_NAME[0]}$([ "$OFF" = 1 ] || echo ", then start")"
    if [ "$DRY" = 1 ]; then
        echo "   [dry run] scripts/sync-clients.sh ${N_NAME[0]} ${N_NAME[$i]}"
    else
        "$ROOT/scripts/sync-clients.sh" "${N_NAME[0]}" "${N_NAME[$i]}" ${KEY:+"$KEY"} 2>&1 | tail -3
    fi
    if [ "$OFF" = 0 ]; then
        act "$i" "run" <<'EOF'
cd "$REPO"
scripts/$OSDIR/run.sh 2>&1 | tail -4
EOF
    fi
done

# ---------------------------------------------------------------- 8. check
say "8. checking"
if [ "$DRY" = 1 ]; then
    echo "   [dry run] would check the pages, sync status and that every machine runs $WANT"
    exit 0
fi
[ "$OFF" = 1 ] || sleep 15
bad=0
for ((i = 0; i < N; i++)); do
    have="$(rsh "$i" "cd '${N_REPO[$i]}' && git rev-parse HEAD" 2>/dev/null || echo ?)"
    if [ "$have" = "$WANT" ]; then echo "   ${N_NAME[$i]}: runs ${WANT:0:7}"; else echo "   ${N_NAME[$i]}: runs ${have:0:7}, not ${WANT:0:7}"; bad=1; fi
done
URLS="${DEPLOY_URLS:-https://game.parshwa.blog/ https://game.parshwa.blog/leaderboard https://game.parshwa.blog/stats https://api-game.parshwa.blog/leaderboard https://game.parshwa.blog/gardn/}"
[ "$OFF" = 0 ] || URLS=""
for u in $URLS; do
    code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$u" || true)"
    echo "   $code $u"
    [ "$code" = 200 ] || bad=1
done
if [ "$OFF" = 0 ]; then
    echo
    rsh 0 "cd '${N_REPO[0]}' && scripts/${N_OS[0]}/sync.sh status 2>&1 | tail -8" || true
fi
[ "$bad" = 0 ] || die "something above is not right"
if [ "$OFF" = 1 ]; then
    say "done: updated and built, every server is off. Start them with scripts/<os>/run.sh (c1 first), or ./quick-deploy.sh"
else
    say "done"
fi
