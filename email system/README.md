# Email system

A real mail server for your domain, in Docker:

- **docker-mailserver**: Postfix (SMTP), Dovecot (IMAP), Rspamd (spam filter, DKIM signing, SPF/DKIM/DMARC checks), fail2ban.
- **Roundcube**: webmail, at `http://127.0.0.1:8989` (change with `WEBMAIL_PORT`).

## What you need first

This only works on a machine that the internet can reach directly. Mail does not travel through
Cloudflare tunnels, and home ISPs usually block port 25.

1. A server (VPS) with a public IPv4 address, Docker, and these ports open: **25, 465, 587, 143, 993**, plus **80** while getting a certificate.
2. A domain (the default is `parshwa.blog`).
3. A VPS provider that allows outbound port 25 and lets you set **reverse DNS (PTR)**. Without a PTR record
   that matches `mail.<your domain>`, Gmail and others will reject or spam-folder your mail.

## Setup

```sh
cd "email system"
cp .env.example .env        # fill in MAIL_DOMAIN, MAIL_HOSTNAME, SERVER_IP, CERT_EMAIL
./manage.sh dns             # shows the DNS records to create (do the A and MX records first)
./manage.sh cert            # gets a Let's Encrypt certificate (port 80 must be free)
./manage.sh up              # starts the mail server and webmail
./manage.sh add you@parshwa.blog
./manage.sh add noreply@parshwa.blog
./manage.sh dkim            # creates the DKIM key
./manage.sh dns             # now also prints the DKIM TXT record; add it
./manage.sh test            # checks DNS and ports
```

The first start takes a minute or two. Check with `./manage.sh status` and `./manage.sh logs mailserver`.

## DNS records

`./manage.sh dns` prints these with your values filled in:

| Type | Name | Value |
|------|------|-------|
| A | `mail.parshwa.blog` | your server IP (Cloudflare: **DNS only**, grey cloud) |
| MX | `parshwa.blog` | `10 mail.parshwa.blog` |
| TXT | `parshwa.blog` | `v=spf1 mx -all` |
| TXT | `mail._domainkey.parshwa.blog` | from `./manage.sh dkim` |
| TXT | `_dmarc.parshwa.blog` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@parshwa.blog` |
| PTR | your server IP | `mail.parshwa.blog` (set at your VPS provider) |

## Using it

| What | Settings |
|------|----------|
| Webmail | `http://127.0.0.1:8989`, log in with the full address and password |
| IMAP (read mail) | host `mail.parshwa.blog`, port 993 (SSL/TLS) or 143 (STARTTLS) |
| SMTP (send mail) | host `mail.parshwa.blog`, port 465 (SSL/TLS) or 587 (STARTTLS), username = full address |

To reach webmail from outside, put a reverse proxy or a Cloudflare tunnel hostname (for example `webmail.parshwa.blog`)
in front of `127.0.0.1:8989`. Webmail is plain HTTP and works through a tunnel; the mail ports do not.

## Sending from the game

The master server has no mail-sending code yet (the game shows "email service is not working"). When you add it,
use an SMTP client such as nodemailer with host `mail.parshwa.blog`, port 587, STARTTLS, and the `noreply@parshwa.blog`
account created above.

## Day to day

```sh
./manage.sh list                              # mailboxes
./manage.sh passwd you@parshwa.blog           # change a password
./manage.sh alias info@parshwa.blog you@parshwa.blog
./manage.sh del old@parshwa.blog
./manage.sh renew                             # renew the certificate (run monthly, e.g. from cron)
```

A cron line for renewal, run as a user that can use Docker:

```
0 4 1 * * cd "/path/to/email system" && ./manage.sh renew
```

## Files

- `compose.yaml`: the two services.
- `mailserver.env`: mail server options (spam filter, fail2ban, size limit). ClamAV is off by default because it needs about 1 GB of RAM.
- `.env`: your domain and IP (not committed).
- `docker-data/`: all mail, accounts, DKIM keys, and certificates (not committed). **Back this folder up.**

## Troubleshooting

- **Mail to Gmail goes to spam or bounces**: check PTR, SPF, DKIM and DMARC. Send a test to <https://www.mail-tester.com>.
- **Port 25 closed**: your provider blocks it. Ask them to unblock it, or pick another provider.
- **`up` says no certificate**: run `./manage.sh cert`; port 80 must reach this machine and the A record must already point to it.
- **Cannot log in**: use the full address as the username, not just the name.
