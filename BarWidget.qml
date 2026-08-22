import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.nag3sy.fpl-tracker"

  property string teamId: ""
  property bool editingId: false
  property string currentTab: "overview" // "overview" | "squad" | "settings"
  property bool showPointsInBar: false
  property var hiddenLeagueIds: []

  property var entryData: null
  property var picksData: null
  property var bootstrapEvents: []
  property var elementsById: ({})
  property var teamsById: ({})
  property var elementTypesById: ({})
  property var liveElementsById: ({})
  property var historyCurrent: []
  property var bootstrapChips: []
  property var historyChips: []

  // Incremented/decremented around the fast-cycle requests (entry, picks,
  // live elements) only — bootstrap/history are background refreshes and
  // shouldn't drive the popup's "Updating…" spinner or last-updated time.
  property int pendingRequests: 0
  readonly property bool refreshing: pendingRequests > 0
  readonly property bool loading: refreshing && !entryData
  property string errorMessage: ""
  property var lastUpdated: null

  property int refreshIntervalMs: 90000

  property bool popupOpen: false
  function close() { popupOpen = false }

  readonly property int currentEventId: entryData ? entryData.current_event : 0
  readonly property var currentEventMeta: Model.findEvent(bootstrapEvents, currentEventId)
  readonly property var nextEventMeta: Model.findNextEvent(bootstrapEvents)
  readonly property string eventStatus: Model.eventStatus(currentEventMeta)

  // `picksData.entry_history` (the picks endpoint) only updates on FPL's
  // periodic backend recalculation and visibly lags during live play — a
  // captain who has scored shows up doubled in `entryData.summary_event_*`
  // (the entry endpoint, refetched on the same cadence) well before
  // `entry_history` catches up. Prefer the entry endpoint for anything that
  // changes during a match; `entry_history` only remains authoritative for
  // fields the entry endpoint doesn't expose at all (bench points as a
  // fallback, transfer cost, which is fixed at the deadline anyway).
  readonly property var entryHistory: picksData ? picksData.entry_history : null
  readonly property var livePoints: entryData ? entryData.summary_event_points : null
  readonly property var gwRank: entryData ? entryData.summary_event_rank : null
  readonly property var benchPoints: {
    var computed = Model.sumBenchPoints(squadRows)
    return computed !== null ? computed : (entryHistory ? entryHistory.points_on_bench : null)
  }
  readonly property var transferCost: entryHistory ? entryHistory.event_transfers_cost : 0
  readonly property string activeChip: picksData && picksData.active_chip ? picksData.active_chip : ""
  readonly property var chipStatuses: Model.chipStatuses(bootstrapChips, historyChips, currentEventId)

  readonly property var overallRank: entryData ? entryData.summary_overall_rank : null
  readonly property var overallPoints: entryData ? entryData.summary_overall_points : null
  readonly property var teamValue: entryData ? entryData.last_deadline_value : null
  readonly property var bank: entryData ? entryData.last_deadline_bank : null
  readonly property var leagues: Model.classicLeagues(entryData)
  readonly property var settingsLeagueList: Model.leaguesForSettings(entryData)
  readonly property var visibleLeagues: leagues.filter(function(l) { return root.hiddenLeagueIds.indexOf(l.id) < 0 })
  readonly property bool showOverallStats: hiddenLeagueIds.indexOf("overall") < 0

  // LiveFPL-style rank movement: current live overall rank vs the last
  // *completed* gameweek's final overall rank. Null on gameweek 1 (or
  // before history has loaded) since there's nothing to compare against yet.
  readonly property var previousHistoryEntry: Model.previousHistoryEntry(historyCurrent, currentEventId)
  readonly property var previousOverallRank: previousHistoryEntry ? previousHistoryEntry.overall_rank : null
  readonly property var rankDelta: (previousOverallRank && overallRank) ? (previousOverallRank - overallRank) : null
  readonly property var rankPercent: (rankDelta !== null && previousOverallRank) ? (rankDelta / previousOverallRank * 100) : null

  readonly property var squadRows: Model.squadRows(picksData, elementsById, teamsById, elementTypesById, liveElementsById)
  readonly property var startingRows: squadRows.filter(function(r) { return !r.onBench })
  readonly property var benchRows: squadRows.filter(function(r) { return r.onBench })

  // ---- persistence ------------------------------------------------------

  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/fpl-tracker.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
  }

  function applyConfig(raw) {
    try {
      var cfg = JSON.parse(raw || "{}")
      if (cfg.teamId && Model.isValidTeamId(cfg.teamId)) root.teamId = String(cfg.teamId)
      if (typeof cfg.showPointsInBar === "boolean") root.showPointsInBar = cfg.showPointsInBar
      if (Array.isArray(cfg.hiddenLeagueIds)) root.hiddenLeagueIds = cfg.hiddenLeagueIds
    } catch (e) {
      // Corrupt state file — fall back to the unconfigured setup prompt.
    }
  }

  function persistConfig() {
    configFile.setText(JSON.stringify({
      teamId: root.teamId,
      showPointsInBar: root.showPointsInBar,
      hiddenLeagueIds: root.hiddenLeagueIds
    }, null, 2) + "\n")
  }

  function toggleLeagueHidden(leagueId) {
    var hidden = root.hiddenLeagueIds.slice()
    var idx = hidden.indexOf(leagueId)
    if (idx >= 0) hidden.splice(idx, 1)
    else hidden.push(leagueId)
    root.hiddenLeagueIds = hidden
    root.persistConfig()
  }

  function saveTeamId(value) {
    var digits = String(value || "").replace(/[^0-9]/g, "")
    if (!Model.isValidTeamId(digits)) return
    root.editingId = false
    root.currentTab = "overview"
    root.entryData = null
    root.picksData = null
    root.liveElementsById = {}
    root.historyCurrent = []
    root.errorMessage = ""
    root.teamId = digits
    root.persistConfig()
    root.refreshAll()
  }

  function setShowPointsInBar(value) {
    root.showPointsInBar = value
    root.persistConfig()
  }

  // ---- fetching -----------------------------------------------------------
  // Every FPL entry endpoint updates live during a gameweek (bonus points
  // included), so the live picture here is just "poll the official API" —
  // no client-side scoring or auto-sub math needed. Per-player captain
  // contribution is live points × `multiplier`, which FPL itself already
  // resolves correctly (2x/3x captain, vice-captain fallback, bench).

  function beginRequest() { root.pendingRequests++ }
  function endRequest() {
    root.pendingRequests = Math.max(0, root.pendingRequests - 1)
    if (root.pendingRequests === 0) root.lastUpdated = new Date()
  }

  function fetchBootstrap() {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) return
      try {
        if (xhr.responseText.length > 8000000) return
        var data = JSON.parse(xhr.responseText)
        root.bootstrapEvents = data.events || []
        root.elementsById = Model.indexById(data.elements)
        root.teamsById = Model.indexById(data.teams)
        root.elementTypesById = Model.indexById(data.element_types)
        root.bootstrapChips = data.chips || []
      } catch (e) {
        // Leave the previous data in place.
      }
    }
    xhr.open("GET", Model.bootstrapUrl())
    xhr.timeout = 15000
    xhr.send()
  }

  function fetchHistory() {
    if (!Model.isValidTeamId(root.teamId)) return
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) return
      try {
        if (xhr.responseText.length > 2000000) return
        var data = JSON.parse(xhr.responseText)
        root.historyCurrent = data.current || []
        root.historyChips = data.chips || []
      } catch (e) {
        // Leave the previous history in place.
      }
    }
    xhr.open("GET", Model.historyUrl(root.teamId))
    xhr.timeout = 10000
    xhr.send()
  }

  function fetchLiveElements(eventId) {
    root.beginRequest()
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > 3000000) throw "too large"
          var data = JSON.parse(xhr.responseText)
          root.liveElementsById = Model.indexById(data.elements)
        } catch (e) {
          // Keep whatever live data we already had.
        }
      }
    }
    xhr.ontimeout = function() { root.endRequest() }
    xhr.open("GET", Model.liveUrl(eventId))
    xhr.timeout = 12000
    xhr.send()
  }

  function fetchPicks(eventId) {
    root.beginRequest()
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > 500000) throw "too large"
          root.picksData = JSON.parse(xhr.responseText)
        } catch (e) {
          // Keep whatever picks data we already had.
        }
      }
    }
    xhr.ontimeout = function() { root.endRequest() }
    xhr.open("GET", Model.picksUrl(root.teamId, eventId))
    xhr.timeout = 10000
    xhr.send()
  }

  function fetchEntry() {
    if (!Model.isValidTeamId(root.teamId)) return
    root.beginRequest()
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > 2000000) throw "too large"
          var data = JSON.parse(xhr.responseText)
          root.entryData = data
          root.errorMessage = ""
          if (data.current_event) {
            root.fetchPicks(data.current_event)
            root.fetchLiveElements(data.current_event)
          }
        } catch (e) {
          root.errorMessage = "Couldn't read FPL data"
        }
      } else if (xhr.status === 404) {
        root.errorMessage = "Team ID not found"
      } else {
        root.errorMessage = "FPL is unreachable"
      }
    }
    xhr.ontimeout = function() {
      root.endRequest()
      root.errorMessage = "FPL request timed out"
    }
    xhr.open("GET", Model.entryUrl(root.teamId))
    xhr.timeout = 10000
    xhr.send()
  }

  function refreshAll() {
    if (root.teamId === "") return
    root.fetchEntry()
  }

  onTeamIdChanged: {
    if (teamId === "") return
    fetchBootstrap()
    fetchHistory()
    refreshAll()
  }

  Timer {
    interval: root.refreshIntervalMs
    running: root.teamId !== ""
    repeat: true
    onTriggered: root.refreshAll()
  }

  Timer {
    interval: 600000
    running: root.teamId !== ""
    repeat: true
    onTriggered: { root.fetchBootstrap(); root.fetchHistory() }
  }

  // ---- bar pill -------------------------------------------------------
  // Icon-only by default (matches the rest of the bar's monotone glyphs);
  // the live points number is opt-in via Settings.

  readonly property string pillText: {
    if (teamId === "") return "Set FPL ID"
    if (!showPointsInBar) return ""
    if (loading) return "…"
    if (errorMessage !== "" && !entryData) return "Error"
    if (livePoints !== null && livePoints !== undefined) return String(livePoints)
    return "–"
  }

  visible: true
  implicitWidth: vertical ? barSize : (pillRow.implicitWidth + Style.space(14))
  implicitHeight: barSize

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      text: "" // fa-futbol-o — plain outline ball, monotone like the rest of the bar icons
      color: root.errorMessage !== "" && !root.entryData ? Color.urgent : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !root.vertical && root.pillText !== ""
      text: root.pillText
      color: root.errorMessage !== "" && !root.entryData ? Color.urgent : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.entryData
      ? Model.plainText(root.entryData.name) + " — GW" + root.currentEventId + (root.livePoints !== null ? ": " + root.livePoints + " pts" : "")
      : "Omarchy FPL Tracker")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // ---- popup ------------------------------------------------------------

  Component {
    id: chipBadgeDelegate

    Column {
      required property var modelData
      readonly property bool activeNow: modelData.name === root.activeChip
      width: Style.space(38) // fixed so the horizontalCenter below lines up across rows regardless of label length
      spacing: Style.space(1)

      Text {
        text: modelData.code
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        color: parent.activeNow ? Color.accent : (modelData.status === "available" ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.8))
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: parent.activeNow || modelData.status === "available"
      }

      Text {
        text: parent.activeNow ? "Active"
          : modelData.status === "used" ? "GW" + modelData.usedEvent
          : modelData.status === "available" ? "Ready"
          : ""
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        color: parent.activeNow ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: squadRowDelegate

    Item {
      required property var modelData
      width: parent.width
      implicitHeight: Math.max(tagText.implicitHeight, nameText.implicitHeight, pointsRow.implicitHeight)
      opacity: modelData.multiplier > 0 ? 1.0 : 0.45

      Text {
        id: tagText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        text: modelData.typeShort
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: pointsRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          visible: modelData.multiplier > 1
          text: "×" + modelData.multiplier
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          text: modelData.contribution !== null && modelData.contribution !== undefined ? String(modelData.contribution) : "–"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Text {
        id: nameText
        anchors.left: tagText.right
        anchors.right: pointsRow.left
        anchors.leftMargin: Style.space(4)
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.name + (modelData.isCaptain ? "  (C)" : modelData.isViceCaptain ? "  (V)" : "")
        textFormat: Text.PlainText // player name is FPL-sourced; never interpret it as rich text
        color: modelData.isCaptain ? Color.accent : root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: modelData.isCaptain
        elide: Text.ElideRight
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      // ---- unconfigured / edit form ----
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.teamId === "" || root.editingId

        Text {
          text: root.teamId === "" ? "Connect your FPL team" : "Change team ID"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          text: "Find it in the URL when viewing your team on fantasy.premierleague.com — e.g. .../entry/1234567/event/1"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }

        TextField {
          id: idField
          width: parent.width
          placeholderText: "Team ID, e.g. 1234567"
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          inputMethodHints: Qt.ImhDigitsOnly
          text: root.teamId
          onTextChanged: {
            var digits = text.replace(/[^0-9]/g, "")
            if (digits !== text) text = digits
          }
          Keys.onReturnPressed: root.saveTeamId(text)
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Save"
            bordered: true
            foreground: root.bar.foreground
            enabled: Model.isValidTeamId(idField.text)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.saveTeamId(idField.text)
          }

          Button {
            visible: root.teamId !== ""
            text: "Cancel"
            bordered: true
            foreground: root.bar.foreground
            onClicked: { idField.text = root.teamId; root.editingId = false }
          }
        }
      }

      // ---- team overview ----
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.teamId !== "" && !root.editingId

        Row {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width - Style.space(74)
            implicitHeight: nameColumn.implicitHeight

            // Stylised watermark: the FPL wordmark, recolored to the theme's
            // foreground and faded almost to nothing, bleeding off the right
            // edge behind the team name — decoration only, never load-bearing.
            Image {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: -Style.space(8)
              source: Model.headlineSvgDataUri(root.bar.foreground)
              fillMode: Image.PreserveAspectFit
              smooth: true
              opacity: 0.09
              height: Style.space(44)
              width: height * Model.FPL_HEADLINE_ASPECT
            }

            Column {
              id: nameColumn
              width: parent.width
              spacing: Style.space(2)

              Text {
                text: root.entryData ? root.entryData.name : "Loading…"
                textFormat: Text.PlainText // team name is FPL-sourced (the entry owner sets it); never interpret it as rich text
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                visible: root.entryData !== null
                text: root.entryData ? (root.entryData.player_first_name + " " + root.entryData.player_last_name) : ""
                textFormat: Text.PlainText // manager name is FPL-sourced; never interpret it as rich text
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          Button {
            text: "Edit"
            bordered: true
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: { idField.text = root.teamId; root.editingId = true }
          }
        }

        // ---- tabs ----
        Row {
          width: parent.width
          spacing: Style.space(6)

          // Button's own `selected` fill reads a theme-controlled token that
          // defaults to `foreground`, not the `accent` we pass, so it doesn't
          // reliably tint with the theme's accent color either. A manual
          // underline in Color.accent gets the theme-matching tab indicator
          // we actually want, without depending on that token.
          Column {
            spacing: Style.space(3)
            Button {
              text: "Overview"
              selected: root.currentTab === "overview"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.currentTab = "overview"
            }
            Rectangle {
              width: parent.width
              height: Style.space(2)
              radius: 1
              color: root.currentTab === "overview" ? Color.accent : "transparent"
            }
          }

          Column {
            spacing: Style.space(3)
            Button {
              text: "Squad"
              selected: root.currentTab === "squad"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.currentTab = "squad"
            }
            Rectangle {
              width: parent.width
              height: Style.space(2)
              radius: 1
              color: root.currentTab === "squad" ? Color.accent : "transparent"
            }
          }

          Button {
            text: "Site"
            tooltipText: "Open fantasy.premierleague.com"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: Qt.openUrlExternally("https://fantasy.premierleague.com/my-team")
          }

          Column {
            spacing: Style.space(3)
            Button {
              text: "Settings"
              selected: root.currentTab === "settings"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.currentTab = "settings"
            }
            Rectangle {
              width: parent.width
              height: Style.space(2)
              radius: 1
              color: root.currentTab === "settings" ? Color.accent : "transparent"
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---- overview tab ----
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.currentTab === "overview"

          Row {
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(7)
              height: Style.space(7)
              y: (parent.height - height) / 2
              radius: width / 2
              color: root.eventStatus === "live" ? Color.accent : Qt.darker(root.bar.foreground, 1.8)
            }

            Text {
              text: root.currentEventMeta ? root.currentEventMeta.name : (root.currentEventId ? "Gameweek " + root.currentEventId : "Gameweek")
              textFormat: Text.PlainText // FPL-sourced; never interpret it as rich text
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              text: Model.eventStatusLabel(root.eventStatus)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.activeChip !== ""
              text: "· " + Model.chipLabel(root.activeChip)
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            visible: root.eventStatus === "upcoming" && root.nextEventMeta
            text: "Next deadline: " + (root.nextEventMeta ? Model.formatDeadline(root.nextEventMeta.deadline_time) : "")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(pointsColumn.implicitHeight, chipGrid.implicitHeight)

            Column {
              id: pointsColumn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              visible: root.eventStatus !== "upcoming"

              Text {
                text: root.livePoints !== null && root.livePoints !== undefined ? String(root.livePoints) : "–"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Text {
                text: "Gameweek points"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: root.activeChip === "bboost" || (root.benchPoints || 0) > 0 || (root.transferCost || 0) > 0
                text: [
                  root.activeChip === "bboost" ? "Bench Boost: bench counts"
                    : ((root.benchPoints || 0) > 0 ? root.benchPoints + " on bench" : ""),
                  (root.transferCost || 0) > 0 ? "-" + root.transferCost + " transfer cost" : ""
                ].filter(function(v) { return v !== "" }).join("  ·  ")
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Chip tracker: which of the season's two Wildcard/Free Hit/Bench
            // Boost/Triple Captain windows is current, and whether it's been
            // used yet. Re-derives from the current gameweek every refresh,
            // so it naturally flips over at the gameweek ~19/20 chip reset
            // without any special-cased "is it GW20 yet" logic.
            Grid {
              id: chipGrid
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              columns: 2
              rowSpacing: Style.space(4)
              columnSpacing: Style.space(10)

              Repeater {
                model: root.chipStatuses
                delegate: chipBadgeDelegate
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Grid {
            width: parent.width
            columns: 2
            rowSpacing: Style.space(8)
            columnSpacing: Style.space(12)

            Column {
              width: (parent.width - Style.space(12)) / 2
              spacing: Style.space(1)
              visible: root.showOverallStats
              Text { text: "OVERALL RANK"; color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              Text { text: Model.formatRank(root.overallRank); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              Text {
                visible: root.rankDelta !== null
                text: (root.rankDelta > 0 ? "▲ " : root.rankDelta < 0 ? "▼ " : "") + Model.formatSignedNumber(root.rankDelta) + " (" + Model.formatSignedPercent(root.rankPercent) + ")"
                color: root.rankDelta > 0 ? Color.accent : (root.rankDelta < 0 ? Color.urgent : Qt.darker(root.bar.foreground, 1.4))
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: root.rankDelta === null
                text: "vs last GW: –"
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              width: (parent.width - Style.space(12)) / 2
              spacing: Style.space(1)
              visible: root.showOverallStats
              Text { text: "OVERALL POINTS"; color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              Text { text: Model.formatNumber(root.overallPoints); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            }

            Column {
              width: (parent.width - Style.space(12)) / 2
              spacing: Style.space(1)
              Text { text: "GW RANK"; color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              Text { text: Model.formatRank(root.gwRank); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            }

            Column {
              width: (parent.width - Style.space(12)) / 2
              spacing: Style.space(1)
              Text { text: "SQUAD / BANK"; color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              Text {
                text: (root.teamValue !== null ? Model.formatMoney(root.teamValue) : "–") + " / " + (root.bank !== null ? Model.formatMoney(root.bank) : "–")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.visibleLeagues.length > 0

            PanelSeparator { foreground: root.bar.foreground }

            PanelSectionHeader {
              text: "LEAGUES"
              foreground: root.bar.foreground
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.visibleLeagues.slice(0, 8)

                Item {
                  required property var modelData
                  width: parent.width
                  implicitHeight: Math.max(leagueName.implicitHeight, leagueRank.implicitHeight)

                  Text {
                    id: leagueName
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    textFormat: Text.PlainText // league name is set by its creator; never interpret it as rich text
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width - Style.space(90)
                  }

                  Row {
                    id: leagueRank
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Text {
                      visible: modelData.delta !== 0
                      text: modelData.delta > 0 ? "▲" : "▼"
                      color: modelData.delta > 0 ? Color.accent : Color.urgent
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      text: Model.formatRank(modelData.rank)
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }

            Text {
              visible: root.visibleLeagues.length > 8
              text: "+" + (root.visibleLeagues.length - 8) + " more leagues"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- squad tab ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "squad"

          Text {
            visible: root.activeChip !== ""
            text: "Chip active: " + Model.chipLabel(root.activeChip)
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            visible: root.squadRows.length === 0
            text: root.picksData ? "No picks for this gameweek" : "Loading squad…"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.startingRows.length > 0

            PanelSectionHeader { text: "STARTING XI"; foreground: root.bar.foreground }

            Repeater {
              model: root.startingRows
              delegate: squadRowDelegate
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.benchRows.length > 0

            PanelSectionHeader { text: "BENCH"; foreground: root.bar.foreground }

            Repeater {
              model: root.benchRows
              delegate: squadRowDelegate
            }
          }
        }

        // ---- settings tab ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "settings"

          Toggle {
            width: parent.width
            label: "Show points in bar"
            description: "Display the live gameweek points total next to the icon in the bar."
            checked: root.showPointsInBar
            foreground: root.bar.foreground
            onClicked: root.setShowPointsInBar(!root.showPointsInBar)
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader { text: "SHOWN IN OVERVIEW"; foreground: root.bar.foreground }

          Text {
            visible: root.settingsLeagueList.length <= 1
            text: "Your leagues will appear here once your team loads."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.settingsLeagueList

              Item {
                required property var modelData
                width: parent.width
                implicitHeight: Math.max(leagueLabel.implicitHeight, leagueSwitch.implicitHeight) + Style.space(4)

                Text {
                  id: leagueLabel
                  anchors.left: parent.left
                  anchors.right: leagueSwitch.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name
                  textFormat: Text.PlainText // league name is set by its creator; never interpret it as rich text
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                ToggleSwitch {
                  id: leagueSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  trackHeight: Math.max(18, Math.round(Style.spacing.controlHeight * 0.45))
                  foreground: root.bar.foreground
                  checked: root.hiddenLeagueIds.indexOf(modelData.id) < 0
                  onToggled: root.toggleLeagueHidden(modelData.id)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---- footer ----
        Item {
          width: parent.width
          implicitHeight: Math.max(footerText.implicitHeight, footerRefresh.implicitHeight)

          Text {
            id: footerText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.errorMessage !== "" ? root.errorMessage
              : root.refreshing ? "Updating…"
              : root.lastUpdated ? "Updated " + Model.pad2(root.lastUpdated.getHours()) + ":" + Model.pad2(root.lastUpdated.getMinutes())
              : ""
            color: root.errorMessage !== "" ? Color.urgent : Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: footerRefresh
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "↻"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            iconSpinning: root.refreshing
            onClicked: root.refreshAll()
          }
        }
      }
    }
  }
}
