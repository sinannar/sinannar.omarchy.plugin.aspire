---
name: omarchy-plugin-contract
description: >-
  **OFFLINE REFERENCE SKILL** — Documents the exact `omarchy plugin *`,
  `omarchy bar *`, `omarchy-shell <target> <action>` IPC, and `qmllint`
  commands relevant to developing this shell plugin, their JSON output
  shapes, exit-code/stderr contracts, and versioned fixture files, so
  plugin-facing changes (manifest fields, IPC actions, settings) can be
  reasoned about without a local Omarchy install (e.g. on GitHub's cloud
  agent runners). USE FOR: editing `manifest.json`, adding/renaming an
  `IpcHandler` action in `BarWidget.qml`, adding a `setting()` key, updating
  README's IPC/Settings tables, reasoning about `checks/validate.sh` /
  `checks/run-inspect.sh` output shape. DO NOT USE FOR: general Hyprland/
  theming/desktop customization (use the `omarchy` skill), actually running
  these commands when a real Omarchy install is available (use `omarchy`
  and `checks/*.sh` directly), or system-level plugin installation/removal
  on a real machine.
  INVOKES: nothing (reference + fixtures only, no executable mock CLI).
license: MIT
metadata:
  author: sinannar
  version: "1.0.0"
---

# Omarchy plugin contract (offline reference)

This skill documents the exact behavior of the Omarchy CLI commands and
`omarchy-shell` IPC surface this plugin's development workflow depends on,
verified directly against the installed Omarchy CLI on this machine (see
"Provenance" below), plus versioned JSON fixtures under `fixtures/` that
reproduce `omarchy plugin list --json`'s shape for this plugin in different
states.

**This is not a mock CLI.** Nothing here executes in place of `omarchy` /
`omarchy-shell` / `qmllint`. It is documentation plus static JSON fixtures,
intended for structural reasoning (e.g. "does my new manifest field survive
`omarchy plugin validate`'s required-field check?") when those binaries are
not on the runner's `PATH`.

## Scope boundary

This covers only the command surface this plugin's own development touches:
plugin lifecycle/inspection (`omarchy plugin *`), this widget's bar
placement/settings (`omarchy bar move` / `omarchy bar set`), this plugin's
own IPC target (`omarchy-shell sinannar.omarchy.plugin.aspire <action>`),
and QML linting (`qmllint`). It does not cover Hyprland, theming, hooks, or
general desktop customization — those remain the `omarchy` skill's scope
(`.github/skills/omarchy/SKILL.md` and its topic guides).

## `omarchy plugin list --json`

Backed by `omarchy-shell shell listPlugins` (verified: `omarchy-plugin-list`
just prints that IPC call's JSON straight through when `--json` is passed;
its human-readable table format runs the same JSON through `jq`/`awk`).

**Shape:** top-level JSON array. Each element (field names and types
confirmed against a live `omarchy plugin list --json` run):

| Field | Type | Notes |
|---|---|---|
| `id` | string | Matches `manifest.json`'s `id`. This plugin's id is `sinannar.omarchy.plugin.aspire`. |
| `name` | string | Matches `manifest.json`'s `name`. |
| `kinds` | array of string | Matches `manifest.json`'s `kinds`, e.g. `["bar-widget"]`. |
| `enabled` | boolean | Whether the plugin is currently enabled (on the bar / active service). |
| `active` | boolean | Whether the plugin is the *currently selected* option for a single-slot kind (e.g. `kind: "bar"` — only one bar can be active at a time). This plugin is `kind: "bar-widget"`, so `active` is always `false` for it; `true` only applies to single-slot kinds like `bar`. |
| `canDisable` | boolean | `false` only for plugins the shell will not let you disable (e.g. the built-in `bar` itself); `true` for this plugin. |
| `firstParty` | boolean | `false` for any plugin installed via `omarchy plugin add`/`clone` from outside the Omarchy repo itself, including this one. |
| `clonedFrom` | string | Empty string unless this plugin id was produced by `omarchy plugin clone` from another plugin id, in which case it holds the source id. |

**`omarchy plugin list` (no `--json`)**: renders the same data as a
column-aligned table (`ID STATE SOURCE KINDS NAME`) via `jq`/`awk` — not
JSON. Always request `--json` for anything meant to be parsed.

**Fixtures** (each a plausible slice of the real array, not a full-machine
dump — see "Non-goals"):
- `fixtures/plugin-list-present-enabled.json` — this plugin present with
  `enabled: true`, alongside an ordinary first-party bar widget and the
  single-slot `omarchy.bar` (`kinds: ["bar"]`, `canDisable: false`,
  `active: true`) for contrast.
- `fixtures/plugin-list-absent.json` — this plugin's id does not appear at
  all (e.g. not yet installed, or removed via `omarchy plugin remove`).
  `.[] | select(.id == "sinannar.omarchy.plugin.aspire")` (the exact filter
  used in `checks/run-inspect.sh`) yields nothing for this fixture.
- `fixtures/plugin-list-present-disabled.json` — this plugin present with
  `enabled: false` (e.g. after `omarchy plugin disable`).
- `fixtures/plugin-list-cloned-variant.json` — models what a
  `omarchy plugin clone` of this plugin would look like: same shape, but
  `clonedFrom` populated with a source id, to exercise code that might
  branch on that field.

## `omarchy plugin validate <plugin-folder>`

Verified live against this repo's own `manifest.json` (`omarchy plugin
validate "$PWD"` exits `0`). Per `omarchy-plugin-validate`'s own `--help`
text and source, it checks, in order, and exits non-zero with a message on
`stderr` (prefixed `omarchy-plugin-validate:`) at the first failure:

1. `manifest.json` exists in the plugin folder and is valid JSON.
2. `schemaVersion` is exactly the JSON number `1` (a string `"1"` fails —
   `jq`'s `==` is type-aware).
3. Required top-level fields are present: `id`, `name`, `version`, `kinds`,
   `entryPoints`.
4. `id` is non-empty, matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`, contains no
   `..`, and does not start with the reserved `omarchy.` namespace.
5. `kinds` is a non-empty array.
6. `entryPoints` is an object; every value is a relative path (no leading
   `/`, no `..`, no embedded newline) that exists on disk under the plugin
   folder.
7. If `barWidget.defaultSection` is present, it is one of `left`, `center`,
   `right`.
8. Each declared kind that requires an entry point has one:
   `bar`→`bar`, `bar-widget`→`barWidget`, `menu`→`menu`, `overlay`→`overlay`,
   `panel`→`panel`, `service`→`service`. A kind not in this table is left
   unchecked.
9. No symlinks anywhere inside the plugin folder (the `.git` directory is
   exempt).

Exits `0` silently on success — no stdout. This plugin's own
`checks/validate.sh` already runs this exact command; use that script when
Omarchy is available rather than re-deriving these checks by hand.

## `omarchy plugin add [git-url] [--enable] [--yes]`

Verified via `--help` (aliased as `omarchy plugin install`). Clones a
plugin repo into `~/.config/omarchy/plugins/`. Interactive by default (git
URL prompted via `gum input` if omitted, confirmation via `gum confirm`
before proceeding); requires `--yes` to run non-interactively (fails with
`refusing to continue without confirmation; pass --yes` otherwise). With
`--enable`, and only for a `bar-widget` kind that is not also a `bar`, it
additionally prompts (interactively) for a bar section placement, defaulting
to `manifest.json`'s `barWidget.defaultSection` (or `center` if unset).

## `omarchy plugin remove [id] [--yes]` (alias: `omarchy plugin rm`)

Verified via `--help`. Removes an installed plugin by id; `--yes` skips
confirmation.

## `omarchy plugin enable <id> [placement]` / `omarchy plugin disable <id>`

Verified via `--help`. `enable` accepts the same placement flags as
`omarchy bar move` (`--section`, `--index`, `--before`, `--after`) for
`bar-widget` kinds. `disable` takes only an id.

## `omarchy bar move <id> [section] [placement-flags]`

Verified via `omarchy bar --help` (`omarchy-bar` source, `cmd_move`).
Backed by `omarchy-shell shell moveBarWidget <id> <placementJson>`; fails
with the IPC call's own error string if it doesn't return exactly `"ok"`.
Placement can be given as a bare positional section (`left`/`center`/
`right`) **or** via flags (`--section`, `--index`, `--before`, `--after`,
`--from-section`, `--from-index`) — never both a positional section and a
conflicting flag in the same call. This repo's README documents
`omarchy bar move sinannar.omarchy.plugin.aspire --section center` as the
supported form.

## `omarchy bar set <id> <key> <value> [--json] [placement-flags]`

Verified via `omarchy-bar` source (`cmd_set`). Requires an id, key, and
value (missing value fails with `set requires a value`). `--json` parses
`value` as a JSON literal (numbers, booleans, objects) instead of a bare
string — this is why README's `pollIntervalSec` example passes `--json`
for the numeric `30`. Does not accept `--before`/`--after` (placement here
is for the widget's own position on the bar, not sibling-relative
insertion).

## `omarchy-shell <ipc-target> <action>` (this plugin's IPC)

Verified live against this plugin's own `IpcHandler` block in
`BarWidget.qml`. A known target/action pair exits `0` with empty stdout on
success. An unknown target exits `1` with `Target not found.` on stderr —
confirmed by calling `omarchy-shell no.such.target refresh`. This plugin's
target is `sinannar.omarchy.plugin.aspire` with actions `refresh`, `open`,
`close`, `show`, `hide`, `toggle` (see README's IPC section — keep both in
sync if adding a new action).

To force a full plugin code reload (distinct from this plugin's own IPC):
`omarchy-shell shell rescanPlugins`.

## `qmllint`

Verified live: `qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml`
(the exact invocation in `checks/validate.sh`) exits `0` for this plugin's
current QML even though it prints several `Warning:` lines to stdout/stderr
— unresolved `qs.Commons`/`qs.Ui` imports, `BarWidget`/`anchors` type
resolution, and an "inheritance cycle" note are all **expected noise** from
linting a single plugin file outside the full Quickshell shell tree, not
regressions. Only a non-zero exit code (an `Error:`-level finding) indicates
an actual problem worth fixing.

## Non-goals

- Fixtures are illustrative slices of the real `omarchy plugin list --json`
  schema (field names/types confirmed live), not a snapshot of any real
  machine's actual installed-plugin catalog. Every id besides this plugin's
  own is a plausible first-party stand-in (`omarchy.clock`, `omarchy.bar`)
  chosen for contrast, not copied verbatim from a live listing.
- These contracts describe CLI behavior as observed at the time this skill
  was written. If a future Omarchy release changes a field name, an exit
  code, or an IPC error string, update this file and its fixtures together
  — do not let them drift out of sync with the installed CLI.
- This skill does not replace running `checks/validate.sh` and
  `checks/run-inspect.sh` on a real Omarchy install before release; it only
  lets structural/manifest reasoning happen when that install is
  unavailable.

## Provenance

The command behaviors and JSON field names above were confirmed by running
`omarchy plugin list --json`, `omarchy plugin validate`, `omarchy plugin add
--help`, `omarchy plugin remove --help`, `omarchy plugin enable --help`,
`omarchy plugin disable --help`, `omarchy bar --help`, `omarchy-shell
sinannar.omarchy.plugin.aspire refresh`, `omarchy-shell no.such.target
refresh`, and `qmllint` directly against this plugin's own files, and by
reading the corresponding `/usr/bin/omarchy-plugin-*` and `/usr/bin/omarchy-
bar` scripts (which are safe to read per the `omarchy` skill's guidance on
`/usr/share/omarchy/` — read-only, never edit).
