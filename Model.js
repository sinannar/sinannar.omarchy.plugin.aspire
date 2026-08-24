// Pure JSON-normalization and aggregation math for the Aspire widget and its
// details panel. Everything here is Qt-free so it can be unit tested under
// node; the QML owns process invocation, polling, and rendering only.
//
// Scope is deliberately narrow: only AppHosts that `aspire ps` currently
// reports as running are ever shown or acted on. Stopped AppHosts are never
// tracked, configured, or started from here.

function tryParseJson(text) {
  try {
    return JSON.parse(String(text === undefined || text === null ? "" : text))
  } catch (e) {
    return null
  }
}

// ---- `aspire ps --format Json` -------------------------------------------

function isRunningPsEntry(entry) {
  return !!entry && String(entry.status || "").toLowerCase() === "running"
}

// Stable identity for a running AppHost: the project path is unique per
// checkout, and falls back to the AppHost pid on the rare entry missing one.
function psEntryId(entry) {
  if (!entry) return ""
  var path = String(entry.appHostPath || "")
  if (path !== "") return path
  return "pid:" + String(entry.appHostPid || "")
}

// Short label for the bar/panel: the AppHost project's own name with the
// conventional ".AppHost" suffix trimmed, so "app1.AppHost.csproj" reads as
// "app1" rather than repeating project-naming boilerplate.
function appHostLabel(appHostPath) {
  var path = String(appHostPath || "")
  if (path === "") return "AppHost"
  var base = path.split("/").pop().split("\\").pop()
  var dot = base.lastIndexOf(".")
  var name = dot > 0 ? base.substring(0, dot) : base
  if (/\.AppHost$/i.test(name)) name = name.substring(0, name.length - ".AppHost".length)
  return name === "" ? base : name
}

// Parses `aspire ps --format Json` output into the running-only entries this
// plugin ever tracks, sorted by label so the panel order is stable across
// refreshes rather than following process-start order.
function parsePsRunning(jsonText) {
  var parsed = tryParseJson(jsonText)
  var entries = Array.isArray(parsed) ? parsed : []
  var running = []
  for (var i = 0; i < entries.length; i++) {
    if (!isRunningPsEntry(entries[i])) continue
    var entry = entries[i]
    running.push({
      id: psEntryId(entry),
      appHostPath: String(entry.appHostPath || ""),
      appHostPid: entry.appHostPid,
      label: appHostLabel(entry.appHostPath),
      dashboardUrl: typeof entry.dashboardUrl === "string" ? entry.dashboardUrl : "",
      sdkVersion: String(entry.sdkVersion || "")
    })
  }
  running.sort(function(a, b) { return a.label === b.label ? 0 : (a.label < b.label ? -1 : 1) })
  return running
}

// ---- `aspire describe --apphost <path> --format Json` --------------------

// States Aspire reports as a resource having failed to come up or having
// stayed up. "Exited"/"Finished" are left out on purpose: those are the
// normal terminal state for a one-shot resource (a migration, a seed job),
// not a failure.
function classifyResourceState(state) {
  var s = String(state || "").toLowerCase()
  if (s === "") return "unknown"
  if (s.indexOf("fail") !== -1) return "failed"
  if (s === "running") return "running"
  if (s === "exited" || s === "finished" || s === "finishedsuccessfully") return "stopped"
  return "starting"
}

function classifyHealth(healthStatus) {
  var h = String(healthStatus || "").toLowerCase()
  if (h === "healthy") return "healthy"
  if (h === "unhealthy") return "unhealthy"
  if (h === "degraded") return "unhealthy"
  return "unknown"
}

// Only http/https endpoints are surfaced. Other URL schemes (tcp, rediss,
// amqp, ...) can carry embedded credentials for some resource types, so they
// are left out of the details panel entirely rather than filtered value by
// value.
function safeUrls(raw) {
  var urls = Array.isArray(raw && raw.urls) ? raw.urls : []
  var result = []
  for (var i = 0; i < urls.length; i++) {
    var u = urls[i]
    if (!u || typeof u.url !== "string") continue
    if (!/^https?:\/\//i.test(u.url)) continue
    result.push({ name: String(u.name || ""), url: u.url })
  }
  return result
}

// Resource action buttons are entirely data-driven: only commands Aspire
// itself reports as "Enabled" are ever offered, and never a hardcoded
// start/stop/restart trio. Sorted by Aspire's own sortOrder so the dashboard
// and this panel agree on button order.
function enabledCommands(raw) {
  var commands = raw && raw.commands && typeof raw.commands === "object" ? raw.commands : {}
  var list = []
  for (var name in commands) {
    if (!Object.prototype.hasOwnProperty.call(commands, name)) continue
    var c = commands[name]
    if (!c || String(c.state) !== "Enabled") continue
    var order = Number(c.sortOrder)
    list.push({
      name: String(name),
      displayName: String(c.displayName || name),
      description: String(c.description || ""),
      sortOrder: isFinite(order) ? order : 999
    })
  }
  list.sort(function(a, b) { return a.sortOrder - b.sortOrder })
  return list
}

function normalizeResource(raw) {
  if (!raw || typeof raw !== "object") return null
  var state = String(raw.state || "")
  var health = raw.healthStatus === undefined || raw.healthStatus === null ? "" : String(raw.healthStatus)
  return {
    name: String(raw.name || ""),
    displayName: String(raw.displayName || raw.name || ""),
    resourceType: String(raw.resourceType || ""),
    state: state,
    stateCategory: classifyResourceState(state),
    healthStatus: health,
    healthCategory: classifyHealth(health),
    dashboardUrl: typeof raw.dashboardUrl === "string" ? raw.dashboardUrl : "",
    urls: safeUrls(raw),
    commands: enabledCommands(raw)
  }
}

// Parses `aspire describe --format Json` into the normalized resource list
// for one AppHost. Missing/malformed input yields an empty list rather than
// throwing, so a transient CLI hiccup degrades to "no resources known" for
// that AppHost instead of breaking the whole panel.
function parseDescribeResources(jsonText) {
  var parsed = tryParseJson(jsonText)
  var raw = parsed && Array.isArray(parsed.resources) ? parsed.resources : []
  var resources = []
  for (var i = 0; i < raw.length; i++) {
    var resource = normalizeResource(raw[i])
    if (resource) resources.push(resource)
  }
  return resources
}

// ---- Aggregation -----------------------------------------------------------

function summarizeResources(resources) {
  var list = Array.isArray(resources) ? resources : []
  var summary = { total: list.length, running: 0, failed: 0, unhealthy: 0, starting: 0, stopped: 0 }
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (r.stateCategory === "running") summary.running++
    else if (r.stateCategory === "failed") summary.failed++
    else if (r.stateCategory === "stopped") summary.stopped++
    else summary.starting++
    if (r.healthCategory === "unhealthy") summary.unhealthy++
  }
  return summary
}

// One severity per AppHost: "critical" if anything failed to start,
// "warning" if something is running but unhealthy, "ok" otherwise.
function appHostSeverity(summary) {
  if (!summary) return "ok"
  if (summary.failed > 0) return "critical"
  if (summary.unhealthy > 0) return "warning"
  return "ok"
}

// Combines one `aspire ps` entry with its already-fetched resource list into
// the view model the panel renders one section from.
function buildAppHostView(psEntry, resources) {
  var list = Array.isArray(resources) ? resources : []
  var summary = summarizeResources(list)
  return {
    id: psEntry.id,
    label: psEntry.label,
    appHostPath: psEntry.appHostPath,
    dashboardUrl: psEntry.dashboardUrl,
    resources: list,
    summary: summary,
    severity: appHostSeverity(summary)
  }
}

// The worst severity across every running AppHost, for the bar icon's color.
function overallSeverity(appHostViews) {
  var list = Array.isArray(appHostViews) ? appHostViews : []
  var worst = "ok"
  for (var i = 0; i < list.length; i++) {
    if (list[i].severity === "critical") return "critical"
    if (list[i].severity === "warning") worst = "warning"
  }
  return worst
}

// Bar label is just the running-AppHost count; the icon glyph carries the
// "this is Aspire" meaning and severity is conveyed by color, not by
// cramming detail into the two or three characters the bar has room for.
function barCountText(appHostViews) {
  var count = Array.isArray(appHostViews) ? appHostViews.length : 0
  return String(count)
}

// ---- Aspire CLI argument builders -----------------------------------------
//
// Pure so the exact argv the widget invokes can be asserted in tests. Every
// call that targets a specific AppHost passes --apphost explicitly so a
// command can never drift onto a different running AppHost, and
// --non-interactive/--nologo keep the CLI script-friendly.

function psArgs() {
  return ["ps", "--format", "Json", "--non-interactive", "--nologo"]
}

function describeArgs(appHostPath) {
  return ["describe", "--apphost", String(appHostPath), "--format", "Json", "--non-interactive", "--nologo"]
}

function stopAppHostArgs(appHostPath) {
  return ["stop", "--apphost", String(appHostPath), "--non-interactive", "--nologo"]
}

function resourceCommandArgs(appHostPath, resourceName, commandName) {
  return ["resource", String(resourceName), String(commandName), "--apphost", String(appHostPath), "--non-interactive", "--nologo"]
}

// Routed through the fixed, always-resolvable /usr/bin/env rather than a bare
// "aspire" argv[0]: Quickshell's Process resolves argv[0] against the
// process's *inherited* PATH before applying the `environment` property
// override below, so a bare "aspire" fails to even launch when the plugin's
// own PATH lacks the CLI's install directory. /usr/bin/env then re-resolves
// "aspire" itself, but against the overridden PATH handed to the child
// process (see augmentedPath), which is what actually contains it.
function aspireCommand(args) {
  return ["/usr/bin/env", "aspire"].concat(args)
}

// The bar/panel's own process environment is not guaranteed to include every
// directory a user's interactive shell adds to PATH (e.g. `~/.dotnet/tools`,
// where `dotnet tool install -g` and the Aspire CLI installer both put their
// binaries) — non-interactive shells commonly skip that part of ~/.bashrc
// entirely. Rather than depend on shell rc semantics, append the well-known
// Aspire/.NET tool locations directly to whatever PATH was inherited, so
// `aspire` resolves the same way it would from a terminal.
function augmentedPath(currentPath, home) {
  var extra = home ? [home + "/.dotnet", home + "/.dotnet/tools", home + "/.local/bin"] : []
  var existing = String(currentPath || "").split(":").filter(function (p) { return p.length > 0 })
  var seen = {}
  var result = []
  existing.concat(extra).forEach(function (p) {
    if (!seen[p]) {
      seen[p] = true
      result.push(p)
    }
  })
  return result.join(":")
}

if (typeof module !== "undefined") {
  module.exports = {
    tryParseJson: tryParseJson,
    isRunningPsEntry: isRunningPsEntry,
    psEntryId: psEntryId,
    appHostLabel: appHostLabel,
    parsePsRunning: parsePsRunning,
    classifyResourceState: classifyResourceState,
    classifyHealth: classifyHealth,
    safeUrls: safeUrls,
    enabledCommands: enabledCommands,
    normalizeResource: normalizeResource,
    parseDescribeResources: parseDescribeResources,
    summarizeResources: summarizeResources,
    appHostSeverity: appHostSeverity,
    buildAppHostView: buildAppHostView,
    overallSeverity: overallSeverity,
    barCountText: barCountText,
    psArgs: psArgs,
    describeArgs: describeArgs,
    stopAppHostArgs: stopAppHostArgs,
    resourceCommandArgs: resourceCommandArgs,
    augmentedPath: augmentedPath,
    aspireCommand: aspireCommand
  }
}
