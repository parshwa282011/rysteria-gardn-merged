#!/usr/bin/env bash
# Runs ON the game instance (Oracle Linux 9), after oracle-cloud-init-game.sh and after the secrets
# were pushed (scripts/push-secrets.sh). ~/finish-setup.sh is a shortcut to this file.
#
#   scripts/oracle-finish-game.sh [--no-build] [--no-start] [--nginx-only]
#     --no-build    do not build (servers and clients already are)
#     --no-start    do not (re)start the game servers
#     --nginx-only  only rewrite the nginx configuration + certificate and reload nginx
#
# What it does:
#   1. switches the pushed secrets from "cloudflared tunnel" to "nginx on this machine":
#      CLOUDFLARED_ENABLED=0, no database copier here (it lives on the database instance).
#      The https:// client URLs and TRUST_PROXY_HEADER=CF-Connecting-IP stay as they are for the tunnel:
#      nginx takes the tunnel's place. Every port of servers.conf is ALSO open on the machine's IP.
#   2. writes /etc/nginx/conf.d/rysteria.conf from scripts/common/servers.conf: one server block per
#      public hostname (<host>.<DOMAIN>) that proxies to the server's port on 127.0.0.1, websockets included.
#      Certificate: /etc/nginx/origin.pem + origin.key (a Cloudflare Origin certificate) when you put them
#      there, else a self-signed one for *.<DOMAIN> that this script makes (Cloudflare SSL mode "Full").
#   3. builds, and restarts the servers through the rysteria systemd user unit (they start at boot too).
#   4. checks every hostname through nginx on this machine, and the database.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source scripts/common/lib.sh

BUILD=1; START=1; NGINX_ONLY=0
for a in "$@"; do
    case "$a" in
    --no-build) BUILD=0 ;;
    --no-start) START=0 ;;
    --nginx-only) NGINX_ONLY=1 ;;
    -h | --help) sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $a" ;;
    esac
done

S="$HOME/.rysteria-secrets"
[ -f "$S/master.env" ] || die "no $S/master.env: run scripts/push-secrets.sh from your Mac first (or ./quick-deploy-oracle.sh game)"
C="$S/common.env"
DOMAIN="$(env_get "$C" DOMAIN)"
[ -n "$DOMAIN" ] || die "DOMAIN is not set in $C"

# ------------------------------------------------------------------ 1. secrets
log "secrets: no cloudflared, no database copier on this machine"
env_set "$C" CLOUDFLARED_ENABLED 0
env_set "$C" REMOTE_COPY_NODE ""
# reachable on the machine's IP as well: master + edge listen on every interface (rrolf and gardn already do),
# the host firewall opens every port of servers.conf, the OCI security list has the same ports. The client
# code is NOT changed: it still points at the website (https://api-game.<domain>, wss://game.<domain>/gardn/)
env_set "$S/master.env" BIND_ADDRESS ""
touch "$S/edge.env"; chmod 600 "$S/edge.env"; env_set "$S/edge.env" EDGE_BIND "0.0.0.0"
for p in $(awk '$1 !~ /^#/ && $4 ~ /^[0-9]+$/ { print $4 }' scripts/common/servers.conf); do
    sudo firewall-cmd --permanent --add-port="$p/tcp" >/dev/null
done
sudo firewall-cmd --reload >/dev/null
# the servers' .env files are written from the secrets by build.sh: write them again now (also with --no-build)
( detect_platform; load_servers
  for ((i = 0; i < ${#SV_NAME[@]}; i++)); do
      [ -d "$RS_TARGET/${SV_NAME[$i]}" ] && compose_env "${SV_NAME[$i]}" "${SV_KIND[$i]}" "$RS_TARGET/${SV_NAME[$i]}"
  done )

# ------------------------------------------------------------------ 2. nginx
write_nginx() {
    command -v nginx >/dev/null 2>&1 || die "nginx is not installed: run oracle-cloud-init-game.sh first"
    local cert=/etc/nginx/origin.pem key=/etc/nginx/origin.key
    if [ ! -f "$cert" ] || [ ! -f "$key" ]; then
        cert=/etc/nginx/rysteria-selfsigned.pem; key=/etc/nginx/rysteria-selfsigned.key
        # new certificate when there is none, or it was made for another domain
        if [ ! -f "$cert" ] || ! sudo openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | grep -q "\*\.$DOMAIN"; then
            log "making a self-signed certificate for *.$DOMAIN (10 years)"
            sudo openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$key" -out "$cert" \
                -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:*.$DOMAIN,DNS:$DOMAIN" 2>/dev/null
            sudo chmod 600 "$key"
        fi
    else
        log "using the Cloudflare Origin certificate in $cert"
    fi

    # host+port pairs from servers.conf: name kind arg port hostnames(comma separated or "-")
    local tmp conf=/etc/nginx/conf.d/rysteria.conf
    tmp="$(mktemp)"
    {
        echo "# written by scripts/oracle-finish-game.sh from scripts/common/servers.conf: do not edit"
        echo 'map $http_upgrade $rys_connection { default upgrade; "" close; }'
        echo '# any other hostname (or none): refused'
        echo 'server { listen 443 ssl default_server; ssl_reject_handshake on; }'
        awk '$1 !~ /^#/ && NF >= 5 && $4 ~ /^[0-9]+$/ && $5 != "-" { print $4, $5 }' scripts/common/servers.conf |
            while read -r port hosts; do
                names=""
                IFS=',' read -ra hs <<<"$hosts"
                for h in "${hs[@]}"; do names="$names $h.$DOMAIN"; done
                cat <<EOF
server {
    listen 443 ssl;
    server_name$names;
    ssl_certificate     $cert;
    ssl_certificate_key $key;
    client_max_body_size 8m;
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$rys_connection;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
EOF
            done
    } >"$tmp"
    sudo install -m 644 "$tmp" "$conf"; rm -f "$tmp"
    sudo rm -f /etc/nginx/conf.d/default.conf
    sudo nginx -t
    sudo systemctl enable nginx >/dev/null 2>&1 || true
    sudo systemctl restart nginx
    log "nginx: $(grep -c '^server_name\|^    server_name' "$conf") hostname block(s) in $conf"
}
write_nginx
[ "$NGINX_ONLY" = 0 ] || exit 0

# ------------------------------------------------------------------ 3. build + start
if [ "$BUILD" = 1 ]; then
    log "building (a few minutes on a fast machine, 30+ on one core)"
    scripts/debian/build.sh
fi
if [ "$START" = 1 ]; then
    # a user service (SELinux does not let a system service run programs from /home), see oracle-cloud-init-game.sh
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    systemctl --user daemon-reload
    systemctl --user enable rysteria >/dev/null 2>&1 || true
    systemctl --user restart rysteria
    sleep 8
fi

# ------------------------------------------------------------------ 4. check
log "checking"
bad=0
if [ "$START" = 1 ]; then
    code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:55554/health || true)"
    echo "  master /health on 127.0.0.1:55554: $code  $(curl -s -m 5 http://127.0.0.1:55554/health || true)"
    [ "$code" = 200 ] || bad=1
    awk '$1 !~ /^#/ && NF >= 5 && $4 ~ /^[0-9]+$/ && $5 != "-" { print $5 }' scripts/common/servers.conf | tr ',' '\n' | while read -r h; do
        code="$(curl -sk -m 10 -o /dev/null -w '%{http_code}' --resolve "$h.$DOMAIN:443:127.0.0.1" "https://$h.$DOMAIN/" || true)"
        echo "  https://$h.$DOMAIN/ via nginx: $code"
    done
fi
[ "$bad" = 0 ] || { echo "something is not right: logs are in builds/*/run/*.log"; exit 1; }
echo "==> done. Point the Cloudflare DNS at this machine's public IP (./quick-deploy-oracle.sh --dns lists the records)."
