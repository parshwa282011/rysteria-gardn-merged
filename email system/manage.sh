#!/usr/bin/env bash
# Helper for the mail server. Run ./manage.sh with no arguments for the command list.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env found. Run: cp .env.example .env   then fill it in." >&2
  exit 1
fi
set -a; . ./.env; set +a
: "${MAIL_DOMAIN:?set MAIL_DOMAIN in .env}"
: "${MAIL_HOSTNAME:?set MAIL_HOSTNAME in .env}"

DMS=mailserver
dms() { docker exec -i "$DMS" setup "$@"; }

# Runs certbot in Docker. With CLOUDFLARE_API_TOKEN set it proves ownership of the
# domain through a DNS record (no open port 80, no public IP needed); otherwise it
# starts a temporary web server on port 80, which must be reachable from the internet.
certbot_run() {
  local sub="$1"; shift
  local vols=(-v "$PWD/docker-data/certbot/etc:/etc/letsencrypt" -v "$PWD/docker-data/certbot/lib:/var/lib/letsencrypt")
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    mkdir -p docker-data/certbot/secrets
    ( umask 077; echo "dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN" > docker-data/certbot/secrets/cloudflare.ini )
    docker run --rm "${vols[@]}" -v "$PWD/docker-data/certbot/secrets:/secrets:ro" \
      certbot/dns-cloudflare "$sub" --dns-cloudflare \
      --dns-cloudflare-credentials /secrets/cloudflare.ini \
      --dns-cloudflare-propagation-seconds 30 "$@"
  else
    docker run --rm -p 80:80 "${vols[@]}" certbot/certbot "$sub" --standalone "$@"
  fi
}
dms_tty() { docker exec -it "$DMS" setup "$@"; }

usage() {
  cat <<USAGE
Usage: ./manage.sh <command>

  cert                    get a Let's Encrypt certificate (DNS challenge if CLOUDFLARE_API_TOKEN is set, else port 80)
  renew                   renew the certificate and reload the mail server
  up                      start mail server and webmail
  down                    stop everything (mail is kept)
  restart                 restart the stack
  status                  show container state and health
  logs [service]          follow logs (mailserver or roundcube)

  add <user@domain>       create a mailbox (prompts for the password)
  passwd <user@domain>    change a mailbox password
  del <user@domain>       delete a mailbox
  list                    list mailboxes
  alias <from> <to>       add an alias, e.g. alias info@$MAIL_DOMAIN me@$MAIL_DOMAIN

  dkim                    create the DKIM key for $MAIL_DOMAIN
  dns                     print the DNS records to create
  dns-apply [--dry-run]   create/update those records in Cloudflare (needs CLOUDFLARE_API_TOKEN)
  ddns                    same, but always uses the current public IP (run from cron if your IP changes)
  test                    check ports and DNS from this machine
USAGE
}

cmd="${1:-}"; shift || true
case "$cmd" in
  cert)
    : "${CERT_EMAIL:?set CERT_EMAIL in .env}"
    mkdir -p docker-data/certbot/etc docker-data/certbot/lib
    certbot_run certonly --non-interactive --agree-tos -m "$CERT_EMAIL" -d "$MAIL_HOSTNAME"
    ;;
  renew)
    certbot_run renew --non-interactive
    docker restart "$DMS"
    ;;
  up)
    if [ ! -d "docker-data/certbot/etc/live/$MAIL_HOSTNAME" ]; then
      echo "No certificate for $MAIL_HOSTNAME yet. Run ./manage.sh cert first." >&2
      exit 1
    fi
    docker compose up -d
    ;;
  down) docker compose down ;;
  restart) docker compose restart ;;
  status) docker compose ps ;;
  logs) docker compose logs -f --tail=100 "$@" ;;

  add)     [ $# -eq 1 ] || { usage; exit 1; }; dms_tty email add "$1" ;;
  passwd)  [ $# -eq 1 ] || { usage; exit 1; }; dms_tty email update "$1" ;;
  del)     [ $# -eq 1 ] || { usage; exit 1; }; dms_tty email del "$1" ;;
  list)    dms email list ;;
  alias)   [ $# -eq 2 ] || { usage; exit 1; }; dms alias add "$1" "$2" ;;

  dkim)
    dms config dkim domain "$MAIL_DOMAIN"
    docker restart "$DMS" >/dev/null
    echo
    echo "DKIM key created. Add the TXT record shown by: ./manage.sh dns"
    ;;

  dns-apply)
    command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
    node dns.mjs "$@"
    ;;

  ddns)
    command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
    SERVER_IP= node dns.mjs "$@"
    ;;

  dns)
    ip="${SERVER_IP:-<SERVER_IP>}"
    cat <<DNS
Create these records at your DNS provider for $MAIL_DOMAIN.
If you use Cloudflare, set the mail host to "DNS only" (grey cloud). Mail cannot go through the proxy.

  Type  Name                    Value
  A     $MAIL_HOSTNAME   $ip
  MX    $MAIL_DOMAIN            10 $MAIL_HOSTNAME
  TXT   $MAIL_DOMAIN            "v=spf1 mx -all"
  TXT   _dmarc.$MAIL_DOMAIN     "v=DMARC1; p=quarantine; rua=mailto:postmaster@$MAIL_DOMAIN"

DKIM (TXT record, created by ./manage.sh dkim):
DNS
    key=$(ls docker-data/dms/config/rspamd/dkim/*"$MAIL_DOMAIN"*.public.txt 2>/dev/null | head -1 || true)
    if [ -n "$key" ]; then
      echo "  from $key"
      cat "$key"
    else
      echo "  (not created yet - run ./manage.sh dkim)"
    fi
    cat <<DNS

Reverse DNS (PTR) for $ip must be $MAIL_HOSTNAME.
Set that in your VPS provider's panel, not at your DNS host. Many providers reject mail without it.
DNS
    ;;

  test)
    echo "== DNS =="
    for q in "A $MAIL_HOSTNAME" "MX $MAIL_DOMAIN" "TXT $MAIL_DOMAIN" "TXT _dmarc.$MAIL_DOMAIN"; do
      set -- $q
      printf '%-4s %-30s ' "$1" "$2"
      dig +short "$1" "$2" | tr '\n' ' '; echo
    done
    echo
    echo "== Ports on $MAIL_HOSTNAME =="
    for p in 25 465 587 143 993; do
      if nc -z -w 3 "$MAIL_HOSTNAME" "$p" 2>/dev/null; then echo "$p open"; else echo "$p closed/blocked"; fi
    done
    ;;

  *) usage; [ -z "$cmd" ] || exit 1 ;;
esac
