#!/usr/bin/env python3
"""Merge and path-map compile_commands.json fragments for Mono OpenWrt work.

The OpenWrt build creates useful compiler databases in build_dir, but ASK
packages are edited in sibling source repositories. This helper combines the
captured databases and rewrites package source paths back to those repositories
without changing any actual build inputs.
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any


CLANGD_UNSUPPORTED_EXACT = {
    "-fhonour-copts",
    "-fno-allow-store-data-races",
    "-fconserve-stack",
    "-femit-struct-debug-baseonly",
    "-Werror",
}

CLANGD_UNSUPPORTED_PREFIXES = (
    "-fmin-function-alignment=",
    "-mabi=",
    "-Werror=",
)


def single_dir(root: Path, pattern: str) -> Path:
    matches = sorted(p for p in root.glob(pattern) if p.is_dir())
    if len(matches) != 1:
        raise SystemExit(f"expected one {pattern!r} directory under {root}, found {len(matches)}")
    return matches[0]


def default_fragments(openwrt_root: Path) -> list[Path]:
    return [
        openwrt_root / "compile_commands.kernel.json",
        openwrt_root / "compile_commands.ask-cdx.json",
        openwrt_root / "compile_commands.ask-cmm.json",
        openwrt_root / "compile_commands.fci.json",
    ]


def build_rewrites(openwrt_root: Path, project_root: Path) -> list[tuple[re.Pattern[str], str]]:
    target_build = re.escape(str(openwrt_root / "build_dir" / "target-aarch64_generic_musl"))
    layerscape_build = target_build + r"/linux-layerscape_armv8_64b"

    ask_cdx_src = single_dir(project_root / "ask-cdx", "cdx-*")
    fci_src = single_dir(project_root / "fci", "fci-*")

    return [
        (
            re.compile(layerscape_build + r"/ask-cdx-[^/=]+/cdx-[^/=]+"),
            str(ask_cdx_src),
        ),
        (
            re.compile(target_build + r"/ask-cmm-[^/=]+"),
            str(project_root / "ask-cmm"),
        ),
        (
            re.compile(layerscape_build + r"/fci-source-[^/=]+/fci-[^/=]+"),
            str(fci_src),
        ),
        (
            re.compile(target_build + r"/fci-source-[^/=]+/fci-[^/=]+"),
            str(fci_src),
        ),
    ]


def rewrite_string(value: str, rewrites: list[tuple[re.Pattern[str], str]]) -> tuple[str, bool]:
    changed = False
    for pattern, replacement in rewrites:
        value, count = pattern.subn(replacement, value)
        changed = changed or count > 0
    return value, changed


def rewrite_entry(entry: dict[str, Any], rewrites: list[tuple[re.Pattern[str], str]]) -> bool:
    changed = False

    for key in ("file", "directory", "output", "command"):
        value = entry.get(key)
        if isinstance(value, str):
            entry[key], key_changed = rewrite_string(value, rewrites)
            changed = changed or key_changed

    arguments = entry.get("arguments")
    if isinstance(arguments, list):
        rewritten_arguments = []
        for argument in arguments:
            if isinstance(argument, str):
                argument, argument_changed = rewrite_string(argument, rewrites)
                changed = changed or argument_changed
            rewritten_arguments.append(argument)
        entry["arguments"] = rewritten_arguments

    return changed


def keep_for_clangd(argument: str) -> bool:
    if argument in CLANGD_UNSUPPORTED_EXACT:
        return False
    return not argument.startswith(CLANGD_UNSUPPORTED_PREFIXES)


def sanitize_entry_for_clangd(entry: dict[str, Any]) -> bool:
    changed = False

    arguments = entry.get("arguments")
    if isinstance(arguments, list):
        kept = [argument for argument in arguments if not isinstance(argument, str) or keep_for_clangd(argument)]
        if len(kept) != len(arguments):
            entry["arguments"] = kept
            changed = True

    command = entry.get("command")
    if isinstance(command, str):
        try:
            parts = shlex.split(command)
        except ValueError:
            return changed

        kept_parts = [part for part in parts if keep_for_clangd(part)]
        if len(kept_parts) != len(parts):
            entry["command"] = shlex.join(kept_parts)
            changed = True

    return changed


def load_fragment(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"missing {path}; generate the fragment before merging") from None

    if not isinstance(data, list):
        raise SystemExit(f"{path} is not a compile command list")

    entries: list[dict[str, Any]] = []
    for index, entry in enumerate(data):
        if not isinstance(entry, dict):
            raise SystemExit(f"{path}:{index} is not a compile command object")
        entries.append(entry)
    return entries


def parse_args() -> argparse.Namespace:
    openwrt_root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(
        description="merge Mono OpenWrt compile command fragments and rewrite ASK package paths"
    )
    parser.add_argument(
        "--openwrt-root",
        type=Path,
        default=openwrt_root,
        help="OpenWrt checkout root, defaults to this script's parent repository",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=openwrt_root.parent,
        help="Mono project root containing ask-cdx, ask-cmm, and fci",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=openwrt_root / "compile_commands.json",
        help="merged compile command output path",
    )
    parser.add_argument(
        "fragments",
        type=Path,
        nargs="*",
        help="compile command fragments to merge; defaults to known Mono fragments",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    openwrt_root = args.openwrt_root.resolve()
    project_root = args.project_root.resolve()
    output = args.output.resolve()
    fragments = args.fragments or default_fragments(openwrt_root)
    rewrites = build_rewrites(openwrt_root, project_root)

    merged: list[dict[str, Any]] = []
    rewritten_entries = 0
    sanitized_entries = 0

    for fragment in fragments:
        for entry in load_fragment(fragment):
            if rewrite_entry(entry, rewrites):
                rewritten_entries += 1
            if sanitize_entry_for_clangd(entry):
                sanitized_entries += 1
            merged.append(entry)

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        json.dump(merged, handle, indent=2)
        handle.write("\n")

    print(f"wrote {output}")
    print(f"entries: {len(merged)}")
    print(f"path-rewritten entries: {rewritten_entries}")
    print(f"clangd-sanitized entries: {sanitized_entries}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
