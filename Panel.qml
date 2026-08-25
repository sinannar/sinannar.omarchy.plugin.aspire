import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details panel for the Aspire bar widget: one section per Aspire AppHost
// `aspire ps` currently reports running, each polling its own
// `aspire describe` while the panel is open. Resource action buttons are
// entirely data-driven from what Aspire reports as enabled for that
// resource — this file never hardcodes a start/stop/restart trio.
//
// Stopping an AppHost is the one destructive action offered here, and it is
// always behind a confirmation. Stopped AppHosts are not tracked or
// startable from this panel — BarWidget.qml's next `aspire ps` poll simply
// stops reporting them.
//
// BarWidget.qml owns AppHost discovery and hands this panel the button to
// anchor against plus the current running-AppHost list.
Panel {
  id: root
  moduleName: "sinannar.omarchy.plugin.aspire"
  ipcTarget: "sinannar.omarchy.plugin.aspire"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var runningAppHosts: []

  // Only one AppHost's resources are ever fetched at a time: the user picks
  // which running AppHost to inspect, and only that selection drives an
  // `aspire describe` call. This keeps the panel responsive with many
  // concurrently running AppHosts instead of polling every one of them.
  property string selectedAppHostId: ""

  readonly property var selectedEntry: {
    var list = root.runningAppHosts
    var id = root.selectedAppHostId
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  function selectAppHost(id) {
    root.selectedAppHostId = id
  }

  // If the selected AppHost stops (or nothing was selected yet), fall back
  // to the first still-running AppHost rather than showing a stale/blank
  // selection.
  onRunningAppHostsChanged: {
    if (root.runningAppHosts.length === 0) return
    for (var i = 0; i < root.runningAppHosts.length; i++) {
      if (root.runningAppHosts[i].id === root.selectedAppHostId) return
    }
    root.selectedAppHostId = root.runningAppHosts[0].id
  }

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Re-poll `aspire ps` the moment the panel is opened, so a bar count that
  // is up to pollIntervalSec stale never shows a stale AppHost list once the
  // user actually looks.
  function requestBarRefresh() {
    if (root.hostWidget && typeof root.hostWidget.refresh === "function") root.hostWidget.refresh()
  }

  // qs.Ui.Button and qs.Ui.ConfirmDialog currently render their own internal
  // Text nodes without forcing PlainText, so CLI/project-derived strings sent
  // through those APIs must be escaped before they reach those components.
  function escapeRichText(text) {
    var s = String(text === undefined || text === null ? "" : text)
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  onOpenedChanged: if (opened) requestBarRefresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: column.width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(14)

          Item {
            width: parent.width
            height: Math.max(titleColumn.implicitHeight, refreshBtn.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.right: refreshBtn.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: "Aspire"
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.runningAppHosts.length === 0
                  ? "No AppHosts running"
                  : root.runningAppHosts.length + " AppHost" + (root.runningAppHosts.length === 1 ? "" : "s") + " running"
                textFormat: Text.PlainText
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              id: refreshBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Refresh"
              fontFamily: root.contentFontFamily
              foreground: root.contentForeground
              bordered: true
              onClicked: root.requestBarRefresh()
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          AppHostPicker {
            visible: root.runningAppHosts.length > 0
            width: column.width
            appHosts: root.runningAppHosts
            selectedId: root.selectedAppHostId
            contentForeground: root.contentForeground
            contentFontFamily: root.contentFontFamily
            onSelectRequested: function(id) { root.selectAppHost(id) }
          }

          PanelSeparator {
            visible: root.runningAppHosts.length > 0
            foreground: root.contentForeground
            strength: 0.08
          }

          AppHostSection {
            visible: root.selectedEntry !== null
            width: column.width
            entry: root.selectedEntry
            panelOpen: root.opened
            bar: root.bar
            contentForeground: root.contentForeground
            contentFontFamily: root.contentFontFamily
            onAppHostStopped: root.requestBarRefresh()
          }

          Text {
            visible: root.runningAppHosts.length === 0
            width: parent.width
            text: root.hostWidget && root.hostWidget.lastPollFailed
              ? "The Aspire CLI is unavailable. Install it from aspire.dev, then refresh this widget."
              : "Start an AppHost with `aspire start`; it shows up here once Aspire reports it running."
            textFormat: Text.PlainText
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            visible: root.runningAppHosts.length === 0 && root.hostWidget && root.hostWidget.lastPollFailed
            text: "Install Aspire CLI"
            fontFamily: root.contentFontFamily
            foreground: root.contentForeground
            bordered: true
            onClicked: Qt.openUrlExternally("https://aspire.dev")
          }
        }
      }
    }
  }

  // Chip-style selector: one clickable item per currently running AppHost.
  // Clicking a chip emits selectRequested(id); the root Panel owns the
  // actual selection state (selectedAppHostId/selectedEntry).
  component AppHostPicker: Flow {
    id: picker

    property var appHosts: []
    property string selectedId: ""
    property color contentForeground: Color.foreground
    property string contentFontFamily: Style.font.family

    signal selectRequested(string id)

    spacing: Style.space(6)

    Repeater {
      model: picker.appHosts

      Rectangle {
        id: chip
        required property var modelData
        readonly property bool selected: modelData.id === picker.selectedId

        width: chipLabel.implicitWidth + Style.space(16)
        height: chipLabel.implicitHeight + Style.space(10)
        radius: Style.space(6)
        color: chip.selected ? Color.accent : "transparent"
        border.width: chip.selected ? 0 : 1
        border.color: Qt.darker(picker.contentForeground, 1.6)

        Text {
          id: chipLabel
          anchors.centerIn: parent
          text: chip.modelData.label
          textFormat: Text.PlainText
          color: chip.selected ? Color.popups.background : picker.contentForeground
          font.family: picker.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: picker.selectRequested(chip.modelData.id)
        }
      }
    }
  }

  // One AppHost's worth of detail: header (label, running/total, dashboard
  // link, stop-with-confirmation), then one ResourceRow per resource. Owns
  // its own describe/command/stop processes so one AppHost's slow CLI call
  // never blocks another's.
  component AppHostSection: Column {
    id: section

    // Not `required`: this is now a single long-lived instance whose entry
    // changes as the user switches which running AppHost is selected, rather
    // than one instance created per AppHost.
    property var entry: null
    property bool panelOpen: false
    property var bar: null
    property color contentForeground: Color.foreground
    property string contentFontFamily: Style.font.family

    property var describedResources: []
    property bool loading: false
    property bool loadFailed: false
    property string describeError: ""
    property bool confirmingStop: false
    property string pendingCommandKey: ""
    property string commandError: ""
    property string describeStdoutText: ""
    property string describeStderrText: ""
    property string commandStdoutText: ""
    property string commandStderrText: ""
    property string stopStdoutText: ""
    property string stopStderrText: ""

    // The AppHost path the currently in-flight describeProcess was launched
    // for, and whether another refresh was requested while it was running
    // (typically because the user switched the selected AppHost mid-flight).
    // Together these let onExited discard a response that no longer matches
    // the selection and immediately re-fetch for whichever AppHost is
    // actually selected now, instead of either applying stale data or
    // silently dropping the queued request.
    property string describeRequestPath: ""
    property bool refreshQueued: false

    signal appHostStopped()

    readonly property var summary: Model.summarizeResources(section.describedResources)
    readonly property string severity: Model.appHostSeverity(section.summary)
    readonly property color severityColor: section.severity === "critical"
      ? Color.urgent
      : (section.severity === "warning" ? Color.muted : section.contentForeground)

    spacing: Style.space(8)

    function refreshResources() {
      if (!section.entry) return
      if (describeProcess.running) {
        // Another describe call is already in flight (for this or a
        // previously selected AppHost). Queue this request rather than
        // dropping it — onExited re-issues it against whatever AppHost is
        // selected once the current call finishes.
        section.refreshQueued = true
        return
      }
      section.refreshQueued = false
      section.loading = true
      section.describeRequestPath = section.entry.appHostPath
      section.describeStdoutText = ""
      section.describeStderrText = ""
      describeProcess.command = Model.aspireCommand(Model.describeArgs(section.entry.appHostPath))
      describeProcess.running = true
    }

    function runCommand(resourceName, commandName) {
      if (!section.entry) return
      if (commandProcess.running) return
      section.pendingCommandKey = resourceName + ":" + commandName
      section.commandStdoutText = ""
      section.commandStderrText = ""
      commandProcess.command = Model.aspireCommand(Model.resourceCommandArgs(section.entry.appHostPath, resourceName, commandName))
      commandProcess.running = true
    }

    function performStop() {
      section.confirmingStop = false
      if (!section.entry) return
      if (stopProcess.running) return
      section.stopStdoutText = ""
      section.stopStderrText = ""
      stopProcess.command = Model.aspireCommand(Model.stopAppHostArgs(section.entry.appHostPath))
      stopProcess.running = true
    }

    // Switching the selected AppHost reuses this same instance, so stale
    // state from the previously selected host (its resources, any in-flight
    // error, a pending confirmation) must be cleared before fetching the
    // newly selected host's resources.
    onEntryChanged: {
      section.describedResources = []
      section.loadFailed = false
      section.describeError = ""
      section.commandError = ""
      section.confirmingStop = false
      section.pendingCommandKey = ""
      if (section.panelOpen && section.entry) section.refreshResources()
    }

    onPanelOpenChanged: if (section.panelOpen && section.entry) section.refreshResources()
    Component.onCompleted: if (section.panelOpen && section.entry) section.refreshResources()

    Timer {
      interval: 6000
      running: section.panelOpen
      repeat: true
      triggeredOnStart: true
      onTriggered: section.refreshResources()
    }

    Process {
      id: describeProcess
      environment: ({ "PATH": Model.augmentedPath(Quickshell.env("PATH"), Quickshell.env("HOME")) })
      stdout: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.describeStdoutText = Model.appendCapped(section.describeStdoutText, data) }
      }
      stderr: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.describeStderrText = Model.appendCapped(section.describeStderrText, data) }
      }
      onExited: function(exitCode) {
        section.loading = false
        // Only apply this result if the selection hasn't moved on to a
        // different AppHost since the request was launched; a stale
        // response is discarded rather than momentarily showing the wrong
        // AppHost's resources under the now-selected header.
        var stillSelected = section.entry !== null && section.entry.appHostPath === section.describeRequestPath
        if (stillSelected) {
          if (exitCode !== 0) {
            section.loadFailed = true
            section.describeError = section.describeStderrText.trim()
          } else if (Model.wasCapped(section.describeStdoutText) && Model.tryParseJson(section.describeStdoutText) === null) {
            // A capped response that fails to parse means real resource
            // data was truncated mid-stream, not that the AppHost has zero
            // resources. Keep the previously displayed resources instead of
            // letting parseDescribeResources's "malformed input -> []"
            // fallback blank the section.
            section.loadFailed = true
            section.describeError = "response too large to read in full; showing the last known resource list"
          } else {
            section.loadFailed = false
            section.describeError = ""
            section.describedResources = Model.parseDescribeResources(section.describeStdoutText)
          }
        }
        if (section.refreshQueued || !stillSelected) {
          section.refreshQueued = false
          section.refreshResources()
        }
      }
    }

    Process {
      id: commandProcess
      environment: ({ "PATH": Model.augmentedPath(Quickshell.env("PATH"), Quickshell.env("HOME")) })
      stdout: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.commandStdoutText = Model.appendCapped(section.commandStdoutText, data) }
      }
      stderr: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.commandStderrText = Model.appendCapped(section.commandStderrText, data) }
      }
      onExited: function(exitCode) {
        section.pendingCommandKey = ""
        section.commandError = exitCode !== 0 ? (section.commandStderrText || "Command failed").trim() : ""
        section.refreshResources()
      }
    }

    Process {
      id: stopProcess
      environment: ({ "PATH": Model.augmentedPath(Quickshell.env("PATH"), Quickshell.env("HOME")) })
      stdout: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.stopStdoutText = Model.appendCapped(section.stopStdoutText, data) }
      }
      stderr: SplitParser {
        splitMarker: ""
        onRead: function(data) { section.stopStderrText = Model.appendCapped(section.stopStderrText, data) }
      }
      onExited: function(exitCode) {
        section.commandError = exitCode !== 0 ? (section.stopStderrText || "Stop failed").trim() : ""
        section.appHostStopped()
      }
    }

    Item {
      width: parent.width
      height: Math.max(headerLabels.implicitHeight, headerActions.implicitHeight)

      Row {
        id: headerLabels
        anchors.left: parent.left
        anchors.right: headerActions.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(8)
          height: Style.space(8)
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: section.severityColor
        }

        Text {
          text: section.entry ? section.entry.label : ""
          textFormat: Text.PlainText
          color: section.contentForeground
          font.family: section.contentFontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          text: "· " + section.summary.running + "/" + section.summary.total + " running"
          textFormat: Text.PlainText
          color: Qt.darker(section.contentForeground, 1.4)
          font.family: section.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Button {
          visible: section.entry !== null && section.entry.dashboardUrl !== ""
          text: "Dashboard"
          fontFamily: section.contentFontFamily
          foreground: section.contentForeground
          fontSize: Style.font.caption
          bordered: true
          onClicked: if (section.entry) Qt.openUrlExternally(section.entry.dashboardUrl)
        }

        Button {
          text: "Stop"
          fontFamily: section.contentFontFamily
          foreground: Color.urgent
          fontSize: Style.font.caption
          bordered: true
          onClicked: section.confirmingStop = true
        }
      }
    }

    Text {
      width: parent.width
      text: section.entry ? section.entry.appHostPath : ""
      textFormat: Text.PlainText
      color: Qt.darker(section.contentForeground, 1.6)
      font.family: section.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }

    Text {
      // Shown only while nothing is known yet for the selected AppHost, so
      // switching to one whose resources haven't loaded doesn't read as
      // silently empty.
      visible: section.loading && section.describedResources.length === 0 && !section.loadFailed
      width: parent.width
      text: "Loading resources…"
      textFormat: Text.PlainText
      color: Qt.darker(section.contentForeground, 1.4)
      font.family: section.contentFontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: section.loadFailed
      width: parent.width
      text: section.describeError !== ""
        ? "Couldn't read resource status: " + section.describeError
        : "Couldn't read resource status for this AppHost."
      textFormat: Text.PlainText
      color: Color.urgent
      font.family: section.contentFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      visible: section.commandError !== ""
      width: parent.width
      text: section.commandError
      textFormat: Text.PlainText
      color: Color.urgent
      font.family: section.contentFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      visible: !section.loading && !section.loadFailed && section.describedResources.length === 0
      width: parent.width
      text: "No resources reported."
      textFormat: Text.PlainText
      color: Qt.darker(section.contentForeground, 1.5)
      font.family: section.contentFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: section.describedResources

      ResourceRow {
        required property var modelData
        width: section.width
        resource: modelData
        appHostSection: section
      }
    }

    ConfirmDialog {
      width: parent.width
      height: Style.space(180)
      opened: section.confirmingStop
      message: "Stop " + root.escapeRichText(section.entry ? section.entry.label : "this AppHost") + "? This stops the whole AppHost and every resource it owns."
      cancelText: "Cancel"
      confirmText: "Stop"
      background: Color.popups.background
      foreground: section.contentForeground
      fontFamily: section.contentFontFamily
      onCanceled: section.confirmingStop = false
      onConfirmed: section.performStop()
    }
  }

  // One resource's row: name/type, state/health, http(s) endpoint links, and
  // whichever commands Aspire currently reports as enabled for it.
  component ResourceRow: Column {
    id: row

    required property var resource
    // Named distinctly from the outer AppHostSection's `id: section` so this
    // property never shadows that id within this component's own bindings
    // (a `required property var section` here previously made every
    // unqualified `section.*` reference resolve to this not-yet-set
    // property instead of the outer section, leaving resources unrendered).
    required property var appHostSection

    readonly property color fg: appHostSection.contentForeground
    readonly property color stateColor: row.resource.stateCategory === "failed"
      ? Color.urgent
      : (row.resource.healthCategory === "unhealthy" ? Color.muted : Qt.darker(row.fg, 1.15))
    readonly property bool commandPending: row.appHostSection.pendingCommandKey !== ""
      && row.appHostSection.pendingCommandKey.indexOf(row.resource.name + ":") === 0

    spacing: Style.space(4)

    Item {
      width: parent.width
      height: Math.max(nameCol.implicitHeight, stateText.implicitHeight)

      Column {
        id: nameCol
        anchors.left: parent.left
        anchors.right: stateText.left
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(1)

        Text {
          text: row.resource.displayName
          textFormat: Text.PlainText
          color: row.fg
          font.family: row.appHostSection.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: row.resource.resourceType
          textFormat: Text.PlainText
          color: Qt.darker(row.fg, 1.5)
          font.family: row.appHostSection.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        id: stateText
        anchors.right: parent.right
        anchors.top: parent.top
        text: row.resource.healthCategory === "unhealthy"
          ? (row.resource.state + " · " + row.resource.healthStatus)
          : row.resource.state
        textFormat: Text.PlainText
        color: row.stateColor
        font.family: row.appHostSection.contentFontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
      }
    }

    Flow {
      visible: row.resource.urls.length > 0
      width: parent.width
      spacing: Style.space(12)

      Repeater {
        model: row.resource.urls

        Text {
          id: linkText
          required property var modelData
          // The endpoint's "name" is often just its scheme ("http"/"https"),
          // which the URL itself already shows — skip that redundant
          // prefix and only label endpoints whose name adds information
          // beyond the scheme (e.g. a named secondary port).
          readonly property bool nameIsScheme: modelData.name !== ""
            && modelData.url.toLowerCase().indexOf(modelData.name.toLowerCase() + "://") === 0
          text: modelData.name !== "" && !nameIsScheme ? modelData.name + ": " + modelData.url : modelData.url
          textFormat: Text.PlainText
          color: Color.accent
          font.family: row.appHostSection.contentFontFamily
          font.pixelSize: Style.font.caption
          font.underline: linkMouse.containsMouse

          MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(linkText.modelData.url)
          }
        }
      }
    }

    Flow {
      visible: row.resource.commands.length > 0
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: row.resource.commands

        Button {
          required property var modelData
          text: row.commandPending && row.appHostSection.pendingCommandKey === (row.resource.name + ":" + modelData.name)
            ? root.escapeRichText(modelData.displayName + "…")
            : root.escapeRichText(modelData.displayName)
          tooltipText: root.escapeRichText(modelData.description)
          fontFamily: row.appHostSection.contentFontFamily
          foreground: row.fg
          fontSize: Style.font.caption
          bordered: true
          enabled: !row.commandPending
          onClicked: row.appHostSection.runCommand(row.resource.name, modelData.name)
        }
      }
    }

    PanelSeparator {
      foreground: row.fg
      strength: 0.08
    }
  }
}
