#!/usr/bin/env python3
"""Makes the PostgreSQL databases of two machines the same, row by row, after asking you.

    python3 scripts/reconcile-db.py            asks about every difference, then shows the plan and stops
    python3 scripts/reconcile-db.py --apply    the same, and after you type "yes" it does the plan

It finds what is different the way scripts/compare-db.py does (every table of the schemas accounts,
rysteria, gardn and leaderboards, every row hashed on its own machine). For each row that is only on one
side or is not the same on both it shows a card: the table, the key, whose account it is (username, when
it was made, last login, the email only as yes/no), and for a row that is on both which columns differ and
what they hold on each side. The secret columns (password hash, token key, provider token) are never
shown; they only say "differs". You answer per row:

    row on both, not the same:   1 = keep the first machine's version   2 = keep the second machine's
    row only on one machine:     c = copy it to the other machine       d = delete it where it is
    s = skip it, q = stop asking.  Add ! (1!, 2!, c!, d!) to answer the same for everything left.

Nothing is changed until you type yes at the end (and only with --apply). Before it changes anything it
makes a pg_dump on each machine it writes to (in the home folder: rysteria-before-reconcile-<time>.dump,
restore with pg_restore --clean) and it checks again that every row is still the way you saw it: a row
that changed in the meantime (a player is playing: c1 is live) is skipped and listed. Each machine is
changed in one transaction: all of it or none of it.

Which way the changes go matters for the copy that the machines keep up with each other (syncd):
  - a change to the PRIMARY (c1, or --primary NAME) is seen by syncd, which copies it to the other machine
  - a change to the other machine is made quietly (sync.applying = 1), so that it is not copied back
Deleting an account deletes its saves, links, player and leaderboard rows with it (ON DELETE CASCADE).
Exit code 0 = done or nothing to do, 1 = stopped, 2 = could not ask.
"""
import argparse
import datetime
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("compare_db", os.path.join(HERE, "compare-db.py"))
cmp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cmp)

SECRET = cmp.SECRET_COLUMNS + ("email", "email_lower")   # (the email is only shown as yes / no)
ORDER = ["accounts.accounts", "accounts.links", "rysteria.players", "gardn.saves", "gardn.crash_backups", "leaderboards.entries"]

TABLES_SQL = """
select json_build_object('t', n.nspname || '.' || c.relname, 'pk', pk.cols, 'names', pk.names)::text
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join lateral (
    select string_agg(format('t.%%I::text', a.attname), ', ' order by array_position(i.indkey::int2[], a.attnum)) as cols,
           json_agg(a.attname order by array_position(i.indkey::int2[], a.attnum)) as names
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
    where i.indrelid = c.oid and i.indisprimary
) pk on true
where c.relkind = 'r' and n.nspname in (%s) and pk.cols is not null
order by 1;
""" % ", ".join("'%s'" % s for s in cmp.SCHEMAS)


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def table_sql(name):
    return ".".join(quote(part) for part in name.split("."))


def rows_sql(tables):
    parts = ["select json_build_object('t', '%s', 'k', concat_ws(':', %s), 'row', to_jsonb(t))::text from %s t"
             % (name, pk, table_sql(name)) for name, pk in tables]
    return "\nunion all\n".join(parts) + ";\n"


def hashes_sql(tables):
    parts = ["select json_build_object('t', '%s', 'k', concat_ws(':', %s), 'h', md5(t::text))::text from %s t"
             % (name, pk, table_sql(name)) for name, pk in tables]
    return "\nunion all\n".join(parts) + ";\n"


def fetch_hashes(target, key, tables):
    out = {}
    for line in cmp.ask(target, key, hashes_sql(tables)):
        j = json.loads(line)
        out[(j["t"], j["k"])] = j["h"]
    return out


def fetch_rows(target, key, tables):
    out = {}
    if not tables:
        return out
    for line in cmp.ask(target, key, rows_sql(tables)):
        j = json.loads(line)
        out[(j["t"], j["k"])] = j["row"]
    return out


def when(epoch):
    try:
        return datetime.datetime.fromtimestamp(int(epoch)).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return "?"


def shorten(value, n=60):
    text = value if isinstance(value, str) else json.dumps(value)
    return text if len(text) <= n else text[: n - 3] + "..."


def show_value(column, value):
    if column in cmp.SECRET_COLUMNS:
        return "(secret)"
    if column in ("email", "email_lower"):
        return "yes" if value else "no"
    return shorten(value)


def account_line(accounts, uuid):
    if not uuid:
        return ""
    parts = []
    for side, info in accounts.items():
        a = info.get(uuid)
        if a is None:
            parts.append("%s: no such account" % side)
        else:
            parts.append("%s: %s, made %s, last login %s, email %s%s" % (
                side, a["username"], when(a["created_at"]), when(a["last_login_at"]) if a["last_login_at"] else "never",
                "yes" if a["email"] else "no", ", verified" if a["email_verified"] else ""))
    return "\n      ".join(parts)


def ask_choice(prompt, allowed):
    while True:
        try:
            answer = input(prompt).strip().lower()
        except EOFError:
            return "q"
        if answer in allowed:
            return answer
        print("      choose one of: " + " ".join(sorted(allowed)))


def upsert_sql(table, names, row):
    columns = list(row)
    payload = json.dumps(row)
    if "$rowjson$" in payload:
        raise SystemExit("a row holds $rowjson$: refusing to build SQL from it")
    sets = ", ".join("%s = EXCLUDED.%s" % (quote(c), quote(c)) for c in columns if c not in names)
    return ("INSERT INTO %s SELECT * FROM jsonb_populate_record(NULL::%s, $rowjson$%s$rowjson$::jsonb) ON CONFLICT (%s) %s;"
            % (table_sql(table), table_sql(table), payload, ", ".join(quote(n) for n in names),
               ("DO UPDATE SET " + sets) if sets else "DO NOTHING"))


def delete_sql(table, names, row):
    payload = json.dumps({n: row[n] for n in names})
    keycols = ", ".join(quote(n) for n in names)
    return ("DELETE FROM %s WHERE (%s) = (SELECT %s FROM jsonb_populate_record(NULL::%s, $rowjson$%s$rowjson$::jsonb));"
            % (table_sql(table), keycols, keycols, table_sql(table), payload))


def dump(target, key, label):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    name = "rysteria-before-reconcile-%s.dump" % stamp
    if target.startswith("postgres"):
        path = os.path.join(os.environ.get("TMPDIR", "/tmp"), name)
        result = subprocess.run(["pg_dump", "-Fc", target, "-f", path], capture_output=True, text=True)
        where = path
    else:
        remote = ("bash -l -c 'U=$(grep -E \"^POSTGRES_URI=\" ~/.rysteria-secrets/master.env | cut -d= -f2-); "
                  "pg_dump -Fc \"$U\" -f ~/%s && ls -la ~/%s'" % (name, name))
        ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"] + (["-i", key, "-o", "IdentitiesOnly=yes"] if key else [])
        result = subprocess.run(ssh + [target, remote], capture_output=True, text=True)
        where = "%s:~/%s" % (target, name)
    if result.returncode != 0:
        raise SystemExit("could not make the backup of %s, nothing was changed: %s" % (label, (result.stderr or "").strip()[-300:]))
    print("   backup of %s: %s" % (label, where))
    return where


def main():
    parser = argparse.ArgumentParser(description="Makes the databases of two machines the same, after asking.")
    parser.add_argument("--a", default="", help="the first machine, a name of secrets/nodes.conf (default: the first, c1)")
    parser.add_argument("--b", default="", help="the second machine (default: the second, the Pi)")
    parser.add_argument("--primary", default="", help="the machine the other copies from (default: the first)")
    parser.add_argument("--apply", action="store_true", help="really do the plan (after you type yes)")
    parser.add_argument("--key", default=os.path.expanduser("~/.ssh/id_c1") if os.path.exists(os.path.expanduser("~/.ssh/id_c1")) else "",
                        help="ssh key (default ~/.ssh/id_c1)")
    args = parser.parse_args()

    known = cmp.nodes()
    names = list(known)

    def resolve(spec, index):
        if spec.startswith("postgres"):          # a database to reach from here (tests)
            return "db%d" % (index + 1), spec
        spec = spec or (names[index] if len(names) > index else "")
        if spec not in known:
            sys.exit("%s is not in nodes.conf (it has: %s)" % (spec or "?", ", ".join(names)))
        return spec, known[spec]

    name_a, target_a = resolve(args.a, 0)
    name_b, target_b = resolve(args.b, 1)
    primary = args.primary or name_a
    if primary not in (name_a, name_b):
        sys.exit("--primary must be %s or %s" % (name_a, name_b))
    targets = {name_a: target_a, name_b: target_b}
    other = {name_a: name_b, name_b: name_a}

    # ---- what is different
    tables = {}
    for name, target in targets.items():
        tables[name] = {}
        for line in cmp.ask(target, args.key, TABLES_SQL):
            j = json.loads(line)
            tables[name][j["t"]] = (j["pk"], j["names"])
    common = sorted(set(tables[name_a]) & set(tables[name_b]), key=lambda t: (ORDER.index(t) if t in ORDER else 99, t))
    if not common:
        sys.exit("no table to compare")
    pk = {t: tables[name_a][t][0] for t in common}
    pknames = {t: tables[name_a][t][1] for t in common}
    pairs = [(t, pk[t]) for t in common]
    hashes = {name: fetch_hashes(target, args.key, pairs) for name, target in targets.items()}

    diffs = []   # (table, key, kind) kind: both | only_<name>
    for t in common:
        ka = {k for (tt, k) in hashes[name_a] if tt == t}
        kb = {k for (tt, k) in hashes[name_b] if tt == t}
        for k in sorted(ka - kb):
            diffs.append((t, k, "only_" + name_a))
        for k in sorted(kb - ka):
            diffs.append((t, k, "only_" + name_b))
        for k in sorted(x for x in ka & kb if hashes[name_a][(t, x)] != hashes[name_b][(t, x)]):
            diffs.append((t, k, "both"))
    if not diffs:
        print("the two databases hold the same rows: nothing to do")
        return 0
    print("%d row(s) are different between %s and %s. Nothing is changed until you say so at the end.\n" % (len(diffs), name_a, name_b))

    # ---- the rows and the accounts
    wanted_tables = sorted({t for t, _, _ in diffs}, key=lambda t: common.index(t))
    rows = {name: fetch_rows(target, args.key, [(t, pk[t]) for t in wanted_tables]) for name, target in targets.items()}
    accounts = {}
    for name, target in targets.items():
        accounts[name] = {}
        sql = ("select json_build_object('uuid', uuid, 'username', username, 'created_at', created_at, 'last_login_at', last_login_at, "
               "'email', email <> '', 'email_verified', email_verified)::text from accounts.accounts;")
        for line in cmp.ask(target, args.key, sql):
            j = json.loads(line)
            accounts[name][j["uuid"]] = j

    # ---- ask
    plan = []    # {target, op, table, key, row, seen: {name: hash or None}}
    bulk = {}     # "both" / "only" -> the answer given with a ! for all that are left
    stop = False
    skipped = 0
    for index, (t, k, kind) in enumerate(diffs, 1):
        if stop:
            skipped += 1
            continue
        ra, rb = rows[name_a].get((t, k)), rows[name_b].get((t, k))
        row = ra or rb
        uuid = row.get("uuid") if row else None
        print("[%d/%d] %s   key %s   %s" % (index, len(diffs), t, k,
              "(on both, not the same)" if kind == "both" else "(only on %s)" % kind[5:]))
        if uuid:
            print("      account: " + account_line(accounts, uuid))
        stamp = max([int(row.get(c) or 0) for c in ("updated_at", "last_login_at") if isinstance(row.get(c), (int, float))] or [0])
        if stamp and time.time() - stamp < 120:
            print("      (changed %d s ago: it may only be on its way to the other machine)" % (time.time() - stamp))
        if kind == "both":
            for c in sorted(set(ra) | set(rb)):
                va, vb = ra.get(c), rb.get(c)
                if va == vb:
                    continue
                if isinstance(va, dict) and isinstance(vb, dict):
                    changed = [e for e in sorted(set(va) | set(vb)) if va.get(e) != vb.get(e)]
                    print("      %s: %d of %d entries differ" % (c, len(changed), len(set(va) | set(vb))))
                    for e in changed[:6]:
                        print("         %s: %s = %s, %s = %s" % (e, name_a, shorten(va.get(e), 30), name_b, shorten(vb.get(e), 30)))
                    if len(changed) > 6:
                        print("         ... and %d more" % (len(changed) - 6))
                else:
                    print("      %s: %s = %s, %s = %s" % (c, name_a, show_value(c, va), name_b, show_value(c, vb)))
            allowed = {"1", "2", "s", "q", "1!", "2!"}
            prompt = "      1 = keep %s's, 2 = keep %s's, s = skip, q = stop, 1! / 2! = for all that are left > " % (name_a, name_b)
        else:
            for c in sorted(row):
                print("      %s: %s" % (c, show_value(c, row[c])))
            here = kind[5:]
            allowed = {"c", "d", "s", "q", "c!", "d!"}
            prompt = "      c = copy to %s, d = delete it from %s, s = skip, q = stop, c! / d! = for all that are left > " % (other[here], here)
        group = "both" if kind == "both" else "only"
        if bulk.get(group):
            answer = bulk[group]
            print("      -> %s (as for all that were left)" % answer)
        else:
            answer = ask_choice(prompt, allowed)
            if answer.endswith("!"):
                answer = answer[0]
                bulk[group] = answer
        if answer == "q":
            stop = True
            skipped += 1
            continue
        if answer == "s":
            skipped += 1
            continue
        seen = {name_a: hashes[name_a].get((t, k)), name_b: hashes[name_b].get((t, k))}
        if kind == "both":
            source, dest = (name_a, name_b) if answer == "1" else (name_b, name_a)
            plan.append({"target": dest, "op": "upsert", "table": t, "key": k, "row": rows[source][(t, k)], "seen": seen,
                         "text": "%s: make %s hold %s's version" % (t, dest, source)})
        else:
            here = kind[5:]
            if answer == "c":
                plan.append({"target": other[here], "op": "upsert", "table": t, "key": k, "row": rows[here][(t, k)], "seen": seen,
                             "text": "%s: copy to %s" % (t, other[here])})
            else:
                plan.append({"target": here, "op": "delete", "table": t, "key": k, "row": rows[here][(t, k)], "seen": seen,
                             "text": "%s: delete from %s" % (t, here)})

    # ---- the plan
    print("\nthe plan (%d change(s), %d row(s) left alone):" % (len(plan), skipped))
    if not plan:
        print("   nothing")
        return 1 if skipped else 0
    for item in plan:
        who = ""
        uuid = item["row"].get("uuid")
        if uuid:
            a = accounts[name_a].get(uuid) or accounts[name_b].get(uuid)
            who = "  (" + a["username"] + ")" if a else ""
        print("   %s %s%s: %s" % (item["op"], item["key"], who, item["text"]))
    if any(i["op"] == "delete" and i["table"] == "accounts.accounts" for i in plan):
        print("\n   WARNING: deleting an account also deletes its saves, links, player and leaderboard rows.")
    if not args.apply:
        print("\nthis was a plan only: run it again with --apply to do it")
        return 1

    if input("\ntype yes to make a backup of each machine and do this > ").strip().lower() != "yes":
        print("nothing was changed")
        return 1

    # ---- backups, then check that nothing moved, then do it
    print()
    for name in sorted({i["target"] for i in plan}):
        dump(targets[name], args.key, name)
    fresh = {name: fetch_hashes(target, args.key, [(t, pk[t]) for t in sorted({i["table"] for i in plan})]) for name, target in targets.items()}
    doing, moved = [], []
    for item in plan:
        key = (item["table"], item["key"])
        if any(fresh[n].get(key) != item["seen"][n] for n in (name_a, name_b)):
            moved.append(item)
        else:
            doing.append(item)
    for item in moved:
        print("   skipped, it changed since you saw it: %s %s" % (item["table"], item["key"]))
    by_target = {}
    for item in doing:
        by_target.setdefault(item["target"], []).append(item)
    for name, items in by_target.items():
        upserts = sorted([i for i in items if i["op"] == "upsert"], key=lambda i: common.index(i["table"]))
        deletes = sorted([i for i in items if i["op"] == "delete"], key=lambda i: -common.index(i["table"]))
        sql = ["BEGIN;"]
        if name != primary:
            sql.append("SET LOCAL sync.applying = '1';   -- so that the change is not logged for the other machine")
        sql += [upsert_sql(i["table"], pknames[i["table"]], i["row"]) for i in upserts]
        sql += [delete_sql(i["table"], pknames[i["table"]], i["row"]) for i in deletes]
        sql.append("COMMIT;")
        cmp.ask(targets[name], args.key, "\n".join(sql) + "\n")
        print("   %s: %d change(s) done%s" % (name, len(items), "" if name != primary else " (syncd copies them to the other machine)"))

    # ---- and again
    print("\nthe same check again:")
    after = {name: fetch_hashes(target, args.key, pairs) for name, target in targets.items()}
    left = sum(1 for key in set(after[name_a]) | set(after[name_b]) if after[name_a].get(key) != after[name_b].get(key))
    print("   %d row(s) still differ%s" % (left, "" if not left else
          " (a change on %s takes a few seconds to reach the other machine: run scripts/compare-db.py in a moment)" % primary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
