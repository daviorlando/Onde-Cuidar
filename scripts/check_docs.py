#!/usr/bin/env python3
"""Check repository Markdown links, fences and basic skill metadata; no network."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]


def markdown_files():
    files = list(ROOT.glob("*.md"))
    for directory in ("app", "data", ".github"):
        files.extend((ROOT / directory).rglob("*.md"))
    return sorted(set(files))


def without_fences(content, relative, errors):
    visible = []
    marker = None
    length = 0
    for line in content.splitlines():
        fence = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line)
        if fence:
            token, suffix = fence.groups()
            if marker is None:
                marker, length = token[0], len(token)
            elif token[0] == marker and len(token) >= length and not suffix.strip():
                marker = None
            continue
        if marker is None:
            visible.append(line)
    if marker is not None:
        errors.append(f"{relative}: unclosed Markdown fence")
    return "\n".join(visible)


def check():
    root = ROOT
    errors = []
    files = markdown_files()
    links = 0
    skills = 0
    for path in files:
        relative = path.relative_to(root)
        content = path.read_text(encoding="utf-8")
        visible = without_fences(content, relative, errors)
        for match in re.finditer(r"!?\[[^\]\n]+\]\((<[^>]+>|[^\s)]+)(?:\s+\"[^\"]*\")?\)", visible):
            target = match.group(1).strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith(("#", "//")):
                continue
            local = unquote(parsed.path)
            if not local:
                continue
            links += 1
            destination = (path.parent / local).resolve()
            if not destination.is_relative_to(root):
                errors.append(f"{relative}: link leaves repository: {target}")
            elif not destination.exists():
                errors.append(f"{relative}: missing local link: {target}")
        if path.name == "SKILL.md":
            skills += 1
            front = re.match(r"\A---\n(.*?)\n---(?:\n|$)", content, re.DOTALL)
            if not front:
                errors.append(f"{relative}: missing skill frontmatter")
                continue
            name = re.search(r"^name:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*$", front[1], re.MULTILINE)
            description = re.search(r"^description:\s*(\S[^\n]*)$", front[1], re.MULTILINE)
            if not name or name[1] != path.parent.name or len(name[1]) > 64:
                errors.append(f"{relative}: invalid skill name or directory mismatch")
            if not description:
                errors.append(f"{relative}: missing skill description")
    if errors:
        print("Documentation checks failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"OK: {len(files)} Markdown files, {links} local links, {skills} skills.")
    print("External URLs, heading anchors, workflow execution and app behavior are not checked.")
    return 0


if __name__ == "__main__":
    sys.exit(check())
