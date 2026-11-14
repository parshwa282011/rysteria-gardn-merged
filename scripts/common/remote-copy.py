#!/usr/bin/env python3
"""Copies the database of this machine into the online database, a few times a day.

The master works on the PostgreSQL of this machine (POSTGRES_URI, as often as it likes: it costs nothing).
Every REMOTE_COPY_INTERVAL seconds (default 1800 = 30 minutes) this copies what changed into the online
database (REMOTE_POSTGRES_URI, e.g. Prisma Postgres, which counts every request):

  * one request for ALL tables, made of ONE statement per table that changed. A statement writes the whole
    table: new and changed rows are upserted, rows that are not in the local table any more are deleted;
  * a table that did not change since the last copy (its fingerprint is the same) is not sent at all, and a
    cycle where nothing changed makes no request to the online database;
  * the local database is only read; the online one is the copy. Nothing here ever writes to the local one,
    except --pull.

Usage:
  remote-copy.py --once            one copy now
  remote-copy.py --loop            copy, wait REMOTE_COPY_INTERVAL, copy, ... (what run.sh starts)
  remote-copy.py --pull            the other way, once: replace the LOCAL database with the online one (to start a
                                   machine from what the online database holds, or after a new install)
  remote-copy.py --status          what was copied last
  --force      push even when the online database has data this machine never copied (first run), or when the
               local one has no accounts at all (a new install would wipe the online copy)
  --dry-run    say what would be sent, send nothing

Settings (environment, as in master.env): POSTGRES_URI, REMOTE_POSTGRES_URI, REMOTE_COPY_INTERVAL,
REMOTE_COPY_STATE (the state file). Looked up in the environment, then ./.env, then master.env / common.env of
~/.rysteria-secrets (or SECRETS_DIR); the state file defaults to ~/.rysteria-secrets/remote-copy-state.json.
"""
import argparse
import fcntl
import hashlib
import json
import os
import random
import subprocess
import sys
import time

# in foreign key order: parents first
TABLES = [
    ("accounts.accounts", ["uuid"]),
    ("accounts.links", ["uuid", "provider"]),
    ("rysteria.players", ["uuid"]),
    ("gardn.saves", ["uuid", "save_id"]),
    ("gardn.crash_backups", ["uuid"]),
    ("leaderboards.entries", ["board", "uuid"]),
]
SCHEMAS = ["accounts", "rysteria", "gardn", "leaderboards"]


def _read_env_file(path, only=None):
    """KEY=VALUE lines of a file for this process; what is already in the environment wins."""
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                if only is None or key in only:
                    os.environ.setdefault(key, value.strip())
    except OSError:
        pass


def load_env():
    """Settings: the environment first, then the .env next to this script's working folder (what run.sh's build
    writes), then the secrets folder (SECRETS_DIR, default ~/.rysteria-secrets): so the script also works when
    started by hand from anywhere."""
    _read_env_file(".env")
    secrets = os.environ.get("SECRETS_DIR") or os.path.expanduser("~/.rysteria-secrets")
    _read_env_file(os.path.join(secrets, "master.env"), {"POSTGRES_URI", "REMOTE_POSTGRES_URI"})
    _read_env_file(os.path.join(secrets, "common.env"), {"REMOTE_COPY_INTERVAL"})
    # one state file for every way of starting it (run.sh, by hand), so a --pull is remembered by the loop
    os.environ.setdefault("REMOTE_COPY_STATE", os.path.join(secrets, "remote-copy-state.json"))


def log(msg):
    print(time.strftime("[%Y-%m-%d %H:%M:%S] ") + msg, flush=True)


class Db:
    """One PostgreSQL, spoken to through psql (it is on every machine that has a PostgreSQL)."""

    def __init__(self, uri, name):
        self.uri = uri
        self.name = name
        self.requests = 0  # requests sent to this database

    def run(self, sql, script=False):
        """Runs sql and returns its output. script=True: sql goes in through stdin (a big one)."""
        env = dict(os.environ, PGCONNECT_TIMEOUT="20", PGOPTIONS="-c statement_timeout=300000")
        cmd = ["psql", self.uri, "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"]
        if script:
            cmd += ["-f", "-"]
            proc = subprocess.run(cmd, input=sql, capture_output=True, text=True, env=env)
        else:
            cmd += ["-c", sql]
            proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
        self.requests += 1
        if proc.returncode != 0:
            raise RuntimeError(f"{self.name}: {proc.stderr.strip() or 'psql failed'}")
        return proc.stdout

    def has_tables(self, tables):
        """True when every table is there (one request)."""
        checks = " and ".join(f"to_regclass('{t}') is not null" for t in tables)
        return self.run(f"select {checks}").strip() == "t"

    def columns(self, table):
        schema, name = table.split(".")
        out = self.run(
            "select column_name from information_schema.columns "
            f"where table_schema='{schema}' and table_name='{name}' order by ordinal_position"
        )
        return [c for c in out.split("\n") if c]

    def fingerprint(self, table, pk):
        order = ", ".join(pk)
        out = self.run(
            f"select count(*) || ' ' || coalesce(md5(string_agg(t::text, '|' order by {order})), '') from {table} t"
        )
        return out.strip()

    def rows_json(self, table, pk):
        order = ", ".join(pk)
        return self.run(f"select coalesce(jsonb_agg(t order by {order}), '[]'::jsonb)::text from {table} t").strip()


def table_statement(table, pk, columns, rows_json):
    """ONE statement that makes `table` hold exactly the rows of rows_json: upsert, and delete the rest."""
    while True:
        tag = "rs" + "".join(random.choice("abcdef0123456789") for _ in range(10))
        if f"${tag}$" not in rows_json:
            break
    rest = [c for c in columns if c not in pk]
    on_pk = ", ".join(pk)
    if rest:
        sets = ", ".join(f"{c} = EXCLUDED.{c}" for c in rest)
        old = ", ".join(f"t.{c}" for c in rest)
        new = ", ".join(f"EXCLUDED.{c}" for c in rest)
        # a row that is the same is not written again
        conflict = f"ON CONFLICT ({on_pk}) DO UPDATE SET {sets} WHERE ({old}) IS DISTINCT FROM ({new})"
    else:
        conflict = f"ON CONFLICT ({on_pk}) DO NOTHING"
    match = " AND ".join(f"s.{c} = d.{c}" for c in pk)
    return (
        f"WITH src AS (SELECT * FROM jsonb_populate_recordset(NULL::{table}, ${tag}${rows_json}${tag}$::jsonb)), "
        f"up AS (INSERT INTO {table} AS t SELECT * FROM src {conflict} RETURNING 1) "
        f"DELETE FROM {table} d WHERE NOT EXISTS (SELECT 1 FROM src s WHERE {match})"
    )


def ensure_schema(src, dst):
    """Makes the tables on dst when it has none yet: the same as src (pg_dump of the four schemas, no data)."""
    if dst.has_tables([t for t, _ in TABLES]):
        return
    log(f"{dst.name} has no tables yet: making them like {src.name}")
    cmd = ["pg_dump", src.uri, "--schema-only", "--no-owner", "--no-privileges", "--no-comments"]
    for s in SCHEMAS:
        cmd += ["-n", s]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"pg_dump of {src.name} failed: {proc.stderr.strip()}")
    # the change log triggers of the time of syncd are not wanted
    sql = "\n".join(l for l in proc.stdout.split("\n") if not l.startswith("CREATE TRIGGER sync_capture "))
    dst.run(sql, script=True)


def copy(src, dst, state_fp=None, dry=False):
    """Copies the tables that changed (their fingerprint is not the one in state_fp) from src to dst in one
    request. Returns the new fingerprints of the tables of src."""
    fps = {}
    statements = []
    sent = []
    for table, pk in TABLES:
        fp = src.fingerprint(table, pk)
        fps[table] = fp
        if state_fp is not None and state_fp.get(table) == fp:
            continue
        rows = src.rows_json(table, pk)
        statements.append(table_statement(table, pk, src.columns(table), rows))
        sent.append(f"{table} ({fp.split()[0]} rows)")
    if not statements:
        log("nothing changed: no request to " + dst.name)
        return fps
    if dry:
        log("would send to " + dst.name + ": " + ", ".join(sent))
        return fps
    # \; keeps the statements together as ONE request, which PostgreSQL runs as one transaction
    dst.run(" \\;\n".join(statements) + ";\n", script=True)
    log(f"copied to {dst.name} in 1 request: " + ", ".join(sent))
    return fps


class State:
    def __init__(self, path):
        self.path = path
        self.data = {"fingerprints": {}, "last_ok": 0, "runs": 0}
        try:
            with open(path) as f:
                self.data.update(json.load(f))
        except (OSError, ValueError):
            pass

    @property
    def known(self):
        return bool(self.data["fingerprints"])

    def save(self, fps):
        self.data["fingerprints"] = fps
        self.data["last_ok"] = int(time.time())
        self.data["runs"] = self.data.get("runs", 0) + 1
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.data, f, indent=1)
        os.replace(tmp, self.path)


def account_count(db):
    return int(db.run("select count(*) from accounts.accounts").strip() or 0)


def push(local, remote, state, force, dry):
    if not local.has_tables([t for t, _ in TABLES]):
        raise RuntimeError(f"{local.name} has no tables yet (is the master started?)")
    if not state.known:
        ensure_schema(local, remote)  # (only the first time: a cycle with nothing to copy asks nothing online)
    mine = account_count(local)
    if not force and mine == 0:
        raise RuntimeError("the local database has no accounts: not copying, that would empty the online one "
                           "(--force if that is what you want)")
    if not state.known and not force:
        # the first copy: the online database must not hold data this machine never saw
        theirs = {t: remote.fingerprint(t, pk) for t, pk in TABLES}
        ours = {t: local.fingerprint(t, pk) for t, pk in TABLES}
        if any(theirs[t].split()[0] != "0" for t in theirs) and theirs != ours:
            raise RuntimeError("the online database has data that is not in the local one, and this machine never "
                               "copied before. Start from the online data with --pull, or --force to replace it")
    known = state.data["fingerprints"] if state.known else None
    try:
        fps = copy(local, remote, known, dry)
    except RuntimeError as e:
        if "does not exist" not in str(e) or dry:
            raise
        # the online tables are gone: make them again and send everything
        ensure_schema(local, remote)
        fps = copy(local, remote, None, dry)
    if not dry:
        state.save(fps)


def pull(local, remote, state, dry):
    if not remote.has_tables([t for t, _ in TABLES]):
        raise RuntimeError(f"{remote.name} has no tables: nothing to pull")
    ensure_schema(remote, local)
    fps = copy(remote, local, None, dry)
    if not dry:
        # what is local now is what the online database holds: the next push has nothing to send
        state.save({t: local.fingerprint(t, pk) for t, pk in TABLES})
    return fps


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--loop", action="store_true")
    mode.add_argument("--pull", action="store_true")
    mode.add_argument("--status", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--interval", type=int)
    ap.add_argument("--state")
    load_env()
    ap.set_defaults(interval=int(os.environ.get("REMOTE_COPY_INTERVAL", "1800")),
                    state=os.environ.get("REMOTE_COPY_STATE", "remote-copy-state.json"))
    args = ap.parse_args()

    state = State(args.state)
    if args.status:
        if not state.known:
            print("never copied")
        else:
            print(f"last copy {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(state.data['last_ok']))}, "
                  f"{state.data['runs']} copies")
        return 0

    local_uri = os.environ.get("POSTGRES_URI", "")
    remote_uri = os.environ.get("REMOTE_POSTGRES_URI", "")
    if not local_uri or not remote_uri:
        secrets = os.environ.get("SECRETS_DIR") or os.path.expanduser("~/.rysteria-secrets")
        print("POSTGRES_URI and REMOTE_POSTGRES_URI must be set: in the environment, in ./.env, or in "
              f"{secrets}/master.env. Missing: " +
              ", ".join(k for k, v in (("POSTGRES_URI", local_uri), ("REMOTE_POSTGRES_URI", remote_uri)) if not v),
              file=sys.stderr)
        return 2
    if local_uri == remote_uri:
        print("POSTGRES_URI and REMOTE_POSTGRES_URI are the same database", file=sys.stderr)
        return 2
    local, remote = Db(local_uri, "local"), Db(remote_uri, "online")

    # one copier at a time
    lock = open(args.state + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("another remote-copy is running", file=sys.stderr)
        return 3

    if args.pull:
        try:
            pull(local, remote, state, args.dry_run)
        except RuntimeError as e:
            log(f"pull failed: {e}")
            return 1
        return 0

    while True:
        before = remote.requests
        try:
            push(local, remote, state, args.force, args.dry_run)
        except RuntimeError as e:
            log(f"copy failed, will try again: {e}")
            if args.once:
                return 1
        if args.once:
            return 0
        wait = f"{args.interval // 60} minutes" if args.interval >= 120 else f"{args.interval} seconds"
        log(f"next copy in {wait} ({remote.requests - before} requests to the online database this time)")
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
