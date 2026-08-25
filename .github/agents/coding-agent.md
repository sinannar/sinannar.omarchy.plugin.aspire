---
name: Aspire Omarchy plugin coding agent
description: >
  Custom coding agent for the sinannar.omarchy.plugin.aspire repository.
  Provides authoritative context for Omarchy/Quickshell plugin conventions
  and Aspire CLI behavior without requiring a local Omarchy or Aspire
  installation.
skills:
  - .github/agents/omarchy.md
  - .github/agents/aspire.md
---

# Aspire Omarchy plugin — coding agent

This agent works on a Quickshell bar-widget plugin that surfaces locally
running [.NET Aspire](https://aspire.dev) AppHosts in the
[Omarchy](https://omarchy.org) desktop environment.  The plugin is a
read-mostly wrapper around the Aspire CLI and never starts or configures
an AppHost itself.

## Domain skills

The agent draws on two skill files for domain-specific context that cannot
be inferred from the code alone:

- **`omarchy`** ([`.github/agents/omarchy.md`](.github/agents/omarchy.md))
  — Omarchy/Quickshell plugin structure, QML component contracts (`BarWidget`,
  `Panel`, `KeyboardPanel`, `IpcHandler`, `Process`, `StdioCollector`),
  manifest schema, validation commands, and the PATH-resolution constraint
  that forces `["/usr/bin/env", "aspire", …]` as the process command array.

- **`aspire`** ([`.github/agents/aspire.md`](.github/agents/aspire.md))
  — Aspire CLI behavior: `aspire ps` / `aspire describe` / `aspire stop` /
  `aspire resource` JSON output shapes, flag requirements
  (`--non-interactive --nologo --apphost`), state/health classification
  rules, URL safety constraints, and error-handling expectations.

Consult these files before making any change that touches CLI argument
construction, JSON parsing, QML component usage, manifest fields, or
IPC/settings conventions.  They replace the locally-installed `omarchy` and
`aspire` CLI skills that are available in a developer's Omarchy environment
but unavailable on GitHub CI.

## Architecture reminders

- `Model.js` contains **all** parsing, normalization, aggregation, and
  CLI-argv-building logic.  It is Qt-free so it can be tested with plain
  Node.  New logic belongs here, not inline in QML.
- `BarWidget.qml` owns `aspire ps` polling and the bar glyph/count.
- `Panel.qml` owns `aspire describe` for the one selected AppHost, plus
  stop and resource-command actions.
- Only `http`/`https` URLs are surfaced — other schemes may carry embedded
  credentials.
- Resource action buttons are data-driven from Aspire's `"Enabled"` command
  state; never hardcode a start/stop/restart trio.
- Every `aspire` call goes through `Model.aspireCommand()` (prefixes
  `/usr/bin/env`) and uses `Model.augmentedPath()` for the child `PATH`.

## Validation (no local Omarchy needed)

Model.js changes can be sanity-checked with plain Node:

```bash
node -e '
const M = require("./Model.js");
console.log(JSON.stringify(M.parsePsRunning("[{\"status\":\"Running\",\"appHostPath\":\"/a/b.csproj\"}]"), null, 2));
'
```

QML and manifest validation require Omarchy (`checks/validate.sh`) and
cannot run on GitHub CI — rely on code review and matching the architecture
described in the skill files above.
