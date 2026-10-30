#!/usr/bin/env bash
# Backup / failover between machines (see dual-server-syncing/README.md).
#
# Usage: scripts/<os>/sync.sh init      create sync.env (CLONE_SECRET) and nodes.conf (in the secrets folder) if missing
#        scripts/<os>/sync.sh status    this machine's view: role, last sync, health of everyone
#        scripts/<os>/sync.sh promote   make this machine the primary now (planned switch;
#                                       stops the old primary over ssh first)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
detect_platform
cmd="${RS_ARGS[0]:-status}"

case "$cmd" in
init)
    secrets_init
    nodes="$RS_SECRETS_DIR/nodes.conf"
    if [ ! -f "$nodes" ]; then
        run cp "$RS_ROOT/dual-server-syncing/nodes.conf.example" "$nodes"
        log "created $nodes: edit it (one line per machine, best first)"
    fi
    log "this machine is called \"$(sync_node_name)\": that name must be in nodes.conf"
    log "to use another name: echo NAME > $RS_SECRETS_DIR/sync-node"
    log "then set SYNC_ENABLED=1 in $RS_SECRETS_DIR/sync.env on every machine, build.sh, run.sh"
    ;;
status | promote)
    dir="$RS_TARGET/syncd"
    [ -f "$dir/syncd.js" ] || die "syncd is not built: set SYNC_ENABLED=1 in $RS_SECRETS_DIR/sync.env and run scripts/$RS_OS/build.sh"
    cd "$dir"
    exec node syncd.js "$cmd"
    ;;
*) die "usage: sync.sh init | status | promote" ;;
esac
