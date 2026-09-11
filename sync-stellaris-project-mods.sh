#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-$SCRIPT_DIR}"
STATE_ROOT="${STATE_ROOT:-/home/cjstorrs/.local/share/Paradox Interactive/Stellaris}"
DEST_ROOT="${DEST_ROOT:-$STATE_ROOT/mod}"
DRY_RUN="${DRY_RUN:-0}"
MOD_NAME="${MOD_NAME:-${1:-}}"

usage() {
  cat <<'EOF'
Usage: sync-stellaris-project-mods.sh [modFolder]

Registers project-backed Stellaris mods through local .mod descriptors.
Each descriptor points to its source folder, is enabled in dlc_load.json, and
is registered in the active Paradox Launcher playset.

With a mod folder argument, synchronizes that one direct-child project mod.
Without an argument, reconciles only project mods already registered through
descriptors that point into SOURCE_ROOT.

Overrides:
  MOD_NAME=ExampleMod ./sync-stellaris-project-mods.sh
  DRY_RUN=1 ./sync-stellaris-project-mods.sh ExampleMod
  SOURCE_ROOT=/path/to/projects DEST_ROOT=/path/to/Stellaris/mod ./sync-stellaris-project-mods.sh
EOF
}

if [[ "${MOD_NAME}" == "-h" || "${MOD_NAME}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  echo "error: expected at most one mod folder argument" >&2
  exit 1
fi

case "$DRY_RUN" in
  ""|0|false|False|FALSE|no|No|NO)
    DRY_RUN=0
    ;;
  1|true|True|TRUE|yes|Yes|YES)
    DRY_RUN=1
    ;;
  *)
    echo "error: DRY_RUN must be 0 or 1" >&2
    exit 1
    ;;
esac

if pgrep -x stellaris >/dev/null; then
  echo "error: close Stellaris before synchronizing its active mod state" >&2
  exit 1
fi

python3 - "$SOURCE_ROOT" "$DEST_ROOT" "$STATE_ROOT" "$MOD_NAME" "$DRY_RUN" <<'PY'
import json
import re
import sqlite3
import sys
import time
import uuid
from pathlib import Path

source_root = Path(sys.argv[1]).expanduser().resolve()
dest_root = Path(sys.argv[2]).expanduser().resolve()
state_root = Path(sys.argv[3]).expanduser().resolve()
mod_name = sys.argv[4]
dry_run = sys.argv[5] == "1"

name_pattern = re.compile(r'^\s*name\s*=\s*"([^"]+)"\s*$')
path_pattern = re.compile(r'^\s*path\s*=\s*"([^"]+)"\s*$')
version_pattern = re.compile(r'^\s*version\s*=\s*"([^"]+)"\s*$')
required_version_pattern = re.compile(
    r'^\s*supported_version\s*=\s*"([^"]+)"\s*$'
)
dependencies_pattern = re.compile(r'dependencies\s*=\s*\{(.*?)\}', re.DOTALL)
quoted_pattern = re.compile(r'"([^"]+)"')


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_descriptor(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read descriptor {path}: {exc}")

    metadata = {
        "text": text,
        "name": None,
        "path": None,
        "version": "1.0.0",
        "required_version": "v4.*",
        "dependencies": [],
    }
    for line in text.splitlines():
        match = name_pattern.match(line)
        if match:
            metadata["name"] = match.group(1)
            continue
        match = path_pattern.match(line)
        if match:
            metadata["path"] = match.group(1)
            continue
        match = version_pattern.match(line)
        if match:
            metadata["version"] = match.group(1)
            continue
        match = required_version_pattern.match(line)
        if match:
            metadata["required_version"] = match.group(1)

    dependencies_match = dependencies_pattern.search(text)
    if dependencies_match:
        metadata["dependencies"] = quoted_pattern.findall(
            dependencies_match.group(1)
        )
    if not metadata["name"]:
        fail(f"descriptor has no name= entry: {path}")
    return metadata


def is_project_mod(path):
    return (
        path.is_dir()
        and not path.is_symlink()
        and not path.name.startswith(".")
        and (path / "descriptor.mod").is_file()
    )


if not source_root.is_dir():
    fail(f"source directory does not exist: {source_root}")
if source_root in {Path("/"), Path.home().resolve()}:
    fail(f"refusing unsafe source root: {source_root}")
if mod_name and ("/" in mod_name or mod_name in {".", ".."}):
    fail("mod folder must be a single top-level directory name")

if mod_name:
    project_path = source_root / mod_name
    if not is_project_mod(project_path):
        fail(f"requested project folder is not a Stellaris mod: {project_path}")
    selected = [project_path]
else:
    selected = []
    if dest_root.is_dir():
        for local_descriptor in sorted(dest_root.glob("*.mod")):
            try:
                metadata = read_descriptor(local_descriptor)
            except SystemExit:
                continue
            registered_path = metadata["path"]
            if not registered_path:
                continue
            try:
                project_path = Path(registered_path).expanduser().resolve()
                project_path.relative_to(source_root)
            except (OSError, ValueError):
                continue
            if project_path.parent == source_root and is_project_mod(project_path):
                selected.append(project_path)

if not selected:
    print("done: no project-backed Stellaris mods selected")
    raise SystemExit(0)


def local_descriptor_map():
    by_name = {}
    if not dest_root.is_dir():
        return by_name
    for descriptor in sorted(dest_root.glob("*.mod")):
        try:
            metadata = read_descriptor(descriptor)
        except SystemExit:
            continue
        by_name.setdefault(metadata["name"], f"mod/{descriptor.name}")
    return by_name


def render_local_descriptor(source_text, project_path):
    lines = [
        line for line in source_text.splitlines() if not path_pattern.match(line)
    ]
    lines.append(f'path="{project_path}"')
    return "\n".join(lines) + "\n"


entries = []
for project_path in selected:
    source_descriptor = project_path / "descriptor.mod"
    metadata = read_descriptor(source_descriptor)
    destination_descriptor = dest_root / f"{project_path.name}.mod"

    if destination_descriptor.exists():
        existing = read_descriptor(destination_descriptor)
        existing_path = existing["path"]
        if not existing_path:
            fail(f"existing local descriptor has no path=: {destination_descriptor}")
        try:
            resolved_existing = Path(existing_path).expanduser().resolve()
        except OSError as exc:
            fail(f"cannot resolve existing descriptor path {existing_path}: {exc}")
        if resolved_existing != project_path:
            fail(
                "refusing to overwrite descriptor for another project: "
                f"{destination_descriptor} -> {resolved_existing}"
            )

    entries.append(
        {
            "project_path": project_path,
            "metadata": metadata,
            "destination_descriptor": destination_descriptor,
            "descriptor_entry": f"mod/{project_path.name}.mod",
            "content": render_local_descriptor(metadata["text"], project_path),
        }
    )

if dry_run:
    for entry in entries:
        print(
            "would register "
            f"{entry['project_path'].name} -> {entry['destination_descriptor']}"
        )
else:
    dest_root.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        entry["destination_descriptor"].write_text(
            entry["content"], encoding="utf-8"
        )
        print(
            "registered "
            f"{entry['project_path'].name} -> {entry['destination_descriptor']}"
        )

descriptor_by_name = local_descriptor_map()
for entry in entries:
    descriptor_by_name[entry["metadata"]["name"]] = entry["descriptor_entry"]

load_path = state_root / "dlc_load.json"
if load_path.exists():
    try:
        load_state = json.loads(load_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read valid JSON from {load_path}: {exc}")
else:
    load_state = {"enabled_mods": [], "disabled_dlcs": []}

enabled_mods = list(load_state.get("enabled_mods", []))
for entry in entries:
    descriptor_entry = entry["descriptor_entry"]
    enabled_mods = [item for item in enabled_mods if item != descriptor_entry]
    dependencies = entry["metadata"]["dependencies"]
    missing_dependencies = [
        dependency
        for dependency in dependencies
        if dependency not in descriptor_by_name
    ]
    if missing_dependencies:
        fail(
            f"{entry['project_path'].name} has no local descriptor for: "
            + ", ".join(missing_dependencies)
        )
    dependency_entries = [descriptor_by_name[name] for name in dependencies]
    inactive_dependencies = [
        dependency
        for dependency in dependency_entries
        if dependency not in enabled_mods
    ]
    if inactive_dependencies:
        fail(
            f"{entry['project_path'].name} depends on inactive descriptor(s): "
            + ", ".join(inactive_dependencies)
        )
    insert_at = (
        max(enabled_mods.index(dependency) for dependency in dependency_entries)
        + 1
        if dependency_entries
        else len(enabled_mods)
    )
    enabled_mods.insert(insert_at, descriptor_entry)

load_state["enabled_mods"] = enabled_mods
load_state.setdefault("disabled_dlcs", [])
if dry_run:
    print(f"would update active mod list: {load_path}")
else:
    load_path.write_text(
        json.dumps(load_state, indent=2) + "\n", encoding="utf-8"
    )
    print(f"updated active mod list: {load_path}")

database_path = state_root / "launcher-v2.sqlite"
if not database_path.is_file():
    print(f"skipped launcher database registration; not found: {database_path}")
    raise SystemExit(0)
if dry_run:
    print(f"would register selected mods in the active playset: {database_path}")
    raise SystemExit(0)

db = sqlite3.connect(database_path)
try:
    cur = db.cursor()
    cur.execute("PRAGMA foreign_keys = ON")
    active_playset = cur.execute(
        "SELECT id FROM playsets WHERE isActive = 1"
    ).fetchone()
    if active_playset is None:
        fail("Paradox Launcher has no active playset")
    playset_id = active_playset[0]

    for entry in entries:
        project_path = str(entry["project_path"])
        metadata = entry["metadata"]
        existing = cur.execute(
            "SELECT id FROM mods WHERE dirPath = ?", (project_path,)
        ).fetchone()
        if existing is None:
            mod_id = str(uuid.uuid4())
            cur.execute(
                "INSERT INTO mods (id, displayName, version, tags, requiredVersion, dirPath, status, source, timeUpdated, isNew, metadataStatus, isMetadataApplied, keepLatest) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    mod_id,
                    metadata["name"],
                    metadata["version"],
                    json.dumps(["Balance"]),
                    metadata["required_version"],
                    project_path,
                    "ready_to_play",
                    "local",
                    int(time.time()),
                    0,
                    "not_applied",
                    0,
                    1,
                ),
            )
        else:
            mod_id = existing[0]
            cur.execute(
                "UPDATE mods SET displayName = ?, version = ?, requiredVersion = ?, status = ?, source = ?, timeUpdated = ? WHERE id = ?",
                (
                    metadata["name"],
                    metadata["version"],
                    metadata["required_version"],
                    "ready_to_play",
                    "local",
                    int(time.time()),
                    mod_id,
                ),
            )

        dependency_ids = []
        for dependency in metadata["dependencies"]:
            row = cur.execute(
                "SELECT pm.modId FROM playsets_mods pm JOIN mods m ON m.id = pm.modId WHERE pm.playsetId = ? AND pm.enabled = 1 AND m.displayName = ? ORDER BY pm.position DESC LIMIT 1",
                (playset_id, dependency),
            ).fetchone()
            if row is None:
                fail(
                    f"{entry['project_path'].name} cannot follow inactive dependency: {dependency}"
                )
            dependency_ids.append(row[0])

        ordered_ids = [
            row[0]
            for row in cur.execute(
                "SELECT modId FROM playsets_mods WHERE playsetId = ? ORDER BY position, rowid",
                (playset_id,),
            )
        ]
        if mod_id in ordered_ids:
            ordered_ids.remove(mod_id)

        target_position = (
            max(ordered_ids.index(dependency_id) for dependency_id in dependency_ids)
            + 1
            if dependency_ids
            else len(ordered_ids)
        )
        ordered_ids.insert(target_position, mod_id)

        relation = cur.execute(
            "SELECT rowid FROM playsets_mods WHERE playsetId = ? AND modId = ?",
            (playset_id, mod_id),
        ).fetchone()
        if relation is None:
            cur.execute(
                "INSERT INTO playsets_mods (playsetId, modId, enabled, position) VALUES (?, ?, 1, ?)",
                (playset_id, mod_id, target_position),
            )
        for position, ordered_mod_id in enumerate(ordered_ids):
            cur.execute(
                "UPDATE playsets_mods SET position = ? WHERE playsetId = ? AND modId = ?",
                (position, playset_id, ordered_mod_id),
            )
        cur.execute(
            "UPDATE playsets_mods SET enabled = 1 WHERE playsetId = ? AND modId = ?",
            (playset_id, mod_id),
        )

    cur.execute(
        "UPDATE playsets SET updatedOn = ? WHERE id = ?",
        (int(time.time() * 1000), playset_id),
    )
    db.commit()
finally:
    db.close()

print(f"registered {len(entries)} mod(s) in the active launcher playset")
PY
