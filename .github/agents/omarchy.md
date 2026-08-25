# Omarchy / Quickshell plugin knowledge

## What Omarchy is

Omarchy is a minimal, opinionated Linux desktop environment built on Wayland.
Its shell layer is [Quickshell](https://quickshell.de/) — a QML-based
compositor shell.  Plugins extend the shell's status bar (and optionally pop
up panels) without modifying core shell code.

## Plugin manifest (`manifest.json`)

Every plugin must declare at least:

```json
{
  "schemaVersion": 1,
  "id": "<author>.<pluginName>",
  "name": "Human-readable name",
  "version": "1.0.0",
  "author": "<author>",
  "license": "MIT",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "...",
    "description": "...",
    "category": "Development",
    "allowMultiple": false
  }
}
```

`id` must be globally unique (by convention `<author>.<pluginName>`).
`allowMultiple: false` prevents the user from adding the widget twice.

## QML module imports used in this plugin

```qml
import QtQuick
import Quickshell
import Quickshell.Io    // Process, StdioCollector
import qs.Commons       // Color, Style, Quickshell.env()
import qs.Ui            // BarWidget, Panel, KeyboardPanel, WidgetButton, …
```

`qs.Commons` and `qs.Ui` are Omarchy-internal modules, not Qt-standard ones.

## `BarWidget` root component

Every bar-widget plugin's entry-point QML file must have `BarWidget` as its
root component (from `qs.Ui`).  Key properties inherited from `BarWidget`:

| Property | Type | Description |
|---|---|---|
| `moduleName` | `string` | Must match `manifest.json` `id`. |
| `bar` | `Bar` | The bar this widget lives in (color, font, IPC target, …). |
| `settings` | `object` | Per-widget settings persisted in `~/.config/omarchy/shell.json`. |

Helper: `setting(key, default)` — reads a typed setting value; numbers need
`--json` when set via CLI.

Sizing convention: set `implicitWidth`/`implicitHeight` from the inner button,
and bind `visible` to the button's `hasVisualContent` so the bar only reserves
space when the widget has something to show.

## `Panel` and `KeyboardPanel`

`Panel` (from `qs.Ui`) is the floating popup that the bar widget opens.  It
must be loaded lazily via a `Loader` in `BarWidget.qml` so it does not block
bar startup.

Key properties set by `BarWidget.qml` on the panel (via `injectPanel()`):

| Property | Set to |
|---|---|
| `bar` | The bar object |
| `settings` | Widget settings |
| `anchorItem` | The bar button used as anchor point |
| `hostWidget` | The `BarWidget` root (for calling `refresh()`) |
| `runningAppHosts` | The list computed by the widget |

`KeyboardPanel` (inner wrapper inside `Panel`) provides: focus management,
size clamping (`fittedContentWidth` / `fittedContentHeight`), anchor, and
keyboard close/tab support via `PanelKeyCatcher`.

## `IpcHandler`

```qml
IpcHandler {
  target: "<module-id>"

  function refresh(): void { … }
  function open(): void    { … }
  function close(): void   { … }
  function show(): void    { … }
  function hide(): void    { … }
  function toggle(): void  { … }
}
```

Called from the command line with:
`omarchy-shell <module-id> <functionName>`

Only one `IpcHandler` per plugin should manage IPC (`manageIpc: false` on
`Panel` suppresses the duplicate).

## `Process` and `StdioCollector` (Quickshell.Io)

```qml
Process {
  id: myProcess
  command: ["/usr/bin/env", "aspire", ...args]   // argv array — NOT a shell string
  environment: ({ "PATH": "..." })               // override child env vars

  stdout: StdioCollector { id: myStdout; waitForEnd: true }
  stderr: StdioCollector { id: myStderr; waitForEnd: true }

  onExited: function(exitCode) {
    // myStdout.text and myStderr.text are fully populated here
  }
}

// Start by flipping `running`:
myProcess.running = true
```

`waitForEnd: true` on `StdioCollector` buffers all output until the process
exits, so `text` is complete inside `onExited`.

**PATH resolution order**: `command[0]` is resolved against the *inherited*
PATH **before** the `environment` override is applied.  Always use
`["/usr/bin/env", "<binary>", ...args]` so `/usr/bin/env` (always reachable)
does the re-resolution after the PATH override takes effect.

## Settings

Set externally with:
```sh
omarchy bar set <module-id> <key> <value>
omarchy bar set <module-id> <key> <value> --json   # numeric/boolean values
```

Read inside QML with `setting("key", defaultValue)`.

## Lifecycle management CLI

```sh
omarchy plugin add <git-url> [--enable]
omarchy plugin remove <module-id>
omarchy plugin list [--json]
omarchy plugin validate <plugin-dir>
omarchy bar move <module-id> --section <left|center|right>
omarchy-shell <module-id> <ipc-action>
```

## Validation

```sh
omarchy plugin validate ~/.config/omarchy/plugins/<module-id>
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

These two commands together catch manifest schema errors and QML type
violations respectively.  Run them (via `checks/validate.sh`) before
every commit that touches QML or `manifest.json`.

## Color and style helpers (qs.Commons / qs.Ui)

| Symbol | Description |
|---|---|
| `Color.foreground` | Default bar foreground colour |
| `Style.font.family` | Default bar font |
| `Style.space(n)` | Scale-aware pixel size (pass logical pixels) |
| `bar.foreground` | Bar-specific foreground (prefer over `Color.foreground` when `bar` is non-null) |
| `bar.fontFamily` | Bar-specific font family |
| `Qt.darker(color, factor)` | Darken a colour (used to dim the icon when CLI is unavailable) |
