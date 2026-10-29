#!/usr/bin/env python3
"""Add or remove a Swift file in PaceOff.xcodeproj without XcodeGen.

XcodeGen (`xcodegen generate`) is the normal way to update the project, but
cloud sessions have no XcodeGen or Xcode. This script makes the same edits
XcodeGen would for a single source file: a file reference in the group that
matches the file's folder, and a build file in each named target's Sources
phase. Running `xcodegen generate` later gives an equivalent project.

usage:
  python3 scripts/pbxproj.py add    <path/to/File.swift> <target> [<target> ...]
  python3 scripts/pbxproj.py remove <path/to/File.swift>

<path> is relative to the repository root and its folder must already be a
group in the project. Targets are named as in project.yml: PaceOff,
PaceOffWidget, PaceOffTests, "PaceOff Watch App". Files in PaceOffShared/
belong in every target, as project.yml compiles that folder into all four.
"""
import hashlib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(REPO, "PaceOff.xcodeproj", "project.pbxproj")


def new_id(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def objects(text: str, isa: str) -> dict[str, str]:
    """Object id → body for every object of one isa."""
    found = {}
    for m in re.finditer(r"\t\t([0-9A-F]{24})(?: /\* [^*]* \*/)? = \{\n(.*?)\n\t\t\};", text, re.S):
        if f"isa = {isa};" in m.group(2):
            found[m.group(1)] = m.group(2)
    return found


def children(body: str) -> list[str]:
    m = re.search(r"children = \((.*?)\);", body, re.S)
    return re.findall(r"([0-9A-F]{24})", m.group(1)) if m else []


def field(body: str, key: str) -> str | None:
    m = re.search(rf"\b{key} = (\"[^\"]*\"|[^;]+);", body)
    return m.group(1).strip('"') if m else None


def find_group(text: str, folder: str) -> str:
    groups = objects(text, "PBXGroup")
    main = re.search(r"mainGroup = ([0-9A-F]{24});", text).group(1)
    current = main
    for part in [p for p in folder.split("/") if p]:
        match = next(
            (c for c in children(groups[current])
             if c in groups and (field(groups[c], "path") == part or field(groups[c], "name") == part)),
            None,
        )
        if match is None:
            sys.exit(f"no group for folder '{folder}' (stopped at '{part}'); "
                     "add the folder with XcodeGen first")
        current = match
    return current


def sources_phase(text: str, target: str) -> str:
    for body in objects(text, "PBXNativeTarget").values():
        if field(body, "name") == target:
            phases = re.search(r"buildPhases = \((.*?)\);", body, re.S).group(1)
            m = re.search(r"([0-9A-F]{24}) /\* Sources \*/", phases)
            if m:
                return m.group(1)
    sys.exit(f"no target named '{target}'")


def add(path: str, targets: list[str]) -> None:
    text = open(PROJECT).read()
    folder, name = os.path.split(path)
    if not name.endswith(".swift"):
        sys.exit("only .swift files are supported")
    if not os.path.exists(os.path.join(REPO, path)):
        sys.exit(f"{path} does not exist; write the file first")
    if f"/* {name} */ = {{isa = PBXFileReference" in text:
        sys.exit(f"{name} is already in the project")
    if not targets:
        sys.exit("name at least one target")

    group = find_group(text, folder)
    ref = new_id("ref:" + path)
    text = text.replace(
        "/* End PBXFileReference section */",
        f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {name}; sourceTree = \"<group>\"; }};\n/* End PBXFileReference section */", 1)
    m = re.search(re.escape(group) + r"(?: /\* [^*]+ \*/)? = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n", text)
    text = text[:m.end()] + f"\t\t\t\t{ref} /* {name} */,\n" + text[m.end():]

    for target in targets:
        phase = sources_phase(text, target)
        build = new_id(f"build:{path}:{target}")
        text = text.replace(
            "/* End PBXBuildFile section */",
            f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n"
            "/* End PBXBuildFile section */", 1)
        m = re.search(re.escape(phase) + r" /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
                      r"\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n", text)
        text = text[:m.end()] + f"\t\t\t\t{build} /* {name} in Sources */,\n" + text[m.end():]

    open(PROJECT, "w").write(text)
    print(f"added {path} to {', '.join(targets)}")


def remove(path: str) -> None:
    text = open(PROJECT).read()
    name = os.path.basename(path)
    updated, count = re.subn(r"[^\n]*/\* " + re.escape(name) + r"( in Sources)? \*/[^\n]*\n", "", text)
    if count == 0:
        sys.exit(f"{name} is not in the project")
    open(PROJECT, "w").write(updated)
    print(f"removed {name} ({count} lines)")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "add":
        add(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 3 and sys.argv[1] == "remove":
        remove(sys.argv[2])
    else:
        sys.exit(__doc__)
