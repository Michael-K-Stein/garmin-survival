# Balance notes (2026-08-31)

Context: a balance pass triggered by "too few nodes, too much automation,
upgrades too expensive on some paths relative to others, too few levels,
progress stalls, no goals, 3 workers at speed lv3 beat 10 levels of
regrowth."

## What this pass fixed

The root cause: node supply is a hard cap (`nodeCount * NODE_MAX /
NODE_RESPAWN`, units/sec), but nothing priced against it.

- `GameState.computeOffline()` capped crew demand by
  `Area.nodeSupplyRate()` - offline income no longer exceeds what the
  nodes could actually regrow, so idling the app is no longer strictly
  better than playing it with 2+ workers.
- `Balance.NODE_RESPAWN` lowered (~2.7x faster) so a full 6-worker crew
  plus the player at level-0 stats roughly matches the node ceiling,
  instead of 2-3 workers maxing it out immediately.
- `Balance.COST_REGROW` cut 400 -> 180 and `PLAYER_REGROW_STEP` raised
  0.15 -> 0.20, so raising the ceiling is cost-competitive with raising
  demand (worker/player speed) instead of ~20x more expensive per unit
  of realized throughput.
- `tools/simulate_economy.py` now models the node cap and the regrowth
  upgrade, so this class of bug (a balance lever the checker can't see)
  fails the sim instead of only surfacing in play.

Numbers are a first pass, not a final tune - re-run
`tools/simulate_economy.py` after any further constant changes and
compare `reached at` minutes per area.

## Deferred - not done in this pass

### More physical nodes (vs. faster respawn)
The fix above raises the ceiling by shrinking `NODE_RESPAWN`, not by
adding node count. Adding real nodes means new tap targets: new entries
in `Balance.NODES`, new coordinates that fit the round-glass check
(`tools/build.sh`'s "checking the round-screen layout" step - currently
reports "6 board objects fit the glass"), and `Layout.mc` changes,
across whatever device configs the build targets. That's real layout
work, not a constant tweak - worth doing if respawn-only tuning turns
out to feel wrong on the watch (e.g. nodes draining to empty too
visibly rather than feeling like more depth).

### Cost-curve consistency across all upgrade paths
Only `COST_REGROW` was repriced. `COST_SPEED` / `COST_CAPACITY` /
`COST_COLLECT` / `COST_WORKER_SPEED` / `COST_WORKER_CAPACITY` /
`MACHINE_COST` were not re-examined against each other - they may have
their own relative mispricing that just wasn't the one reported. Worth
a systematic pass: for each upgrade, compute cash cost per unit of
realized (node-capped) throughput at a few price points, the way this
session did for regrowth vs. worker speed, and compare across all of
them.

### Level caps / "too few levels, progress stalls"
Not addressed. No upgrade currently has a level cap in code (they grow
forever on the `COST_GROWTH` curve), so "too few levels" likely means
the exponential curve outpaces income long before the player runs out
of *content*, not that levels are literally capped - i.e. this is the
same underlying pricing problem, not a separate one. Should mostly
resolve once the cost-curve pass above is done; revisit if it doesn't.

### Missions / goals system
Nothing exists today beyond area-unlock thresholds
(`Balance.AREA_UNLOCK`). No design work done this pass. Rough shape to
consider: a short list of discrete, checkable milestones (e.g. "build
your first machine", "hire a full crew in one area", "reach $X
lifetime") surfaced somewhere in the UI (a 5th Manage page? a toast on
completion?) with a small one-time cash reward, distinct from the
continuous upgrade grind. Needs: a persistence slot (bitmask of
completed goals is cheapest), a check hook (probably in
`GameState.tick()`/purchase functions where the relevant stat already
changes), and UI space - `ManageView`'s row layout is already tight at
3 rows per page.
