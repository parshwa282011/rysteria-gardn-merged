#!/usr/bin/env bash
# Looks at the accounts in the live database and wipes the Rysteria progress of one.
# Run it from your computer: it asks the database on the main machine (the first one
# in secrets/nodes.conf) over ssh, with the POSTGRES_URI of ~/.rysteria-secrets/master.env
# there. The database runs on its own, so this works with the game servers stopped.
#
#   scripts/accounts.sh list [--dups]        every account: uuid, name, email, last login, how much
#                                            Rysteria and Gardn data it has. --dups only shows
#                                            accounts that share an e-mail address
#   scripts/accounts.sh wipe <name|uuid>     deletes the Rysteria save of the account and its
#                                            Rysteria leaderboard rows. The account, its
#                                            password and its Gardn saves stay. The player gets a
#                                            fresh start (5 basic petals) the next time they join
#   scripts/accounts.sh restore <name|uuid>  puts the Rysteria save back from the copy that
#                                            "wipe" kept (public.wiped_rysteria, the latest one)
#
# Options: --yes (do not ask), --node NAME (another machine of nodes.conf), --key FILE (ssh key,
#          default ~/.ssh/id_c1), --uri URI (use this database from here instead of a machine)
#
# The player has to be offline. While they are connected, the master keeps their save in
# memory and writes it back, so a wipe would be undone. Stop the servers, or wait until they
# have left and a few seconds have passed. The Pi gets the change on its own (the database
# logs every delete for it); the copy "wipe" keeps is only on the machine you ran it on.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"
[ $# -gt 0 ] && shift
NEEDLE=""; YES=0; DUPS=0; NODE=""; URI=""; KEY=""
[ -f "$HOME/.ssh/id_c1" ] && KEY="$HOME/.ssh/id_c1"
while [ $# -gt 0 ]; do
    case "$1" in
    --yes) YES=1 ;;
    --dups) DUPS=1 ;;
    --node) shift; NODE="${1:?--node needs a name}" ;;
    --key) shift; KEY="${1:?--key needs a file}" ;;
    --uri) shift; URI="${1:?--uri needs a postgresql:// address}" ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$NEEDLE" ] || { echo "one name or uuid at a time" >&2; exit 2; }; NEEDLE="$1" ;;
    esac
    shift
done
usage() { sed -n 2,/^set/p "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-0}"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
case "$CMD" in
list) ;;
wipe | restore) [ -n "$NEEDLE" ] || usage 2 ;;
-h | --help | help | "") usage 0 ;;
*) usage 2 ;;
esac
if [ -n "$NEEDLE" ] && ! [[ "$NEEDLE" =~ ^[A-Za-z0-9_.@-]{1,64}$ ]]; then
    die "\"$NEEDLE\" is not a username or uuid (letters, digits and _ . @ - only)"
fi

# ------------------------------------------------------------ the database
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
[ -n "$KEY" ] && SSH_OPTS+=(-i "$KEY" -o IdentitiesOnly=yes)
TARGET=""
if [ -z "$URI" ]; then
    nodes="$ROOT/secrets/nodes.conf"; [ -f "$nodes" ] || nodes="$ROOT/dual-server-syncing/nodes.conf"
    [ -f "$nodes" ] || die "no secrets/nodes.conf"
    TARGET="$(awk -v n="$NODE" '$1 !~ /^#/ && NF >= 5 && $4 != "-" && (n == "" || $1 == n) { print $4; exit }' "$nodes")"
    [ -n "$TARGET" ] || die "no machine${NODE:+ called $NODE} with an ssh target in $nodes"
fi

# psql with the SQL on stdin and these arguments
pg() {
    if [ -n "$URI" ]; then
        psql "$URI" -X -q -v ON_ERROR_STOP=1 "$@"
        return
    fi
    local args="" a script b64
    for a in "$@"; do args="$args $(printf '%q' "$a")"; done
    script='uri="$(grep -m1 "^POSTGRES_URI=" "$HOME/.rysteria-secrets/master.env" | cut -d= -f2-)"; uri="${uri%\"}"; uri="${uri#\"}"
[ -n "$uri" ] || { echo "no POSTGRES_URI in ~/.rysteria-secrets/master.env" >&2; exit 1; }
exec psql "$uri" -X -q -v ON_ERROR_STOP=1'"$args"
    b64="$(printf '%s' "$script" | base64 | tr -d '\n')"
    ssh "${SSH_OPTS[@]}" "$TARGET" "bash -l -c \"\$(printf %s '$b64' | base64 -d)\""
}

# is the master of that machine answering
master_up() {
    if [ -n "$URI" ]; then return 1; fi
    [ "$(ssh -n "${SSH_OPTS[@]}" "$TARGET" 'curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:55554/health' 2>/dev/null || true)" = 200 ]
}

# ------------------------------------------------------------------- list
if [ "$CMD" = list ]; then
    filter=""; [ "$DUPS" = 1 ] && filter="WHERE dup <> ''"
    pg -P pager=off <<SQL
SELECT uuid, username, email, dev, created, last_login, xp, pvp, petals, gardn_saves, links, dup FROM (
  SELECT a.uuid, a.username, a.email,
         CASE WHEN a.is_dev THEN 'dev' ELSE '' END AS dev,
         to_char(to_timestamp(a.created_at), 'YYYY-MM-DD') AS created,
         CASE WHEN a.last_login_at > 0 THEN to_char(to_timestamp(a.last_login_at), 'YYYY-MM-DD HH24:MI') ELSE '-' END AS last_login,
         coalesce(round(p.xp)::bigint, 0) AS xp,
         coalesce(p.pvp_points, 0) AS pvp,
         coalesce((SELECT sum(value::numeric)::bigint FROM jsonb_each_text(p.petals)), 0) AS petals,
         (SELECT count(*) FROM gardn.saves s WHERE s.uuid = a.uuid) AS gardn_saves,
         coalesce((SELECT string_agg(provider, ',') FROM accounts.links l WHERE l.uuid = a.uuid), '') AS links,
         CASE WHEN a.email_lower <> '' AND count(*) OVER (PARTITION BY a.email_lower) > 1 THEN 'SAME EMAIL' ELSE '' END AS dup,
         a.username_lower
  FROM accounts.accounts a LEFT JOIN rysteria.players p ON p.uuid = a.uuid
) x $filter ORDER BY username_lower;
SQL
    exit 0
fi

# ----------------------------------------------- find the account of wipe/restore
found="$(pg -At -F '|' -v "needle=$NEEDLE" <<'SQL'
SELECT uuid, username, email FROM accounts.accounts
WHERE uuid = :'needle' OR username_lower = lower(:'needle');
SQL
)"
[ -n "$found" ] || die "no account with the uuid or username \"$NEEDLE\""
[ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = 1 ] || die "more than one account matches:
$found"
IFS='|' read -r UUID NAME EMAIL <<<"$found"
echo "account: $NAME  ($UUID)  ${EMAIL:-no e-mail}"

if [ "$CMD" = wipe ]; then
    summary="$(pg -At -F '|' -v "uuid=$UUID" <<'SQL'
SELECT coalesce(round(p.xp)::bigint::text, 'none'), coalesce(p.pvp_points::text, '-'),
       coalesce((SELECT sum(value::numeric)::bigint::text FROM jsonb_each_text(p.petals)), '-'),
       coalesce(nullif(p.nickname, ''), '-'),
       (SELECT count(*) FROM leaderboards.entries e WHERE e.uuid = :'uuid' AND e.board LIKE 'rr\_%')
FROM (SELECT 1) one LEFT JOIN rysteria.players p ON p.uuid = :'uuid';
SQL
)"
    IFS='|' read -r XP PVP PETALS NICK ROWS <<<"$summary"
    echo "rysteria save: xp $XP, pvp points $PVP, $PETALS petals, nickname $NICK, $ROWS leaderboard rows"
    if [ "$XP" = none ] && [ "$ROWS" = 0 ]; then echo "nothing to wipe."; exit 0; fi
    ACTION="WIPE the Rysteria progress of $NAME"
else
    have="$(pg -At -v "uuid=$UUID" <<'SQL'
SELECT to_char(wiped_at, 'YYYY-MM-DD HH24:MI') FROM public.wiped_rysteria
WHERE uuid = :'uuid' AND player IS NOT NULL ORDER BY wiped_at DESC LIMIT 1;
SQL
)" || die "there is no copy of a wipe on this machine (public.wiped_rysteria)"
    [ -n "$have" ] || die "no copy of a wiped save of $NAME"
    echo "the latest copy was made $have"
    ACTION="RESTORE the Rysteria save of $NAME from that copy"
fi

if master_up; then
    echo
    echo "WARNING: the master server on $TARGET is running. $NAME must not be connected, or the"
    echo "         master writes the old save back. Stop the servers first if you are not sure."
fi
if [ "$YES" = 0 ]; then
    printf '\n%s? Type the username (%s) to go on: ' "$ACTION" "$NAME"
    read -r answer
    [ "$answer" = "$NAME" ] || die "not confirmed, nothing was changed"
fi

if [ "$CMD" = wipe ]; then
    pg -v "uuid=$UUID" <<'SQL'
BEGIN;
CREATE TABLE IF NOT EXISTS public.wiped_rysteria (
    wiped_at timestamptz NOT NULL DEFAULT now(), uuid text NOT NULL, username text NOT NULL,
    player jsonb, leaderboards jsonb);
INSERT INTO public.wiped_rysteria (uuid, username, player, leaderboards)
SELECT a.uuid, a.username, (SELECT to_jsonb(p) FROM rysteria.players p WHERE p.uuid = a.uuid),
       coalesce((SELECT jsonb_agg(to_jsonb(e)) FROM leaderboards.entries e WHERE e.uuid = a.uuid AND e.board LIKE 'rr\_%'), '[]')
FROM accounts.accounts a WHERE a.uuid = :'uuid';
DELETE FROM rysteria.players WHERE uuid = :'uuid';
DELETE FROM leaderboards.entries WHERE uuid = :'uuid' AND board LIKE 'rr\_%';
COMMIT;
SQL
    left="$(pg -At -F '|' -v "uuid=$UUID" <<'SQL'
SELECT (SELECT count(*) FROM rysteria.players WHERE uuid = :'uuid'),
       (SELECT count(*) FROM leaderboards.entries WHERE uuid = :'uuid' AND board LIKE 'rr\_%');
SQL
)"
    [ "$left" = "0|0" ] || die "something is left after the wipe: $left"
    echo "done: the Rysteria save and leaderboard rows of $NAME are gone (a copy is in public.wiped_rysteria)."
    echo "undo: scripts/accounts.sh restore $NAME"
else
    pg -v "uuid=$UUID" <<'SQL'
BEGIN;
INSERT INTO rysteria.players
SELECT (jsonb_populate_record(NULL::rysteria.players, w.player)).*
FROM (SELECT player FROM public.wiped_rysteria
      WHERE uuid = :'uuid' AND player IS NOT NULL ORDER BY wiped_at DESC LIMIT 1) w
ON CONFLICT (uuid) DO UPDATE SET xp = EXCLUDED.xp, checkpoint = EXCLUDED.checkpoint,
    pvp_points = EXCLUDED.pvp_points, petals = EXCLUDED.petals, failed_crafts = EXCLUDED.failed_crafts,
    mob_kills = EXCLUDED.mob_kills, loadout = EXCLUDED.loadout, nickname = EXCLUDED.nickname,
    updated_at = EXCLUDED.updated_at;
COMMIT;
SQL
    echo "done: the Rysteria save of $NAME is back. Their leaderboard rows come back when they next join."
fi
