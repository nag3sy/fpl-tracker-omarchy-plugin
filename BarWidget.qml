import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.nag3sy.fpl-tracker"

  // Positive/success accent (rank moved up, player price rose). Red is the
  // theme's own Color.urgent. Gold marks the captain. Same green as the
  // Dockhand plugin uses for its healthy/active states.
  readonly property color successGreen: "#4ade80"
  readonly property color captainGold: "#f5c542"

  property string teamId: ""
  property bool editingId: false
  property string currentTab: "overview" // "overview" | "squad" | "fixtures" | "settings"
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
  // Raw per-gameweek fixture lists (parsed into view models by derived
  // properties below, since bootstrap's teamsById may land after the
  // fixtures do). Fetched with the lightweight `?event=N` form — see
  // Model.fixturesUrl.
  property var rawCurrentFixtures: []
  property var rawNextFixtures: []

  // Incremented/decremented around the fast-cycle requests (entry, picks,
  // live elements, current fixtures) only — bootstrap/history/next-fixtures
  // are background refreshes and shouldn't drive the popup's "Updating…"
  // spinner or last-updated time.
  property int pendingRequests: 0
  readonly property bool refreshing: pendingRequests > 0
  readonly property bool loading: refreshing && !entryData
  property string errorMessage: ""
  property var lastUpdated: null

  property int refreshIntervalMs: 90000

  // Response caps below are enforced during transfer (aborted as soon as
  // they're exceeded — see the fetch* functions), not just checked against
  // the finished body. Sized generously per endpoint's actual payload shape:
  // bootstrap carries every player/team in the game, /fixtures/?event=N is
  // one gameweek's fixture list (~30KB), the rest are scoped to one
  // entry/gameweek.
  readonly property int maxBootstrapBytes: 8000000
  readonly property int maxHistoryBytes: 2000000
  readonly property int maxLiveElementsBytes: 3000000
  readonly property int maxPicksBytes: 500000
  readonly property int maxEntryBytes: 2000000
  readonly property int maxFixturesBytes: 400000
  // fpl-tracker.json only ever holds a team ID, a bool, and a handful of
  // league IDs — a few hundred bytes in practice.
  readonly property int maxConfigFileBytes: 65536

  property bool popupOpen: false
  function close() { popupOpen = false }

  function openPopup() {
    popupOpen = true
    // Show fresh data immediately instead of whatever the last 90-second
    // poll left behind.
    root.refreshAll()
  }

  readonly property int currentEventId: entryData ? entryData.current_event : 0
  readonly property var currentEventMeta: Model.findEvent(bootstrapEvents, currentEventId)
  readonly property var nextEventMeta: Model.findNextEvent(bootstrapEvents)
  readonly property string eventStatus: Model.eventStatus(currentEventMeta)

  // The gameweek after the one in play — where the "Next up for your squad"
  // fixture difficulty section looks. Null while the current gameweek is
  // still upcoming (its own fixtures ARE the upcoming ones then).
  readonly property int upcomingEventId: {
    if (!root.currentEventId) return 0
    return root.eventStatus === "upcoming" ? 0 : root.currentEventId + 1
  }

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

  // Team IDs across all 15 picks — the lookup set behind "next up for your
  // squad" in the Fixtures tab. Uses the current squad as a proxy for the
  // next-deadline squad (transfers haven't happened yet at display time).
  readonly property var squadTeamIds: {
    var out = {}
    for (var i = 0; i < squadRows.length; i++) {
      if (squadRows[i].teamId) out[squadRows[i].teamId] = true
    }
    return out
  }

  // Parsed fixture view models. Parsing happens in derived properties (not
  // in the fetch handlers) so rows re-resolve their team short names the
  // moment bootstrap's teamsById arrives, without re-fetching fixtures.
  readonly property var currentFixtures: Model.parseFixtures(rawCurrentFixtures, teamsById)
  readonly property bool anyFixtureLive: Model.anyLiveFixtures(currentFixtures)
  // Green "Live" treatment only while matches are ACTUALLY in play — the
  // gameweek can sit "in progress" overnight between match days, and a
  // finished evening of football must not keep the hero pulsing green.
  readonly property bool matchLiveNow: root.eventStatus === "live" && root.anyFixtureLive
  // The 15 picked element ids — lookup set behind the Overview goal feed.
  readonly property var squadPlayerIds: {
    var out = {}
    for (var i = 0; i < squadRows.length; i++) out[squadRows[i].element] = true
    return out
  }
  readonly property var squadGoalEvents: Model.squadGoalEvents(currentFixtures, squadPlayerIds, elementsById)
  // Where FPL's half-season chip allowance resets (typically GW20).
  readonly property int chipResetGw: Model.chipResetEvent(bootstrapChips)
  readonly property var nextFixtures: Model.parseFixtures(rawNextFixtures, teamsById)
  readonly property var nextSquadFixtures: Model.fixturesForTeams(nextFixtures, squadTeamIds)

  // Ticker so the deadline-countdown text re-evaluates without waiting for
  // a data refresh. Only ticks while the popup is open.
  property int clockTick: 0

  // Next-gameweek fixtures are opt-in — this week's games are the priority
  // view; the following week's list is one click away.
  property bool showNextGwFixtures: false

  readonly property var tabModel: [
    { id: "overview", label: "Overview" },
    { id: "squad", label: "Squad" },
    { id: "fixtures", label: "Fixtures" },
    { id: "settings", label: "Settings" }
  ]

  // ---- persistence ------------------------------------------------------
  // FileView has no size-limited or streaming read, and its own read path
  // is check-then-open internally (stat the path, then separately open()
  // it) — so it's never used to *read* the state file, only to write it
  // (setText/atomicWrites) and to watch it for external changes. Reads go
  // through scripts/read-state-file, which opens the path with a single
  // O_NOFOLLOW|O_NONBLOCK descriptor, validates type and size with fstat()
  // on that same descriptor, and only then reads up to the cap from it —
  // no separate check step for a symlink/FIFO/oversized-file swap to land
  // in between. See that script for the full rationale.

  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/fpl-tracker.json"
  readonly property string readStateScript: String(Qt.resolvedUrl("scripts/read-state-file")).replace("file://", "")

  FileView {
    id: configFile
    preload: false
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: root.readConfig()
  }

  Process {
    id: configReader
    command: [root.readStateScript, root.configPath, String(root.maxConfigFileBytes)]
    stdout: StdioCollector {
      id: configReaderOutput
      // Rejected reads (missing, symlink, wrong type, oversized) print
      // nothing and exit non-zero; applyConfig("") is a no-op since it
      // only ever *sets* fields it finds present in the parsed object, so
      // treating that the same as a genuine empty file is safe either way.
      onStreamFinished: root.applyConfig(configReaderOutput.text)
    }
  }

  function readConfig() {
    if (configReader.running) return
    configReader.running = true
  }

  Component.onCompleted: root.readConfig()

  function applyConfig(raw) {
    if (raw && raw.length > root.maxConfigFileBytes) {
      // Belt-and-suspenders only: read-state-file's own size check (against
      // the open descriptor, not the path) is what actually keeps an
      // oversized file from being read at all.
      return
    }
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
    root.rawCurrentFixtures = []
    root.rawNextFixtures = []
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
  //
  // Fixtures come from the per-gameweek `/fixtures/?event=N` form (~30KB)
  // rather than the megabyte-scale full-season list: the current gameweek's
  // list is polled on the fast cycle because it doubles as the live-scores
  // feed (scores/minutes update during play, and it carries the official
  // FDR), while next gameweek's list is static until the rollover and
  // rides the slow 10-minute cycle.

  function beginRequest() { root.pendingRequests++ }
  function endRequest() {
    root.pendingRequests = Math.max(0, root.pendingRequests - 1)
    if (root.pendingRequests === 0) root.lastUpdated = new Date()
  }

  function fetchBootstrap() {
    var xhr = new XMLHttpRequest()
    var aborted = false
    xhr.onreadystatechange = function() {
      // Reject on declared size before the body downloads at all.
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxBootstrapBytes) { aborted = true; xhr.abort() }
        return
      }
      // No (or a dishonest) Content-Length: abort mid-transfer the moment
      // what's buffered so far crosses the cap.
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxBootstrapBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (aborted || xhr.status !== 200) return
      try {
        if (xhr.responseText.length > root.maxBootstrapBytes) return
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
    var aborted = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxHistoryBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxHistoryBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (aborted || xhr.status !== 200) return
      try {
        if (xhr.responseText.length > root.maxHistoryBytes) return
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
    var aborted = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxLiveElementsBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxLiveElementsBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (aborted) return
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > root.maxLiveElementsBytes) throw "too large"
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
    var aborted = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxPicksBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxPicksBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (aborted) return
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > root.maxPicksBytes) throw "too large"
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

  // Per-gameweek fixtures: live scores + official FDR for one event.
  // `track` selects whether the fetch drives the popup's spinner — the
  // current gameweek's list does (it's the live-scores feed), the next
  // gameweek's background refresh does not.
  function fetchFixtures(eventId, onReady, track) {
    if (!eventId) return
    if (track) root.beginRequest()
    var xhr = new XMLHttpRequest()
    var aborted = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxFixturesBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxFixturesBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (track) root.endRequest()
      if (aborted) return
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > root.maxFixturesBytes) throw "too large"
          var data = JSON.parse(xhr.responseText)
          if (Array.isArray(data)) onReady(data)
        } catch (e) {
          // Keep whatever fixtures we already had.
        }
      }
    }
    xhr.ontimeout = function() { if (track) root.endRequest() }
    xhr.open("GET", Model.fixturesUrl(eventId))
    xhr.timeout = 10000
    xhr.send()
  }

  function fetchCurrentFixtures() {
    if (!root.currentEventId) return
    root.fetchFixtures(root.currentEventId, function(data) {
      root.rawCurrentFixtures = data
    }, true)
  }

  function fetchNextFixtures() {
    if (!root.upcomingEventId) return
    root.fetchFixtures(root.upcomingEventId, function(data) {
      root.rawNextFixtures = data
    }, false)
  }

  function fetchEntry() {
    if (!Model.isValidTeamId(root.teamId)) return
    root.beginRequest()
    var xhr = new XMLHttpRequest()
    var aborted = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        var declaredLength = parseInt(xhr.getResponseHeader("Content-Length"), 10)
        if (declaredLength > root.maxEntryBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (xhr.responseText.length > root.maxEntryBytes) { aborted = true; xhr.abort() }
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.endRequest()
      if (aborted) { root.errorMessage = "Couldn't read FPL data"; return }
      if (xhr.status === 200) {
        try {
          if (xhr.responseText.length > root.maxEntryBytes) throw "too large"
          var data = JSON.parse(xhr.responseText)
          root.entryData = data
          root.errorMessage = ""
          if (data.current_event) {
            root.fetchPicks(data.current_event)
            root.fetchLiveElements(data.current_event)
            root.fetchCurrentFixtures()
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

  onUpcomingEventIdChanged: root.fetchNextFixtures()

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
    onTriggered: { root.fetchBootstrap(); root.fetchHistory(); root.fetchNextFixtures() }
  }

  // While matches are in play and the popup is open, poll the fixtures
  // feed on a faster cycle than the 90-second data poll — scores and
  // minutes arrive on FPL's ~60s fixture updates.
  Timer {
    interval: 60000
    running: root.popupOpen && root.currentEventId !== 0 && root.anyFixtureLive
    repeat: true
    onTriggered: root.fetchCurrentFixtures()
  }

  Timer {
    interval: 30000
    running: root.popupOpen && root.eventStatus === "upcoming"
    repeat: true
    onTriggered: root.clockTick++
  }

  // IPC so the popup can be toggled from a keybind, e.g.
  //   bind = SUPER, F, exec, omarchy-shell fpl-tracker toggle
  IpcHandler {
    target: "fpl-tracker"

    function toggle(): void {
      root.popupOpen ? root.close() : root.openPopup()
    }

    function open(): void { root.openPopup() }
    function close(): void { root.close() }

    // Jump to a tab directly: overview | squad | fixtures | settings
    function tab(name: string): void {
      root.openPopup()
      var n = String(name).toLowerCase()
      for (var i = 0; i < root.tabModel.length; i++) {
        if (root.tabModel[i].id === n) { root.currentTab = n; return }
      }
    }
  }

  // ---- bar pill -------------------------------------------------------
  // Icon-only by default (matches the rest of the bar's monotone glyphs);
  // the live points number is opt-in via Settings. While the gameweek is
  // in play the pill tints with the theme accent so a glance at the bar
  // tells you football is happening.

  readonly property bool pillError: root.errorMessage !== "" && !root.entryData
  readonly property bool pillLive: root.eventStatus === "live" && root.entryData
  readonly property bool pillUnconfigured: root.teamId === ""

  // Full-brightness bar text whenever connected and healthy — muted only
  // while no FPL ID is set, urgent red on connection/API errors.
  readonly property color pillColor: pillError ? Color.urgent
    : pillUnconfigured ? Color.muted
    : root.bar.barForeground

  readonly property string pillText: {
    if (teamId === "") return "Set FPL ID"
    if (!showPointsInBar) return ""
    if (loading) return "…"
    if (pillError) return "!"
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
      color: root.pillColor
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !root.vertical && root.pillText !== ""
      text: root.pillText
      color: root.pillColor
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.pillLive
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen ? root.close() : root.openPopup()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.entryData
      ? Model.plainText(root.entryData.name) + " — GW" + root.currentEventId + (root.livePoints !== null ? ": " + root.livePoints + " pts" : "")
      : "Omarchy FPL Tracker")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // ---- shared delegates -------------------------------------------------

  // Inline component: the official 1-5 fixture difficulty rating as a small
  // colored pill. Colors are the domain-standard green→red FDR spectrum
  // (see Model.FDR_COLORS), not theme tokens.
  component FdrPill: Rectangle {
    id: fdrRoot
    required property int difficulty
    width: Style.space(14)
    height: Style.space(14)
    radius: Style.space(4)
    color: Model.fdrColor(difficulty)

    Text {
      anchors.centerIn: parent
      text: fdrRoot.difficulty
      textFormat: Text.PlainText
      color: Model.fdrTextColor(fdrRoot.difficulty)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Component {
    id: chipPillDelegate

    Rectangle {
      required property var modelData
      readonly property bool activeNow: modelData.name === root.activeChip
      readonly property bool used: modelData.status === "used"
      readonly property bool known: modelData.status !== "unknown"

      width: chipPillContent.implicitWidth + Style.space(14)
      height: chipPillContent.implicitHeight + Style.space(8)
      radius: height / 2
      color: activeNow ? root.successGreen
        : (known && !used ? Util.alpha(root.bar.foreground, 0.08)
        : "transparent")
      border.width: activeNow || used ? 0 : 1
      border.color: known ? Util.alpha(root.bar.foreground, 0.15) : "transparent"

      Row {
        id: chipPillContent
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.code
          textFormat: Text.PlainText
          color: activeNow ? "#1a1a1a"
            : (used ? Color.muted : root.bar.foreground)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: activeNow || !used
        }

        Text {
          visible: activeNow || used
          anchors.verticalCenter: parent.verticalCenter
          text: activeNow ? "Active" : "GW" + modelData.usedEvent
          textFormat: Text.PlainText
          color: activeNow ? "#1a1a1a" : Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Component {
    id: statTileDelegate

    Rectangle {
      id: tile
      required property var modelData
      width: (parent.width - parent.columnSpacing) / 2
      height: tileContent.implicitHeight + Style.space(16)
      // Theme rounding when the theme has any; a gentle fallback keeps the
      // tiles from looking square on square-cornered themes.
      radius: Math.max(Style.cornerRadius, Style.space(6))
      color: Util.alpha(root.bar.foreground, 0.06)

      Column {
        id: tileContent
        // Explicit width (not implicit) so the centered children below have
        // a real surface to center within — an implicit-width Column plus
        // width-bound children is a circular binding that collapses to zero.
        width: tile.width - Style.space(16)
        anchors.centerIn: parent
        spacing: Style.space(2)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: tile.modelData.label
          textFormat: Text.PlainText
          color: Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: tile.modelData.value
          textFormat: Text.PlainText
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          // Every tile renders a detail line — empty ones fall back to a
          // space so all four tiles keep identical heights and the grid
          // stays symmetric.
          text: tile.modelData.detail || " "
          textFormat: Text.PlainText
          color: tile.modelData.detailColor !== undefined ? tile.modelData.detailColor : Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Component {
    id: squadRowDelegate

    Item {
      id: squadRowRoot
      required property var modelData
      width: parent.width
      implicitHeight: Math.max(squadNameText.implicitHeight, squadPointsPill.implicitHeight)
      opacity: modelData.multiplier > 0 ? 1.0 : 0.45

      Text {
        id: squadTagText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        text: modelData.typeShort
        color: Color.muted
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: squadPointsArea
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        Text {
          visible: squadRowRoot.modelData.priceDelta !== 0
          anchors.verticalCenter: parent.verticalCenter
          text: Model.formatPriceDelta(squadRowRoot.modelData.priceDelta)
          textFormat: Text.PlainText
          color: squadRowRoot.modelData.priceDelta > 0 ? root.successGreen : Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: squadRowRoot.modelData.multiplier > 1
          anchors.verticalCenter: parent.verticalCenter
          text: "×" + squadRowRoot.modelData.multiplier
          color: root.captainGold
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Rectangle {
          id: squadPointsPill
          anchors.verticalCenter: parent.verticalCenter
          width: squadPointsText.implicitWidth + Style.space(12)
          height: squadPointsText.implicitHeight + Style.space(4)
          radius: height / 2
          color: squadRowRoot.modelData.contribution > 0
            ? (squadRowRoot.modelData.isCaptain ? root.captainGold : Util.alpha(root.bar.foreground, 0.1))
            : Util.alpha(root.bar.foreground, 0.05)

          Text {
            id: squadPointsText
            anchors.centerIn: parent
            text: squadRowRoot.modelData.contribution !== null && squadRowRoot.modelData.contribution !== undefined ? String(squadRowRoot.modelData.contribution) : "–"
            textFormat: Text.PlainText
            color: squadRowRoot.modelData.isCaptain && squadRowRoot.modelData.contribution > 0 ? "#1a1a1a" : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
      }

      Row {
        id: squadNameArea
        anchors.left: squadTagText.right
        anchors.right: squadPointsArea.left
        anchors.leftMargin: Style.space(4)
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          id: squadNameText
          anchors.verticalCenter: parent.verticalCenter
          text: squadRowRoot.modelData.name
          textFormat: Text.PlainText // player name is FPL-sourced; never interpret it as rich text
          color: squadRowRoot.modelData.isCaptain ? root.captainGold : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: squadRowRoot.modelData.isCaptain
          elide: Text.ElideRight
          width: Math.min(implicitWidth, squadNameArea.width - captainBadge.implicitWidth - squadNameArea.spacing)
          visible: squadNameArea.width > 0
        }

        Rectangle {
          id: captainBadge
          visible: squadRowRoot.modelData.isCaptain || squadRowRoot.modelData.isViceCaptain
          anchors.verticalCenter: parent.verticalCenter
          width: captainBadgeText.implicitWidth + Style.space(8)
          height: captainBadgeText.implicitHeight + Style.space(2)
          radius: height / 2
          color: squadRowRoot.modelData.isCaptain ? root.captainGold : Util.alpha(root.bar.foreground, 0.1)

          Text {
            id: captainBadgeText
            anchors.centerIn: parent
            text: squadRowRoot.modelData.isCaptain ? "C" : "V"
            textFormat: Text.PlainText
            color: squadRowRoot.modelData.isCaptain ? "#1a1a1a" : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }

  Component {
    id: fixtureRowDelegate

    Item {
      id: fixtureRow
      required property var modelData
      width: parent.width
      implicitHeight: summaryRow.height
        + (expanded ? matchReview.implicitHeight + Style.space(10) : 0)

      readonly property bool live: Model.fixtureIsLive(modelData)
      // `!!` — object lookups on squadTeamIds yield undefined for teams the
      // manager doesn't own, and QML bool bindings reject undefined.
      readonly property bool inSquad: !!(root.squadTeamIds[modelData.teamH] || root.squadTeamIds[modelData.teamA])
      readonly property var goalLines: Model.fixtureGoalLines(modelData, root.elementsById)
      property bool expanded: false
      readonly property bool clickable: goalLines.length > 0
      readonly property bool hovered: fixtureMouse.containsMouse

      // Hover/click affordance: a faint surface on hover and while expanded.
      Rectangle {
        anchors.fill: parent
        radius: Style.space(6)
        color: fixtureRow.clickable && (fixtureRow.hovered || fixtureRow.expanded)
          ? Util.alpha(root.bar.foreground, 0.05)
          : "transparent"
      }

      // ---- summary line: fixed-width columns so every row — played or
      // upcoming, long name or short — shares identical geometry and the
      // FDR bars line up down the tab ----
      Item {
        id: summaryRow
        width: parent.width
        height: summaryGrid.implicitHeight + Style.space(6)

        Row {
          id: summaryGrid
          anchors.centerIn: parent
          spacing: Style.space(10)

          // home: name + slim FDR bar underneath (the 1-5 pill colors,
          // muted into a strip so ten rows don't shout)
          Column {
            width: Style.space(52)
            spacing: Style.space(2)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              text: Model.plainText(fixtureRow.modelData.shortH)
              textFormat: Text.PlainText
              color: fixtureRow.inSquad ? root.bar.foreground : Color.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: fixtureRow.inSquad
            }

            Rectangle {
              width: Style.space(30)
              height: 3
              radius: 1
              anchors.horizontalCenter: parent.horizontalCenter
              color: Model.fdrColor(fixtureRow.modelData.difficultyH)
            }
          }

          // center: live dot + score / kickoff + minute — fixed-width slot
          // so the name columns never shift between rows
          Item {
            width: Style.space(96)
            height: scoreText.implicitHeight

            Row {
              anchors.centerIn: parent
              spacing: Style.space(5)

              Rectangle {
                visible: fixtureRow.live
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(5)
                height: Style.space(5)
                radius: width / 2
                color: root.successGreen

                SequentialAnimation on opacity {
                  running: fixtureRow.live
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.25; duration: 900 }
                  NumberAnimation { to: 1.0; duration: 900 }
                }
              }

              Text {
                id: scoreText
                anchors.verticalCenter: parent.verticalCenter
                text: Model.fixtureScoreText(fixtureRow.modelData)
                textFormat: Text.PlainText
                color: fixtureRow.modelData.started ? root.bar.foreground : Color.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: fixtureRow.modelData.started
              }

              Text {
                visible: fixtureRow.live
                anchors.verticalCenter: parent.verticalCenter
                text: Model.fixtureMinuteText(fixtureRow.modelData)
                textFormat: Text.PlainText
                color: root.successGreen
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // away: mirror of home
          Column {
            width: Style.space(52)
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: Model.plainText(fixtureRow.modelData.shortA)
              textFormat: Text.PlainText
              color: fixtureRow.inSquad ? root.bar.foreground : Color.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: fixtureRow.inSquad
            }

            Rectangle {
              width: Style.space(30)
              height: 3
              radius: 1
              anchors.horizontalCenter: parent.horizontalCenter
              color: Model.fdrColor(fixtureRow.modelData.difficultyA)
            }
          }
        }
      }

      // ---- match review: scorers with assisters in parentheses ----
      Column {
        id: matchReview
        anchors.top: summaryRow.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(56)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        spacing: Style.space(2)
        visible: fixtureRow.expanded

        Repeater {
          model: fixtureRow.goalLines

          delegate: Text {
            required property var modelData
            width: matchReview.width
            text: (modelData.team !== "" ? Model.plainText(modelData.team) + "  " : "") + Model.plainText(modelData.text)
            textFormat: Text.PlainText // player names are FPL-sourced; never interpret as rich text
            color: modelData.team !== "" ? root.bar.foreground : Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            // Wrap, never elide — a 5-goal thriller's full scorer list must
            // be readable, not truncated.
            wrapMode: Text.WordWrap
          }
        }
      }

      MouseArea {
        id: fixtureMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: fixtureRow.clickable
        cursorShape: fixtureRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: fixtureRow.expanded = !fixtureRow.expanded
      }
    }
  }

  // ---- popup ------------------------------------------------------------

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
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
          color: Color.muted
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

      // ---- configured view ----
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.teamId !== "" && !root.editingId

        // ---- header: team identity + actions ----
          Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: headerIcon
            anchors.verticalCenter: parent.verticalCenter
            text: "" // nf-fa-futbol-o — same glyph as the bar pill, sized up to anchor the header
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Math.round(Style.font.title * 1.5)
          }

          Item {
            width: parent.width - parent.spacing * 3 - headerIcon.implicitWidth - editButton.implicitWidth - siteButton.implicitWidth
            implicitHeight: nameColumn.implicitHeight

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
                color: Color.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          Button {
            id: editButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Edit"
            bordered: true
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: { idField.text = root.teamId; root.editingId = true }
          }

          Button {
            id: siteButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Site"
            tooltipText: "Open fantasy.premierleague.com"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: Qt.openUrlExternally("https://fantasy.premierleague.com/my-team")
          }
        }

        // ---- tabs ----
        Row {
          id: tabRow
          width: parent.width
          spacing: 0

          Repeater {
            model: root.tabModel

            delegate: Item {
              id: tabItem
              required property var modelData
              width: tabRow.width / root.tabModel.length
              height: tabLabel.implicitHeight + Style.space(8)

              readonly property bool isCurrent: root.currentTab === modelData.id

              Text {
                id: tabLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                text: tabItem.modelData.label
                textFormat: Text.PlainText
                color: tabItem.isCurrent ? root.bar.foreground : Color.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: tabItem.isCurrent
              }

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: tabLabel.implicitWidth + Style.space(12)
                height: 2
                radius: 1
                color: tabItem.isCurrent ? Color.accent : "transparent"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = tabItem.modelData.id
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---- overview tab ----
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.currentTab === "overview"

          // -- hero card: the gameweek at a glance --
          Rectangle {
            width: parent.width
            height: heroContent.implicitHeight + Style.space(24)
            radius: Math.max(Style.cornerRadius, Style.space(8))
            color: Util.alpha(root.bar.foreground, 0.05)

            Column {
              id: heroContent
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  id: liveDot
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7)
                  height: Style.space(7)
                  radius: width / 2
                  color: root.matchLiveNow ? root.successGreen : Color.muted

                  SequentialAnimation on opacity {
                    running: root.matchLiveNow
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 900 }
                    NumberAnimation { to: 1.0; duration: 900 }
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.currentEventMeta ? root.currentEventMeta.name : (root.currentEventId ? "Gameweek " + root.currentEventId : "Gameweek")
                  textFormat: Text.PlainText // FPL-sourced; never interpret it as rich text
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.eventStatusLabel(root.eventStatus)
                  textFormat: Text.PlainText
                  color: root.matchLiveNow ? root.successGreen : Color.muted
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.matchLiveNow
                }

                Text {
                  visible: root.activeChip !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  text: "· " + Model.chipLabel(root.activeChip)
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                visible: root.eventStatus !== "upcoming"
                text: root.livePoints !== null && root.livePoints !== undefined ? String(root.livePoints) : "–"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Text {
                visible: root.eventStatus === "upcoming" && root.nextEventMeta
                text: {
                  root.clockTick
                  return Model.formatTimeUntil(root.nextEventMeta ? root.nextEventMeta.deadline_time : "") || "–"
                }
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Text {
                text: root.eventStatus === "upcoming"
                  ? "until the GW" + root.currentEventId + " deadline" + (root.nextEventMeta ? " · " + Model.formatDeadline(root.nextEventMeta.deadline_time) : "")
                  : "Gameweek points"
                color: Color.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: root.eventStatus !== "upcoming"
                  && (root.activeChip === "bboost" || (root.benchPoints || 0) > 0 || (root.transferCost || 0) > 0)
                text: [
                  root.activeChip === "bboost" ? "Bench Boost: bench counts"
                    : ((root.benchPoints || 0) > 0 ? root.benchPoints + " on bench" : ""),
                  (root.transferCost || 0) > 0 ? "-" + root.transferCost + " transfer cost" : ""
                ].filter(function(v) { return v !== "" }).join("  ·  ")
                color: Color.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Your players' goal involvements this gameweek, straight from
              // the fixture feed — "Haaland scored!" without opening a tab.
              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.squadGoalEvents.length > 0 && root.eventStatus !== "upcoming"

                Repeater {
                  model: root.squadGoalEvents.slice(0, 4)

                  delegate: Text {
                    required property var modelData
                    width: parent.width
                    text: {
                      var main = modelData.goals > 0 ? (modelData.goals > 1 ? " ×" + modelData.goals : "") : ""
                      if (modelData.assists > 0) main += (main !== "" ? " · " : "") + modelData.assists + "A"
                      return "<font color=\"#4ade80\">\uF1E3</font> <b>" + Model.plainText(modelData.name) + "</b>" + main
                        + "  ·  " + Model.plainText(modelData.fixture)
                    }
                    textFormat: Text.StyledText // we own the markup; names are stripped of <> first
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  visible: root.squadGoalEvents.length > 4
                  text: "+" + (root.squadGoalEvents.length - 4) + " more — see Fixtures"
                  textFormat: Text.PlainText
                  color: Color.muted
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // -- chip tracker --
          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.chipStatuses
              delegate: chipPillDelegate
            }
          }

          // Season strip: one tick per gameweek, hoverable. Played weeks
          // are faint, chip-played weeks gold (hover for which chip), the
          // half-season token reset is purple, and this week glows green
          // while matches are in play.
          Item {
            id: seasonStripArea
            width: parent.width
            height: stripCaption.implicitHeight + seasonStrip.height + Style.space(4)
            visible: root.bootstrapEvents.length > 0 && root.currentEventId > 0

            property int hoverEventId: 0

            // Hover readout / idle legend. Reserves its line so the strip
            // never jumps when hover text appears.
            Text {
              id: stripCaption
              anchors.top: parent.top
              anchors.horizontalCenter: parent.horizontalCenter
              height: Math.max(implicitHeight, Style.font.caption)
              text: {
                var id = seasonStripArea.hoverEventId
                if (id === 0) return "Season so far · gold = chip played · purple = tokens reset"
                for (var i = 0; i < root.historyChips.length; i++) {
                  var h = root.historyChips[i]
                  if (h && h.event === id) return "GW" + id + " · " + Model.chipLabel(h.name) + " used"
                }
                if (id === root.currentEventId) return "GW" + id + " · current gameweek"
                if (id === root.chipResetGw) return "GW" + id + " · FPL tokens reset"
                if (id < root.currentEventId) return "GW" + id + " · finished"
                return "GW" + id
              }
              textFormat: Text.PlainText
              color: seasonStripArea.hoverEventId === 0 ? Color.muted : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: seasonStrip
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              spacing: Style.space(3)

              Repeater {
                model: root.bootstrapEvents

                delegate: Rectangle {
                  id: seasonTick
                  required property var modelData
                  width: Style.space(6)
                  height: isCurrent ? Style.space(9) : (chipPlayed ? Style.space(8) : Style.space(6))
                  radius: 1

                  readonly property bool isCurrent: root.currentEventId === modelData.id
                  readonly property bool chipPlayed: {
                    for (var i = 0; i < root.historyChips.length; i++) {
                      if (root.historyChips[i] && root.historyChips[i].event === modelData.id) return true
                    }
                    return false
                  }
                  readonly property bool isReset: root.chipResetGw === modelData.id && !isCurrent

                  color: isCurrent ? (root.matchLiveNow ? root.successGreen : Util.alpha(root.bar.foreground, 0.45))
                    : chipPlayed ? root.captainGold
                    : isReset ? "#a78bfa"
                    : modelData.id < root.currentEventId ? Util.alpha(root.bar.foreground, 0.18)
                    : Util.alpha(root.bar.foreground, 0.08)

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: seasonStripArea.hoverEventId = seasonTick.modelData.id
                    onExited: seasonStripArea.hoverEventId = 0
                  }
                }
              }
            }
          }

          // -- stat tiles --
          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            Repeater {
              model: [
                {
                  label: "GW RANK",
                  value: Model.formatRank(root.gwRank),
                  detail: "",
                  detailColor: Color.muted
                },
                {
                  label: "OVERALL RANK",
                  value: Model.formatRank(root.overallRank),
                  detail: root.rankDelta !== null
                    ? (root.rankDelta > 0 ? "▲ " : root.rankDelta < 0 ? "▼ " : "") + Model.formatSignedNumber(root.rankDelta) + " (" + Model.formatSignedPercent(root.rankPercent) + ")"
                    : "vs last GW: –",
                  detailColor: root.rankDelta > 0 ? root.successGreen : (root.rankDelta < 0 ? Color.urgent : Color.muted)
                },
                {
                  label: "OVERALL POINTS",
                  value: Model.formatNumber(root.overallPoints),
                  detail: "",
                  detailColor: Color.muted
                },
                {
                  label: "SQUAD / BANK",
                  value: (root.teamValue !== null ? Model.formatMoney(root.teamValue) : "–") + " / " + (root.bank !== null ? Model.formatMoney(root.bank) : "–"),
                  detail: "",
                  detailColor: Color.muted
                }
              ]
              delegate: statTileDelegate
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.visibleLeagues.length > 0

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
                      color: modelData.delta > 0 ? root.successGreen : Color.urgent
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
              textFormat: Text.PlainText
              color: Color.muted
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
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            visible: root.squadRows.length === 0
            text: root.picksData ? "No picks for this gameweek" : "Loading squad…"
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.startingRows.length > 0

            Rectangle {
              width: parent.width
              height: startingList.implicitHeight + panelStartingHeader.implicitHeight + Style.space(20)
              radius: Math.max(Style.cornerRadius, Style.space(8))
              color: Util.alpha(root.bar.foreground, 0.05)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                PanelSectionHeader { id: panelStartingHeader; text: "STARTING XI"; foreground: root.bar.foreground }

                Column {
                  id: startingList
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: root.startingRows
                    delegate: squadRowDelegate
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.benchRows.length > 0

            Rectangle {
              width: parent.width
              height: benchList.implicitHeight + panelBenchHeader.implicitHeight + Style.space(20)
              radius: Math.max(Style.cornerRadius, Style.space(8))
              color: Util.alpha(root.bar.foreground, 0.03)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                PanelSectionHeader { id: panelBenchHeader; text: "BENCH"; foreground: root.bar.foreground }

                Column {
                  id: benchList
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: root.benchRows
                    delegate: squadRowDelegate
                  }
                }
              }
            }
          }
        }

        // ---- fixtures tab ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "fixtures"

          // Matchday snapshot: GW, then played / in-play / to-come counts,
          // the live count glowing green.
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: {
              var played = 0, live = 0, toCome = 0
              for (var i = 0; i < root.currentFixtures.length; i++) {
                var f = root.currentFixtures[i]
                if (Model.fixtureIsLive(f)) live++
                else if (f.started) played++
                else toCome++
              }
              var segs = ["<b>GW" + root.currentEventId + "</b>"]
              if (played > 0) segs.push(played + " FT")
              if (live > 0) segs.push('<font color="#4ade80"><b>' + live + ' live</b></font>')
              if (toCome > 0) segs.push(toCome + " to come")
              return segs.join("  ·  ")
            }
            textFormat: Text.StyledText
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          // FDR legend — the same 1-5 scale FPL's site and every fixture
          // tool uses: 1 (easiest, green) through 5 (hardest, red).
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Repeater {
              model: [1, 2, 3, 4, 5]

              delegate: FdrPill {
                required property var modelData
                difficulty: modelData
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "FDR · fixture difficulty rating (1 easy — 5 hard)"
            textFormat: Text.PlainText
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.eventStatus === "upcoming"
              ? "Kickoff times shown · click a started match for scorers"
              : "Click a match for scorers & assists · dimmed = no squad players"
            textFormat: Text.PlainText
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.currentFixtures.length === 0
            text: root.currentEventId ? "Loading fixtures…" : "No gameweek fixtures yet"
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.currentFixtures.length > 0

            Repeater {
              model: root.currentFixtures
              delegate: fixtureRowDelegate
            }
          }

          // ---- next gameweek, opt-in ----
          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.upcomingEventId > 0
              && (root.nextSquadFixtures.length > 0 || root.nextFixtures.length > 0)

            Item {
              width: parent.width
              height: nextGwLabel.implicitHeight + Style.space(6)

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  id: nextGwChevron
                  text: root.showNextGwFixtures ? "▾" : "▸"
                  textFormat: Text.PlainText
                  color: Color.muted
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: nextGwLabel
                  text: "Next up for your squad · GW" + root.upcomingEventId
                  textFormat: Text.PlainText
                  color: root.showNextGwFixtures ? root.bar.foreground : Color.muted
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.showNextGwFixtures
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showNextGwFixtures = !root.showNextGwFixtures
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(2)
              visible: root.showNextGwFixtures

              Repeater {
                // Squad-relevant fixtures first; if none of your players
                // have a GW+1 fixture yet, fall back to the full slate.
                model: root.nextSquadFixtures.length > 0 ? root.nextSquadFixtures : root.nextFixtures
                delegate: fixtureRowDelegate
              }
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
            color: Color.muted
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
            color: root.errorMessage !== "" ? Color.urgent : Color.muted
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
