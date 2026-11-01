#!/usr/bin/env python3
"""Puts gardn's petal names and rarities into the stats page.

The master only knows petal ids; rrolf/Client/public/stats.html shows names, so it
carries a table of them. Run this after a petal is added or renamed in
gardn/Shared/StaticData.cc, then commit rrolf:

    scripts/gen-petal-table.py            # rewrites the table in stats.html
    scripts/gen-petal-table.py --check    # only checks that it is up to date
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "gardn", "Shared", "StaticData.cc")
DEFS = os.path.join(ROOT, "gardn", "Shared", "StaticDefinitions.hh")
PAGE = os.path.join(ROOT, "rrolf", "Client", "public", "stats.html")
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

page = open(PAGE).read()
head, rest = page.split(BEGIN, 1)
_, tail = rest.split(END, 1)
new = head + table + tail
if "--check" in sys.argv:
    if new != page:
        sys.exit("stats.html is out of date: run scripts/gen-petal-table.py")
    print("stats.html is up to date (%d petals)" % len(names))
else:
    open(PAGE, "w").write(new)
    print("%d petals written to %s" % (len(names), PAGE))
