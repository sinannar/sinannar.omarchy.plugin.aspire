---
name: Aspire Omarchy plugin coding agent
description: >
  Custom coding agent for the sinannar.omarchy.plugin.aspire repository.
  Provides authoritative context for Omarchy/Quickshell plugin conventions
  and Aspire CLI behavior without requiring a local Omarchy or Aspire
  installation. Use for any code change in this repository.
---

# Aspire Omarchy plugin — coding agent

This agent works on a Quickshell bar-widget plugin that surfaces locally
running [.NET Aspire](https://aspire.dev) AppHosts in the
[Omarchy](https://omarchy.org) desktop environment.  The plugin is a
read-mostly wrapper around the Aspire CLI and never starts or configures
an AppHost itself.

## Domain skills

This agent carries the same skills used for local development on this
plugin (normally sourced from the Omarchy/Aspire CLI installs), copied
verbatim into `.github/skills/` so they are available on GitHub's cloud
agent runners where no local Omarchy or Aspire install exists. Read the
relevant skill before making any change that touches the areas it covers:

- **`omarchy`** ([`.github/skills/omarchy/SKILL.md`](.github/skills/omarchy/SKILL.md))
  — Omarchy/Quickshell plugin structure, QML component contracts (`BarWidget`,
  `Panel`, `KeyboardPanel`, `IpcHandler`, `Process`, `StdioCollector`),
  manifest schema, validation commands, and the PATH-resolution constraint
  that forces `["/usr/bin/env", "aspire", …]` as the process command array.
  Reference: [omarchy.org](https://omarchy.org), [github.com/basecamp/omarchy](https://github.com/basecamp/omarchy)

- **`aspire`** ([`.github/skills/aspire/SKILL.md`](.github/skills/aspire/SKILL.md))
  — Aspire CLI behavior: `aspire ps` / `aspire describe` / `aspire stop` /
  `aspire resource` JSON output shapes, flag requirements
  (`--non-interactive --nologo --apphost`), state/health classification
  rules, URL safety constraints, and error-handling expectations.
  Reference: [aspire.dev](https://aspire.dev), [microsoft/aspire-skills](https://github.com/microsoft/aspire-skills)

- **`aspire-orchestration`** ([`.github/skills/aspire-orchestration/SKILL.md`](.github/skills/aspire-orchestration/SKILL.md))
  — lifecycle safety guardrails (`aspire start`/`stop`/`wait`, file-lock
  recovery). This plugin only ever calls `aspire ps`, `aspire describe`,
  `aspire stop`, and `aspire resource <name> <command>` — it never starts an
  AppHost — but this skill documents the guardrails other tooling in the
  ecosystem expects and is useful context if a task ever touches AppHost
  lifecycle expectations.

- **`aspire-monitoring`** ([`.github/skills/aspire-monitoring/SKILL.md`](.github/skills/aspire-monitoring/SKILL.md))
  — local diagnostics (`aspire logs`, `aspire otel logs/traces`, dashboard).
  Not currently used by this plugin (it doesn't surface logs/traces), but
  kept for context if that scope ever expands.

- **`aspire-deployment`** ([`.github/skills/aspire-deployment/SKILL.md`](.github/skills/aspire-deployment/SKILL.md))
  and **`aspire-init`** ([`.github/skills/aspire-init/SKILL.md`](.github/skills/aspire-init/SKILL.md))
  — AppHost scaffolding and deployment. Out of scope for this plugin (it
  never runs `dotnet` or configures an AppHost) but included for completeness
  since they are part of the same locally-installed skill set.

> These skills were copied as-is from the local `~/.agents/skills/` install
> used for day-to-day development on this repo, not rewritten for GitHub.
> When the local skills are updated, re-sync `.github/skills/` from them
> rather than hand-editing the copies here.

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
