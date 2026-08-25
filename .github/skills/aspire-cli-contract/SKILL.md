---
name: aspire-cli-contract
description: >-
  **OFFLINE REFERENCE SKILL** — Documents the exact Aspire CLI commands this
  plugin invokes (`aspire ps`, `aspire describe`, `aspire stop`, `aspire
  resource <name> <command>`), their JSON output shapes, and versioned
  fixture files, so `Model.js` parsing/normalization logic can be reasoned
  about and exercised with plain Node when no `aspire` binary is installed
  (e.g. on GitHub's cloud agent runners). USE FOR: editing `Model.js` parsing
  functions, adding a new read-only Aspire command to this plugin, writing
  or reviewing `node -e` sanity checks against `Model.js`, understanding
  what `aspire ps --format Json` / `aspire describe --format Json` return.
  DO NOT USE FOR: actually running the Aspire CLI (use the `aspire` skill
  and its sub-skills when a real `aspire` binary is available), AppHost
  authoring/deployment/start (out of scope for this plugin), or as a
  substitute for live integration testing before a release.
  INVOKES: nothing (reference + fixtures only, no executable mock CLI).
license: MIT
metadata:
  author: sinannar
  version: "1.0.0"
---

# Aspire CLI contract (offline reference)

This skill exists because `Model.js`'s parsing/normalization functions are
Qt-free and unit-testable under plain Node (see the repo's
`.github/agents/coding-agent.agent.md`), but doing that testing usefully
requires knowing the *exact* shape of the JSON the real `aspire` CLI
produces. This file documents that shape as currently consumed by
`Model.js`, plus versioned fixture files under `fixtures/` that reproduce
it, so an agent without a local `aspire` install can still validate parser
changes.

**This is not a mock CLI.** Nothing here executes in place of `aspire`. It
is documentation plus static JSON fixtures for feeding directly into
`Model.js` functions via Node, exactly as `README.md`'s existing validation
pattern already does with a single piped file.

## Scope boundary

This skill covers only the commands `Model.js` / `BarWidget.qml` /
`Panel.qml` currently invoke, plus a small set of read-only commands the
plugin is likely to add next (see "Likely near-future reads" below). It
explicitly excludes `aspire start`, `aspire init`/`new`, `aspire add`,
`aspire deploy`/`publish`/`destroy`, and any other authoring/lifecycle/
deployment command — those remain covered by the general `aspire` skill and
its sub-skills, and are out of scope for this plugin by design (see this
repo's root README "Scope" section).

## Current commands

Every invocation goes through `Model.aspireCommand(args)` (prefixes
`/usr/bin/env aspire`) with `Model.augmentedPath()` supplying `PATH`, and
always includes `--non-interactive --nologo`. Argv is built by the
corresponding `Model.js` function; do not hand-construct argv elsewhere.

### `aspire ps --format Json --non-interactive --nologo`

Built by `Model.psArgs()`. Invoked on a timer by `BarWidget.qml` and parsed
by `Model.parsePsRunning(jsonText)`.

**Shape:** top-level JSON array. Each element:

| Field | Type | Notes |
|---|---|---|
| `status` | string | Compared case-insensitively to `"running"` by `Model.isRunningPsEntry`; every other value (`Stopped`, `Starting`, …) is dropped entirely — this plugin never tracks non-running AppHosts. |
| `appHostPath` | string | Used as the stable identity (`Model.psEntryId`) and to derive the label (`Model.appHostLabel`). Falls back to `"pid:" + appHostPid` if empty. |
| `appHostPid` | number | Passed through unchanged. |
| `dashboardUrl` | string | Passed through as-is (not filtered like resource URLs — this one field is already known-safe: it is the Aspire CLI's own dashboard link). |
| `sdkVersion` | string | Passed through unchanged. |

**Label derivation edge case** (`Model.appHostLabel`): the basename minus
extension has a trailing `.AppHost` suffix stripped case-insensitively. A
conventional MSBuild-style path like
`.../ContosoShop.AppHost/ContosoShop.AppHost.csproj` yields label
`ContosoShop`. A file-based AppHost literally named `apphost.cs` or
`apphost.ts` (the Aspire CLI's own naming convention for that mode) yields
label `apphost` unchanged, since there's no `.AppHost` suffix to strip — see
`fixtures/ps-running.json`'s second entry for exactly this case.

**Fixtures:**
- `fixtures/ps-running.json` — two running AppHosts, one MSBuild-style path
  and one file-based (`apphost.cs`), demonstrating the label edge case
  above.
- `fixtures/ps-empty.json` — no AppHosts running (`[]`). Bar shows count 0
  and collapses out of the bar (see `BarWidget.qml`'s `hasVisualContent`).
- `fixtures/ps-mixed-status.json` — one `Running`, one `Stopped`, one
  `Starting` entry; only the `Running` one survives `parsePsRunning`.
- `fixtures/ps-malformed-shape.json` — a top-level *object* instead of an
  array, modeling a future/misbehaving CLI response. `parsePsRunning` must
  degrade to `[]` via its `Array.isArray` guard, never throw.

### `aspire describe --apphost <path> --format Json --non-interactive --nologo`

Built by `Model.describeArgs(appHostPath)`. Invoked by `Panel.qml` for only
the one currently-selected AppHost, on a fixed refresh timer while the panel
is open. Parsed by `Model.parseDescribeResources(jsonText)`.

**Shape:** top-level JSON object with a `resources` array. Each element:

| Field | Type | Notes |
|---|---|---|
| `name` | string | Resource identifier, also used as the argv for `aspire resource <name> <command>`. |
| `displayName` | string | Falls back to `name` if absent. |
| `resourceType` | string | e.g. `Project`, `Container`. Passed through unchanged. |
| `state` | string | Classified by `Model.classifyResourceState` — see table below. |
| `healthStatus` | string \| null | Classified by `Model.classifyHealth` — see table below. |
| `dashboardUrl` | string | Per-resource dashboard deep link, passed through as-is. |
| `urls` | array of `{name, url}` | Filtered by `Model.safeUrls` — only `http://`/`https://` URLs survive; every other scheme (`tcp`, `rediss`, `amqp`, …) is dropped even if some entries in the same array are safe. |
| `commands` | object keyed by command name | Filtered by `Model.enabledCommands` — only entries with `state === "Enabled"` survive, sorted by `sortOrder` (missing/non-finite `sortOrder` defaults to `999`). Each surviving entry exposes `name`, `displayName`, `description`, `sortOrder`. |

**State classification** (`Model.classifyResourceState`, case-insensitive
substring/exact match against `state`):

| Input contains/equals | `stateCategory` |
|---|---|
| *(empty string)* | `unknown` |
| contains `"fail"` (e.g. `FailedToStart`) | `failed` |
| exactly `"running"` | `running` |
| exactly `"exited"`, `"finished"`, or `"finishedsuccessfully"` | `stopped` |
| anything else (e.g. `Starting`, `Building`) | `starting` |

Note: `"exited"`/`"finished"` classify as `stopped`, **not** `failed` — this
is deliberate so a one-shot resource (a migration or seed job) that
completed successfully doesn't read as a failure. See
`fixtures/describe-one-shot-finished.json`.

**Health classification** (`Model.classifyHealth`, case-insensitive):

| Input | `healthCategory` |
|---|---|
| `"healthy"` | `healthy` |
| `"unhealthy"` | `unhealthy` |
| `"degraded"` | `unhealthy` |
| anything else (including `null`/missing) | `unknown` |

**Fixtures:**
- `fixtures/describe-normal.json` — two running/healthy resources; one
  `Project` with enabled `restart`/`stop` commands and a `Disabled`
  `view-source` command (must be dropped by `enabledCommands`); one
  `Container` with a `tcp://` URL only (must be dropped by `safeUrls`,
  leaving that resource's `urls` empty).
- `fixtures/describe-empty.json` — `{"resources": []}`.
- `fixtures/describe-unhealthy-failed.json` — one resource with
  `state: "FailedToStart"` (→ `failed`) and one `Running` resource with
  `healthStatus: "Degraded"` (→ `running` state, `unhealthy` health) and an
  empty `commands` object.
- `fixtures/describe-one-shot-finished.json` — one resource with
  `state: "FinishedSuccessfully"` and `healthStatus: null`, expected to
  classify as `stopped` / `unknown`, not `failed`.
- `fixtures/describe-mixed-url-schemes.json` — one resource with four URLs
  (`http`, `amqp`, `rediss`, `https`); only the two `http(s)` entries must
  survive `safeUrls`, in their original order.
- `fixtures/describe-malformed.txt` — not valid JSON at all (simulates
  truncated/garbled stdout). `tryParseJson` must return `null` and
  `parseDescribeResources` must degrade to `[]`, never throw.

### `aspire stop --apphost <path> --non-interactive --nologo`

Built by `Model.stopAppHostArgs(appHostPath)`. Invoked by `Panel.qml` only
from behind a confirmation dialog (the one destructive action this plugin
offers). No JSON parsing on the result — the panel reads stderr on failure
and re-polls `aspire ps` on success. No fixture needed beyond the plain
success/failure exit-code contract already handled by `Panel.qml`.

### `aspire resource <name> <command> --apphost <path> --non-interactive --nologo`

Built by `Model.resourceCommandArgs(appHostPath, resourceName, commandName)`.
`commandName` must be one of the names surfaced by `enabledCommands` for
that resource in the most recent `describe` response — never a hardcoded
`start`/`stop`/`restart` trio. Same no-JSON, stderr-on-failure contract as
`stop`.

## Likely near-future reads

If this plugin's scope grows to surface logs/traces (still read-only,
still no AppHost start/config), the following commands are the most likely
additions, per the `aspire-monitoring` skill. Treat any of these as
requiring a new `Model.js` parser function and new fixtures added to this
skill before merging QML that invokes them:

- `aspire logs --apphost <path> --format Json --non-interactive --nologo`
- `aspire otel logs --apphost <path> --format Json --non-interactive --nologo`
- `aspire otel traces --apphost <path> --format Json --non-interactive --nologo`

None of these are implemented yet — there is no `Model.js` function or
fixture for them. Do not assume a shape for these without consulting
`aspire-monitoring`'s `references/monitoring.md` for the current CLI output
schema first, since these are more likely to change across Aspire releases
than `ps`/`describe`.

## Using the fixtures

Matches the pattern already documented in this repo's `README.md` and
`.github/agents/coding-agent.agent.md`:

```bash
node -e '
const Model = require("./Model.js");
const text = require("fs").readFileSync(
  ".github/skills/aspire-cli-contract/fixtures/describe-normal.json", "utf8"
);
console.log(JSON.stringify(Model.parseDescribeResources(text), null, 2));
'
```

## Non-goals

- These fixtures are illustrative of the *contract*, not exhaustive replays
  of a real AppHost. Every path, hostname, port, and identifier in them is
  fictional (`contoso-*`, `fabrikam-*`, `northwind-*`, `adventure-*`) and
  must stay that way — never replace a fixture with output copied from a
  real machine or a real developer's project.
- Passing fixtures through `Model.js` does not replace live testing against
  a real `aspire` install before release; it only proves the parser handles
  the documented contract shapes without throwing and classifies them as
  described above.
- If the real Aspire CLI's JSON output shape changes (e.g. a 13.5 release
  renames a field), update this file and its fixtures together in the same
  change — do not let them drift out of sync with `Model.js`.
