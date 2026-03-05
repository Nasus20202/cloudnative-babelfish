#!/usr/bin/env python3
import re
from pathlib import Path


def derive(tag):
    m = re.match(r"BABEL_(\d+)_(\d+)_(\d+)__PG_(\d+)_(\d+)", tag)
    if not m:
        return None
    return {
        "semver": f"{m[1]}.{m[2]}.{m[3]}",
        "pg_version": f"{m[4]}.{m[5]}",
        "pg_major": m[4],
    }


def find_block_tag(block_lines):
    for line in block_lines:
        if re.match(r"\s*#", line):
            continue
        m = re.search(
            r'(?:babelfish_version|BABELFISH_VERSION|PG\d+_VERSION)\s*[=:]\s*["\']?(BABEL_\d+_\d+_\d+__PG_\d+_\d+)',
            line,
        )
        if m:
            return derive(m.group(1))
    return None


def update_block(block_lines, tag):
    result = []
    for line in block_lines:
        if re.match(r"\s*#", line):
            result.append(line)
            continue
        line = re.sub(
            r'(babelfish_semver\s*[=:]\s*["\']?)\d+\.\d+\.\d+(["\']?)',
            lambda m: f"{m.group(1)}{tag['semver']}{m.group(2)}",
            line,
        )
        line = re.sub(
            r'(pg_version\s*[=:]\s*["\']?)\d+\.\d+(["\']?)',
            lambda m: f"{m.group(1)}{tag['pg_version']}{m.group(2)}",
            line,
        )
        line = re.sub(
            r'(pg_major\s*[=:]\s*["\']?)\d+(["\']?)',
            lambda m: f"{m.group(1)}{tag['pg_major']}{m.group(2)}",
            line,
        )
        result.append(line)
    return result


def split_into_blocks(lines):
    blocks, current = [], []
    for line in lines:
        if re.match(r"\s*-\s", line) and current:
            blocks.append(current)
            current = [line]
        else:
            current.append(line)
    if current:
        blocks.append(current)
    return blocks


def process(filepath):
    print(f"Processing {filepath}...")
    lines = Path(filepath).read_text().splitlines(keepends=True)
    blocks = split_into_blocks(lines)
    result = []
    for block in blocks:
        tag = find_block_tag(block)
        if tag:
            print(f"  Found tag in block -> {tag}")
            block = update_block(block, tag)
        result.extend(block)
    Path(filepath).write_text("".join(result))


for f in [
    *Path(".github/workflows").glob("*.yml"),
    *Path(".github/workflows").glob("*.yaml"),
]:
    if f.exists():
        process(f)

print("Done.")
