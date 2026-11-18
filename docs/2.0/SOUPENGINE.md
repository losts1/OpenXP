# OpenXP 2.0 and SoupEngine

SoupEngine (Matt's own route builder, in its own repo) turns quest data and
SoupNav's walking maps into leveling routes. It writes two things for OpenXP 2.0:

1. **Guide files**: normal OpenXP 2.0 guide Lua (`OXP.AddGuides({...})`).
2. **OpenXP_Nav**: a separate, load-on-demand addon folder with baked walking
   paths and floor heights for the arrow.

This note says what OpenXP needs to know about both, what changed in this repo
for it, and what is still open.

## What changed in this repo

Branch `soupengine-test`, made from `68049d0` ("Clean slate: keep only what
OpenXP 2.0 uses", the newest 2.0 code, same as `origin/polestar-guides`).
The 2.0 code itself is untouched.

- `tests/playthrough_test.lua`: the headless play-through now also plays the
  guide group `SoupEngine Test (<Faction>)` for every race and class, but only
  when SoupEngine guide files are listed in `Guides.xml`. Without them nothing
  changes.
- `docs/2.0/SOUPENGINE.md`: this note.

No engine, UI or nav code changed.

## SoupEngine guides in OpenXP

The guide files need **no OpenXP code changes**. They use the same format as
`Guides/Leveling/<Faction>/PoleStar-01-60.lua`; SoupEngine reads them back
and compares every step and goal before it finishes ("round trip").

They live in their own guide group so they never replace the default:

| | Default (live) | SoupEngine test |
|---|---|---|
| group | `OpenXP Leveling (<Faction>)` | `SoupEngine Test (<Faction>)` |
| file id | `<Faction>-PoleStar-01-60` | `<Faction>-SoupEngine-Test-PoleStar-01-60` (or `<Faction>-SoupTest-<lo>-<hi>`) |
| file | `PoleStar-01-60.lua` | `SoupEngine-Test-PoleStar-01-60.lua` (or `SoupTest-<lo>-<hi>.lua`) |

Why this is safe with the current engine:

- `Registry` keys guides by group + name + only, so the same guide names in
  two groups don't collide.
- `Registry.Next` looks for a guide's `next` in its own group first, so a
  SoupEngine chain stays in the SoupEngine group.
- `SmartStart` only ever picks from `OpenXP Leveling (<Faction>)`, so new
  characters never land on a test guide by accident.
- The guide picker lists every group, so the test group shows up as its own
  entry and players pick it on purpose.

### Loading them for a test

SoupEngine side (in the SoupEngine repo):

```
python -m soup write --faction Alliance --route build/seed_route-Alliance.json \
    --group "SoupEngine Test (Alliance)" --out <OpenXP>/OpenXP/Guides/Leveling/Alliance --check
```

Then add one line per faction to `OpenXP/Guides/Guides.xml`, right after that
faction's `PoleStar-01-60.lua` line:

```
<Script file="Leveling\Alliance\SoupEngine-Test-PoleStar-01-60.lua"/>
```

(`python -m soup build ... --openxp <checkout>` writes a one-band file,
`SoupTest-<lo>-<hi>.lua`, and adds the `Guides.xml` line itself.)

Checked on 2026-11-17: both factions' files (from the seed route, so the same
steps as PoleStar's) loaded with no registry problems, and the play-through
finished every guide for all 90 race/class combos in the test group, 0 failures.

The generated guide files are not committed: they're ~2 MB per faction and,
until SoupEngine has an optimized route, the same steps as the default.

## OpenXP_Nav (walking paths) — not used by OpenXP yet

`python -m soup navexport --faction X` (also step 7 of `soup build`) writes
`build/OpenXP_Nav/`, a separate addon folder meant to sit next to `OpenXP/`:

| File | What | Size |
|---|---|---|
| `OpenXP_Nav.toc` | `## LoadOnDemand: 1`, `## Dependencies: OpenXP` | tiny |
| `Init.lua` | tables `paths`, `spots`, `packed`; sets the global `OpenXP_Nav` | tiny |
| `Paths-Alliance.lua`, `Paths-Horde.lua` | baked walking paths and guide-spot floors; each only runs for its own faction | ~1.3 MB each |
| `Unpack.lua` | SoupNav's graph unpacker (sets `NAV.Unpack`) | tiny |
| `Graphs/<zone>.lua` (48 zones) | SoupNav's packed walking graph per zone | ~9.4 MB |

Formats:

- `OpenXP_Nav.paths["map:x,y>map:x,y"] = { x1, y1, z1, i1, x2, ... }`: one
  walking leg from one spot to the next, as corners in map % with height in
  yards and 1 = indoors. Keys use two decimals. Most legs (2982 of 3607 for
  Alliance) end exactly on a guide `goto` (`zone`, `x`, `y`); the rest end at
  travel points on the way (flight masters, zone crossings, boats).
- `OpenXP_Nav.spots["map:x,y"] = { z, indoor }`: the floor of a guide spot
  (addons can't read height on Forever, `UnitPosition`'s z is always 0).
  Every Alliance `goto` spot has one.

What it contains: only points derived from SoupNav's walking map and the
packed graphs. No terrain, meshes or anything read from the game client.
**Open question for Matt:** the packed graphs are still a compact form of the
walkable map. Shipping only the paths and floors (~2.6 MB) avoids that
question and is enough for "follow the baked path".

### What OpenXP would need (not done)

1. Load it: `C_AddOns.LoadAddOn("OpenXP_Nav")` (or `LoadAddOn`) after login,
   then read the global `OpenXP_Nav`. OpenXP must keep working when it's
   missing or disabled.
2. Use it in the arrow: in `Nav/Target.lua` `Target.Update`, next to
   `PathHints.ForArrow(aim)`, look up the legs that end at the current
   guide spot, find the corner on that leg nearest ahead of the player and
   point at it (like a stepping stone) until the spot is close.
3. Floors: `spots` can tell the arrow "this spot is in a cave below you".
4. Tests: a `nav_test.lua` case with a small fake `OpenXP_Nav` table.
5. Packaging: ship `OpenXP_Nav/` as a second folder in the release zip.

## Known issues (SoupNav side, not fixed here)

- Zone meshes stop at zone edges, so ~10 border crossings sit off the mesh.
- Floors pick the ground above mines (Goldtooth, Fargodeep), because guide
  spots have no height.
- SoupEngine already works around `Unpack.lua` ending in `return Unpack`.
