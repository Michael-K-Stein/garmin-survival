#!/usr/bin/env python3
"""Play Timberline on paper and check the progression curve is sane.

An idle game lives on its pacing, and pacing is the one thing you cannot see
by reading a constant. This reads the balance table straight out of
Balance.mc, plays a greedy buyer through it - always buy the cheapest thing
that pays off, sell whenever there is stock - and reports how long each area
takes to reach.

It fails the build if the curve collapses: an area that unlocks in seconds is
as broken as one that never unlocks at all.
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


def constants(text):
    return dict(re.findall(r"const\s+(\w+)\s*=\s*([^;]+);", text))


def floats(raw):
    return [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", raw)]


class Sim:
    """The same arithmetic the Monkey C does, in the same order."""

    def __init__(self, c):
        self.c = c
        self.cash = 0.0
        self.unlocked = [True, False, False, False]
        self.machine = [0, 0, 0, 0]
        self.crew = [0, 0, 0, 0]
        self.stock = [0.0, 0.0, 0.0, 0.0]
        self.lvl_speed = 0
        self.lvl_capacity = 0
        self.lvl_collect = 0
        self.lvl_wspeed = 0
        self.lvl_wcapacity = 0

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

    # --- costs ----------------------------------------------------------
    def cost(self, base, level, growth=None):
        growth = growth if growth is not None else self.c["COST_GROWTH"]
        return base * growth ** level

    def payroll(self):
        return sum(self.crew)

    def options(self):
        """Everything buyable right now, as (cost, label, apply)."""
        out = [
            (self.cost(self.c["COST_SPEED"], self.lvl_speed), "player speed",
             lambda: setattr(self, "lvl_speed", self.lvl_speed + 1)),
            (self.cost(self.c["COST_CAPACITY"], self.lvl_capacity), "player carry",
             lambda: setattr(self, "lvl_capacity", self.lvl_capacity + 1)),
            (self.cost(self.c["COST_COLLECT"], self.lvl_collect), "player gather",
             lambda: setattr(self, "lvl_collect", self.lvl_collect + 1)),
            (self.cost(self.c["COST_WORKER_SPEED"], self.lvl_wspeed), "crew speed",
             lambda: setattr(self, "lvl_wspeed", self.lvl_wspeed + 1)),
            (self.cost(self.c["COST_WORKER_CAPACITY"], self.lvl_wcapacity), "crew carry",
             lambda: setattr(self, "lvl_wcapacity", self.lvl_wcapacity + 1)),
        ]
        for a in range(4):
            if not self.unlocked[a]:
                out.append((self.c["AREA_UNLOCK"][a], "unlock %d" % a, self.unlock(a)))
                continue
            if self.crew[a] < self.c["WORKER_MAX"]:
                out.append((self.cost(self.c["COST_HIRE"], self.payroll(),
                                      self.c["HIRE_GROWTH"]), "hire %d" % a, self.hire(a)))
            out.append((self.cost(self.c["MACHINE_COST"][a], self.machine[a]),
                        "machine %d" % a, self.build(a)))
        return out

    def unlock(self, a):
        def apply():
            self.unlocked[a] = True
        return apply

    def hire(self, a):
        def apply():
            self.crew[a] += 1
        return apply

    def build(self, a):
        def apply():
            self.machine[a] += 1
        return apply

    # --- the loop -------------------------------------------------------
    def step(self):
        """One second of play: gather, process, sell, then spend."""
        speed, capacity, collect = (self.worker_speed(), self.worker_capacity(),
                                    self.worker_collect())
        for a in range(4):
            if not self.unlocked[a]:
                continue
            gathered = self.crew[a] * self.cycle_rate(speed, capacity, collect)
            # The player works the first area they are standing in.
            if a == 0:
                gathered += self.cycle_rate(self.player_speed(), self.player_capacity(),
                                            self.player_collect())
            self.stock[a] += gathered
            processed = min(self.machine_rate(a), self.stock[a])
            self.stock[a] -= processed
            self.cash += processed * self.c["RESOURCE_VALUE"][a] * self.machine_value(a)
            # Anything the machine cannot keep up with gets sold raw.
            self.cash += self.stock[a] * self.c["RESOURCE_VALUE"][a]
            self.stock[a] = 0.0

        # Greedy buyer: always take the cheapest thing that is affordable.
        while True:
            affordable = [o for o in self.options() if o[0] <= self.cash]
            if not affordable:
                break
            cost, _, apply = min(affordable, key=lambda o: o[0])
            self.cash -= cost
            apply()


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

    sim = Sim(c)
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

    if errors:
        for line in errors:
            print("economy: " + line, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
