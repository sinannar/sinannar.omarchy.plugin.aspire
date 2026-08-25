# Aspire Omarchy plugin

An Omarchy/Quickshell bar-widget plugin (QML + JS) that shows how many
locally running Aspire AppHosts `aspire ps` reports, plus a details
panel with per-resource status (`aspire describe`) and lifecycle actions.
It is a thin, read-mostly wrapper around the Aspire CLI: it never runs
`dotnet` directly and never starts an AppHost, only observes/acts on ones
already running.

## Relevant skills

Domain context for this plugin is captured in two agent skill files under
`.github/skills/`.  Read them before making changes that touch the areas they
cover — they replace the locally-installed Omarchy/Aspire CLI skills that are
not available on GitHub CI:

- **[`omarchy`](.github/skills/omarchy/SKILL.md)** — for anything touching the
  bar widget, panel, IPC, settings, or how Quickshell plugins are
  structured/loaded in Omarchy's shell.  External reference:
  [omarchy.org](https://omarchy.org) / [github.com/basecamp/omarchy](https://github.com/basecamp/omarchy).
- **[`aspire`](.github/skills/aspire/SKILL.md)** — for Aspire CLI behavior this
  plugin depends on (`aspire ps`, `aspire describe`, `aspire stop`,
  `aspire resource <name> <command>`), including output shapes and flags,
  before changing how `Model.js` builds argv or parses CLI output.  External
  references: [aspire.dev](https://aspire.dev) and the first-party
  [microsoft/aspire-skills](https://github.com/microsoft/aspire-skills) pack.

## Files

- `manifest.json` — plugin metadata, registers `BarWidget.qml` as the bar-widget entry point.
- `BarWidget.qml` — owns AppHost discovery (`aspire ps`), the bar glyph/count, the poll timer, and IPC handlers.
- `Panel.qml` — owns AppHost selection, per-AppHost resource detail (`aspire describe`), and lifecycle actions (stop, resource commands).
- `Model.js` — pure JSON parsing/normalization/aggregation and CLI argv builders. Deliberately Qt-free (no Quickshell imports) so it can run under plain Node.

## Validating changes to `Model.js`

There is no test framework or `package.json` in this repo. `Model.js` uses
`module.exports` specifically so its pure functions can be exercised
directly with Node, e.g.:

```bash
node -e '
const Model = require("./Model.js");
console.log(Model.parseDescribeResources(require("fs").readFileSync("/dev/stdin", "utf8")));
' < describe-output.json
```

Use this pattern (`node -e '...require("./Model.js")...'`) to sanity-check
any change to a `Model.js` function before touching the QML that calls it.
QML changes (`BarWidget.qml`, `Panel.qml`) can't be run headless here — rely
on code review and matching the architecture below.

## Architecture

- **Separation of concerns is strict**: `Model.js` contains all JSON
  parsing, normalization, aggregation, and CLI-argv-building logic. QML
  files own process invocation, polling/timers, and rendering only. New
  parsing/aggregation logic belongs in `Model.js`, not inline in QML.
- **Data flow**: `BarWidget.qml` polls `aspire ps` on a timer and holds the
  list of running AppHosts. It hands that list down into `Panel.qml` (via
  `injectPanel()`), which owns fetching `aspire describe` for only the one
  currently-selected AppHost (not all of them, to keep the panel responsive
  with many AppHosts running).
- **Scope is deliberately narrow** — preserve this when extending the plugin:
  - Only AppHosts `aspire ps` reports as `running` are ever shown/tracked/acted on. Stopped AppHosts are never remembered, configured, or started from here.
  - Only one AppHost's resources are fetched at a time (the one selected in the panel's chip row).
  - Only `http`/`https` endpoints are surfaced (`Model.safeUrls`); other schemes (`tcp`, `rediss`, `amqp`, …) can carry embedded credentials and are excluded entirely.
  - Resource action buttons are entirely data-driven from whatever Aspire reports as `"state": "Enabled"` for that resource (`Model.enabledCommands`) — never a hardcoded start/stop/restart trio.
  - Stopping an AppHost is the one destructive action offered, and it always sits behind a confirmation dialog.
- **CLI invocation** goes through `Model.aspireCommand()`, which prefixes
  args with `/usr/bin/env aspire` rather than a bare `"aspire"` argv[0]:
  Quickshell's `Process` resolves argv[0] against the *inherited* PATH
  before the QML's `environment` override applies, so a bare `"aspire"`
  fails to launch if the plugin's own PATH lacks the CLI's install dir.
  `Model.augmentedPath()` appends `~/.dotnet`, `~/.dotnet/tools`, and
  `~/.local/bin` to whatever PATH was inherited, so `aspire` resolves like
  it would from an interactive shell. Any new process invocation should
  reuse both of these helpers rather than shelling out directly.
- **In-flight request handling**: switching the selected AppHost mid-request
  must never apply a stale result — an in-flight `describe` for the AppHost
  navigated away from is discarded, and a fresh request for the newly
  selected one is queued. Preserve this discard/requeue behavior in
  `Panel.qml` if touching the describe-refresh logic.
- Every `aspire` CLI call passes `--non-interactive --nologo` and, where it
  targets a specific AppHost, an explicit `--apphost <path>` so a command can
  never drift onto the wrong AppHost (see the `*Args` builders in `Model.js`).

## Conventions

- Comments in `Model.js` and the QML files explain *why*, not *what* — many
  document a subtle constraint (PATH resolution order, stale-result
  discarding, credential-bearing URL schemes). Preserve/update these
  rationale comments when changing the logic they describe rather than
  deleting them.
- Settings are read via `setting("key", default)` in `BarWidget.qml` (e.g.
  `pollIntervalSec`, clamped to a 5s minimum) and are configured externally
  via `omarchy bar set sinannar.omarchy.plugin.aspire <key> <value>` — see
  README.md's Settings table before adding a new configurable value.
- IPC actions are registered in `BarWidget.qml`'s `IpcHandler` block
  (`refresh`, `open`, `close`, `show`, `hide`, `toggle`) and documented in
  README.md's IPC section — keep both in sync if adding a new one.
