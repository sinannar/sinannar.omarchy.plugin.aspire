import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar presence for locally running Aspire AppHosts. This widget only
// ever tracks AppHosts `aspire ps` currently reports as running — it never
// remembers, configures, or starts a stopped one. Left click opens the
// details panel; middle click forces an immediate refresh.
//
// BarWidget.qml owns AppHost discovery (aspire ps) and hands the resolved
// list of running AppHosts to Panel.qml, which owns per-AppHost resource
// detail (aspire describe) and lifecycle actions.
BarWidget {
  id: root
  moduleName: "sinannar.omarchy.plugin.aspire"

  readonly property int pollIntervalSec: Math.max(5, Number(setting("pollIntervalSec", 15)))

  // Raw `aspire ps` results, running AppHosts only. Kept even while a
  // refresh is in flight so the bar never blanks out mid-poll.
  property var runningAppHosts: []
  property bool lastPollFailed: false
  property bool everPolled: false

  readonly property string countText: Model.barCountText(runningAppHosts)
  readonly property bool hasAppHosts: runningAppHosts.length > 0

  // Bar glyph carries "this is Aspire"; color carries severity. Panel.qml
  // recomputes the same severity per-AppHost from its own describe calls,
  // so the two surfaces agree without this widget having to fetch describe
  // data it would not otherwise use.
  readonly property color statusColor: {
    if (!everPolled || lastPollFailed) return Qt.darker(bar ? bar.foreground : Color.foreground, 1.5)
    return bar ? bar.foreground : Color.foreground
  }

  function refresh() {
    if (psProcess.running) return
    psProcess.running = true
  }

  Process {
    id: psProcess
    command: Model.aspireCommand(Model.psArgs())
    environment: ({ "PATH": Model.augmentedPath(Quickshell.env("PATH"), Quickshell.env("HOME")) })

    stdout: StdioCollector {
      id: psStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: psStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.everPolled = true
      if (exitCode !== 0) {
        // Keep the last good snapshot on a transient CLI error (Docker down,
        // aspire not installed anymore, etc.) rather than flashing to empty.
        root.lastPollFailed = true
        return
      }
      root.lastPollFailed = false
      root.runningAppHosts = Model.parsePsRunning(psStdout.text)
    }
  }

  Timer {
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("runningAppHosts" in target) target.runningAppHosts = root.runningAppHosts
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onRunningAppHostsChanged: injectPanel()

  Component.onCompleted: refresh()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "sinannar.omarchy.plugin.aspire"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Rocket-launch glyph (nf-md-rocket_launch_outline) stands in for
    // Aspire itself; the number beside it is the running-AppHost count.
    text: "󱓟 " + root.countText
    foreground: root.statusColor
    // The widget only earns bar space once there is something to show —
    // matching how other data-driven widgets here (agents, system-update)
    // collapse out of the bar rather than sit there empty.
    hasVisualContent: root.hasAppHosts || root.lastPollFailed
    tooltipText: root.lastPollFailed
      ? "Aspire CLI unavailable — click to retry"
      : (root.hasAppHosts
        ? root.countText + " Aspire AppHost" + (root.runningAppHosts.length === 1 ? "" : "s") + " running"
        : "No Aspire AppHosts running")

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
