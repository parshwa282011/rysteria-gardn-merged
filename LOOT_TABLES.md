# Loot tables

Made by `scripts/gen-loot-tables.py` from the code. Run it again after changing a table.

# Rysteria

## Mob loot

Every mob has up to four loot entries, a petal and a number (the *seed*). When the mob dies each entry is rolled on its own (`Shared/Component/Mob.c`): one random number is compared with a limit for every rarity from common up to the mob's own, and the first limit it is under decides the result. The higher the mob's rarity, the more likely a drop and the higher its rarity; a petal never drops below its lowest rarity (a common mob never drops an unusual-or-better-only petal). Exotic and ancient mobs use the limits of one rarity lower (`cap`) with their own multiplier. The drops go to every squad that did more than 20% of the mob's health in damage (the first squad into an arena for hives and holes), each member getting their own copy that only they can pick up.

| Mob | Loot (petal, seed) |
|---|---|
| Triceratops | Leaf (0.15), Fossil (0.05) |
| T-Rex | Stinger (0.03), Egg (0.05), Meat (0.01) |
| Fern | Leaf (0.1), Azalea (0.25) |
| Tree | Leaf (2.5), Peas (2.5), Seed (0.05) |
| Pteranodon | Shell (0.05), Beak (0.15), Nest (0.01) |
| Dakotaraptor | Crest (0.1), Feather (0.1), Pellet (0.05) |
| Pachycephalosaurus | Fossil (0.1), Berry (0.1), Web (0.05) |
| Ornithomimus | Feather (0.1), Droplet (0.05), Pellet (0.1) |
| Ankylosaurus | Club (0.15), Gravel (0.05), Bubble (0.1) |
| Meteor | Magnet (0.5), Uranium (0.05), Fireball (1), Meteor (2) |
| Quetzalcoatlus | Beak (0.05), Fossil (0.1), Lightning (0.01) |
| Edmontosaurus | Bone (0.01), Fossil (0.1), Third Eye (0.05) |
| Ant | Pellet (0.1), Leaf (0.1), Mandible (0.05) |
| Fighter Bee | Stinger (0.1), Crest (0.05) |
| Dragonfly | Pellet (0.1), Magnet (0.05) |
| Honeybee | Wax (0.05), Stinger (0.05) |
| Beehive | Wax (0.05), Azalea (0.05) |
| Spider | Web (0.1), Third Eye (0.01) |
| House Centipede | Peas (0.1), Sand (0.05) |
| Lanternfly | Mint (0.1), Sand (0.05) |
| Queen Bee | Wax (0.1), Mandible (0.02), Bee Egg (0.02) |
| Beehive Core | Wax (0.05), Azalea (0.05), Beehive Post (0.0005) |
| Bush | Leaf (0.15), Azalea (0.15), Berry (0.1) |
| Ant Hole | Pellet (0.05), Mandible (0.05) |
| Queen Ant | Mandible (0.1), Pellet (0.1), Sand (0.03), Egg (0.03) |
| Ant Egg | Pellet (0.02) |
| Baby Ant | Pellet (0.03) |
| Digger Ant | Sand (0.1), Gravel (0.05), Mandible (0.05) |
| Snail | nothing: its reward comes from the snail run (below) |

## What each seed gives

The table for one loot entry depends on the seed, on the lowest rarity of the petal and on the mob's rarity. The same table is shared by every entry with the same seed and lowest rarity. Chances are in percent for one kill; the columns are what comes out (nothing, or a petal of that rarity).

### Seed 0.0005, petal's lowest rarity Legendary

Used by: **Beehive Post** from Beehive Core

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 100 | - | - | - | - | - | - | - | - |
| Epic | 100 | - | - | - | - | - | - | - | - |
| Legendary | 100 | - | - | - | - | 0.001934 | - | - | - |
| Mythic | 99.9 | - | - | - | - | 0.09644 | 0.0001931 | - | - |
| Exotic | 88.62 | - | - | - | - | 11.36 | 0.02413 | - | - |
| Ancient | 1.34e-06 | - | - | - | - | 96.44 | 3.554 | 0.001311 | - |

### Seed 0.01, petal's lowest rarity Common

Used by: **Meat** from T-Rex; **Bone** from Edmontosaurus

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 97.52 | 2.481 | - | - | - | - | - | - | - |
| Unusual | 90.44 | 8.39 | 1.172 | - | - | - | - | - | - |
| Rare | 54.72 | 38.46 | 6.377 | 0.4512 | - | - | - | - | - |
| Epic | 0.01179 | 34.6 | 58.83 | 6.392 | 0.1664 | - | - | - | - |
| Legendary | 3.23e-136 | 7.48e-15 | 9.31 | 85.03 | 5.623 | 0.03867 | - | - | - |
| Mythic | - | - | 2.80e-50 | 5.426 | 92.66 | 1.911 | 0.003861 | - | - |
| Exotic | - | - | - | 6.41e-157 | 8.918 | 90.6 | 0.4815 | - | - |
| Ancient | - | - | - | - | 3.49e-156 | 48.48 | 51.49 | 0.02885 | - |

### Seed 0.01, petal's lowest rarity Unusual

Used by: **Lightning** from Quetzalcoatlus

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 98.83 | - | 1.172 | - | - | - | - | - | - |
| Rare | 93.17 | - | 6.377 | 0.4512 | - | - | - | - | - |
| Epic | 34.61 | - | 58.83 | 6.392 | 0.1664 | - | - | - | - |
| Legendary | 7.48e-15 | - | 9.31 | 85.03 | 5.623 | 0.03867 | - | - | - |
| Mythic | - | - | 2.80e-50 | 5.426 | 92.66 | 1.911 | 0.003861 | - | - |
| Exotic | - | - | - | 6.41e-157 | 8.918 | 90.6 | 0.4815 | - | - |
| Ancient | - | - | - | - | 3.49e-156 | 48.48 | 51.49 | 0.02885 | - |

### Seed 0.01, petal's lowest rarity Legendary

Used by: **Nest** from Pteranodon; **Third Eye** from Spider

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 100 | - | - | - | - | - | - | - | - |
| Epic | 100 | - | - | - | - | - | - | - | - |
| Legendary | 99.96 | - | - | - | - | 0.03867 | - | - | - |
| Mythic | 98.08 | - | - | - | - | 1.911 | 0.003861 | - | - |
| Exotic | 8.918 | - | - | - | - | 90.6 | 0.4815 | - | - |
| Ancient | 3.49e-156 | - | - | - | - | 48.48 | 51.49 | 0.02885 | - |

### Seed 0.02, petal's lowest rarity Common

Used by: **Mandible** from Queen Bee; **Pellet** from Ant Egg

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 95.07 | 4.925 | - | - | - | - | - | - | - |
| Unusual | 81.71 | 15.96 | 2.331 | - | - | - | - | - | - |
| Rare | 29.76 | 57.05 | 12.3 | 0.9004 | - | - | - | - | - |
| Epic | 1.27e-06 | 11.97 | 75.35 | 12.35 | 0.3325 | - | - | - | - |
| Legendary | 4.18e-275 | 5.35e-31 | 0.8665 | 88.13 | 10.93 | 0.07732 | - | - | - |
| Mythic | - | - | 7.75e-102 | 0.2944 | 95.91 | 3.786 | 0.007722 | - | - |
| Exotic | - | - | - | 4.11e-315 | 0.7954 | 98.24 | 0.9606 | - | - |
| Ancient | - | - | - | - | 1.22e-313 | 23.51 | 76.44 | 0.05801 | - |

### Seed 0.02, petal's lowest rarity Unusual

Used by: **Bee Egg** from Queen Bee

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 97.67 | - | 2.331 | - | - | - | - | - | - |
| Rare | 86.8 | - | 12.3 | 0.9004 | - | - | - | - | - |
| Epic | 11.97 | - | 75.35 | 12.35 | 0.3325 | - | - | - | - |
| Legendary | 5.35e-31 | - | 0.8665 | 88.13 | 10.93 | 0.07732 | - | - | - |
| Mythic | - | - | 7.75e-102 | 0.2944 | 95.91 | 3.786 | 0.007722 | - | - |
| Exotic | - | - | - | 4.11e-315 | 0.7954 | 98.24 | 0.9606 | - | - |
| Ancient | - | - | - | - | 1.22e-313 | 23.51 | 76.44 | 0.05801 | - |

### Seed 0.03, petal's lowest rarity Common

Used by: **Stinger** from T-Rex; **Sand** from Queen Ant; **Pellet** from Baby Ant

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 92.67 | 7.332 | - | - | - | - | - | - | - |
| Unusual | 73.74 | 22.78 | 3.479 | - | - | - | - | - | - |
| Rare | 16.08 | 64.78 | 17.79 | 1.348 | - | - | - | - | - |
| Epic | 1.24e-10 | 4.132 | 77.45 | 17.92 | 0.4983 | - | - | - | - |
| Legendary | - | 3.66e-47 | 0.08064 | 83.88 | 15.93 | 0.116 | - | - | - |
| Mythic | - | - | 2.13e-153 | 0.01597 | 94.35 | 5.624 | 0.01158 | - | - |
| Exotic | - | - | - | - | 0.07093 | 98.49 | 1.437 | - | - |
| Ancient | - | - | - | - | - | 11.4 | 88.52 | 0.08685 | - |

### Seed 0.03, petal's lowest rarity Unusual

Used by: **Egg** from Queen Ant

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 96.52 | - | 3.479 | - | - | - | - | - | - |
| Rare | 80.86 | - | 17.79 | 1.348 | - | - | - | - | - |
| Epic | 4.132 | - | 77.45 | 17.92 | 0.4983 | - | - | - | - |
| Legendary | 3.66e-47 | - | 0.08064 | 83.88 | 15.93 | 0.116 | - | - | - |
| Mythic | - | - | 2.13e-153 | 0.01597 | 94.35 | 5.624 | 0.01158 | - | - |
| Exotic | - | - | - | - | 0.07093 | 98.49 | 1.437 | - | - |
| Ancient | - | - | - | - | - | 11.4 | 88.52 | 0.08685 | - |

### Seed 0.05, petal's lowest rarity Common

Used by: **Fossil** from Triceratops; **Pellet** from Dakotaraptor, Ant Hole; **Droplet** from Ornithomimus; **Mandible** from Ant, Ant Hole, Digger Ant; **Stinger** from Honeybee; **Azalea** from Beehive, Beehive Core; **Sand** from House Centipede, Lanternfly

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 87.96 | 12.04 | - | - | - | - | - | - | - |
| Unusual | 59.87 | 34.39 | 5.737 | - | - | - | - | - | - |
| Rare | 4.607 | 65.55 | 27.61 | 2.236 | - | - | - | - | - |
| Epic | 8.94e-19 | 0.4907 | 70.74 | 27.94 | 0.8291 | - | - | - | - |
| Legendary | - | 1.51e-79 | 0.0006981 | 74.72 | 25.09 | 0.1932 | - | - | - |
| Mythic | - | - | 1.57e-256 | 4.70e-05 | 90.78 | 9.196 | 0.0193 | - | - |
| Exotic | - | - | - | - | 0.0005642 | 97.62 | 2.384 | - | - |
| Ancient | - | - | - | - | - | 2.679 | 97.18 | 0.1445 | - |

### Seed 0.05, petal's lowest rarity Unusual

Used by: **Egg** from T-Rex; **Gravel** from Ankylosaurus, Digger Ant; **Beak** from Quetzalcoatlus; **Magnet** from Dragonfly; **Wax** from Honeybee, Beehive, Beehive Core

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 94.26 | - | 5.737 | - | - | - | - | - | - |
| Rare | 70.15 | - | 27.61 | 2.236 | - | - | - | - | - |
| Epic | 0.4907 | - | 70.74 | 27.94 | 0.8291 | - | - | - | - |
| Legendary | 1.51e-79 | - | 0.0006981 | 74.72 | 25.09 | 0.1932 | - | - | - |
| Mythic | - | - | 1.57e-256 | 4.70e-05 | 90.78 | 9.196 | 0.0193 | - | - |
| Exotic | - | - | - | - | 0.0005642 | 97.62 | 2.384 | - | - |
| Ancient | - | - | - | - | - | 2.679 | 97.18 | 0.1445 | - |

### Seed 0.05, petal's lowest rarity Rare

Used by: **Shell** from Pteranodon; **Web** from Pachycephalosaurus; **Uranium** from Meteor; **Crest** from Fighter Bee

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 97.76 | - | - | 2.236 | - | - | - | - | - |
| Epic | 71.23 | - | - | 27.94 | 0.8291 | - | - | - | - |
| Legendary | 0.0006981 | - | - | 74.72 | 25.09 | 0.1932 | - | - | - |
| Mythic | 1.57e-256 | - | - | 4.70e-05 | 90.78 | 9.196 | 0.0193 | - | - |
| Exotic | - | - | - | - | 0.0005642 | 97.62 | 2.384 | - | - |
| Ancient | - | - | - | - | - | 2.679 | 97.18 | 0.1445 | - |

### Seed 0.05, petal's lowest rarity Legendary

Used by: **Seed** from Tree; **Third Eye** from Edmontosaurus

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 100 | - | - | - | - | - | - | - | - |
| Epic | 100 | - | - | - | - | - | - | - | - |
| Legendary | 99.81 | - | - | - | - | 0.1932 | - | - | - |
| Mythic | 90.78 | - | - | - | - | 9.196 | 0.0193 | - | - |
| Exotic | 0.0005642 | - | - | - | - | 97.62 | 2.384 | - | - |
| Ancient | - | - | - | - | - | 2.679 | 97.18 | 0.1445 | - |

### Seed 0.1, petal's lowest rarity Common

Used by: **Feather** from Dakotaraptor, Ornithomimus; **Fossil** from Pachycephalosaurus, Quetzalcoatlus, Edmontosaurus; **Pellet** from Ornithomimus, Ant, Dragonfly, Queen Ant; **Bubble** from Ankylosaurus; **Stinger** from Fighter Bee; **Mandible** from Queen Ant; **Sand** from Digger Ant

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 76.84 | 23.16 | - | - | - | - | - | - | - |
| Unusual | 34.87 | 53.96 | 11.18 | - | - | - | - | - | - |
| Rare | 0.1797 | 48.93 | 46.46 | 4.423 | - | - | - | - | - |
| Epic | 6.58e-40 | 0.002333 | 50.73 | 47.61 | 1.651 | - | - | - | - |
| Legendary | - | 7.51e-161 | 4.85e-09 | 55.83 | 43.78 | 0.386 | - | - | - |
| Mythic | - | - | - | 2.21e-11 | 82.42 | 17.54 | 0.0386 | - | - |
| Exotic | - | - | - | - | 3.18e-09 | 95.29 | 4.712 | - | - |
| Ancient | - | - | - | - | - | 0.07176 | 99.64 | 0.2891 | - |

### Seed 0.1, petal's lowest rarity Unusual

Used by: **Leaf** from Fern, Ant; **Mint** from Lanternfly; **Wax** from Queen Bee

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 88.82 | - | 11.18 | - | - | - | - | - | - |
| Rare | 49.11 | - | 46.46 | 4.423 | - | - | - | - | - |
| Epic | 0.002333 | - | 50.73 | 47.61 | 1.651 | - | - | - | - |
| Legendary | 7.51e-161 | - | 4.85e-09 | 55.83 | 43.78 | 0.386 | - | - | - |
| Mythic | - | - | - | 2.21e-11 | 82.42 | 17.54 | 0.0386 | - | - |
| Exotic | - | - | - | - | 3.18e-09 | 95.29 | 4.712 | - | - |
| Ancient | - | - | - | - | - | 0.07176 | 99.64 | 0.2891 | - |

### Seed 0.1, petal's lowest rarity Rare

Used by: **Crest** from Dakotaraptor; **Berry** from Pachycephalosaurus, Bush; **Web** from Spider; **Peas** from House Centipede

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 95.58 | - | - | 4.423 | - | - | - | - | - |
| Epic | 50.74 | - | - | 47.61 | 1.651 | - | - | - | - |
| Legendary | 4.85e-09 | - | - | 55.83 | 43.78 | 0.386 | - | - | - |
| Mythic | - | - | - | 2.21e-11 | 82.42 | 17.54 | 0.0386 | - | - |
| Exotic | - | - | - | - | 3.18e-09 | 95.29 | 4.712 | - | - |
| Ancient | - | - | - | - | - | 0.07176 | 99.64 | 0.2891 | - |

### Seed 0.15, petal's lowest rarity Common

Used by: **Club** from Ankylosaurus; **Azalea** from Bush

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 66.61 | 33.39 | - | - | - | - | - | - | - |
| Unusual | 19.69 | 63.98 | 16.33 | - | - | - | - | - | - |
| Rare | 0.005823 | 34.3 | 59.13 | 6.562 | - | - | - | - | - |
| Epic | 3.00e-62 | 1.07e-05 | 36.13 | 61.4 | 2.467 | - | - | - | - |
| Legendary | - | 1.22e-242 | 3.36e-14 | 41.72 | 57.7 | 0.5784 | - | - | - |
| Mythic | - | - | - | 1.04e-17 | 74.82 | 25.12 | 0.0579 | - | - |
| Exotic | - | - | - | - | 1.80e-14 | 93.02 | 6.984 | - | - |
| Ancient | - | - | - | - | - | 0.001922 | 99.56 | 0.4331 | - |

### Seed 0.15, petal's lowest rarity Unusual

Used by: **Leaf** from Triceratops, Bush; **Beak** from Pteranodon

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 83.67 | - | 16.33 | - | - | - | - | - | - |
| Rare | 34.31 | - | 59.13 | 6.562 | - | - | - | - | - |
| Epic | 1.07e-05 | - | 36.13 | 61.4 | 2.467 | - | - | - | - |
| Legendary | 1.22e-242 | - | 3.36e-14 | 41.72 | 57.7 | 0.5784 | - | - | - |
| Mythic | - | - | - | 1.04e-17 | 74.82 | 25.12 | 0.0579 | - | - |
| Exotic | - | - | - | - | 1.80e-14 | 93.02 | 6.984 | - | - |
| Ancient | - | - | - | - | - | 0.001922 | 99.56 | 0.4331 | - |

### Seed 0.25, petal's lowest rarity Common

Used by: **Azalea** from Fern

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 48.71 | 51.29 | - | - | - | - | - | - | - |
| Unusual | 5.631 | 68.53 | 25.84 | - | - | - | - | - | - |
| Rare | 3.19e-06 | 16.63 | 72.67 | 10.7 | - | - | - | - | - |
| Epic | 3.59e-111 | 2.07e-10 | 18.32 | 77.61 | 4.078 | - | - | - | - |
| Legendary | - | - | 1.58e-24 | 23.29 | 75.75 | 0.9622 | - | - | - |
| Mythic | - | - | - | 2.29e-30 | 61.67 | 38.24 | 0.09648 | - | - |
| Exotic | - | - | - | - | 5.72e-25 | 88.63 | 11.37 | - | - |
| Ancient | - | - | - | - | - | 1.38e-06 | 99.28 | 0.721 | - |

### Seed 0.5, petal's lowest rarity Unusual

Used by: **Magnet** from Meteor

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 54.49 | - | 45.51 | - | - | - | - | - | - |
| Rare | 2.618 | - | 77.11 | 20.27 | - | - | - | - | - |
| Epic | 1.86e-22 | - | 3.344 | 88.67 | 7.989 | - | - | - | - |
| Legendary | - | - | 2.25e-50 | 5.425 | 92.66 | 1.915 | - | - | - |
| Mythic | - | - | - | 5.25e-62 | 38.03 | 61.78 | 0.1929 | - | - |
| Exotic | - | - | - | - | 3.27e-51 | 78.56 | 21.44 | - | - |
| Ancient | - | - | - | - | - | 1.90e-14 | 98.56 | 1.437 | - |

### Seed 1, petal's lowest rarity Unusual

Used by: **Fireball** from Meteor

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 28.55 | - | 71.45 | - | - | - | - | - | - |
| Rare | 0.05416 | - | 63.46 | 36.49 | - | - | - | - | - |
| Epic | 1.01e-47 | - | 0.1104 | 84.55 | 15.34 | - | - | - | - |
| Legendary | - | - | 3.21e-102 | 0.2942 | 95.91 | 3.793 | - | - | - |
| Mythic | - | - | - | 2.72e-125 | 14.46 | 85.15 | 0.3854 | - | - |
| Exotic | - | - | - | - | 1.07e-103 | 61.72 | 38.28 | - | - |
| Ancient | - | - | - | - | - | 3.62e-30 | 97.15 | 2.853 | - |

### Seed 2, petal's lowest rarity Unusual

Used by: **Meteor** from Meteor

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 6.809 | - | 93.19 | - | - | - | - | - | - |
| Rare | 9.97e-06 | - | 40.2 | 59.8 | - | - | - | - | - |
| Epic | 9.51e-104 | - | 0.0001158 | 71.67 | 28.33 | - | - | - | - |
| Legendary | - | - | 1.68e-206 | 0.0008647 | 92.56 | 7.443 | - | - | - |
| Mythic | - | - | - | 6.99e-252 | 2.091 | 97.14 | 0.7693 | - | - |
| Exotic | - | - | - | - | 1.14e-208 | 38.09 | 61.91 | - | - |
| Ancient | - | - | - | - | - | 1.31e-61 | 94.37 | 5.625 | - |

### Seed 2.5, petal's lowest rarity Unusual

Used by: **Leaf** from Tree

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 3.054 | - | 96.95 | - | - | - | - | - | - |
| Rare | 8.11e-08 | - | 31.94 | 68.06 | - | - | - | - | - |
| Epic | 4.30e-135 | - | 3.67e-06 | 65.94 | 34.06 | - | - | - | - |
| Legendary | - | - | 6.08e-259 | 4.69e-05 | 90.78 | 9.216 | - | - | - |
| Mythic | - | - | - | 3.47e-315 | 0.7954 | 98.24 | 0.9606 | - | - |
| Exotic | - | - | - | - | 3.72e-261 | 29.92 | 70.08 | - | - |
| Ancient | - | - | - | - | - | 2.49e-77 | 93.02 | 6.981 | - |

### Seed 2.5, petal's lowest rarity Rare

Used by: **Peas** from Tree

| Mob rarity | Nothing | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|---|
| Common | 100 | - | - | - | - | - | - | - | - |
| Unusual | 100 | - | - | - | - | - | - | - | - |
| Rare | 31.94 | - | - | 68.06 | - | - | - | - | - |
| Epic | 3.67e-06 | - | - | 65.94 | 34.06 | - | - | - | - |
| Legendary | 6.08e-259 | - | - | 4.69e-05 | 90.78 | 9.216 | - | - | - |
| Mythic | - | - | - | 3.47e-315 | 0.7954 | 98.24 | 0.9606 | - | - |
| Exotic | - | - | - | - | 3.72e-261 | 29.92 | 70.08 | - | - |
| Ancient | - | - | - | - | - | 2.49e-77 | 93.02 | 6.981 | - |

## The snail run reward

Every player in the game, wherever they are, gets their own drops at their feet when the snail gets home. A shell and a mint always (one each); a nazar is rolled for every nazar rarity on its own.

**Which snail comes** (percent): Epic 65, Legendary 25, Mythic 9, Exotic 0.75, Ancient 0.25

**Rarity of the shell and the mint** (percent): the snail's own rarity, one below, two below, three below (never below the petal's lowest rarity)

| Snail | own | one below | two below | three below |
|---|---|---|---|---|
| Common | 10 | 70 | 20 | 0 |
| Unusual | 10 | 70 | 20 | 0 |
| Rare | 10 | 70 | 20 | 0 |
| Epic | 10 | 70 | 20 | 0 |
| Legendary | 10 | 70 | 20 | 0 |
| Mythic | 10 | 70 | 20 | 0 |
| Exotic | 0.5 | 14.5 | 70 | 15 |
| Ancient | 0.5 | 14.5 | 70 | 15 |

**Nazar** (percent chance of a nazar of that rarity, each rolled on its own)

| Snail | Common | Unusual | Rare | Epic | Legendary | Mythic | Exotic | Ancient |
|---|---|---|---|---|---|---|---|---|
| Common | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Unusual | 1.5 | 0.3 | 0 | 0 | 0 | 0 | 0 | 0 |
| Rare | 10 | 2 | 0.3 | 0 | 0 | 0 | 0 | 0 |
| Epic | 25 | 8 | 2 | 0.15 | 0 | 0 | 0 | 0 |
| Legendary | 40 | 15 | 5 | 1 | 0.03 | 0 | 0 | 0 |
| Mythic | 55 | 25 | 10 | 2.5 | 0.4 | 0.015 | 0 | 0 |
| Exotic | 70 | 35 | 16 | 5 | 1 | 0.15 | 0 | 0 |
| Ancient | 85 | 50 | 25 | 10 | 2.5 | 0.5 | 0.1 | 0 |

## Dropped when a player dies (PvP)

In the PvP zone a flower that dies drops one **Petal** (basic) of the highest rarity it has PvP points for, up to mythic. Points needed: Common 20, Unusual 100, Rare 1,000, Epic 10,000, Legendary 150,000, Mythic 2,250,000.

# Gardn

A mob that dies drops each petal of its list on its own: a number from 0 to 1 is compared with the chance below (`Server/EntityFunctions/Death.cc`, `MOB_DROP_CHANCES` in `Shared/StaticData.cc`). The chance is worked out from how often the mob spawns (the zones' spawn tables and their drop multipliers), how many mobs share the petal and how rare the petal is, so rarer petals drop less often. For a mob with several segments the chance is per segment. The sandbox has the same tables, nothing in it is kept.

| Mob | Rarity | Petal | Petal rarity | Chance per kill |
|---|---|---|---|---|
| **Baby Ant** | Common | | | |
| | | Fast | Common | 54.51% |
| | | Leaf | Unusual | 32.71% |
| | | Twin | Unusual | 14.02% |
| | | Rice | Epic | 0.6542% |
| | | Triplet | Epic | 0.07268% |
| **Worker Ant** | Common | | | |
| | | Fast | Common | 99.19% |
| | | Leaf | Unusual | 59.51% |
| | | Twin | Unusual | 25.51% |
| | | Corn | Epic | 1.19% |
| | | Bone | Legendary | 0.05951% |
| **Soldier Ant** | Unusual | | | |
| | | Twin | Unusual | 18.55% |
| | | Iris | Unusual | 18.55% |
| | | Wing | Rare | 2.164% |
| | | Faster | Rare | 5.41% |
| | | Triplet | Epic | 0.09618% |
| **Bee** | Common | | | |
| | | Fast | Common | 9.973% |
| | | Stinger | Unusual | 5.984% |
| | | Twin | Unusual | 2.564% |
| | | Wing | Rare | 0.2992% |
| | | Stinger | Mythic | 0.002992% |
| | | Honey | Rare | 2.992% |
| **Ladybug** | Common | | | |
| | | Fast | Common | 11.55% |
| | | Rose | Unusual | 10.39% |
| | | Twin | Unusual | 2.969% |
| | | Bubble | Rare | 0.8661% |
| **Beetle** | Unusual | | | |
| | | Iris | Unusual | 5.082% |
| | | Salt | Rare | 1.976% |
| | | Wing | Rare | 0.5929% |
| | | Triplet | Epic | 0.02635% |
| | | Egg | Mythic | 0.005929% |
| **Massive Ladybug** | Epic | | | |
| | | Rose | Unusual | 100% |
| | | Rose | Rare | 100% |
| | | Bubble | Rare | 100% |
| | | Rose | Epic | 51.5% |
| | | Butterfly | Mythic | 2.575% |
| | | Observer | Mythic | 2.575% |
| **Massive Beetle** | Rare | | | |
| | | Iris | Unusual | 100% |
| | | Wing | Rare | 44.54% |
| | | Iris | Epic | 8.908% |
| | | Triplet | Epic | 1.979% |
| | | Egg | Epic | 17.82% |
| | | Third Eye | Mythic | 0.4454% |
| **Ladybug** | Unusual | | | |
| | | Rose | Rare | 13.18% |
| | | Wing | Rare | 3.953% |
| | | Yin Yang | Epic | 1.581% |
| | | Rose | Epic | 0.7906% |
| | | Triplet | Epic | 0.1757% |
| **Hornet** | Unusual | | | |
| | | Dandelion | Rare | 8.585% |
| | | Missile | Rare | 8.585% |
| | | Wing | Rare | 0.8585% |
| | | Bubble | Rare | 2.146% |
| | | Antennae | Legendary | 0.03434% |
| | | Egg | Legendary | 0.03434% |
| **Cactus** | Common | | | |
| | | Stinger | Unusual | 5.114% |
| | | Yucca | Unusual | 7.671% |
| | | Cactus | Rare | 2.557% |
| | | Cactus | Epic | 0.1023% |
| | | Cactus | Legendary | 0.01023% |
| **Rock** | Common | | | |
| | | Heavy | Common | 10.3% |
| | | Fast | Common | 3.433% |
| | | Rock | Rare | 0.515% |
| | | Shell | Legendary | 0.00412% |
| **Boulder** | Unusual | | | |
| | | Heavy | Common | 78.45% |
| | | Rock | Rare | 3.923% |
| | | Heaviest | Epic | 0.3138% |
| | | Moon | Mythic | 0.007845% |
| | | Sponge | Legendary | 0.03138% |
| **Centipede** | Unusual, 10 segments | | | |
| | | Fast | Common | 11.68% |
| | | Twin | Unusual | 3.004% |
| | | Leaf | Unusual | 7.009% |
| | | Peas | Rare | 3.504% |
| | | Triplet | Epic | 0.01557% |
| | | Leaf | Legendary | 0.01402% |
| **Evil Centipede** | Rare, 10 segments | | | |
| | | Iris | Unusual | 7.933% |
| | | Peas | Epic | 0.3702% |
| | | Iris | Epic | 0.1851% |
| | | Triplet | Epic | 0.04113% |
| | | Lightning | Epic | 0.3702% |
| **Desert Centipede** | Rare, 6 segments | | | |
| | | Sand | Rare | 8.523% |
| | | Faster | Rare | 4.262% |
| | | Salt | Rare | 5.682% |
| | | Stick | Legendary | 0.03409% |
| | | Powder | Legendary | 0.06819% |
| **Sandstorm** | Unusual | | | |
| | | Sand | Rare | 10.23% |
| | | Faster | Rare | 5.114% |
| | | Stick | Legendary | 0.04091% |
| | | Web | Mythic | 0.02046% |
| **Scorpion** | Unusual | | | |
| | | Iris | Unusual | 17.53% |
| | | Pincer | Rare | 20.46% |
| | | Triplet | Epic | 0.09091% |
| | | Lotus | Epic | 0.4091% |
| | | Missile | Epic | 0.8182% |
| **Spider** | Unusual | | | |
| | | Stinger | Unusual | 17.17% |
| | | Web | Rare | 8.585% |
| | | Faster | Rare | 2.146% |
| | | Web | Legendary | 0.03434% |
| | | Missile | Legendary | 0.03434% |
| **Ant Hole** | Rare | | | |
| | | Iris | Unusual | 100% |
| | | Wing | Rare | 23.81% |
| | | Egg | Epic | 3.174% |
| | | Triplet | Epic | 1.058% |
| | | Soil | Legendary | 0.9522% |
| **Queen Ant** | Rare | | | |
| | | Twin | Unusual | 100% |
| | | Iris | Unusual | 100% |
| | | Wing | Rare | 23.81% |
| | | Egg | Epic | 3.174% |
| | | Stinger | Legendary | 0.9522% |
| **Ladybug** | Epic | | | |
| | | Rose | Rare | 100% |
| | | Wing | Rare | 100% |
| | | Bubble | Rare | 100% |
| | | Yggdrasil | Mythic | 1.023% |
| **Square** | Unique | | | |
| | | Square | Unique | 100% |
| **Digger** | Epic | | | |
| | | Cutter | Epic | 37.33% |
| | | Uranium | Legendary | 3.733% |
| **Fire Ant** | Unusual | | | |
| | | Yucca | Unusual | 19.39% |
| | | Wing | Rare | 0.6463% |
| | | Lotus | Epic | 0.1293% |
| | | Bone | Legendary | 0.01293% |
| **Ant Burrow** | Rare | | | |
| | | Salt | Rare | 51.17% |
| | | Egg | Epic | 2.047% |
| | | Lightning | Legendary | 0.614% |
| | | Magnet | Mythic | 0.1535% |

## Dropped when a player dies

Up to three of the petals the flower had (not Basic), the rarest first, each kept with 95%; a rare or better one has a 5% chance to turn into a Pollen. A flower that leaves the game (a save, the X of the sandbox) drops nothing. The rest of the petals go back to the camera's inventory for the next life (a lower level means fewer slots).
