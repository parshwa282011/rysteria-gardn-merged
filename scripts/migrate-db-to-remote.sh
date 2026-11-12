#!/usr/bin/env bash
# Copies the data of one machine's local PostgreSQL into the remote database that
# POSTGRES_URI of secrets/master.env points at (Prisma Postgres, Neon, ...), so that the
# masters of every machine can use that one database. Syncing (syncd) is not needed then.
#
# Usage: scripts/migrate-db-to-remote.sh user@host [--force] [--key FILE]
#   user@host   the machine whose local database has the data (its master.env is read for the
#               old connection string: OLD_POSTGRES_URI, or POSTGRES_URI while it is still local)
#   --force     replace what is already in the remote schemas. Without it the script stops when the
#               remote database has accounts in it, so that a running game is never overwritten.
#   --key FILE  ssh key (default ~/.ssh/id_c1 if it exists)
#
# What it does: pg_dump of the schemas accounts, rysteria, gardn and leaderboards (data and tables),
# without the sync_capture triggers (the change log is only for syncd), kept as backup/*.sql.gz,
# loaded into the remote database in ONE transaction, then every table is counted on both sides.
#
# To move the data again just before the masters are switched (stop them on the old machines first,
# or what they write in between is lost): scripts/migrate-db-to-remote.sh user@host --force
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src=""
force=0
key=""
[ -f "$HOME/.ssh/id_c1" ] && key="$HOME/.ssh/id_c1"
while [ $# -gt 0 ]; do
    case "$1" in
    --force) force=1 ;;
    --key) shift; key="${1:?--key needs a file}" ;;
    -h | --help) sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) src="$1" ;;
    esac
    shift
done
[ -n "$src" ] || { echo "usage: $0 user@host [--force] [--key FILE]" >&2; exit 2; }

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
env_get() { grep -E "^$2=" "$1" 2>/dev/null | head -n1 | cut -d= -f2- || true; }

target="$(env_get "$here/secrets/master.env" POSTGRES_URI)"
[ -n "$target" ] || die "no POSTGRES_URI in $here/secrets/master.env"
case "$target" in *127.0.0.1* | *localhost*) die "POSTGRES_URI in secrets/master.env is still a local database" ;; esac
command -v psql >/dev/null || die "psql is not installed here"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
[ -n "$key" ] && ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)

tables=(accounts.accounts accounts.links rysteria.players gardn.saves gardn.crash_backups leaderboards.entries)
count_sql=""
for t in "${tables[@]}"; do count_sql+="select '$t', count(*) from $t union all "; done
count_sql="${count_sql% union all } order by 1"

echo "==> remote database: $(printf '%s' "$target" | sed -E 's#(://[^:]+:)[^@]*@#\1***@#')"
if [ "$force" = 0 ]; then
    existing="$(psql "$target" -X -At -c "select to_regclass('accounts.accounts') is not null and exists (select 1 from accounts.accounts)" 2>/dev/null || echo f)"
    [ "$existing" != t ] || die "the remote database already has accounts in it. Run again with --force to replace them"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$here/backup"
dump="$(mktemp)"
trap 'rm -f "$dump"' EXIT
echo "==> dumping the database of $src"
ssh "${ssh_opts[@]}" "$src" 'export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    f="$HOME/.rysteria-secrets/master.env"
    U=$(grep "^OLD_POSTGRES_URI=" "$f" | head -n1 | cut -d= -f2-)
    [ -n "$U" ] || U=$(grep "^POSTGRES_URI=" "$f" | head -n1 | cut -d= -f2-)
    case "$U" in *127.0.0.1*|*localhost*) ;; *) echo "no local database string in $f" >&2; exit 1 ;; esac
    pg_dump "$U" -n accounts -n rysteria -n gardn -n leaderboards --no-owner --no-privileges --no-comments' \
    | grep -v '^CREATE TRIGGER sync_capture ' >"$dump"
grep -q '^COPY accounts.accounts' "$dump" || die "the dump has no accounts table in it"
gzip -c "$dump" >"$here/backup/rysteria-$stamp-before-remote.sql.gz"
chmod 600 "$here/backup/rysteria-$stamp-before-remote.sql.gz"
echo "    kept as backup/rysteria-$stamp-before-remote.sql.gz"

echo "==> loading it into the remote database (one transaction)"
{
    if [ "$force" = 1 ]; then
        echo "DROP SCHEMA IF EXISTS accounts, rysteria, gardn, leaderboards CASCADE;"
    fi
    cat "$dump"
} | psql "$target" -X -q -v ON_ERROR_STOP=1 --single-transaction -f - >/dev/null

echo "==> row counts (source | remote)"
src_counts="$(ssh "${ssh_opts[@]}" "$src" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH
    f=\$HOME/.rysteria-secrets/master.env
    U=\$(grep '^OLD_POSTGRES_URI=' \$f | head -n1 | cut -d= -f2-)
    [ -n \"\$U\" ] || U=\$(grep '^POSTGRES_URI=' \$f | head -n1 | cut -d= -f2-)
    psql \"\$U\" -X -At -c \"$count_sql\"")"
dst_counts="$(psql "$target" -X -At -c "$count_sql")"
paste -d' ' <(printf '%s\n' "$src_counts") <(printf '%s\n' "$dst_counts") | awk -F'[| ]' '{ printf "    %-24s %5s | %5s %s\n", $1, $2, $4, ($2==$4 ? "ok" : "DIFFERENT") }'
[ "$src_counts" = "$dst_counts" ] || die "the counts differ"
echo "done."
