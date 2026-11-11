# Databases and everything else that is stored

Written 2026-11-08 from the code (`rrolf/MasterServer/c/db_postgres.c`, `db_mongo.c`, `leaderboard.c`, `tmpstore.c`,
`dual-server-syncing/`) and read-only queries on c1. The row counts are from that day.

There is **one database**, and only the master server talks to it. The game servers (Parteria's four, gardn) and the
web pages never open a connection to it: they ask the master over HTTP (`X-Server-Secret` for the game servers, the
login tokens for players).

| Store | What | Where | Used by |
|---|---|---|---|
| PostgreSQL, database `rysteria` | everything that must survive a restart (below) | `127.0.0.1:5432` on **each** machine (c1 and the Pi have their own copy) | the master (`DB_BACKEND=postgres`, `POSTGRES_URI` in `master.env`) |
| MongoDB (optional) | the same data as documents, an alternative backend | the `MONGO_URI` database | the master, only when `DB_BACKEND=mongo`. Not used now, and it has **no** crash backups or replication feed |
| The master's memory | short-lived records (below) | RAM | the master |
| Game server memory | the world, players, mobs, drops | RAM | the game servers. Lost on a restart on purpose |
| Files | state and secrets (below) | `~/.rysteria-secrets/`, `backup/` | scripts, syncd |
| The browser | the login and a few settings (below) | `localStorage` of the site | the clients |

PostgreSQL on a machine also has the default database `postgres`; nothing of ours is in it.

## PostgreSQL: database `rysteria`

The master creates all of this when it starts (`CREATE ... IF NOT EXISTS`), nothing is made by hand. Every table in the
schemas `accounts`, `rysteria`, `gardn` and `leaderboards` has a trigger `sync_capture` that writes each change into
`sync.changes`, which is what the backup machine copies (see Replication).

### Schema `accounts`

**`accounts.accounts`** (18 rows) one row per player account.

| Column | Type | Meaning |
|---|---|---|
| `uuid` | text, primary key | the account id (also what both games use to say who a player is) |
| `username`, `username_lower` | text | the name, and the lower case copy that is unique |
| `email`, `email_lower` | text | the address ('' when none; unique when set) |
| `email_verified` | boolean | the code sent to the address was typed in |
| `pw_hash` | text | the password hash (never the password) |
| `token_key` | text | the key that signs this account's login tokens |
| `is_dev` | boolean | a developer account |
| `tag` | text | the tag of the player in Parteria: `Spider` (also gives the flower the legs of a spider), `Supporter`, or empty for none. Accounts made before it existed have no value there, which means none (the column can also be NULL on purpose: a standby copying a row from a master from before the tags fills it so). Set it with `scripts/accounts.sh tag <name> spider` |
| `created_at`, `last_login_at` | bigint | Unix seconds |

**`accounts.links`** (9 rows) the Discord/Google/Apple accounts linked to an account. Primary key `(uuid, provider)`,
unique `(provider, provider_user_id)`; columns `provider_email`, `display_name`, `linked_at`, `provider_token` (kept for
Apple, whose token has to be revoked when the account is deleted). Deleted with the account.

### Schema `rysteria`

**`rysteria.players`** (13 rows) a Parteria player's progress. `uuid` (key, deletes with the account), `xp`,
`checkpoint`, `pvp_points`, `petals` (jsonb: the inventory), `failed_crafts`, `mob_kills`, `loadout` (jsonb),
`nickname`, `updated_at`.

### Schema `gardn`

**`gardn.saves`** (14 rows) the progress saves of gardn, up to `MS_GARDN_MAX_SAVES` = 100 per account (oldest go
first). Primary key `(uuid, save_id)`; `score`, `loadout` (jsonb, 24 petal ids), `created_at`. A player restores one
and it is removed.

**`gardn.crash_backups`** (0 rows now, filled while somebody plays) who is in the world of gardn right now, sent by
the game server every 30 seconds: `uuid` (key), `score`, `loadout`, `updated_at`. It holds exactly the last list
that was sent. On every start of a primary master, and when the Pi takes over, the rows are turned into
`gardn.saves` and the table is emptied. A standby keeps them. Players in gardn's **sandbox** are never in it.

### Schema `leaderboards`

**`leaderboards.entries`** (49 rows) one row per `(board, uuid)`: `score`, `extra` (jsonb), `updated_at`. The boards:

| Board | Game | Counts |
|---|---|---|
| `rr_level` | Parteria | level |
| `rr_pvp_kills`, `rr_pvp_best` | Parteria | kills in the PvP zone, best score there |
| `rr_ancient_attempts`, `rr_ancients`, `rr_ancient_kills` | Parteria | tries to craft an Ancient, Ancients owned, Ancients killed |
| `rr_kills` | Parteria | mobs killed |
| `gardn_kills`, `gardn_best_score`, `gardn_mythics` | gardn | kills of players, best score of a save, mythic petals in saves |
| `mg_ctf_wins`, `mg_tdm_wins`, `mg_has_wins` | Parteria minigames | matches won (only when the host typed the PIN) |
| `mg_ctf_played`, `mg_tdm_played`, `mg_has_played` | hidden | matches played (the profile shows "won x, lost y") |

Counts on 2026-11-08: `gardn_best_score` 7, `gardn_kills` 5, `gardn_mythics` 2, `rr_level` 13, `rr_kills` 11, the other
Parteria boards 1 to 3 each. Nothing from gardn's sandbox is ever written here.

### Schema `sync` (replication, not game data)

**`sync.meta`** `source_id` (which database the change list belongs to) and `pruned_before` (how far back the list
goes). **`sync.changes`** (47 rows) the change log: `id`, `xid`, `at`, `tbl`, `op` (`U` or `D`), `data` (the whole row
as jsonb). The function `sync.capture()` and the triggers fill it. A backup machine that applies the feed sets
`sync.applying` so its own copy does not log what it receives.

## Replication between the two machines

`dual-server-syncing/syncd.js` runs on both machines. The standby pulls `GET /backup` from the primary's master
(`X-Clone-Secret`): a full snapshot first, then only the row changes since its cursor. `dual-server-syncing/store.js`
applies them in foreign-key order. When the primary stops answering, the standby fences it, becomes primary, turns
the crash backups into saves and starts the tunnel. c1 is priority 1, the Pi is priority 2.

## MongoDB collections (only with `DB_BACKEND=mongo`)

One collection per section, in the configured database: `accounts` (`_id` = uuid), `account_links`
(`_id` = `provider:id`), `rysteria` (`_id` = uuid), `gardn` (`_id` = `uuid:save_id`, one document per save),
`leaderboards` (`_id` = `board:uuid`).

## In the master's memory (`tmpstore.c`, rate limits)

Password reset challenges, OAuth state, one-time OAuth codes and pending social sign-ups (they live minutes and are
lost on a restart), and the request counters of the rate limit (60 a minute per address). Bounded, expired entries
are dropped as they are found.

## Files

| File | What |
|---|---|
| `~/.rysteria-secrets/master.env`, `common.env`, `edge.env`, `gardn.env`, `rrolf-*.env`, `sync.env`, `nodes.conf` | settings and secrets of each machine (git-ignored; `scripts/push-secrets.sh` copies them). `POSTGRES_URI` is in `master.env`, the gardn command password in `gardn.env` |
| `~/.rysteria-secrets/sync-state.json` | syncd's state: its role, `wasPrimary`, the last sync and the cursor |
| `~/.rysteria-secrets/apple-rysteria.p8` | the Sign in with Apple key |
| `backup/*.sql.gz`, `backup/*.dump` | `pg_dump` copies of the database (git-ignored) |
| `builds/` | the built servers and clients (git-ignored) |
| `rrolf/Client/public/changelog.txt` | the changelog of both games (served at `/changelog.txt`, read by both clients when they start). Not a database, but it is the one file both games share |

## In the browser (`localStorage`)

| Key | Set by | What |
|---|---|---|
| `uuid`, `PL-P`, `PL-T` | the Parteria login page | the account id and the login tokens, shared with gardn (also passed in the address when the Gardn button opens it) |
| `rrolf_account_data`, `rrolf_cache_owner` | Parteria | a cache of the account, and whose it is |
| `version_hash` | both | the version of the page that is loaded |
| gardn: `nickname`, `settings`, `gamemode`, `petals`, `mobs`, `changelog`, `recovery_id` | gardn | the name, the options (mouse or keyboard movement and the others), the last mode (the sandbox is never kept), the petals and mobs seen, the changelog entries seen, the id used to come back to the same flower after a disconnect |

## What is not stored

Game worlds, chat, the position of players and the matches of the minigames are only in the game servers' memory.
Gardn's sandbox keeps nothing at all: no saves, no crash backups, no kills and no leaderboard rows.
