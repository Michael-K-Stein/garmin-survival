#!/usr/bin/env python3
"""Play Timberline on paper and check the progression curve is sane.

An idle game lives on its pacing, and pacing is the one thing you cannot see
by reading a constant. This reads the balance table straight out of
Balance.mc, plays a buyer through it, and reports how long each area takes to
reach.

The buyer spends on whatever buys the most income per dollar, rather than on
whatever is cheapest. That is both a better model of a real player and the
thing that makes the cost curve checkable: an upgrade priced badly against its
siblings is one this buyer simply never touches, which `--report` will show as
a path stuck at level 0.

It fails the build if the curve collapses: an area that unlocks in seconds is
as broken as one that never unlocks at all.

Not modelled, on purpose:
  - Rich veins. They are gated on the player being on the board and tapping
    the right site inside a 16-second window; modelling them as always-on
    would overstate a bonus that a hands-off player never sees at all.
  - Moving camp. Legacy is a voluntary late loop on top of a run this sim
    already plays to completion, and a buyer who never takes it is the
    conservative case.
Both make the sim's timings an upper bound on how long a real run takes.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BALANCE = ROOT / "source" / "Balance.mc"

# What "sane" means, in minutes of wall-clock play with the app open.
MIN_MINUTES = 3
MAX_MINUTES = 600
# The simulation runs a second at a time; anything past this is a failure.
HORIZON_SECS = MAX_MINUTES * 60

# Every upgrade path that has to stay live. A path the value-greedy buyer
# never buys is mispriced against its siblings, which is exactly the class of
# bug the cost-curve pass was meant to catch.
PATHS = ("player speed", "player carry", "player gather", "crew speed",
         "crew carry", "regrowth")


def constants(text):
    return dict(re.findall(r"const\s+(\w+)\s*=\s*([^;]+);", text))


def floats(raw):
    return [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", raw)]


class Sim:
    """The same arithmetic the Monkey C does, in the same order."""

    def __init__(self, c, node_count):
        self.c = c
        self.node_count = node_count
        self.cash = 0.0
        self.lifetime = 0.0
        self.unlocked = [True, False, False, False]
        self.machine = [0, 0, 0, 0]
        self.crew = [0, 0, 0, 0]
        self.stock = [0.0, 0.0, 0.0, 0.0]
        self.mastery = [0, 0, 0, 0]
        self.credited = [0.0, 0.0, 0.0, 0.0]
        self.goals_done = 0
        self.lvl_speed = 0
        self.lvl_capacity = 0
        self.lvl_collect = 0
        self.lvl_wspeed = 0
        self.lvl_wcapacity = 0
        self.lvl_regrow = 0
        self.spent = {name: 0 for name in PATHS}

    # --- stats ----------------------------------------------------------
    def worker_speed(self):
        return self.c["WORKER_SPEED"] * (1 + self.c["WORKER_SPEED_STEP"] * self.lvl_wspeed)

    def worker_capacity(self):
        return self.c["WORKER_CAPACITY"] + self.c["WORKER_CAPACITY_STEP"] * self.lvl_wcapacity

    def worker_collect(self):
        return self.c["WORKER_COLLECT"] * (1 + self.c["WORKER_COLLECT_STEP"] * self.lvl_wspeed)

    def player_speed(self):
        return self.c["PLAYER_SPEED"] * (1 + self.c["PLAYER_SPEED_STEP"] * self.lvl_speed)

    def player_capacity(self):
        return self.c["PLAYER_CAPACITY"] + self.c["PLAYER_CAPACITY_STEP"] * self.lvl_capacity

    def player_collect(self):
        return self.c["PLAYER_COLLECT"] * (1 + self.c["PLAYER_COLLECT_STEP"] * self.lvl_collect)

    def cycle_rate(self, speed, capacity, collect):
        """Units per second for one gatherer doing round trips."""
        return capacity / (self.c["OFFLINE_TRIP_PX"] / speed + capacity / collect)

    def regrow_boost(self):
        return 1 + self.c["PLAYER_REGROW_STEP"] * self.lvl_regrow

    def node_supply_rate(self, area):
        """The hard ceiling on that area's output: nodes regrowing, not
        gatherers fetching. Demand past this is wasted cash - a crew or
        speed upgrade only pays off below it."""
        return (self.node_count * self.c["NODE_MAX"][area]
                / self.c["NODE_RESPAWN"][area]) * self.regrow_boost()

    def machine_rate(self, area):
        level = self.machine[area]
        if level <= 0:
            return 0.0
        return self.c["MACHINE_RATE"][area] * (1 + self.c["MACHINE_RATE_STEP"] * (level - 1))

    def machine_value(self, area):
        level = self.machine[area]
        if level <= 0:
            return 1.0
        return self.c["MACHINE_VALUE"] + self.c["MACHINE_VALUE_STEP"] * (level - 1)

    def mastery_bonus(self, area):
        return 1 + self.c["MASTERY_STEP"] * self.mastery[area]

    def mastery_target(self, area):
        return self.c["MASTERY_BASE"] * self.c["MASTERY_GROWTH"] ** self.mastery[area]

    def credit(self, area, units):
        self.credited[area] += units
        while self.credited[area] >= self.mastery_target(area):
            self.credited[area] -= self.mastery_target(area)
            self.mastery[area] += 1

    # --- costs ----------------------------------------------------------
    def cost(self, base, level, growth=None):
        growth = growth if growth is not None else self.c["COST_GROWTH"]
        return base * growth ** level

    def payroll(self):
        return sum(self.crew)

    def gather_rate(self, area):
        """Units per second actually realised in an area, ceiling included."""
        rate = self.crew[area] * self.cycle_rate(
            self.worker_speed(), self.worker_capacity(), self.worker_collect())
        # The player works the first area they are standing in.
        if area == 0:
            rate += self.cycle_rate(self.player_speed(), self.player_capacity(),
                                    self.player_collect())
        return min(rate, self.node_supply_rate(area))

    def income_rate(self):
        """Cash per second across the whole operation, as it stands."""
        total = 0.0
        for a in range(4):
            if not self.unlocked[a]:
                continue
            gathered = self.gather_rate(a)
            processed = min(self.machine_rate(a), gathered)
            value = self.c["RESOURCE_VALUE"][a] * self.mastery_bonus(a)
            total += processed * value * self.machine_value(a)
            total += (gathered - processed) * value
        return total

    def options(self):
        """Everything buyable right now, as (cost, label, bump).

        `bump(+1)` applies the purchase and `bump(-1)` undoes it, which is
        what lets the buyer price each option by the income it would actually
        add before committing to it.
        """
        def level(attr):
            return lambda d, attr=attr: setattr(self, attr, getattr(self, attr) + d)

        def slot(store, a):
            return lambda d, store=store, a=a: store.__setitem__(a, store[a] + d)

        out = [
            (self.cost(self.c["COST_SPEED"], self.lvl_speed),
             "player speed", level("lvl_speed")),
            (self.cost(self.c["COST_CAPACITY"], self.lvl_capacity),
             "player carry", level("lvl_capacity")),
            (self.cost(self.c["COST_COLLECT"], self.lvl_collect),
             "player gather", level("lvl_collect")),
            (self.cost(self.c["COST_WORKER_SPEED"], self.lvl_wspeed),
             "crew speed", level("lvl_wspeed")),
            (self.cost(self.c["COST_WORKER_CAPACITY"], self.lvl_wcapacity),
             "crew carry", level("lvl_wcapacity")),
            (self.cost(self.c["COST_REGROW"], self.lvl_regrow),
             "regrowth", level("lvl_regrow")),
        ]
        for a in range(4):
            if not self.unlocked[a]:
                out.append((self.c["AREA_UNLOCK"][a], "unlock %d" % a,
                            slot(self.unlocked, a)))
                continue
            if self.crew[a] < self.c["WORKER_MAX"]:
                out.append((self.cost(self.c["COST_HIRE"], self.payroll(),
                                      self.c["HIRE_GROWTH"]),
                            "hire %d" % a, slot(self.crew, a)))
            out.append((self.cost(self.c["MACHINE_COST"][a], self.machine[a]),
                        "machine %d" % a, slot(self.machine, a)))
        return out

    def buy(self):
        """Spend down: always take the best income per dollar on offer.

        Opening an area is taken on sight - a board with nobody on it adds no
        income yet, so pricing it by marginal income would leave the sim
        sitting in the forest forever - and when nothing on offer adds income
        at all, the cheapest thing breaks the tie.
        """
        while True:
            affordable = [o for o in self.options() if o[0] <= self.cash]
            if not affordable:
                return
            unlocks = [o for o in affordable if o[1].startswith("unlock")]
            if unlocks:
                pick = min(unlocks, key=lambda o: o[0])
            else:
                before = self.income_rate()
                best, best_score = None, 0.0
                for option in affordable:
                    cost, _, bump = option
                    bump(+1)
                    gain = self.income_rate() - before
                    bump(-1)
                    score = gain / cost if cost > 0 else 0.0
                    if score > best_score:
                        best, best_score = option, score
                pick = best or min(affordable, key=lambda o: o[0])
            cost, label, bump = pick
            self.cash -= cost
            bump(+1)
            if label in self.spent:
                self.spent[label] += 1

    def earn(self, amount):
        self.cash += amount
        self.lifetime += amount

    def check_goals(self):
        """Contracts pay out once, in order, off state the game already has."""
        kinds = self.c["GOAL_KIND_RESOLVED"]
        while self.goals_done < len(kinds):
            kind = kinds[self.goals_done]
            target = self.c["GOAL_TARGET"][self.goals_done]
            have = {
                0: self.lifetime,
                1: self.payroll(),
                2: sum(self.machine),
                3: sum(self.unlocked),
                4: sum(self.mastery),
                5: (self.lvl_speed + self.lvl_capacity + self.lvl_collect
                    + self.lvl_regrow),
                6: 0,  # legacy: this buyer never moves camp
            }[kind]
            if have < target:
                return
            self.earn(self.c["GOAL_REWARD"][self.goals_done])
            self.goals_done += 1

    # --- the loop -------------------------------------------------------
    def step(self):
        """One second of play: gather, process, sell, then spend."""
        for a in range(4):
            if not self.unlocked[a]:
                continue
            gathered = self.gather_rate(a)
            self.stock[a] += gathered
            processed = min(self.machine_rate(a), self.stock[a])
            self.stock[a] -= processed
            value = self.c["RESOURCE_VALUE"][a] * self.mastery_bonus(a)
            self.earn(processed * value * self.machine_value(a))
            # Anything the machine cannot keep up with gets sold raw.
            self.earn(self.stock[a] * value)
            self.credit(a, processed + self.stock[a])
            self.stock[a] = 0.0

        self.check_goals()
        self.buy()


def main():
    text = BALANCE.read_text(encoding="utf-8")
    raw = constants(text)

    c = {}
    for key, value in raw.items():
        nums = floats(value)
        if not nums:
            continue
        c[key] = nums if "[" in value else nums[0]
    c["WORKER_MAX"] = int(c["WORKER_MAX"])
    node_count = len(c["NODES"]) // 2

    # GOAL_KIND is written as names, so resolve it through the GOAL_* scalars
    # rather than duplicating the ordering here.
    kinds = re.findall(r"GOAL_\w+", raw["GOAL_KIND"])
    c["GOAL_KIND_RESOLVED"] = [int(c[name]) for name in kinds]

    sim = Sim(c, node_count)
    reached = {0: 0}
    for second in range(1, HORIZON_SECS + 1):
        sim.step()
        for a in range(1, 4):
            if sim.unlocked[a] and a not in reached:
                reached[a] = second
        if len(reached) == 4:
            break

    names = re.findall(r'"([^"]+)"', raw["AREA_NAME"])
    errors = []
    for a in range(4):
        if a not in reached:
            errors.append("%s is unreachable within %d minutes"
                          % (names[a], MAX_MINUTES))
            continue
        minutes = reached[a] / 60.0
        print("economy: %-12s reached at %6.1f min" % (names[a], minutes))
        if a > 0 and minutes < MIN_MINUTES:
            errors.append("%s unlocks after only %.1f min; the curve is too flat"
                          % (names[a], minutes))

    order = [reached[a] for a in sorted(reached)]
    if order != sorted(order):
        errors.append("areas are not reached in order: %s" % order)

    if "--report" in sys.argv:
        # Everything after the last unlock is the tail the contracts and the
        # mastery ladder are there to fill, so report where it actually gets
        # to rather than stopping at the last board.
        tail = HORIZON_SECS - max(reached.values())
        for _ in range(max(tail, 0)):
            sim.step()
        print("economy: at %d min - lifetime $%.3g" % (MAX_MINUTES, sim.lifetime))
        print("economy: levels bought " + ", ".join(
            "%s %d" % (name, sim.spent[name]) for name in PATHS))
        print("economy: mastery %s, contracts %d/%d"
              % (sim.mastery, sim.goals_done, len(c["GOAL_TARGET"])))

    # A path nobody ever buys is priced wrong against the others, which is
    # invisible in the unlock times but is exactly what makes some upgrades
    # feel like traps.
    dead = [name for name in PATHS if sim.spent[name] == 0]
    if dead:
        errors.append("never worth buying: %s" % ", ".join(dead))

    if errors:
        for line in errors:
            print("economy: " + line, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
