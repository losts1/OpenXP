#!/usr/bin/env python3
"""Build the OpenXP 2.0 test zip from the OpenXP/ folder (and OpenXP_Nav/).

    python3 tools/package_2.py [out.zip]

The zip holds OpenXP/ and, when it is there, OpenXP_Nav/ (the optional walking
paths SoupEngine makes, see docs/2.0/SOUPENGINE.md; SoupEngine's navexport
--openxp copies it next to OpenXP/), exactly what goes in
World of Warcraft/_forever_/Interface/AddOns: two addon folders in one download,
and players can turn OpenXP_Nav off in the AddOns list. For each folder it checks that
every file the .toc and .xml files list exists with exactly that upper and
lower case (Windows doesn't care, Mac and Linux disks do), and that no file
in the folder is left unlisted by mistake (Lua files only).
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "OpenXP")
NAV = "OpenXP_Nav"   # optional second addon folder


def exact(path, addon=ADDON):
    cur = addon
    for part in os.path.relpath(path, addon).split(os.sep):
        if part not in os.listdir(cur):
            return False
        cur = os.path.join(cur, part)
    return True


def listed(addon=ADDON):
    """Every file the .toc loads, following .xml includes."""
    out, missing = [], []
    name = os.path.basename(addon)

    def visit(path):
        if not os.path.exists(path) or not exact(path, addon):
            missing.append(os.path.join(name, os.path.relpath(path, addon)))
            return
        out.append(path)
        if path.lower().endswith(".xml"):
            text = open(path, encoding="utf-8").read()
            for f in re.findall(r'<(?:Script|Include)\s+file="([^"]+)"', text):
                visit(os.path.join(os.path.dirname(path), *f.split("\\")))

    toc = os.path.join(addon, name + ".toc")
    out.append(toc)
    for line in open(toc, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            visit(os.path.join(addon, *line.split("\\")))
    return out, missing


def check(addon):
    """Files to zip for one addon folder, or None after printing what's wrong."""
    files, missing = listed(addon)
    if missing:
        print("missing (or wrong case): " + ", ".join(missing))
        return None
    loaded = {os.path.normcase(f) for f in files}
    stray = []
    for base, _, names in os.walk(addon):
        for n in names:
            p = os.path.join(base, n)
            if n.endswith(".lua") and os.path.normcase(p) not in loaded:
                stray.append(os.path.join(os.path.basename(addon), os.path.relpath(p, addon)))
    if stray:
        print("Lua files the .toc never loads: " + ", ".join(stray))
        return None
    return [os.path.join(base, n) for base, _, names in os.walk(addon) for n in sorted(names)
            if not (addon.endswith(NAV) and n.endswith(".json"))]   # OpenXP_Nav's Graphs-<Faction>.json: build notes


def main(argv):
    toc = open(os.path.join(ADDON, "OpenXP.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    out = argv[0] if argv else os.path.join(ROOT, "dist", "OpenXP-%s.zip" % version)
    addons = [ADDON] + ([os.path.join(ROOT, NAV)] if os.path.isdir(os.path.join(ROOT, NAV)) else [])
    if len(addons) == 1:
        print("note: no %s/ next to OpenXP/, so the zip has no walking paths (see docs/2.0/SOUPENGINE.md)" % NAV)
    todo = []
    for addon in addons:
        files = check(addon)
        if files is None:
            return 1
        todo += [(f, os.path.relpath(f, ROOT)) for f in files]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p, arc in todo:
            z.write(p, arc)
            n += 1
    print("%s: %d files, version %s" % (os.path.relpath(out, ROOT), n, version))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
