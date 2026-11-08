#!/usr/bin/env python3
"""Compares the data of the PostgreSQL databases of two machines (the first two of secrets/nodes.conf: c1 and the Pi).

    python3 scripts/compare-db.py                 the summary: rows per table, what is only on one side,
                                                  what is on both but is not the same
    python3 scripts/compare-db.py --detail        also which columns differ (and the values, except the
                                                  secret columns: they only say "differs")
    python3 scripts/compare-db.py --a c1 --b pi --key ~/.ssh/id_c1   (the names are the ones of secrets/nodes.conf)

Every table of the schemas accounts, rysteria, gardn and leaderboards is compared, whichever
tables there are (found through the primary keys). Each machine hashes its own rows (md5 of the
whole row) and only the hashes and keys come here, so nothing secret leaves a machine unless
--detail asks for the other columns of the rows that differ. Only SELECTs are run.

The Pi copies c1 through syncd every few seconds, so a row that changed a moment ago can show
up as different: run it again. Exit code 0 = the same, 1 = different, 2 = could not ask.
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMAS = ("accounts", "rysteria", "gardn", "leaderboards")
SECRET_COLUMNS = ("pw_hash", "token_key", "provider_token")


def nodes():
    """name -> ssh target, from secrets/nodes.conf (name os lan ssh repo)"""
    for path in (os.path.join(ROOT, "secrets", "nodes.conf"), os.path.join(ROOT, "dual-server-syncing", "nodes.conf")):
        if os.path.exists(path):
            break
    else:
        sys.exit("no secrets/nodes.conf")
    found = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 4 and not line.lstrip().startswith("#") and parts[3] != "-":
            found[parts[0]] = parts[3]
    return found


def ask(target, key, sql):
    """runs the SQL with psql on the machine, with the POSTGRES_URI of its master.env, returns the lines.
    A target that starts with postgres:// is a database to reach from here, for tests."""
    if target.startswith("postgres"):
        result = subprocess.run(["psql", target, "-Atq", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
        if result.returncode != 0:
            sys.stderr.write("could not ask the database: %s\n" % (result.stderr or "").strip()[-400:])
            sys.exit(2)
        return [line for line in result.stdout.splitlines() if line.strip()]
    remote = ("bash -l -c 'U=$(grep -E \"^POSTGRES_URI=\" ~/.rysteria-secrets/master.env | cut -d= -f2-); "
              "[ -n \"$U\" ] || { echo no POSTGRES_URI in master.env >&2; exit 3; }; psql \"$U\" -Atq -v ON_ERROR_STOP=1'")
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    if key:
        cmd += ["-i", key, "-o", "IdentitiesOnly=yes"]
    result = subprocess.run(cmd + [target, remote], input=sql, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write("could not ask %s: %s\n" % (target, (result.stderr or "").strip()[-400:]))
        sys.exit(2)
    return [line for line in result.stdout.splitlines() if line.strip()]


TABLES_SQL = """
select json_build_object('t', n.nspname || '.' || c.relname, 'pk', pk.cols)::text
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join lateral (
    select string_agg(format('t.%%I::text', a.attname), ', ' order by array_position(i.indkey::int2[], a.attnum)) as cols
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
    where i.indrelid = c.oid and i.indisprimary
) pk on true
where c.relkind = 'r' and n.nspname in (%s) and pk.cols is not null
order by 1;
""" % ", ".join("'%s'" % s for s in SCHEMAS)


def hashes_sql(tables):
    parts = ["select json_build_object('t', '%s', 'k', concat_ws(':', %s), 'h', md5(t::text))::text from %s t"
             % (name, pk, name) for name, pk in tables]
    return "\nunion all\n".join(parts) + ";\n"


def rows_sql(tables):
    strip = "".join(" - '%s'" % c for c in SECRET_COLUMNS)
    parts = ["select json_build_object('t', '%s', 'k', concat_ws(':', %s), 'row', to_jsonb(t)%s)::text from %s t"
             % (name, pk, strip, name) for name, pk in tables]
    return "\nunion all\n".join(parts) + ";\n"


def shorten(value):
    text = json.dumps(value) if not isinstance(value, str) else value
    return text if len(text) <= 60 else text[:57] + "..."


def main():
    parser = argparse.ArgumentParser(description="Compares the PostgreSQL data of two machines.")
    parser.add_argument("--a", default="", help="the first machine, a name of nodes.conf (default: the first one, c1)")
    parser.add_argument("--b", default="", help="the second machine (default: the second one, the Pi)")
    parser.add_argument("--detail", action="store_true", help="say which columns differ")
    parser.add_argument("--key", default=os.path.expanduser("~/.ssh/id_c1") if os.path.exists(os.path.expanduser("~/.ssh/id_c1")) else "",
                        help="ssh key (default ~/.ssh/id_c1)")
    parser.add_argument("--limit", type=int, default=15, help="how many keys to list per table (default 15)")
    args = parser.parse_args()

    known = nodes()
    # a postgres://... address instead of a name is a database to reach from here (tests)
    for flag, label in (("a", "db1"), ("b", "db2")):
        if getattr(args, flag).startswith("postgres"):
            known[label] = getattr(args, flag)
            setattr(args, flag, label)
    names = list(known)
    if len(names) < 2 and not (args.a and args.b):
        sys.exit("nodes.conf has fewer than two machines")
    args.a = args.a or names[0]
    args.b = args.b or names[1]
    for name in (args.a, args.b):
        if name not in known:
            sys.exit("%s is not in nodes.conf (it has: %s)" % (name, ", ".join(known)))
    side = {args.a: known[args.a], args.b: known[args.b]}

    # the tables: the same on both when they run the same version, so each side lists its own
    tables = {}
    for name, target in side.items():
        tables[name] = [(j["t"], j["pk"]) for j in map(json.loads, ask(target, args.key, TABLES_SQL))]
    both = sorted(set(tables[args.a]) & set(tables[args.b]))
    for name in (args.a, args.b):
        missing = sorted(set(tables[name]) - set(both))
        if missing:
            print("only on %s (not compared): %s" % (name, ", ".join(t for t, _ in missing)))
    if not both:
        sys.exit("no table to compare")

    data = {}
    for name, target in side.items():
        data[name] = {}
        for line in ask(target, args.key, hashes_sql(both)):
            j = json.loads(line)
            data[name][(j["t"], j["k"])] = j["h"]

    a, b = data[args.a], data[args.b]
    width = max(len(t) for t, _ in both)
    print("%-*s  %8s  %8s  %8s  %8s  %8s" % (width, "table", args.a, args.b, "only " + args.a, "only " + args.b, "differ"))
    different = {}
    total_diff = 0
    for table, _ in both:
        ka = {k for (t, k) in a if t == table}
        kb = {k for (t, k) in b if t == table}
        only_a, only_b = sorted(ka - kb), sorted(kb - ka)
        differ = sorted(k for k in ka & kb if a[(table, k)] != b[(table, k)])
        total_diff += len(only_a) + len(only_b) + len(differ)
        print("%-*s  %8d  %8d  %8d  %8d  %8d%s" % (width, table, len(ka), len(kb), len(only_a), len(only_b), len(differ),
                                                     "" if not (only_a or only_b or differ) else "   <--"))
        if only_a or only_b or differ:
            different[table] = (only_a, only_b, differ)

    if not different:
        print("\nthe two databases hold the same rows")
        return 0

    print()
    pk_of = dict(both)
    detail = {}
    if args.detail:
        wanted = [(t, pk_of[t]) for t in different if different[t][2]]
        if wanted:
            for name, target in side.items():
                detail[name] = {}
                for line in ask(target, args.key, rows_sql(wanted)):
                    j = json.loads(line)
                    detail[name][(j["t"], j["k"])] = j["row"]
    for table, (only_a, only_b, differ) in different.items():
        print(table)
        for label, keys in (("only on " + args.a, only_a), ("only on " + args.b, only_b), ("different", differ)):
            if not keys:
                continue
            shown = keys[:args.limit]
            print("  %s (%d): %s%s" % (label, len(keys), ", ".join(shown), " ..." if len(keys) > len(shown) else ""))
        if args.detail:
            for k in differ[:args.limit]:
                ra, rb = detail.get(args.a, {}).get((table, k)), detail.get(args.b, {}).get((table, k))
                if ra is None or rb is None:
                    continue
                cols = [c for c in sorted(set(ra) | set(rb)) if ra.get(c) != rb.get(c)]
                if not cols:
                    print("    %s: only the secret columns (%s) differ" % (k, ", ".join(SECRET_COLUMNS)))
                for c in cols:
                    va, vb = ra.get(c), rb.get(c)
                    if isinstance(va, dict) and isinstance(vb, dict):
                        # a json column (the inventory...): say which entries differ
                        for entry in sorted(set(va) | set(vb)):
                            if va.get(entry) != vb.get(entry):
                                print("    %s . %s[%s]: %s = %s, %s = %s" % (k, c, entry, args.a, shorten(va.get(entry)), args.b, shorten(vb.get(entry))))
                    else:
                        print("    %s . %s: %s = %s, %s = %s" % (k, c, args.a, shorten(va), args.b, shorten(vb)))
    print("\n%d difference(s). The Pi copies c1 every few seconds: run it again before believing a row that is very new." % total_diff)
    return 1


if __name__ == "__main__":
    sys.exit(main())
