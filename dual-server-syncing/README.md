# Backup servers and automatic failover

One machine (the **primary**, e.g. `c1`) serves the game through the Cloudflare
tunnel. Up to four other machines (**backups**, e.g. a Raspberry Pi) run the whole
game stack too, but with **no tunnel**, so nobody can connect to them. Every 30
seconds a backup asks the primary for what changed and copies it into its own
PostgreSQL. If the primary dies, the best backup stops it (over ssh, if it can),
starts its own tunnel and carries on with the copied data.

```
players ---> Cloudflare ---> tunnel on the PRIMARY ---> master ---> postgres
                                                           |  GET /backup (every 30 s, X-Clone-Secret)
                 backups: full stack, no tunnel  <---------+
                 (c1, pi, ...) own postgres kept in step
```

## Set up (every machine)

1. **Same secrets everywhere.** Copy `secrets/*.env` (or `~/.rysteria-secrets/`) to every
   machine unchanged: same `master.env` secrets (so logins survive a failover), same
   tunnel name and credentials (`common.env`), same `sync.env`. Each machine has its own
   local PostgreSQL with the **same** database, user and password, so the same
   `POSTGRES_URI` (`...@127.0.0.1:5432/rysteria`) works on all of them. PostgreSQL 13+.
2. `scripts/<os>/sync.sh init` creates `sync.env` (with a random `CLONE_SECRET`) and
   `nodes.conf` in the secrets folder if missing. Run it on one machine and copy
   `sync.env` and `nodes.conf` to the others.
3. Edit `~/.rysteria-secrets/nodes.conf` (or `secrets/nodes.conf` in the repo, which is
   imported like the `.env` files): one line per machine, **best first**, the same file on
   every machine. At most 5 lines. `dual-server-syncing/nodes.conf` is only a fallback.
4. Name: each machine must find itself in `nodes.conf`. By default its short host name
   (`hostname -s`, lower case). To use another: `echo c1 > ~/.rysteria-secrets/sync-node`.
5. Passwordless ssh (key login) from every machine to every other one, so a backup can
   stop a dead primary: `ssh-copy-id user@host`, then check `ssh user@host true`.
   macOS: System Settings > General > Sharing > Remote Login. Windows: OpenSSH Server.
6. Set `SYNC_ENABLED=1` in `sync.env`, then on each machine
   `scripts/<os>/build.sh` and `scripts/<os>/run.sh`. Start the primary first.
   A machine started later sees the game already running and becomes a backup.
7. `scripts/<os>/sync.sh status` shows role, last sync and the health of everyone.

`build.sh` must be run again whenever `sync.env`, `nodes.conf` or the node name change
(it writes the `.env` files). The master must be rebuilt once to get the new code
(`/backup`, richer `/health`).

## What each machine does

**Primary** (the one that has the tunnel) every 30 s:
- checks its own master and PostgreSQL (`127.0.0.1:55554/health`). Broken twice in a row
  → it **steps down** (stops its tunnel) so a backup can take over.
- checks `https://api-game.<domain>/health` as the world sees it. Local fine but public
  not → the tunnel is broken, so it **restarts cloudflared**.
- if the public address is answered by another node as well (two primaries), the one with
  the lower priority steps down.

**Backup** every 30 s:
- keeps its own stack running (`run.sh` without tunnel) and makes sure cloudflared is **not** running.
- `api-game.<domain>/health` ok → pulls `/backup` and applies it. The first time (or after
  a failover) it gets the whole database, afterwards only the changes since the last pull.
- otherwise it decides whether the primary is really down (below).

## When does a backup take over?

1. Its own internet works (otherwise it never judges anyone).
2. The public health check failed 3 times, 5 s apart (`SYNC_FAIL_PROBES`). "Failed" means
   no answer / Cloudflare 502/530 (server or tunnel died), or the master answered but its
   PostgreSQL is down (HTTP 503).
3. It also asks the old primary directly at its `lan` address. If that works the fault is
   only the tunnel, and the backup waits 60 s more for the primary to fix it itself.
4. **Priority:** it waits `45 s × (number of better nodes)` and re-checks before every
   step. If a better node has taken over by then, it stays a backup. So `c1` goes first,
   `pi` 45 s later, and so on.
5. It is allowed only if it is current: it was the primary last, or its last sync is
   younger than 15 min (`SYNC_MAX_STALE`). A machine that has never synced only takes over
   if it is the first line of `nodes.conf` (a fresh start of the main machine). Otherwise it
   logs `NOT taking over` and waits for a human: `scripts/<os>/sync.sh promote`.
6. **Fence:** it runs `scripts/<os>/stop.sh` (`stop.ps1` for windows) on the old primary
   over ssh. If ssh fails or the machine is dead, it carries on immediately.
7. It starts a new "source id" (the other backups will take a fresh snapshot from it), writes
   `primary` to `builds/<os>-<arch>/run/sync.role` and runs `run.sh`, which starts cloudflared.
   It waits until `api-game.<domain>/health` answers with its own name.

`run.sh` only starts the tunnel when `sync.role` says `primary` (and not at all for a leftover
role after a reboot), so starting `run.sh` by hand on a backup can not create a second primary.
`stop.sh` also stops syncd.

A returning machine does **not** take the game back: it starts as a backup, clones the
current primary (replacing its own data) and stays a backup. To switch back on purpose:
`scripts/<os>/sync.sh promote` on the machine you want.

## How the copying works

The master (`rrolf/MasterServer/c`) logs every row written to its data tables into
`sync.changes` (trigger, with the transaction id). `GET /backup` with the header
`X-Clone-Secret` returns newline-delimited json: a head line, one line per row change (or per
row for a full snapshot) and an end line. The backup applies the whole answer in one
transaction, so a cut connection changes nothing. The cursor is the oldest transaction not read
yet, and only finished transactions are returned, so a slow write is never skipped. History is
kept 3 days; a backup that was off longer takes a snapshot. `GET /health` now also says which
node answered (`"node"`) and whether it can serve backups (`"backup"`).

## Things to know

- A failover can lose up to ~35 s of writes (the 30 s interval plus the master's own 5 s save
  delay); players online during it are disconnected and log in again on the new primary.
- If the old primary comes back with data the new one never saw, that data is overwritten when
  it re-syncs. Nothing is merged.
- Only PostgreSQL is copied (not MongoDB). Mail server and builds are not part of failover.
- Backups need the master to listen on the LAN for the direct health check:
  `SYNC_LAN_HEALTH=1` (default) sets `BIND_ADDRESS` empty in the master's `.env`. Set it to `0`
  and leave `lan` as `-` in `nodes.conf` to use only the public check.
- `/backup` is protected by `CLONE_SECRET` (constant-time compare, failed attempts are
  rate-limited). Treat it like the other secrets: it lets its holder download every account.
- Settings (`sync.env`): `SYNC_INTERVAL`, `SYNC_FAIL_PROBES`, `SYNC_STAGGER`, `SYNC_MAX_STALE`,
  `SYNC_TUNNEL_GRACE`, `SYNC_LAN_HEALTH`.
- Windows machines run everything in WSL2 Ubuntu, so list them as `debian` in `nodes.conf`
  unless you want ssh to reach the Windows host itself (`windows`, runs `stop.ps1`).

## Files

- `syncd.js` – the supervisor (roles, health checks, takeover, fencing)
- `store.js` – applies a feed to PostgreSQL, starts a new source id
- `util.js` – env files, health probes, running commands
- `nodes.conf.example` – the machine list
