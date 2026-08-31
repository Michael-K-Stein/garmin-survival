#!/usr/bin/env python3
"""Guard against the onSelect/onTap hardware trap.

On real Venu 2 hardware a screen tap arrives as *two* separate events: onTap,
with real coordinates, and the physical select behaviour, onSelect, with
none. A WatchUi.BehaviorDelegate that overrides onSelect to do anything
target-dependent will therefore run that logic a second time, unconditionally,
right after every real tap - which is how a tap on the crew screen turned into
"buy the most expensive tier" (CrewDelegate, fixed in bde4e9f) and a tap
anywhere on the mine screen turned into a center-of-screen swing
(MineDelegate/DigDelegate, and GameDelegate in the sibling Foundry and
Timberline projects).

The fix, applied everywhere this has come up, is the same: hang the
physical-button-only action off onKey(WatchUi.KEY_ENTER) instead, which only
the physical START/select button actually produces, and drop onSelect
entirely. This script enforces that a WatchUi.BehaviorDelegate subclass never
defines onSelect() again - onSelect belongs to Menu2InputDelegate and
ConfirmationDelegate, which react to a chosen item rather than a raw screen
event, and are unaffected.

    python3 tools/check_input.py
"""
import glob
import re
import sys

CLASS_RE = re.compile(
    r'class\s+(\w+)\s+extends\s+([\w.]+)\s*\{')
ONSELECT_RE = re.compile(r'\bfunction\s+onSelect\s*\(')


def find_class_bodies(text):
    """Yield (name, base, body) for every top-level `class X extends Y { ... }`."""
    for m in CLASS_RE.finditer(text):
        name, base = m.group(1), m.group(2)
        start = m.end()
        depth = 1
        i = start
        while i < len(text) and depth > 0:
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        yield name, base, text[start:i]


def check_file(path, problems):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    for name, base, body in find_class_bodies(text):
        if base != "WatchUi.BehaviorDelegate":
            continue
        if ONSELECT_RE.search(body):
            problems.append(
                "%s: %s extends WatchUi.BehaviorDelegate and defines onSelect() - "
                "a real screen tap also fires onSelect with no coordinates, so this "
                "will re-run after every onTap. Move the physical-button action to "
                "onKey(WatchUi.KEY_ENTER) instead." % (path, name))


def main():
    problems = []
    for path in sorted(glob.glob("source/**/*.mc", recursive=True)):
        check_file(path, problems)

    if problems:
        for problem in problems:
            print("FAIL %s" % problem)
        return 1
    print("OK   no BehaviorDelegate defines onSelect()")
    return 0


if __name__ == "__main__":
    sys.exit(main())
