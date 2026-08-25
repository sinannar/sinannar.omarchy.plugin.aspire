---
name: aspire
description: >-
  **WORKFLOW SKILL** — Aspire CLI observer for the sinannar.omarchy.plugin.aspire
  Omarchy bar-widget plugin. Covers aspire ps, aspire describe, aspire stop, and
  aspire resource <name> <command> JSON output shapes, universal CLI flags,
  state/health classification, URL safety, install locations, and error-handling
  conventions. USE FOR: any change touching Model.js argv builders or JSON
  parsing, or any QML change that invokes the Aspire CLI. DO NOT USE FOR:
  aspire init / aspire new / AppHost wiring / deployment / monitoring telemetry —
  this plugin never starts or configures an AppHost.
license: MIT
metadata:
  author: sinannar
  version: "1.0.0"
  references:
    - https://aspire.dev
    - https://github.com/microsoft/aspire-skills
---

# Aspire CLI — Observer Skill

> **Scope of this skill**: this plugin is a **read-mostly observer**.
> It never runs `dotnet` directly and never starts or configures an AppHost.
> It only reads state from AppHosts that are already running via `aspire ps`,
> `aspire describe`, `aspire stop`, and `aspire resource <name> <command>`.
>
> For full Aspire CLI and AppHost authoring guidance see:
> - **[aspire.dev](https://aspire.dev)** — official Aspire documentation and install guide
> - **[microsoft/aspire-skills](https://github.com/microsoft/aspire-skills)** — first-party agent skill pack
>   covering `aspire-orchestration`, `aspire-monitoring`, `aspire-deployment`, and more

## What Aspire is

[.NET Aspire](https://aspire.dev) is a cloud-ready orchestration framework for
.NET.  An **AppHost** is a .NET project (`.csproj`) that declares the resources
(containers, databases, services, …) making up an application.  The **Aspire CLI**
(`aspire`) talks to a running AppHost over a local IPC channel and exposes its
state via JSON-formatted subcommands.

## Install locations

The `aspire` binary may live in any of:

| Path | How it gets there |
|---|---|
| `~/.aspire/bin/aspire` | `curl -sSL https://aspire.dev/install.sh \| bash` (most common) |
| `~/.dotnet/tools/aspire` | `dotnet tool install -g Aspire.Cli` |
| `~/.local/bin/aspire` | Manual / distro package |

`PATH` in non-interactive shells commonly omits these directories.  The plugin
appends all three (plus `~/.dotnet`) to whatever `PATH` it inherits before
running the CLI via `Model.augmentedPath()`.

## Common flags (used in every call)

| Flag | Effect |
|---|---|
| `--non-interactive` | Suppresses confirmation prompts and progress spinners. Required for scripting. |
| `--nologo` | Suppresses the Aspire copyright/version banner on stdout. |
| `--apphost <path>` | Targets a specific AppHost by its `.csproj` path. Required whenever more than one AppHost may be running to avoid operating on the wrong one. |
| `--format Json` | Emit machine-readable JSON instead of human-readable tables. |

## `aspire ps --format Json`

Lists all running AppHost processes.

```sh
aspire ps --format Json --non-interactive --nologo
```

### Output shape (array)

```json
[
  {
    "appHostPath": "/home/user/myapp/MyApp.AppHost/MyApp.AppHost.csproj",
    "appHostPid": 12345,
    "status": "Running",
    "dashboardUrl": "http://localhost:18888",
    "sdkVersion": "9.0.0"
  }
]
```

| Field | Notes |
|---|---|
| `appHostPath` | Absolute path to the `.csproj`; stable identity and the `--apphost` value for subsequent calls. |
| `appHostPid` | Fallback identity if `appHostPath` is absent. |
| `status` | `"Running"` (case-insensitive check). This plugin only ever tracks `"Running"` entries. |
| `dashboardUrl` | URL of the Aspire web dashboard for this AppHost. |
| `sdkVersion` | Informational only. |

An empty array means no AppHosts are running.  Any non-zero exit code indicates a
CLI error (Docker unavailable, `aspire` not on PATH, etc.).

## `aspire describe --apphost <path> --format Json`

Describes all resources declared by one AppHost.

```sh
aspire describe \
  --apphost /path/to/MyApp.AppHost.csproj \
  --format Json \
  --non-interactive --nologo
```

### Output shape

```json
{
  "resources": [
    {
      "name": "cache",
      "displayName": "Cache",
      "resourceType": "Container",
      "state": "Running",
      "healthStatus": "Healthy",
      "dashboardUrl": "http://localhost:18888/...",
      "urls": [
        { "name": "http", "url": "http://localhost:8080" }
      ],
      "commands": {
        "restart": {
          "displayName": "Restart",
          "description": "Restart this resource",
          "state": "Enabled",
          "sortOrder": 0
        },
        "stop": {
          "displayName": "Stop",
          "description": "Stop this resource",
          "state": "Disabled",
          "sortOrder": 1
        }
      }
    }
  ]
}
```

| Field | Notes |
|---|---|
| `name` | Internal resource name (used in `aspire resource <name> <command>`). |
| `displayName` | Human-readable label for the UI. |
| `resourceType` | E.g. `"Container"`, `"Project"`, `"Executable"`, `"Parameter"`. |
| `state` | Raw state string. Normalised by `Model.classifyResourceState()`. |
| `healthStatus` | `"Healthy"`, `"Unhealthy"`, `"Degraded"`, or absent/null. |
| `urls` | Array of `{name, url}`. Only `http`/`https` URLs are safe to surface. |
| `commands` | Object keyed by command name. Only `"state": "Enabled"` commands are offered in the UI. |

### Resource state categories (`Model.classifyResourceState`)

| Raw state (case-insensitive) | Category |
|---|---|
| `""` / absent | `"unknown"` |
| contains `"fail"` | `"failed"` |
| `"Running"` | `"running"` |
| `"Exited"`, `"Finished"`, `"FinishedSuccessfully"` | `"stopped"` (normal terminal state for one-shot jobs — not a failure) |
| anything else | `"starting"` |

### Health categories (`Model.classifyHealth`)

| Raw value | Category |
|---|---|
| `"Healthy"` | `"healthy"` |
| `"Unhealthy"`, `"Degraded"` | `"unhealthy"` |
| absent / other | `"unknown"` |

### URL safety constraint

Only `http`/`https` endpoints are surfaced.  Other URL schemes (`tcp`, `rediss`,
`amqp`, …) can carry embedded credentials for some resource types and are excluded
entirely from the details panel rather than filtered value by value.

## `aspire stop --apphost <path>`

Stops the AppHost and all its managed resources.

```sh
aspire stop \
  --apphost /path/to/MyApp.AppHost.csproj \
  --non-interactive --nologo
```

This is the only destructive action the plugin offers, and it always sits behind a
confirmation dialog.  After `aspire stop`, the next `aspire ps` poll stops
reporting that AppHost, and the panel removes it automatically.

## `aspire resource <name> <command> --apphost <path>`

Runs an enabled lifecycle command on a single resource.

```sh
aspire resource cache restart \
  --apphost /path/to/MyApp.AppHost.csproj \
  --non-interactive --nologo
```

`<name>` is the resource's `name` field from `aspire describe` output.
`<command>` is the key in the `commands` object (e.g. `"restart"`, `"stop"`).
The plugin only calls commands Aspire reports as `"state": "Enabled"` — never a
hardcoded set.

## Error handling conventions

- **Non-zero exit from `aspire ps`**: keep the last good AppHost snapshot; set
  `lastPollFailed = true` to dim the bar icon.
- **Non-zero exit from `aspire describe`**: surface stderr as "Couldn't read resource
  status — \<stderr\>"; do not crash the panel.
- **Non-zero exit from `aspire stop` / `aspire resource`**: surface stderr beneath
  the resource list.
- **Empty stdout**: treat as a parse failure (empty list), not as a hard error.
