# Balance notes

## 2026-08-31, second pass: content, not constants

Context: "implement more enticing features to keep the gameplay more
interesting for longer". The first pass (below) fixed the node-supply
mispricing but left the game with nothing to *do* once the curve was
straight - three area unlocks, then an exponential grind with no goals.

Four systems went in, plus the cost-curve pass the first note deferred.

### Rich veins (`Balance.RICH_*`, `Area`, `Actor`, `GameView`)
One site on the player's current board flares every 35-90s for 16s. Working
it by hand yields `RICH_MULTIPLIER` units per unit actually pulled out of the
ground, so it multiplies *yield* without touching *drain* - which is what
makes it the only mechanic that beats the node ceiling instead of racing
against it. Crews get 1.0 always, and it is not modelled offline, so this is
strictly a reward for having the watch out. The bottom button reroutes to
`ACT_RICH` while one is live.

### Area mastery (`Balance.MASTERY_*`, `Area.credit`)
Units realised in an area - `runMachine`, `sellStock`, and the offline
machine path - accumulate toward per-area mastery levels on a
`MASTERY_GROWTH` curve, each worth `+MASTERY_STEP` on everything that area is
worth. `Area.unitValue()` applies it; `Machine.valueBonus` mirrors it because
`Machine.valueOf` prices offline production without an `Area` in hand, so
`Area.syncMastery()` must be called after anything that moves mastery (it is,
from `credit()`, `load()` and `prestige()`).

This is the direct answer to "too few levels, progress stalls": mastery is
unbounded, is not for sale, and does not ride the cash curve, so it keeps
moving after cash has stopped.

### Contracts (`Balance.GOAL_*`, `GameState.checkContracts`)
Eighteen ordered milestones, one open at a time. `contractsDone` is the whole
of the state - it is both the completed set and the index of the open one -
and every kind reads state the game already keeps (`payroll()`,
`machineTotal()`, `masteryTotal()`, `lifetime`, ...), so a contract costs a
row in four parallel arrays and nothing else. Checked from `tick()` and from
`claimOffline()`; the check loops, because a long offline haul can carry two
at once.

### Moving camp (`Balance.PRESTIGE_SCALE`, `LEGACY_STEP`, `GameState.prestige`)
Replaces WIPE SAVE on the options page, at the user's request - same slab,
but it is progress rather than the loss of it, and `PrestigeDelegate` still
asks. Points are `floor(sqrt(lifetime / PRESTIGE_SCALE))` scored on **this
run's** lifetime, added to the banked total; the square root means a run has
to be 4x as big to be worth 2x as much, so there is no reward for resetting
at the threshold over and over. `legacyBonus()` is applied in `earn()` - the
single place money is created - so no income path added later can quietly
skip it.

`GameState.wipe()` and `WipeDelegate.mc` are gone.

### The deferred cost-curve pass
Done, and mechanised rather than eyeballed. `simulate_economy.py`'s buyer now
spends on the best marginal income per dollar instead of on whatever is
cheapest, which is both a better model of a real player and what makes
relative pricing checkable: it prices every option by the income it would add
(`bump(+1)`, measure, `bump(-1)`) before committing. The sim then **fails** if
any of the six upgrade paths is never bought at all - that is what "priced
wrong against its siblings" looks like from the outside, and it was invisible
in the unlock times.

All six paths come out live at the current numbers, so no base cost needed
changing. The pricing problem the first note suspected was not in
`COST_SPEED`/`COST_CAPACITY`/etc.

### Where the curve landed
`tools/simulate_economy.py --report`:

```
FOREST 0.0 min, QUARRY 12.5, MINE 48.4, FLAX FIELD 172.7
at 600 min - lifetime $2.66e+08
levels bought: player speed 26, carry 26, gather 27,
               crew speed 23, carry 23, regrowth 26
mastery [16, 16, 16, 14], contracts 14/18
```

First-cut numbers for the new systems were far too generous - contract
rewards and mastery together finished the whole game in 15 minutes. What
fixed it: `GOAL_REWARD` cut ~5x across the board (a contract should be a
nudge toward the next thing, not the income source), `MASTERY_BASE` 300 ->
900, `MASTERY_GROWTH` 1.34 -> 1.45, `MASTERY_STEP` 0.14 -> 0.10.

Re-run the sim after any further constant change and compare those numbers.

## Still not done

### More physical nodes (vs. faster respawn)
Unchanged from the first pass, and now partly obsoleted: rich veins give the
node board something that changes over time without new tap targets. Adding
real nodes still means new `Balance.NODES` entries, new coordinates that pass
`tools/check_layout.py` (currently "6 board objects fit the glass"), and
`Layout.mc` work across device configs. Worth doing only if the boards still
feel static with veins in.

### Mastery is invisible outside the machine page
It is drawn under `ManageView`'s machine detail with a progress bar, which is
correct but out of the way - the board itself never says how well-known the
ground is. A tint on the node colour by mastery tier would say it without
costing a row.

## 2026-08-31, first pass: the node ceiling

Context: a balance pass triggered by "too few nodes, too much automation,
upgrades too expensive on some paths relative to others, too few levels,
progress stalls, no goals, 3 workers at speed lv3 beat 10 levels of
regrowth."

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
