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
Not pushed. The 2.0 branches themselves are untouched.

- `Nav/WalkPaths.lua` (new, listed in `OpenXP.toc` after `Nav\PathHints.lua`):
  loads the optional OpenXP_Nav add-on at login if it's installed and
  enabled, and gives the arrow the next corner of the baked walk to the
  guide's spot. Without OpenXP_Nav it does nothing.
- `Nav/Target.lua`: `Target.Real()` also keeps the spot's map `x`, `y`
  (to find its baked walk), and `Target.Update()` asks
  `WalkPaths.ForArrow(aim)` before `PathHints.ForArrow(aim)`.
- `tools/package_2.py`: the zip holds `OpenXP/` and, when it's there,
  `OpenXP_Nav/` next to it: one download, two add-on folders (like DBM), and
  players can turn OpenXP_Nav off in the AddOns list. Both folders get the
  same "every listed file exists, nothing unlisted" checks.
- `tests/nav_test.lua`: a baked-walk case with a small fake OpenXP_Nav.
- `tests/playthrough_test.lua`: also plays the guide group
  `SoupEngine Test (<Faction>)` for every race and class when SoupEngine
  guide files are listed in `Guides.xml`; skipped otherwise.
- `docs/2.0/SOUPENGINE.md`: this note.

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

## OpenXP_Nav (walking paths)

`python -m soup navexport --faction X` (also step 7 of `soup build`) writes
`build/OpenXP_Nav/` in SoupEngine; `--openxp <checkout>` copies it next to this
repo's `OpenXP/` folder, where `tools/package_2.py` picks it up. Decided by
Matt (2026-11-18): ship it whole, maps included, in the same download as
OpenXP, as its own add-on folder players can turn off.

| File | What | Size |
|---|---|---|
| `OpenXP_Nav.toc` | `## LoadOnDemand: 1`, `## Dependencies: OpenXP` | tiny |
| `README.txt` | what's in it, for players and add-on site reviewers | tiny |
| `Init.lua` | tables `paths`, `spots`, `packed`; sets the global `OpenXP_Nav` | tiny |
| `Paths-Alliance.lua`, `Paths-Horde.lua` | baked walking paths and guide-spot floors; each only runs for its own faction | ~1.3 MB each |
| `Unpack.lua` | SoupNav's readable graph unpacker (sets `NAV.Unpack`) | tiny |
| `Graphs/<zone>.lua` (48 zones) | SoupNav's packed walking network per zone | ~9.4 MB |

About 12 MB unpacked; the release zip with both folders was 7.6 MB.

Formats:

- `OpenXP_Nav.paths["map:x,y>map:x,y"] = { x1, y1, z1, i1, x2, ... }`: one
  walking leg inside one zone, as corners in map % with height in yards and
  1 = indoors. Keys use two decimals. Most legs (2982 of 3607 for Alliance)
  end exactly on a guide `goto` (`zone`, `x`, `y`); the rest end at other
  points of a trip.
- `OpenXP_Nav.spots["map:x,y"] = { z, indoor }`: the floor of a guide spot
  (addons can't read height on Forever, `UnitPosition`'s z is always 0).
  Every Alliance `goto` spot has one. `WalkPaths.Floor(map, x, y)` reads it;
  nothing uses it yet.

It holds only points derived from SoupNav's walking map and SoupNav's packed
graphs: no terrain, meshes, models or anything else copied from the game.
The packed strings could look like hidden code to a reviewer, so README.txt
says what they are and `Unpack.lua` stays plain Lua. If an add-on site
objects anyway, the fallback is shipping only the paths and floors (~2.6 MB).

### How the arrow uses it

`WalkPaths.ForArrow(aim)` looks up every baked leg that ends at the guide
spot the arrow is aiming at, finds the one passing nearest the player, and
points at the next corner ahead (corners within 8 yards count as passed).
It gives up, and the arrow behaves as before, when:

- the player is more than 40 yards from every baked leg to that spot,
- the next corner is the spot itself,
- the aim isn't a guide spot (another zone's trip, a kill area, a chain
  walk, `/oxp path to`).

Baked walks win over path hints and terrain ways, in both route styles.
Checked against the real Alliance export in the headless client: standing on
each Elwynn 1-11 spot, the arrow got a corner toward the next one 137 times
out of 344; the rest were straight walks, repeat spots or walks baked from
somewhere else, which fall back to the old arrow. No Lua errors.

### Ideas for later (not approved, not built)

- Off the path (after dying, or wandering off): lead back to the nearest
  point on the baked walk, or route on the zone graphs (`NAV.packed` +
  `NAV.Unpack`), which ship but aren't used yet.
- Bake walks from graveyards to the guide spots.
- A light waypoint web between spots, for walks the route never takes.
- Floors: tell the player a spot is in a cave or upstairs.

## Known issues (SoupNav side, not fixed here)

SoupNav is being fixed separately; these were open when this was written.


- Zone meshes stop at zone edges, so ~10 border crossings sit off the mesh.
- Floors pick the ground above mines (Goldtooth, Fargodeep), because guide
  spots have no height.
- Since SoupNav's latest `Unpack.lua` (it now sets `NAV.Unpack` itself),
  SoupEngine copies it as is (SoupEngine branch `openxp-nav-readme`).
- The `build/OpenXP_Nav` checked here was made before SoupNav's latest
  floors and links fixes: re-run `soup navexport` for both factions before
  a release.
