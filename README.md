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
you have not bought yet.

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
  ManageView.mc      the four management pages
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
- `simulate_economy.py` replays the balance table with a greedy buyer and
  reports how long each area takes to reach, failing if the curve collapses
  or the areas come out of order.
