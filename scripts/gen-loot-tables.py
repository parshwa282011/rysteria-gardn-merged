#!/usr/bin/env python3
"""Writes LOOT_TABLES.md: every loot table of Rysteria and gardn, worked out from the
code (so run it again after changing a table or a coefficient):

    python3 scripts/gen-loot-tables.py > LOOT_TABLES.md

Rysteria: the loot of every mob is read from rrolf/Shared/StaticData.c and the chance of
every result rarity is worked out with the same formula as Shared/Component/Mob.c.
Gardn: a small program is compiled with clang++ against gardn/Shared/StaticData.cc and
prints MOB_DROP_CHANCES."""
import math
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RR = os.path.join(ROOT, "rrolf", "Shared")
GARDN = os.path.join(ROOT, "gardn")


def read(path):
    with open(path) as f:
        return f.read()


def block(text, start, end="};"):
    a = text.index(start)
    return text[a: text.index(end, a)]


h = read(os.path.join(RR, "StaticData.h"))
c = read(os.path.join(RR, "StaticData.c"))

petal_enum = re.findall(r"rr_petal_id_(\w+)", block(h, "enum rr_petal_id"))
petal_enum = [p for p in petal_enum if p != "max"]
mob_enum = [m for m in re.findall(r"rr_mob_id_(\w+)", block(h, "enum rr_mob_id")) if m != "max"]
rarity_names = re.findall(r'"(\w+)"', block(c, "char const *RR_RARITY_NAMES"))
rarity_enum = [r for r in re.findall(r"rr_rarity_id_(\w+)", block(h, "enum rr_rarity_id")) if r != "max"]
petal_names = re.findall(r'"([^"]+)"', block(c, "char const *RR_PETAL_NAMES"))
mob_names = re.findall(r'"([^"]+)"', block(c, "char const *RR_MOB_NAMES"))
R = len(rarity_enum)


def pname(ident):
    return petal_names[petal_enum.index(ident)]


# minimum rarity of each petal
min_rarity = {}
for m in re.finditer(r"\{rr_petal_id_(\w+),\s*rr_rarity_id_(\w+),", block(c, "struct rr_petal_data RR_PETAL_DATA")):
    min_rarity[m.group(1)] = rarity_enum.index(m.group(2))

# the coefficients, as init_game_coefficients() makes them
drop_c = [float(x) for x in re.search(r"RR_DROP_RARITY_COEFFICIENTS\[rr_rarity_id_max\] = \{([^}]*)\}", c).group(1).split(",")]
loot_c = [float(x) for x in re.search(r"RR_MOB_LOOT_RARITY_COEFFICIENTS\[rr_rarity_id_max\] = \{([^}]*)\}", c).group(1).replace("\n", " ").split(",")]
for a in range(1, R):
    loot_c[a] *= loot_c[a - 1]
exotic = rarity_enum.index("exotic")
total = 1.0
for a in range(1, exotic + 1):
    drop_c[a + 1] = drop_c[a] / drop_c[a + 1]
    total += drop_c[a + 1]
for a in range(1, exotic + 2):
    drop_c[a] = drop_c[a] / total + drop_c[a - 1]
drop_c[exotic + 1] = 1.0


def chances(mob_rarity, seed_param, petal_min):
    """P(no drop), then P(each result rarity) for one loot entry, the loop of Mob.c"""
    cap = mob_rarity - 1 if mob_rarity >= exotic else mob_rarity
    fs = []
    for drop in range(cap + 2):
        end = 1.0 if drop == cap + 1 else drop_c[drop]
        if cap < petal_min:
            end = 1.0
        elif drop < petal_min:
            end = drop_c[petal_min]
        base = 1 - (1 - end) * seed_param
        f = float("nan") if base < 0 else base ** loot_c[mob_rarity]
        fs.append(f)
    out = [0.0] * (R + 1)  # index 0: nothing, i + 1: rarity i
    best = 0.0
    for drop, f in enumerate(fs):
        if f != f:  # the C comparison seed <= NaN is false: never stops here
            continue
        p = max(0.0, f - best)
        best = max(best, f)
        out[drop] += p
    # the loop ends at drop == cap + 1 with end 1 and base^C == 1 at the latest
    out[cap + 1] += max(0.0, 1.0 - best)
    return out


def pct(x):
    if x == 0:
        return "-"
    if x >= 0.9999995:
        return "100"
    v = x * 100
    return f"{v:.4g}" if v >= 0.0001 else f"{v:.2e}"


# the mobs and their loot
mobs = []
for line in block(c, "struct rr_mob_data RR_MOB_DATA").splitlines():
    m = re.match(r"\s*\{rr_mob_id_(\w+),", line)
    if not m:
        continue
    pairs = re.findall(r"\{rr_petal_id_(\w+),\s*([0-9.]+)\}", line)
    mobs.append((m.group(1), [(p, float(s)) for p, s in pairs]))

out = []
w = out.append
w("# Loot tables")
w("")
w("Made by `scripts/gen-loot-tables.py` from the code. Run it again after changing a table.")
w("")
w("# Rysteria")
w("")
w("## Mob loot")
w("")
w("Every mob has up to four loot entries, a petal and a number (the *seed*). When the mob dies each entry is "
  "rolled on its own (`Shared/Component/Mob.c`): one random number is compared with a limit for every rarity from "
  "common up to the mob's own, and the first limit it is under decides the result. The higher the mob's rarity, "
  "the more likely a drop and the higher its rarity; a petal never drops below its lowest rarity (a common mob "
  "never drops an unusual-or-better-only petal). Exotic and ancient mobs use the limits of one rarity lower "
  "(`cap`) with their own multiplier. The drops go to every squad that did more than 20% of the mob's health in "
  "damage (the first squad into an arena for hives and holes), each member getting their own copy that only they "
  "can pick up.")
w("")
w("| Mob | Loot (petal, seed) |")
w("|---|---|")
for ident, loot in mobs:
    name = mob_names[mob_enum.index(ident)]
    text = ", ".join(f"{pname(p)} ({s:g})" for p, s in loot) if loot else "nothing"
    if ident == "snail":
        text = "nothing: its reward comes from the snail run (below)"
    w(f"| {name} | {text} |")
w("")
w("## What each seed gives")
w("")
w("The table for one loot entry depends on the seed, on the lowest rarity of the petal and on the mob's rarity. "
  "The same table is shared by every entry with the same seed and lowest rarity. Chances are in percent for one "
  "kill; the columns are what comes out (nothing, or a petal of that rarity).")
w("")
groups = {}
for ident, loot in mobs:
    for p, s in loot:
        groups.setdefault((min_rarity.get(p, 0), s), []).append((mob_names[mob_enum.index(ident)], pname(p)))
for (pm, s), users in sorted(groups.items(), key=lambda kv: (kv[0][1], kv[0][0])):
    w(f"### Seed {s:g}, petal's lowest rarity {rarity_names[pm]}")
    w("")
    uses = {}
    for mob, petal in users:
        uses.setdefault(petal, []).append(mob)
    w("Used by: " + "; ".join(f"**{petal}** from {', '.join(mobs_)}" for petal, mobs_ in uses.items()))
    w("")
    w("| Mob rarity | Nothing | " + " | ".join(rarity_names) + " |")
    w("|---|---|" + "---|" * R)
    for r in range(R):
        row = chances(r, s, pm)
        w(f"| {rarity_names[r]} | " + " | ".join(pct(x) for x in row) + " |")
    w("")

w("## The snail run reward")
w("")
w("Every player in the game, wherever they are, gets their own drops at their feet when the snail gets home. A "
  "shell and a mint always (one each); a nazar is rolled for every nazar rarity on its own.")
w("")
weights = [float(x) for x in re.search(r"RR_SNAIL_RARITY_WEIGHTS\[rr_rarity_id_max\] = \{([^}]*)\}", c).group(1).replace("f", "").split(",")]
w("**Which snail comes** (percent): " + ", ".join(f"{rarity_names[i]} {weights[i]:g}" for i in range(R) if weights[i] > 0))
w("")
tier = re.search(r"RR_SNAIL_REWARD_TIER_CHANCE\[rr_rarity_id_max\]\[4\] = \{(.*?)\n\};", c, re.S).group(1)
rows = re.findall(r"\{([^}]*)\}", tier)
w("**Rarity of the shell and the mint** (percent): the snail's own rarity, one below, two below, three below (never below the petal's lowest rarity)")
w("")
w("| Snail | own | one below | two below | three below |")
w("|---|---|---|---|---|")
for i, row in enumerate(rows):
    vals = [v.strip().replace("f", "") for v in row.split(",")]
    w(f"| {rarity_names[i]} | " + " | ".join(vals) + " |")
w("")
nz = re.search(r"RR_SNAIL_NAZAR_CHANCE\[rr_rarity_id_max\]\[rr_rarity_id_max\] = \{(.*?)\n\};", c, re.S).group(1)
rows = [r for r in re.findall(r"\{([^}]*)\}", nz)]
w("**Nazar** (percent chance of a nazar of that rarity, each rolled on its own)")
w("")
w("| Snail | " + " | ".join(rarity_names) + " |")
w("|---|" + "---|" * R)
for i, row in enumerate(rows):
    vals = [v.strip().replace("f", "") for v in row.split(",")]
    w(f"| {rarity_names[i]} | " + " | ".join(vals) + " |")
w("")

w("## Dropped when a player dies (PvP)")
w("")
pvp = [x.strip().rstrip("ULL") for x in re.search(r"RR_PVP_POINTS_PER_RARITY\[rr_rarity_id_max\] = \{([^}]*)\}", c).group(1).replace("\n", " ").split(",")]
w("In the PvP zone a flower that dies drops one **Petal** (basic) of the highest rarity it has PvP points for, up to "
  "mythic. Points needed: " + ", ".join(f"{rarity_names[i]} {int(pvp[i]):,}" for i in range(rarity_enum.index('mythic') + 1)) + ".")
w("")

# ------------------------------------------------------------------------ gardn
w("# Gardn")
w("")
w("A mob that dies drops each petal of its list on its own: a number from 0 to 1 is compared with the chance below "
  "(`Server/EntityFunctions/Death.cc`, `MOB_DROP_CHANCES` in `Shared/StaticData.cc`). The chance is worked out from "
  "how often the mob spawns (the zones' spawn tables and their drop multipliers), how many mobs share the petal and "
  "how rare the petal is, so rarer petals drop less often. For a mob with several segments the chance is per "
  "segment. The sandbox has the same tables, nothing in it is kept.")
w("")
cc = r'''
#include <Shared/StaticData.hh>
#include <cstdio>
static char const *RN[] = {"Common","Unusual","Rare","Epic","Legendary","Mythic","Unique"};
int main() {
    for (MobID::T id = 0; id < MobID::kNumMobs; ++id) {
        MobData const &m = MOB_DATA[id];
        printf("M\t%s\t%s\t%u\n", m.name, RN[m.rarity], (unsigned) m.attributes.segments);
        for (uint32_t i = 0; i < m.drops.size(); ++i) {
            PetalData const &p = PETAL_DATA[m.drops[i]];
            printf("D\t%s\t%s\t%.8g\n", p.name, RN[p.rarity], MOB_DROP_CHANCES[id][i]);
        }
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory() as d:
    src = os.path.join(d, "g.cc")
    exe = os.path.join(d, "g")
    with open(src, "w") as f:
        f.write(cc)
    helpers = [os.path.join(GARDN, "Helpers", x) for x in sorted(os.listdir(os.path.join(GARDN, "Helpers"))) if x.endswith(".cc")]
    r = subprocess.run(["clang++", "-std=c++20", "-DSERVERSIDE=1", "-DUSE_CODEPOINT_LEN=1", "-I" + GARDN, "-o", exe, src,
                        os.path.join(GARDN, "Shared", "StaticData.cc")] + helpers, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    text = subprocess.run([exe], capture_output=True, text=True).stdout
w("| Mob | Rarity | Petal | Petal rarity | Chance per kill |")
w("|---|---|---|---|---|")
mob = None
for line in text.splitlines():
    parts = line.split("\t")
    if parts[0] == "M":
        mob = parts[1:]
        seg = f", {mob[2]} segments" if mob[2] != "1" else ""
        w(f"| **{mob[0]}** | {mob[1]}{seg} | | | |")
    elif parts[0] == "D":
        w(f"| | | {parts[1]} | {parts[2]} | {pct(float(parts[3]))}% |")
w("")
w("## Dropped when a player dies")
w("")
w("Up to three of the petals the flower had (not Basic), the rarest first, each kept with 95%; a rare or better one "
  "has a 5% chance to turn into a Pollen. A flower that leaves the game (a save, the X of the sandbox) drops nothing. "
  "The rest of the petals go back to the camera's inventory for the next life (a lower level means fewer slots).")
print("\n".join(out))
