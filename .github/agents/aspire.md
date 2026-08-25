# Aspire CLI knowledge

## What Aspire is

[.NET Aspire](https://aspire.dev) is a cloud-ready orchestration framework for
.NET.  An **AppHost** is a .NET project (`.csproj`) that declares the
resources (containers, databases, services, …) making up an application and
wires them together at startup.  The **Aspire CLI** (`aspire`) talks to a
running AppHost over a local IPC channel and exposes its state via JSON-
formatted subcommands.

This plugin is a read-mostly observer: it never runs `dotnet` directly and
never starts an AppHost — it only reads what is already running.

## Install locations

The `aspire` binary may live in any of:

| Path | How it gets there |
|---|---|
| `~/.aspire/bin/aspire` | `curl \| bash` from aspire.dev (most common) |
| `~/.dotnet/tools/aspire` | `dotnet tool install -g Aspire.Cli` |
| `~/.local/bin/aspire` | Manual / distro package |

`PATH` in non-interactive shells commonly omits these directories.  The plugin
appends all three (plus `~/.dotnet`) to whatever `PATH` it inherits before
running the CLI.

## Common flags (used in every call)

| Flag | Effect |
|---|---|
| `--non-interactive` | Suppresses confirmation prompts and progress spinners. Required for scripting. |
| `--nologo` | Suppresses the Aspire copyright/version banner on stdout. |
| `--apphost <path>` | Targets a specific AppHost by its `.csproj` path. Required whenever more than one AppHost may be running to avoid operating on the wrong one. |
| `--format Json` | Emit machine-readable JSON instead of human-readable tables. |

## `aspire ps --format Json`

Lists all running AppHost processes managed by the local Aspire session.

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

Key fields:

| Field | Notes |
|---|---|
| `appHostPath` | Absolute path to the `.csproj`; used as a stable identity and as `--apphost` value in subsequent calls. |
| `appHostPid` | Fallback identity if `appHostPath` is absent. |
| `status` | `"Running"` (case-insensitive check). Other values (`"Stopped"`, etc.) are never tracked by this plugin. |
| `dashboardUrl` | URL of the Aspire web dashboard for this AppHost. |
| `sdkVersion` | SDK version string; informational only. |

An empty array means no AppHosts are running.  Any non-zero exit code
indicates a CLI error (Docker unavailable, `aspire` not on PATH, etc.).

## `aspire describe --apphost <path> --format Json`

Describes all resources declared by one AppHost.

```sh
aspire describe \
  --apphost /path/to/MyApp.AppHost.csproj \
  --format Json \
  --non-interactive --nologo
```

### Output shape (object with `resources` array)

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

Key fields per resource:

| Field | Notes |
|---|---|
| `name` | Internal resource name (used in `aspire resource <name> <command>`). |
| `displayName` | Human-readable label for the UI. |
| `resourceType` | E.g. `"Container"`, `"Project"`, `"Executable"`, `"Parameter"`. |
| `state` | Raw state string from Aspire. Normalised by `Model.classifyResourceState()`. |
| `healthStatus` | `"Healthy"`, `"Unhealthy"`, `"Degraded"`, or absent/null. |
| `urls` | Array of `{name, url}` objects. Only `http`/`https` URLs are safe to surface (others may carry embedded credentials). |
| `commands` | Object keyed by command name. Each command has `state` (`"Enabled"` / `"Disabled"`), `displayName`, `description`, `sortOrder`. Only `"Enabled"` commands are offered in the UI. |

### Resource state categories (as classified by `Model.classifyResourceState`)

| Raw state (case-insensitive) | Category |
|---|---|
| `""` / absent | `"unknown"` |
| contains `"fail"` | `"failed"` |
| `"Running"` | `"running"` |
| `"Exited"`, `"Finished"`, `"FinishedSuccessfully"` | `"stopped"` (normal terminal state for one-shot jobs — not a failure) |
| anything else | `"starting"` |

### Health categories

| Raw value | Category |
|---|---|
| `"Healthy"` | `"healthy"` |
| `"Unhealthy"`, `"Degraded"` | `"unhealthy"` |
| absent / other | `"unknown"` |

## `aspire stop --apphost <path>`

Stops (kills) the AppHost and all its managed resources.

```sh
aspire stop \
  --apphost /path/to/MyApp.AppHost.csproj \
  --non-interactive --nologo
```

This is the only destructive action the plugin offers, and it always sits
behind a confirmation dialog.  After `aspire stop`, the next `aspire ps` poll
will no longer list the AppHost, and the panel removes it automatically.

## `aspire resource <name> <command> --apphost <path>`

Runs an enabled lifecycle command on a single resource.

```sh
aspire resource cache restart \
  --apphost /path/to/MyApp.AppHost.csproj \
  --non-interactive --nologo
```

`<name>` is the resource's `name` field from `aspire describe` output.
`<command>` is the key in the `commands` object (e.g. `"restart"`, `"stop"`).
The plugin only calls commands Aspire itself reports as `"state": "Enabled"` —
it never hardcodes a fixed set.

## Aspire monitoring sub-skill

The `aspire-monitoring` sub-skill covers the Aspire OpenTelemetry / dashboard
side (traces, metrics, logs).  This plugin does **not** use the monitoring
stack — it is a pure CLI observer — so `aspire-monitoring` context is not
relevant here.

## Error handling conventions

- **Non-zero exit from `aspire ps`**: treat as a transient failure; keep the
  last good AppHost snapshot rather than resetting to empty.  Set
  `lastPollFailed = true` to dim the bar icon.
- **Non-zero exit from `aspire describe`**: surface the stderr text to the
  user as "Couldn't read resource status — \<stderr\>"; do not crash the panel.
- **Non-zero exit from `aspire stop` / `aspire resource`**: surface stderr
  text beneath the resource list.
- The CLI may output nothing (empty stdout) if the AppHost is shutting down
  mid-call; treat that as a parse failure (empty resource list), not as an
  error.
