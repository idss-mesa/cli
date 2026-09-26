#!/usr/bin/env python3
"""Build-time guard for the GPU layer's pip installs into the CPU image's conda base env.

    pip-guard.py snapshot STATE   record every installed distribution and its version
    pip-guard.py check STATE      exit 1 if a recorded distribution was removed or
                                  downgraded since the snapshot (upgrades are listed)

The GPU image must only ADD to the CPU image's Python stack. If a future CPU
base or a new wheel makes pip downgrade something (numpy, typing_extensions, ...),
the build fails here instead of silently changing the CPU environment.
"""
import json
import sys
from importlib.metadata import distributions

try:
    from packaging.version import InvalidVersion, Version
except ImportError:  # packaging is not a declared dependency of the env; pip vendors it
    from pip._vendor.packaging.version import InvalidVersion, Version


def installed():
    found = {}
    for dist in distributions():
        name = dist.metadata["Name"]
        if name:
            found[name.lower().replace("_", "-")] = dist.version
    return found


def older(new, old):
    try:
        return Version(new) < Version(old)
    except InvalidVersion:
        return new != old


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("snapshot", "check"):
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    if cmd == "snapshot":
        with open(path, "w") as f:
            json.dump(installed(), f)
        return 0
    with open(path) as f:
        before = json.load(f)
    after = installed()
    bad = [f"{n} {v} -> removed" for n, v in sorted(before.items()) if n not in after]
    bad += [f"{n} {v} -> {after[n]}" for n, v in sorted(before.items())
            if n in after and after[n] != v and older(after[n], v)]
    upgraded = [f"{n} {v} -> {after[n]}" for n, v in sorted(before.items())
                if n in after and after[n] != v and not older(after[n], v)]
    added = len(set(after) - set(before))
    print(f"pip-guard: {added} added, upgraded: {', '.join(upgraded) or 'none'}")
    if bad:
        print("pip-guard: the GPU layer must not downgrade or remove CPU-image packages:\n  "
              + "\n  ".join(bad), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
