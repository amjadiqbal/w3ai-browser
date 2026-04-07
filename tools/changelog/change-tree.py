#!/usr/bin/env python3
"""
W3Ai Change Tree Generator

Reads git history and renders a graphical, tree-based view of every file
changed across all commits.  Output is printed to stdout and written to
tools/changelog/CHANGE_TREE.md so you always have a persistent visual log.

Usage:
  python3 tools/changelog/change-tree.py            # full history
  python3 tools/changelog/change-tree.py --recent   # last 10 commits
  python3 tools/changelog/change-tree.py --limit 20
  python3 tools/changelog/change-tree.py --since "2 weeks ago"
  python3 tools/changelog/change-tree.py --branch w3ai/develop
  python3 tools/changelog/change-tree.py --no-file  # stdout only
"""

import subprocess
import sys
import argparse
from pathlib import Path
from datetime import datetime

REPO_ROOT   = Path(__file__).resolve().parent.parent.parent
OUTPUT_FILE = Path(__file__).resolve().parent / "CHANGE_TREE.md"

# Box-drawing
BRANCH_CON = "├── "
LAST_CON   = "└── "
PIPE_CON   = "│   "
SPACE_CON  = "    "

STATUS_LABEL = {
    "M": "M",   # modified
    "A": "A",   # added
    "D": "D",   # deleted
    "R": "R",   # renamed
    "C": "C",   # copied
    "T": "T",   # type-changed
}


def _git(*args):
    result = subprocess.run(
        ["git"] + list(args),
        capture_output=True, text=True, cwd=REPO_ROOT,
    )
    return result.stdout


def current_branch():
    return _git("rev-parse", "--abbrev-ref", "HEAD").strip()


def get_commits_and_files(limit=None, since=None, branch=None):
    """
    Two git-log passes (name-status + numstat) merged by commit hash.
    Returns a list of commit dicts ordered newest-first.
    """
    extra = []
    if limit:
        extra += [f"-{limit}"]
    if since:
        extra += [f"--since={since}"]
    if branch:
        extra += [branch]

    # Pass 1 — file status (M / A / D …)
    ns_raw = _git(
        "log",
        "--format=COMMIT %H|%ad|%s|%an",
        "--date=short",
        "--name-status",
        *extra,
    )

    # Pass 2 — line counts (+N / -N)
    num_raw = _git(
        "log",
        "--format=COMMIT %H",
        "--numstat",
        *extra,
    )

    # --- Parse pass 1 ---
    commits = []
    commit_map = {}
    current = None
    for line in ns_raw.splitlines():
        if line.startswith("COMMIT "):
            rest = line[7:]
            parts = rest.split("|", 3)
            if len(parts) < 4:
                continue
            h = parts[0].strip()
            current = {
                "hash":       h,
                "short_hash": h[:8],
                "date":       parts[1].strip(),
                "subject":    parts[2].strip(),
                "author":     parts[3].strip(),
                "files":      {},
            }
            commits.append(current)
            commit_map[h] = current
        elif current and "\t" in line:
            parts = line.split("\t")
            status = parts[0].strip()[0].upper() if parts[0].strip() else "?"
            path   = parts[-1].strip()
            if path:
                current["files"][path] = {"status": status, "added": 0, "removed": 0}

    # --- Parse pass 2 ---
    cur_hash = None
    for line in num_raw.splitlines():
        if line.startswith("COMMIT "):
            cur_hash = line[7:].strip()
        elif cur_hash and "\t" in line:
            parts = line.split("\t", 2)
            if len(parts) == 3 and cur_hash in commit_map:
                path   = parts[2].strip()
                commit = commit_map[cur_hash]
                if path in commit["files"]:
                    try:
                        commit["files"][path]["added"]   = int(parts[0])
                    except ValueError:
                        pass
                    try:
                        commit["files"][path]["removed"] = int(parts[1])
                    except ValueError:
                        pass

    return commits


# ───────────────────────────── tree rendering ─────────────────────────────

def _build_tree(files_dict):
    """
    Build a nested dict from {path: info}.
    Leaf entries go into '__files__' lists at their parent node.
    """
    tree = {}
    for path, info in files_dict.items():
        parts = path.replace("\\", "/").split("/")
        node  = tree
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node.setdefault("__files__", []).append({
            "name":      parts[-1],
            "full_path": path,
            **info,
        })
    return tree


def _render_tree(node, prefix=""):
    lines   = []
    subdirs = sorted((k, v) for k, v in node.items() if k != "__files__")
    files   = sorted(node.get("__files__", []), key=lambda f: f["name"])

    entries = [("dir", k, v) for k, v in subdirs] + [("file", f) for f in files]

    for idx, entry in enumerate(entries):
        is_last      = idx == len(entries) - 1
        connector    = LAST_CON   if is_last else BRANCH_CON
        child_prefix = prefix + (SPACE_CON if is_last else PIPE_CON)

        if entry[0] == "dir":
            _, name, subtree = entry
            lines.append(f"{prefix}{connector}{name}/")
            lines.extend(_render_tree(subtree, child_prefix))
        else:
            _, f = entry
            stat   = STATUS_LABEL.get(f["status"], f["status"])
            added  = f["added"]
            removed = f["removed"]
            if added and removed:
                counts = f"   +{added} −{removed}"
            elif added:
                counts = f"   +{added}"
            elif removed:
                counts = f"   −{removed}"
            else:
                counts = ""
            lines.append(f"{prefix}{connector}[{stat}]  {f['name']}{counts}")

    return lines


def _format_commit(commit):
    n_files   = len(commit["files"])
    total_add = sum(v["added"]   for v in commit["files"].values())
    total_rem = sum(v["removed"] for v in commit["files"].values())

    subj = commit["subject"]
    if len(subj) > 78:
        subj = subj[:75] + "…"

    header = f"◉  {commit['date']}  [{commit['short_hash']}]  {subj}"

    parts = [f"{n_files} file{'s' if n_files != 1 else ''} changed"]
    if total_add:
        parts.append(f"+{total_add}")
    if total_rem:
        parts.append(f"−{total_rem}")
    summary = "  ".join(parts)

    lines = [header, f"   {summary}"]

    if commit["files"]:
        tree = _build_tree(commit["files"])
        lines.append("   │")
        tree_lines = _render_tree(tree, prefix="   ")
        lines.extend(tree_lines)

    return "\n".join(lines)


# ───────────────────────────── main generation ────────────────────────────

def generate(limit=None, since=None, branch=None):
    br      = branch or current_branch()
    commits = get_commits_and_files(limit=limit, since=since, branch=branch)

    SEP  = "━" * 72
    SEP2 = "─" * 42
    now  = datetime.now().strftime("%Y-%m-%d  %H:%M")

    header = "\n".join([
        SEP,
        f"  W3Ai Change Tree  ·  {now}  ·  branch: {br}",
        SEP,
    ])

    if not commits:
        return header + "\n\n  (no commits found)\n"

    blocks = [_format_commit(c) for c in commits]
    body   = f"\n\n{SEP2}\n\n".join(blocks)

    return header + "\n\n" + body + "\n"


def main():
    p = argparse.ArgumentParser(
        description="Render a graphical W3Ai change tree from git history."
    )
    p.add_argument(
        "--limit", type=int, default=None, metavar="N",
        help="Show only the N most recent commits (default: all)",
    )
    p.add_argument(
        "--since", type=str, default=None, metavar="DATE",
        help='Show commits since DATE, e.g. "2 weeks ago" or "2026-01-01"',
    )
    p.add_argument(
        "--branch", type=str, default=None, metavar="BRANCH",
        help="Branch to inspect (default: current branch)",
    )
    p.add_argument(
        "--no-file", dest="no_file", action="store_true",
        help="Print to stdout only; do not write CHANGE_TREE.md",
    )
    p.add_argument(
        "--recent", action="store_true",
        help="Shorthand for --limit 10 — handy after each commit",
    )
    args = p.parse_args()

    if args.recent and args.limit is None:
        args.limit = 10

    output = generate(limit=args.limit, since=args.since, branch=args.branch)
    print(output)

    if not args.no_file:
        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_FILE.write_text(output, encoding="utf-8")
        try:
            rel = OUTPUT_FILE.relative_to(REPO_ROOT)
        except ValueError:
            rel = OUTPUT_FILE
        print(f"\n[change-tree] Saved → {rel}", file=sys.stderr)


if __name__ == "__main__":
    main()
