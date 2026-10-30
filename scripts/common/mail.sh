#!/usr/bin/env bash
# The mail server in "email system/" (docker-mailserver + Roundcube webmail).
#
#   setup   one time: writes "email system/.env" from ~/.rysteria-secrets/mail.env,
#           creates the DNS records in Cloudflare, routes the webmail hostname
#           through the tunnel, gets the TLS certificate, starts the stack,
#           creates the DKIM key (and its DNS record) and the MAIL_ACCOUNTS mailboxes.
#           Safe to run again. Also sets MAIL_ENABLED=1 so run.sh starts the mail server.
#   start   starts the stack (run.sh does this when MAIL_ENABLED=1)
#   stop    stops the stack (mail is kept)
#   dns     creates/updates the DNS records again (also fixes the A record after your IP changed)
#   status  containers, DNS and port check
#
# Usage: scripts/<os>/mail.sh <setup|start|stop|dns|status> [--dry-run]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_common_flags "$@"
detect_platform
[ "${#RS_ARGS[@]}" = 1 ] || die "usage: mail.sh <setup|start|stop|dns|status> [--dry-run]"

MAIL_DIR="$RS_ROOT/email system"
MAIL_ENV="$RS_SECRETS_DIR/mail.env"
[ -f "$MAIL_DIR/compose.yaml" ] || die "no 'email system' folder in $RS_ROOT"

need_docker() {
    [ "$RS_DRY_RUN" = 1 ] && return 0
    command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/get-docker/"
    docker info >/dev/null 2>&1 || die "Docker is installed but not running: start it and try again"
}

# "email system/.env" only gets what compose and manage.sh read
write_mail_env() {
    log "writing $MAIL_DIR/.env"
    [ "$RS_DRY_RUN" = 1 ] && return 0
    [ -f "$MAIL_ENV" ] || die "missing $MAIL_ENV: run scripts/$RS_OS/setup.sh first"
    local key
    (
        umask 077
        for key in MAIL_DOMAIN MAIL_HOSTNAME SERVER_IP CERT_EMAIL CLOUDFLARE_API_TOKEN WEBMAIL_PORT TZ; do
            echo "$key=$(mail_get "$key")"
        done >"$MAIL_DIR/.env"
    )
}

check_mail_config() {
    [ "$RS_DRY_RUN" = 1 ] && return 0
    local missing=0 key
    for key in "$@"; do
        if [ -z "$(mail_get "$key")" ]; then
            warn "set $key in $MAIL_ENV"
            missing=1
        fi
    done
    [ "$missing" = 0 ] || die "mail.env is incomplete"
}

wait_healthy() {
    [ "$RS_DRY_RUN" = 1 ] && return 0
    local i status
    log "waiting for the mail server to start (first start takes a minute or two)"
    for i in $(seq 1 60); do
        status="$(docker inspect -f '{{.State.Health.Status}}' mailserver 2>/dev/null || true)"
        [ "$status" = healthy ] && return 0
        sleep 3
    done
    warn "mailserver is not healthy yet, see: docker logs mailserver"
    return 1
}

create_accounts() {
    local accounts entry addr pass existing
    accounts="$(mail_get MAIL_ACCOUNTS)"
    [ -n "$accounts" ] || return 0
    if [ "$RS_DRY_RUN" = 1 ]; then
        for entry in $accounts; do echo "[dry-run] create mailbox ${entry%%:*}"; done
        return 0
    fi
    existing="$(docker exec mailserver setup email list 2>/dev/null || true)"
    for entry in $accounts; do
        addr="${entry%%:*}"
        pass="${entry#*:}"
        if printf '%s' "$existing" | grep -qF -- "$addr"; then
            log "mailbox $addr already exists"
        else
            log "creating mailbox $addr"
            docker exec mailserver setup email add "$addr" "$pass" >/dev/null
        fi
    done
}

has_certificate() {
    [ -d "$MAIL_DIR/docker-data/certbot/etc/live/$(mail_get MAIL_HOSTNAME)" ]
}

has_dkim_key() {
    compgen -G "$MAIL_DIR/docker-data/dms/config/rspamd/dkim/*.public.txt" >/dev/null
}

cmd_setup() {
    if [ ! -f "$MAIL_ENV" ]; then
        mail_secrets_init "${DOMAIN:-$(common_get DOMAIN)}"
        [ "$RS_DRY_RUN" = 1 ] || die "created $MAIL_ENV: fill it in, then run mail.sh setup again"
    fi
    check_mail_config MAIL_DOMAIN MAIL_HOSTNAME CERT_EMAIL CLOUDFLARE_API_TOKEN
    need_docker
    need node curl

    local domain webmail_host
    domain="$(mail_get MAIL_DOMAIN)"
    webmail_host="$(mail_get WEBMAIL_HOST)"

    if [ -f "$RS_SECRETS_DIR/common.env" ] && [ "$RS_DRY_RUN" != 1 ]; then
        env_set "$RS_SECRETS_DIR/common.env" MAIL_ENABLED 1
    fi
    write_mail_env

    log "DNS records in Cloudflare (A, MX, SPF, DMARC)"
    run "$MAIL_DIR/manage.sh" dns-apply

    if [ -n "$webmail_host" ]; then
        if [ "$(common_get CLOUDFLARED_ENABLED)" = 1 ]; then
            need cloudflared
            log "tunnel route: $webmail_host.$domain -> webmail"
            run cloudflared tunnel route dns "$(common_get TUNNEL_NAME)" "$webmail_host.$domain" ||
                warn "could not route $webmail_host.$domain (already routed, or run: cloudflared tunnel login)"
        else
            warn "CLOUDFLARED_ENABLED is not 1 in common.env: webmail will only be on http://127.0.0.1:$(mail_get WEBMAIL_PORT)"
        fi
    fi

    if [ "$RS_DRY_RUN" = 1 ] || ! has_certificate; then
        log "TLS certificate (Let's Encrypt, needs port 80 open to the internet)"
        run "$MAIL_DIR/manage.sh" cert
    fi

    log "starting the mail server"
    run "$MAIL_DIR/manage.sh" up
    wait_healthy || true

    if [ "$RS_DRY_RUN" = 1 ] || ! has_dkim_key; then
        log "DKIM key"
        run "$MAIL_DIR/manage.sh" dkim
    fi
    log "DNS records again (adds DKIM)"
    run "$MAIL_DIR/manage.sh" dns-apply

    create_accounts

    log "mail server is set up"
    echo "  webmail:  https://$webmail_host.$domain  (run.sh must be running with cloudflared)"
    echo "  local:    http://127.0.0.1:$(mail_get WEBMAIL_PORT)"
    echo "  IMAP/SMTP host: $(mail_get MAIL_HOSTNAME)"
    echo "  check:    scripts/$RS_OS/mail.sh status"
    [ -n "$(mail_get MAIL_ACCOUNTS)" ] || echo "  no mailboxes yet: set MAIL_ACCOUNTS in mail.env, or run: \"$MAIL_DIR/manage.sh\" add you@$domain"
}

cmd_start() {
    need_docker
    write_mail_env
    if [ "$RS_DRY_RUN" != 1 ] && ! has_certificate; then
        die "no TLS certificate yet: run scripts/$RS_OS/mail.sh setup"
    fi
    log "starting the mail server"
    run "$MAIL_DIR/manage.sh" up
}

cmd_stop() {
    [ -f "$MAIL_DIR/.env" ] || return 0
    command -v docker >/dev/null 2>&1 || return 0
    log "stopping the mail server"
    run docker compose --project-directory "$MAIL_DIR" stop
}

case "${RS_ARGS[0]}" in
setup) cmd_setup ;;
start) cmd_start ;;
stop) cmd_stop ;;
dns)
    check_mail_config CLOUDFLARE_API_TOKEN
    write_mail_env
    run "$MAIL_DIR/manage.sh" dns-apply
    ;;
status)
    need_docker
    run "$MAIL_DIR/manage.sh" status
    run "$MAIL_DIR/manage.sh" test
    ;;
*) die "unknown command ${RS_ARGS[0]} (setup, start, stop, dns, status)" ;;
esac
