# Stellaris Workspace Instructions

This workspace contains independent Stellaris mod repositories. Its local
Codex skill and sync scripts are tracked here; direct-child mod folders remain
separate repositories and are ignored by this parent repository.

Before creating, changing, packaging, registering, or debugging a Stellaris
mod in this workspace, read and apply:

- .codex/skills/stellaris-modding/SKILL.md

Use the project-backed sync scripts rather than copying a mod into the
Paradox user-data directory. The scripts register a local descriptor that
points to the project folder and keep the active load order in sync.
