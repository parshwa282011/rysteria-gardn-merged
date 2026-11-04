#!/usr/bin/env bash
# Makes the DNS records of the Cloudflare tunnel: one CNAME <hostname>.<domain> -> <tunnel id>.cfargotunnel.com per
# hostname of scripts/common/servers.conf (api-game, game, hc-game, default-game, pvp-game, ga-game, garden-game,
# mini-game, ctf-game). Safe to run again: a record that already points at the tunnel stays as it is.
#
# What it does NOT need to do: the "forwards" (which hostname goes to which port on the machine). run.sh writes those
# into builds/<os>-<arch>/run/tunnel.yml every time it starts cloudflared, from the same servers.conf, on every machine.
# The DNS records belong to the tunnel, not to a machine: c1 and the Pi use the same tunnel (the same credentials
# json), so ONE run of this script, on either of them, covers both.
#
# Needs ~/.cloudflared/cert.pem on the machine you run it on (cloudflared tunnel login, once).
#   scripts/tunnel-setup.sh                 the game hostnames
#   scripts/tunnel-setup.sh --with-ssh      also ssh.<domain> (SSH_HOST in common.env): it then reaches the machine that
#                                           is primary at that moment, so it is off by default
#   scripts/tunnel-setup.sh --dry-run       only prints what it would do
source "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
with_ssh=0
parse_common_flags "$@"
for arg in ${RS_ARGS[@]+"${RS_ARGS[@]}"}; do
    case "$arg" in
    --with-ssh) with_ssh=1 ;;
    *) die "unknown option $arg" ;;
    esac
done
detect_platform
load_servers
need cloudflared
[ "$RS_DRY_RUN" = 1 ] || [ -f "$HOME/.cloudflared/cert.pem" ] || die "no ~/.cloudflared/cert.pem: run 'cloudflared tunnel login' on this machine first"

id="$(common_get TUNNEL_ID)"
[ -n "$id" ] || id="$(common_get TUNNEL_NAME)"
[ -n "$id" ] || die "TUNNEL_ID (or TUNNEL_NAME) is not set in common.env"
domain="$(common_get DOMAIN)"
[ -n "$domain" ] || die "DOMAIN is not set in common.env"

hosts=()
for entry in "${SV_HOST[@]}"; do
    [ "$entry" = "-" ] && continue
    IFS=',' read -ra parts <<<"$entry" # "hc-game,default-game" are two names of one server
    hosts+=("${parts[@]}")
done
[ "$with_ssh" = 1 ] && [ -n "$(common_get SSH_HOST)" ] && hosts+=("$(common_get SSH_HOST)")

log "tunnel $id, ${#hosts[@]} hostnames under $domain"
for h in "${hosts[@]}"; do
    run cloudflared tunnel route dns --overwrite-dns "$id" "$h.$domain"
done
log "done. Check: every <hostname>.$domain must answer; the forwards come from run.sh"
