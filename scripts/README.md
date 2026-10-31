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
restart-one.sh   start one game server again (the master runs it when a server drops, once)
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

* `common.env` – `CLOUDFLARED_ENABLED`, tunnel name, id + credentials, domain, the URLs
  baked into the clients. `TUNNEL_CREDENTIALS` may use `~`, so the same file serves a Mac and a Pi; if it is
  not there `~/.cloudflared/<TUNNEL_NAME>.json` and `<TUNNEL_ID>.json` are tried. The credentials file itself
  is not a `.env`: copy it to `~/.cloudflared/` on every machine that may run the tunnel.
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

## gardn

`edge.js` serves `/gardn/*` from the gardn process (the `/gardn` prefix and the query are dropped, as nginx did).
When gardn does not answer, the edge runs `GARDN_RESTART_COMMAND` (`restart-one.sh gardn`, written into the edge's
`.env` by `build.sh`) at most once a minute. A page and websocket test of `/gardn/` (the first packet is the version
hash as a varint, then uuid and PL-P as length prefixed strings) checks it end to end; a wrong PL-P must be closed
with 4006.

## A machine without emscripten (the Raspberry Pi)

`build.sh --skip-clients` builds the servers but not the WASM clients (rrolf client, gardn), so that machine keeps
whatever client and gardn it had, and serves them the day it takes over the tunnel. After building on a machine
that has emscripten (the Mac), copy them from your own computer:

```sh
scripts/sync-clients.sh c1 pi ~/.ssh/id_c1     # names from secrets/nodes.conf
```
then restart gardn there (`stop.sh`, `run.sh`). The files are WebAssembly, so they run on any machine. Check
gardn end to end with a page + websocket test of `/gardn/` (the first packet is the version hash as a varint).

## The tunnel

`run.sh` starts cloudflared over TCP (`--protocol http2`): QUIC (UDP) timed out every few minutes on a network
that drops UDP, taking the site down with it. It waits for the first "Registered tunnel connection" and tries up
to three times; when it cannot connect it says so, with the last lines of `run/cloudflared.log`, and the game
keeps running locally. A missing credentials file is named in the warning.

## When a game server dies

The master restarts a game server that drops its connection without saying it was stopping (a crash, `kill -9`)
once; `stop.sh` and a plain `kill` (SIGTERM) are "on purpose" and are left alone. `RESTART_DROPPED_SERVERS=0` in
`common.env` turns it off. See `rrolf/MasterServer/c/README.md`.

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
