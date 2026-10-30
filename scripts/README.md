# Deployment scripts

One folder per OS, all calling the shared logic in `common/`:

| | macOS | Debian / Ubuntu / Raspberry Pi OS | Windows |
|---|---|---|---|
| folder | `macos/` | `debian/` (arm64 or amd64 is detected) | `windows/*.ps1` (runs `debian/` inside WSL2 Ubuntu) |

```
setup.sh         install dependencies, git pull the merged repo + submodules,
                 create ~/.rysteria-secrets/ with .env templates
build.sh         build every server + both clients into builds/<os>-<arch>/<name>/
run.sh           start master, game servers, gardn, edge; cloudflared if enabled
stop.sh          stop them (players and saves are flushed first)
clean-builds.sh  delete builds/ (only that) so the next build starts clean
up.sh            setup + build + run
sync.sh          backup / failover between machines: init | status | promote
                 (see ../dual-server-syncing/README.md)
mail.sh          the mail server in "email system/": setup | start | stop | dns | status
```
Every script takes `--dry-run` (print, don't do). `bootstrap.sh` / `windows\bootstrap.ps1`
start from an empty machine.

## Secrets: `~/.rysteria-secrets/` (override with `SECRETS_DIR`)

Outside the checkout and outside `builds/`, mode 700/600, never overwritten:

* `common.env` – `CLOUDFLARED_ENABLED`, tunnel name + credentials, domain, the URLs
  baked into the clients.
* `master.env` – the single source of truth (database, secrets, Discord keys).
* `<server>.env` – values for one server only (`rrolf-default.env`, `rrolf-hc.env`,
  `rrolf-garden.env`, `gardn.env`, `edge.env`).

`build.sh` writes `builds/<os>-<arch>/<name>/.env` for each server: the master gets
`master.env`; game servers and gardn get **only** the shared `SERVER_SECRET`, the
master address and their own file – never database credentials, token secrets or
Discord keys.

## Servers

Edit `common/servers.conf` to add or remove processes (name, kind, biome, port,
public hostname). `edge` serves the rrolf client at `/` and gardn under `/gardn/`
on one hostname; with cloudflared enabled, `run.sh` generates the tunnel ingress
from the same file.

## Backup servers

With `SYNC_ENABLED=1` in `sync.env`, `run.sh` also starts `syncd` and only the primary machine
gets the cloudflared tunnel; the others run the full stack as copies and take over when the
primary fails. Setup and rules: `dual-server-syncing/README.md`.

## Mail server

`mail.sh setup` (macOS: `scripts/macos/mail.sh setup`) sets up the "email system" folder
in one go: creates the DNS records in Cloudflare, routes `webmail.<domain>` through the
tunnel, gets the TLS certificate, starts the stack, creates DKIM and the mailboxes.
Fill in `~/.rysteria-secrets/mail.env` first (or `secrets/mail.env` in the repo, which
is copied over on every run): `CERT_EMAIL`, `CLOUDFLARE_API_TOKEN` (Zone > DNS > Edit)
and optionally `MAIL_ACCOUNTS`. After that `run.sh` / `stop.sh` start and stop the mail
server too. Only webmail goes through the tunnel; the mail ports (25, 465, 587, 143,
993, plus 80 for the certificate) must be open on your router.
