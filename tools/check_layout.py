#!/usr/bin/env python3
"""Check the board against the round screen it has to live on.

The layout in Balance.mc is authored as bare numbers in a 416x416 design
space, which is easy to nudge and easy to break: a tree half a bezel out or a
storage hut sitting under the contextual button only shows up on a watch. This
reads the constants back out of the source and asserts the things a round
touchscreen needs to be true. All four areas share one set of sites, so one
pass covers the whole world.
"""
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BALANCE = ROOT / "source" / "Balance.mc"

DESIGN = 416
CENTRE = DESIGN / 2
# Objects are drawn a little larger than their centre point, and text sits
# under the yard and the mill, so keep everything this far inside the glass.
BEZEL_MARGIN = 34
# The contextual button, mirroring GameView.onLayout().
BUTTON_TOP = 322
BUTTON_HEIGHT = 56
# Half-height of the tallest board sprite, measured from its centre.
SPRITE_REACH = 44


def constants(text):
    """Every `const NAME = ...;` in Balance.mc, as raw source strings."""
    return dict(re.findall(r"const\s+(\w+)\s*=\s*([^;]+);", text))


def numbers(raw):
    return [int(n) for n in re.findall(r"-?\d+", raw)]


def pairs(raw):
    return [tuple(numbers(p)) for p in re.findall(r"\[\s*-?\d+\s*,\s*-?\d+\s*\]", raw)]


def main():
    text = BALANCE.read_text(encoding="utf-8")
    const = constants(text)

    sites = pairs(const["NODES"])
    storage = pairs("[" + const["STORAGE"].strip()[1:-1] + "]")[0]
    machine = pairs("[" + const["MACHINE"].strip()[1:-1] + "]")[0]
    player = pairs("[" + const["PLAYER_START"].strip()[1:-1] + "]")[0]
    tap_radius = numbers(const["TAP_RADIUS"])[0]

    # Every area reuses the same sites, so checking them once checks all four.
    objects = [("node %d" % i, p) for i, p in enumerate(sites)]
    objects += [("storage", storage), ("machine", machine), ("player start", player)]

    errors = []

    for name, (x, y) in objects:
        if math.hypot(x - CENTRE, y - CENTRE) > CENTRE - BEZEL_MARGIN:
            errors.append(
                "%s at (%d, %d) is %.0fpx from centre; the safe radius is %d"
                % (name, x, y, math.hypot(x - CENTRE, y - CENTRE), CENTRE - BEZEL_MARGIN)
            )
        if y + SPRITE_REACH > BUTTON_TOP:
            errors.append(
                "%s at (%d, %d) reaches under the contextual button at y=%d"
                % (name, x, y, BUTTON_TOP)
            )

    # Tap targets must not overlap, or a tap near two of them is a coin toss.
    for i in range(len(objects)):
        for j in range(i + 1, len(objects)):
            (a_name, a), (b_name, b) = objects[i], objects[j]
            if a_name == "player start" or b_name == "player start":
                continue  # the player is not a tap target
            gap = math.hypot(a[0] - b[0], a[1] - b[1])
            if gap < tap_radius:
                errors.append(
                    "%s and %s are %.0fpx apart, closer than the %dpx tap radius"
                    % (a_name, b_name, gap, tap_radius)
                )

    # The button itself has to fit the chord it sits on.
    half = math.sqrt(CENTRE ** 2 - max(abs(BUTTON_TOP - CENTRE),
                                       abs(BUTTON_TOP + BUTTON_HEIGHT - CENTRE)) ** 2)
    if half * 2 < 180:
        errors.append(
            "the contextual button is only %.0fpx wide at y=%d; move it up"
            % (half * 2, BUTTON_TOP)
        )

    if errors:
        for line in errors:
            print("layout: " + line, file=sys.stderr)
        return 1

    print("layout: %d board objects fit the glass, button is %.0fpx wide"
          % (len(objects), half * 2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
