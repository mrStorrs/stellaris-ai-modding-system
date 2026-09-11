---
name: stellaris-modding
description: Create, maintain, register, or troubleshoot project-backed Stellaris mods in CJ's local workspace. Use for new mods, CJS tweaks of Workshop mods, local descriptors, active playsets, and mod repositories; do not use for unrelated game support.
---

# Stellaris Modding

Use this skill for Stellaris mod work in /home/cjstorrs/projects/games/stellaris. Read
the workspace AGENTS.md before changing a mod, descriptor, launcher state, or
sync script.

## Workspace And Live Paths

- Project workspace: /home/cjstorrs/projects/games/stellaris
- Local descriptor directory: /home/cjstorrs/.local/share/Paradox Interactive/Stellaris/mod
- Active mod list: /home/cjstorrs/.local/share/Paradox Interactive/Stellaris/dlc_load.json
- Launcher state: /home/cjstorrs/.local/share/Paradox Interactive/Stellaris/launcher-v2.sqlite
- Steam Workshop source: /home/cjstorrs/.steam/steam/steamapps/workshop/content/281990
- Game installation: /home/cjstorrs/.steam/steam/steamapps/common/Stellaris

Direct-child mod folders are individual Git repositories. The workspace
repository tracks only its instructions and sync scripts, so do not add mod
folders to it.

Before editing, inspect the project descriptor, the target Workshop descriptor
when applicable, the current local descriptor, and whether Stellaris is
running. Do not edit a Workshop copy in place.
Close both Stellaris and the Paradox Launcher before synchronizing state;
ask the user to close an open launcher rather than terminating their session.

## New Mods And CJS Tweak Mods

Use a standalone CJS mod name only for a new, independent feature:

- Project folder and internal identifier: lower camel case, such as
  cjsQuickSurvey.
- Display name: CJS Quick Survey.
- GitHub repository: stellaris-cjs-quick-survey.

For a narrow local change to an existing Workshop or third-party mod, create a
separate CJS tweak:

- Derive the target name from its display name, folder, or stable identifier:
  lowercase, split words and camel case, remove punctuation, convert ampersand
  to and and plus to plus, then use kebab case for the repository.
- Project folder and internal identifier: the same target words in lower camel
  case plus CjsTweaks, such as reworkedAdvancedAscensionCjsTweaks.
- Display name: CJS Reworked Advanced Ascension Tweaks.
- GitHub repository: stellaris-reworked-advanced-ascension-cjs-tweaks.
- Include the exact target display name in dependencies and load the tweak
  immediately after its target.
- Keep the patch narrow. Copy only a definition that must be overridden and
  preserve all unrelated target behavior.

Do not call an independent mod a tweak, and do not use a standalone CJS name
for a patch that requires another mod.

## Repository Discipline

Each mod owns its Git repository. Initialize it with git init -b main. For an
imported or already-created local mod, make a baseline commit before changing
mod metadata or gameplay files. Create its GitHub repository under mrStorrs,
set origin to git@github.com:mrStorrs/<repository>.git, and push main.

Use private repositories for tweaks, forks, imported payloads, and
third-party-derived work. A clearly CJ-authored, independent new mod may be
public. After every commit, push the committed branch. Do not force-push.

## Project-Backed Registration

Keep mod content in its project folder. A local descriptor in the Paradox mod
directory points to that folder through path=; it is the Stellaris equivalent
of a project-backed live link.

After a change, run:

    DRY_RUN=1 ./sync-stellaris-project-mod.sh <modFolder>
    ./sync-stellaris-project-mod.sh <modFolder>

The sync process creates or updates the local descriptor, enables the mod in
dlc_load.json, and registers it in the active launcher playset. It places a
tweak immediately after its declared dependency. Do not hand-edit all three
state locations when the sync script can do so consistently.

Launcher records must include gameRegistryId matching the relative descriptor
entry, such as mod/reworkedAdvancedAscensionCjsTweaks.mod. A dirPath alone is
insufficient: the launcher can discover a second record and omit the original
from its generated active mod list. Reuse the launcher-discovered record and
transfer legacy playset memberships when repairing an unregistered duplicate.

Use the no-argument form of sync-stellaris-project-mods.sh only to reconcile
already project-backed local descriptors; it does not register every project
folder automatically.

## Stellaris Overrides

For a targeted definition override, put a file with the same top-level key in
the appropriate common directory and ensure the tweak loads after its target.
Retain the complete source definition when replacement semantics require it,
then make only the requested changes. Avoid replace_path for a one-definition
tweak because it can hide unrelated definitions.

Source descriptor.mod files describe the project payload. The sync script adds
the path= field only to the local descriptor in the Paradox user-data
directory.

Stellaris localisation files require UTF-8 with BOM and a correct language
header. Preserve this when adding or overriding localisation.

## Validation And Closeout

Before finishing:

- Check descriptor names, dependency names, source paths, and active load
  order.
- Validate structured files changed by the task, including balanced
  Clausewitz braces and valid JSON for dlc_load.json.
- Verify a local descriptor points to the project folder and the active
  launcher playset enables the same mod in the same relative order.
- Check that the launcher record's gameRegistryId matches the descriptor entry
  and that no unregistered duplicate remains for the same project path.
- After running the targeted sync script, repeat the registration checks
  against the written state. Require exactly one local record for the project
  with the expected gameRegistryId, and ensure the enabled descriptor entries
  in dlc_load.json match the active playset's enabled records in load order.
  A tweak must immediately follow its dependency in both places.
- When changing registration or repairing launcher visibility, verify after
  reopening the launcher that the mod appears in the intended playset and
  retains its enabled state and load position. Respect desktop permissions;
  if reopening or visual inspection is unavailable, report this check as
  pending rather than claiming database checks prove launcher visibility.
- For sync-script changes, test fresh registration, repair of legacy records
  without gameRegistryId, and repair when the launcher has already created a
  duplicate. Use temporary state copies; verify a repeated sync preserves IDs
  and ordering, and preserves unrelated mods and playset memberships.
- Commit and push changes to the repository that owns them: mod files in the
  individual mod repository, skill and sync-script changes in the workspace
  repository.

Use a test game or a non-interactive parser when practical. If in-game
behavior cannot be proven outside Stellaris, state the exact in-game check
that remains.
