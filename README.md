# Timberline

An idle automation game for the Garmin Venu 2 family. You start by chopping a
tree yourself, one tap per trip. You end up watching four boards run without
you.

```
DO THE WORK  ->  HELP THE WORKERS  ->  MANAGE THE OPERATION  ->  WATCH IT RUN
```

Every purchase is meant to delete something you were doing by hand a minute
earlier: a worker takes over the walking, a machine takes over the selling, an
area gives the money somewhere better to go.

## Playing

The board is one compact clearing that fits the glass - no camera, no
scrolling, no joystick.

| Gesture | What it does |
| --- | --- |
| Tap a tree, boulder, seam or flax stand | Walk there and work it until full |
| Tap the yard | Drop off, or sell the pile |
| Tap the machine | Open its page |
| Bottom button | The one action that makes sense right now |
| Swipe up | Upgrades, crew, machine, options |
| Swipe down / back | Back to the board |
| Swipe left / right | Change area |
| Select key | Same as the bottom button |

Every target is at least 96px across. Nothing needs precision, and nothing
needs two hands.

The bottom button is contextual and never shows more than one choice:
`COLLECT` when your hands are empty, `STORE` when they are not, `SELL $n`
when there is a pile in the yard, `UNLOCK` when you are standing in a place
you have not bought yet, and `RICH VEIN` when one is up - that one outranks
everything else, because it is on a clock.

## The loop

1. Collect a resource; your pack fills and you walk it home.
2. Sell the yard for cash, or leave it for the machine.
3. Machines eat the yard on their own and pay out more than the raw material
   was worth - that is the first income you do not have to walk for.
4. Hire crew, who do the whole walk-collect-deposit cycle themselves.
5. Unlock the next area, where everything is worth more and costs more.

Four areas, one resource and one machine each:

| Area | Resource | Machine | Product |
| --- | --- | --- | --- |
| Forest | wood | Lumber Mill | planks |
| Quarry | stone | Stone Cutter | blocks |
| Mine | iron | Smelter | ingots |
| Flax Field | fiber | Loom | cloth |

There is one currency. Crew upgrades are bought once and apply everywhere;
hiring and machinery are per area. That is the whole of worker management -
there is no per-worker configuration to fiddle with, on purpose.

Away from the watch, every unlocked board keeps producing for up to 8 hours at
60% rate, and you get a card on the way back in.

## Four things that outlast the upgrade curve

The exponential cost curve outruns any wallet eventually. These are what is
left to do when it does.

**Rich veins.** Every 35-90 seconds one site on the board you are standing on
comes in rich, marked by a ring that visibly runs out. Working it by hand pays
4x per swing *without* draining the site faster, so it is the one thing in the
game that beats the node ceiling. Crews walk straight past it. This is the
only reason to have the watch out rather than in a pocket, and it is
deliberately not modelled in the offline maths.

**Mastery.** Every unit an area realises - sold raw or run through its machine
- counts toward that area's mastery, a permanent multiplier on everything that
area is worth. It is per area, it is never for sale at any price, and it
survives moving camp. It is the ladder that keeps climbing after cash has
stopped.

**Contracts.** Eighteen of them, worked in order, one open at a time on its
own management page. Each reads off state the game already keeps, so it costs
a row in `Balance.mc` and nothing else, and each pays out once. They exist to
put a next thing on screen at every point in the game, including the stretches
between area unlocks where there was previously nothing to aim at.

**Moving camp.** Once a run has earned $5M you can walk away from the valley
and start it again. Cash, upgrades, crews, machines and unlocks all go;
mastery, contracts and legacy points come with you, and every legacy point is
a permanent +30% on everything you will ever earn again. Points are scored on
that run's earnings and square-rooted, so a run has to be four times as big to
be worth twice as much - there is no reward for bailing out early over and
over.

## Building

Needs a Connect IQ SDK and a JDK. If you installed an SDK with the graphical
SDK Manager it is found automatically; otherwise point `CIQ_SDK` at it.

```sh
tools/build.sh              # build build/venu2.prg
tools/verify.sh             # the checks that need no SDK
CIQ_SDK=~/my-sdk tools/build.sh
```

`tools/build.sh` generates the launcher icons, runs the layout check and
signs the build with `build/developer_key.der`, generating one if there is
none. That key is personal and is never committed.

To sideload, copy `build/venu2.prg` to `GARMIN/APPS` on the watch. To run it
in the simulator:

```sh
"$CIQ_SDK/bin/simulator" &
"$CIQ_SDK/bin/monkeydo" build/venu2.prg venu2
```

`manifest.xml` ships `venu2` only, because that is the device profile this was
tested against. The layout scales from a 416x416 design space, so adding
`venu2s` and `venu2plus` to the manifest and to `tools/build.sh` is enough to
cover the rest of the family.

## Layout

```
source/
  TimberlineApp.mc   entry point; picks the board or the welcome card
  GameState.mc       the wallet, the four areas, save/load, offline maths
  Area.mc            one board: nodes, yard, machine, crew
  Actor.mc           the gatherer state machine, shared by player and crew
  ResourceNode.mc    one harvest site and its regrowth timer
  Machine.mc         raw material in, cash out
  Balance.mc         every tunable number in the game
  GameView.mc        the board
  ManageView.mc      the six management pages
  PrestigeDelegate.mc  confirms moving camp
  WelcomeView.mc     what happened while you were away
  Scenery.mc         the ground, the horizon and the trails
  Theme.mc           colours and drawing primitives
  Layout.mc          416x416 design space to whatever the device has
  Fmt.mc             big numbers, short strings
  Events.mc          state changes, announced rather than polled
```

Two things are worth knowing before changing anything:

**Balance lives in `Balance.mc`.** Areas are described by parallel arrays
indexed by area id. Nothing else in the game hardcodes a cost, a rate or a
position.

**Idle progress is arithmetic, not simulation.** A crew's output comes from a
round-trip cycle time, and the same formula prices what you watch on screen
and what accrues while the app is closed, so the two agree. Nothing steps a
worker while the app is shut.

## Checks

`tools/verify.sh` runs without an SDK and is what CI runs:

- `check_layout.py` reads the board out of `Balance.mc` and asserts every
  object clears the bezel, clears the contextual button, and does not overlap
  another object's tap radius.
- `simulate_economy.py` replays the balance table with a buyer that spends on
  whatever adds the most income per dollar, and reports how long each area
  takes to reach. It fails if the curve collapses, if the areas come out of
  order, or if any upgrade path is priced so badly against its siblings that
  the buyer never touches it. `--report` adds the tail: levels bought,
  mastery reached and contracts signed off by the ten-hour mark.
