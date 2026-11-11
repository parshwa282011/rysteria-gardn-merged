#!/usr/bin/env python3
"""Puts the petal names into the stats pages.

The master only knows petal ids; the pages show names, so they carry a table of them:
  gardn-stats.html  gardn's petals and rarities (gardn/Shared/StaticData.cc)
  stats.html        Parteria's petal names (rrolf/Shared/StaticData.c), for the loadout
Run this after a petal is added or renamed, then commit rrolf:

    scripts/gen-petal-table.py            # rewrites the tables
    scripts/gen-petal-table.py --check    # only checks that they are up to date
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "gardn", "Shared", "StaticData.cc")
DEFS = os.path.join(ROOT, "gardn", "Shared", "StaticDefinitions.hh")
PAGE = os.path.join(ROOT, "rrolf", "Client", "public", "gardn-stats.html")
PROFILE = os.path.join(ROOT, "rrolf", "Client", "public", "stats.html")
RR_DATA = os.path.join(ROOT, "rrolf", "Shared", "StaticData.c")
RR_BEGIN, RR_END = "/*RRPETALS-BEGIN*/", "/*RRPETALS-END*/"
BEGIN, END = "/*PETALS-BEGIN*/", "/*PETALS-END*/"

defs = open(DEFS).read()
rarities = re.findall(r"\bk(\w+)", re.search(r"namespace RarityID \{.*?enum \{(.*?)\};", defs, re.S).group(1))
rarities = [r for r in rarities if r != "NumRarities"]
enum = re.search(r"namespace PetalID \{.*?enum[^{]*\{(.*?)\};", defs, re.S).group(1)
ids = [i for i in re.findall(r"\bk(\w+)", enum) if i != "NumPetals"]

src = open(DATA).read()
start = src.index("PETAL_DATA = {{")
block = src[start:src.index("\n}};", start)]
names = re.findall(r'\.name = "([^"]*)"', block)
rars = re.findall(r"\.rarity = RarityID::k(\w+)", block)
if not (len(ids) == len(names) == len(rars)):
    sys.exit("petal enum has %d ids, PETAL_DATA %d names and %d rarities" % (len(ids), len(names), len(rars)))

rows = ",\n".join("    [%s, %d]" % (json.dumps(n), rarities.index(r)) for n, r in zip(names, rars))
table = "%s\nconst RARITIES = %s;\nconst PETALS = [   // [name, rarity], the index is the petal id\n%s\n];\n%s" % (
    BEGIN, json.dumps(rarities), rows, END)

def rewrite(path, begin, end, table):
    page = open(path).read()
    head, rest = page.split(begin, 1)
    _, tail = rest.split(end, 1)
    return page, head + table + tail

# Parteria's names, by petal id
rr = open(RR_DATA).read()
start = rr.index("RR_PETAL_NAMES[rr_petal_id_max] = {")
rr_names = re.findall(r'"([^"]*)"', rr[start:rr.index("};", start)])
rr_table = "%s\nconst RR_PETALS = %s;   // the index is the petal id\n%s" % (RR_BEGIN, json.dumps(rr_names), RR_END)

ok = True
for path, begin, end, table, label in ((PAGE, BEGIN, END, table, "gardn-stats.html"),
                                       (PROFILE, RR_BEGIN, RR_END, rr_table, "stats.html")):
    old, new = rewrite(path, begin, end, table)
    if "--check" in sys.argv:
        if new != old:
            print("%s is out of date: run scripts/gen-petal-table.py" % label)
            ok = False
    else:
        open(path, "w").write(new)
        print("table written to %s" % path)
if "--check" in sys.argv:
    if not ok:
        sys.exit(1)
    print("petal tables are up to date (%d gardn, %d rysteria petals)" % (len(names), len(rr_names)))
