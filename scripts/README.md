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
mail.sh          the mail server (the "email system/" folder was removed for now, it is in the git history before the commit "Remove the mail server folder"; the script stops with an error until it is back)
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

`build.sh` never builds PDEV (the give-petals cheat, behind a PIN): every build passes `-UPDEV`. To test with it,
build by hand with `cmake -DPDEV=1` in `rrolf/Server` and `rrolf/Client`. `quick-deploy.sh` still refuses to continue
if a PDEV build or cache is found.

### SSH through the tunnel (off until you turn it on)

`SSH_HOST=ssh` in `common.env` adds the route `ssh.<domain>` -> `ssh://127.0.0.1:22` to the tunnel that `run.sh`
generates, so the sshd of the machine that holds the tunnel (the primary, or the Mac in split mode) can be reached
without port forwarding. It is off unless that line is there. To switch it on:

1. DNS: the name has to point at this tunnel (it may point at an older one): `cloudflared tunnel route dns --overwrite-dns rysteria2 ssh.parshwa.blog`
2. Cloudflare Zero Trust > Access > Applications > Add > Self-hosted, domain `ssh.parshwa.blog`, an Allow policy for your e-mail. **Do this first**: without it anybody with `cloudflared` can reach the sshd's login prompt.
3. Add `SSH_HOST=ssh` to `secrets/common.env`, `scripts/push-secrets.sh user@host ~/.ssh/id_c1` for the machines, then restart the tunnel (`stop.sh`, `run.sh`: a few seconds without the game).
4. On the computer you connect from: `brew install cloudflared`, and in `~/.ssh/config`:
   ```
   Host home-mac
       HostName ssh.parshwa.blog
       User tejashshah
       ProxyCommand cloudflared access ssh --hostname %h
   ```
   then `ssh home-mac` (a browser opens once for the Access login).

Remote Login must be on for the machine (System Settings > General > Sharing on macOS). Because the tunnel moves with
failover, `ssh.parshwa.blog` leads to whichever machine has the tunnel.

### Split mode: the game on two machines

Normally the Mac runs the whole game and the Pi is a spare that is started by hand. `./split-pi.sh` and
`./split-mac.sh` (from your computer, over ssh) divide the game instead:

| machine | runs |
|---|---|
| Mac (line 1 of `nodes.conf`) | PostgreSQL, the master, gardn, the web edge, rrolf-garden, rrolf-minigames, and the **one** cloudflared tunnel for every hostname |
| Pi (line 2) | rrolf-hc (hell creek) and rrolf-pvp, which talk to the master over the LAN. No master, no database |

The tunnel's routes do not change: `hc-game` and `pvp-game` still point at `127.0.0.1:1234` / `:1235` on the Mac, where
`scripts/common/forward.js` passes every connection on to the Pi (plain TCP, so websockets just work). The Pi never
runs cloudflared. If a game server of the Pi drops, the master on the Mac restarts it over ssh (`restart-one.sh`).

```sh
./split-pi.sh      # first: stops the Pi, writes ~/.rysteria-secrets/split.env, builds, starts (waits for the master)
./split-mac.sh     # then: the same on the Mac, starts the master, then starts the Pi's servers
./split-mac.sh --status    # what runs where, whether the Pi answers (also ./split-pi.sh --status)
./split-pi.sh --off; ./split-mac.sh --off      # back to the full stack on both, failover as before
./split-pi.sh --tunnel-check                   # read-only: cloudflared credentials, clock, network, who is connected
```
Both need the committed code on the machines (`./quick-deploy.sh` first) and, for the Mac, a passwordless ssh key
to the Pi. `--dry-run` shows what would happen, `--no-apply` only writes `split.env`. While split mode is on there is
**no automatic failover**: if the Mac dies the game is down, and the Pi only keeps the data. `quick-deploy.sh` works
in both modes (in split mode it copies no web clients to the Pi). The Pi's database must already have the master's
tables, which any earlier run of its master created.

### Deploying everything from your computer

`./quick-deploy.sh` (at the top of the repository) does all of it in the right order: pushes what is committed,
stops the Pi so it can not take over, updates and builds every machine, restarts c1, copies the clients to the Pi
and starts it, and checks the pages. `--dry-run` only prints the steps. It stops before restarting anything if a
build fails or has PDEV in it, and never deploys uncommitted files (`--allow-dirty` deploys the commits anyway).

## The tunnel

`run.sh` starts cloudflared over QUIC (`CLOUDFLARED_PROTOCOL=quic`, the default, in `common.env`): every request
has its own stream, so one lost packet does not stall the others the way it does on the single TCP connection
of `http2`. It waits for the first "Registered tunnel connection" and tries up to three times; the **third try
is over `http2`** whatever was asked, because on a network that drops UDP QUIC timed out every few minutes.
Set `CLOUDFLARED_PROTOCOL=http2` to use TCP from the start (or `auto`). When it cannot connect it says so, with
the last lines of `run/cloudflared.log`, and the game keeps running locally. A missing credentials file is named
in the warning. The "precheck" lines cloudflared writes into `cloudflared.log` when it starts say whether the
network lets UDP through (`UDP Connectivity: QUIC connection successful`).

## When a game server dies

The master restarts a game server that drops its connection without saying it was stopping (a crash, `kill -9`)
once; `stop.sh` and a plain `kill` (SIGTERM) are "on purpose" and are left alone. `RESTART_DROPPED_SERVERS=0` in
`common.env` turns it off. See `rrolf/MasterServer/c/README.md`.

## The database: local, and copied online every 30 minutes

The master works on the PostgreSQL of its own machine (`POSTGRES_URI` in `master.env`): as many requests as it
likes, they cost nothing. A free online database (Prisma Postgres, Neon, ...) counts every request, so the master
never talks to it. `scripts/common/remote-copy.py` does, every `REMOTE_COPY_INTERVAL` seconds (default 1800):

* it fingerprints each of the six tables locally and sends only the tables that changed, all in **one request**
  (one statement per table: new and changed rows are upserted, rows that are gone are deleted). A cycle in which
  nothing changed asks the online database nothing;
* it runs only on the machine named by `REMOTE_COPY_NODE` in `common.env` (`c1`), and only when `master.env` has a
  `REMOTE_POSTGRES_URI`. `run.sh` starts it (kind `copier` in `servers.conf`), `stop.sh` stops it. A spare machine
  with an old database can not overwrite the online one;
* it refuses to copy when the local database has no accounts, or when the online one holds data this machine never
  saw (the first run): start from the online data with `--pull`, or `--force`.

```sh
python3 scripts/common/remote-copy.py --pull    # replace the local database with the online one (once, to start)
python3 scripts/common/remote-copy.py --once    # copy now        (--dry-run: only say what would be sent)
python3 scripts/common/remote-copy.py --status  # when it last copied
```
Needs `POSTGRES_URI` and `REMOTE_POSTGRES_URI` in the environment (or the `.env` next to it, which `build.sh`
writes), `psql` and `pg_dump`. Roughly: 48 copies a day, at most one request each, so under 50 requests a day
against the online database, however many players there are or however often the leaderboard is read.

Inside the master the players who are online are kept in memory and saved together: every
`FLUSH_INTERVAL_MS` (5 seconds) ONE request writes all the players that changed, and one more their leaderboard
numbers. A player who leaves is saved at once.

## Mail server

`mail.sh setup` (macOS: `scripts/macos/mail.sh setup`) sets up the "email system" folder
in one go: creates the DNS records in Cloudflare, routes `webmail.<domain>` through the
tunnel, gets the TLS certificate, starts the stack, creates DKIM and the mailboxes.
Fill in `~/.rysteria-secrets/mail.env` first (or `secrets/mail.env` in the repo, which
is copied over on every run): `CERT_EMAIL`, `CLOUDFLARE_API_TOKEN` (Zone > DNS > Edit)
and optionally `MAIL_ACCOUNTS`. After that `run.sh` / `stop.sh` start and stop the mail
server too. Only webmail goes through the tunnel; the mail ports (25, 465, 587, 143,
993, plus 80 for the certificate) must be open on your router.

## Petal icons for the stats pages

`build.sh` (with the clients) runs `scripts/gen-icons.mjs` last: both clients have a hidden mode
(`/?iconsheet` for Parteria, `/gardn/?iconsheet` for gardn) in which the game draws every petal as its
loadout does instead of playing, and headless Chrome cuts each petal out as a png into
`rrolf-client/icons/rysteria/<id>-<rarity>.png` and `rrolf-client/icons/gardn/<id>.png`. The pages
`/status` and `/gardn/stats` show them. It needs Chrome on the machine that builds the clients (c1); without
it the build says so and the pages show plain coloured tiles. The Pi gets the icons with the clients
(`scripts/sync-clients.sh`).
