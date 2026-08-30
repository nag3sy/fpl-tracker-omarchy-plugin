.pragma library

// The shell's shared tooltip (Bar.showTooltip -> PanelToolTip -> QtQuick
// Controls ToolTip) doesn't pin textFormat to PlainText, so it will
// auto-detect and render basic HTML if a manager or league name is crafted
// to look like markup. Strip angle brackets before handing FPL-sourced text
// to that sink; every in-popup Text element sets textFormat explicitly
// instead, since we own those.
function plainText(value) {
  return String(value === undefined || value === null ? "" : value).replace(/[<>]/g, "")
}

var API_BASE = "https://fantasy.premierleague.com/api"

function isValidTeamId(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  return /^[1-9][0-9]{0,9}$/.test(s)
}

function bootstrapUrl() {
  return API_BASE + "/bootstrap-static/"
}

function entryUrl(teamId) {
  return API_BASE + "/entry/" + encodeURIComponent(teamId) + "/"
}

function picksUrl(teamId, eventId) {
  return API_BASE + "/entry/" + encodeURIComponent(teamId) + "/event/" + encodeURIComponent(eventId) + "/picks/"
}

function liveUrl(eventId) {
  return API_BASE + "/event/" + encodeURIComponent(eventId) + "/live/"
}

function historyUrl(teamId) {
  return API_BASE + "/entry/" + encodeURIComponent(teamId) + "/history/"
}

// Per-gameweek fixture list. Fetched with `?event=N` (one gameweek's worth,
// ~30KB) rather than the full-season /fixtures/ (megabytes of per-fixture
// stat arrays we'd throw away). Each fixture carries live scores/minutes
// once play is underway AND the official two-sided difficulty rating
// (team_h_difficulty / team_a_difficulty, 1 easy … 5 hard) used by FDR
// displays everywhere in the FPL ecosystem.
function fixturesUrl(eventId) {
  return API_BASE + "/fixtures/?event=" + encodeURIComponent(eventId)
}

function formatNumber(n) {
  if (n === undefined || n === null) return "–"
  var num = Number(n)
  if (!isFinite(num)) return "–"
  var sign = num < 0 ? "-" : ""
  var s = Math.abs(Math.round(num)).toString()
  var out = ""
  while (s.length > 3) {
    out = "," + s.slice(-3) + out
    s = s.slice(0, -3)
  }
  return sign + s + out
}

function formatRank(n) {
  if (n === undefined || n === null) return "–"
  return formatNumber(n)
}

function formatMoney(tenths) {
  if (tenths === undefined || tenths === null) return "–"
  var num = Number(tenths)
  if (!isFinite(num)) return "–"
  return "£" + (num / 10).toFixed(1) + "m"
}

// formatNumber already prints a leading "-" for negatives; only the "+"
// for positives needs adding here.
function formatSignedNumber(n) {
  if (n === undefined || n === null) return "–"
  return (n > 0 ? "+" : "") + formatNumber(n)
}

function formatSignedPercent(n) {
  if (n === undefined || n === null) return "–"
  return (n > 0 ? "+" : "") + n.toFixed(1) + "%"
}

function findEvent(events, eventId) {
  if (!events || !eventId) return null
  for (var i = 0; i < events.length; i++) {
    if (events[i] && events[i].id === eventId) return events[i]
  }
  return null
}

function findNextEvent(events) {
  if (!events) return null
  for (var i = 0; i < events.length; i++) {
    if (events[i] && events[i].is_next) return events[i]
  }
  return null
}

// FPL never reports a live/in-progress flag directly: `finished` flips once
// results are in, `data_checked` flips later once bonus points are fully
// verified. Everything between deadline and `finished` is "live" as far as
// a manager is concerned.
function eventStatus(eventMeta) {
  if (!eventMeta) return "unknown"
  if (eventMeta.is_next && !eventMeta.is_current) return "upcoming"
  if (eventMeta.finished && eventMeta.data_checked) return "confirmed"
  if (eventMeta.finished) return "final"
  return "live"
}

function eventStatusLabel(status) {
  switch (status) {
    case "live": return "Live"
    case "final": return "Final – bonus pending"
    case "confirmed": return "Confirmed"
    case "upcoming": return "Upcoming"
    default: return ""
  }
}

function chipLabel(code) {
  switch (code) {
    case "wildcard": return "Wildcard"
    case "freehit": return "Free Hit"
    case "bboost": return "Bench Boost"
    case "3xc": return "Triple Captain"
    case "manager": return "Assistant Manager"
    // Unknown/future API codes: strip angle brackets so the raw code can
    // never ride into a rich-text rendering path.
    default: return code ? String(code).replace(/[<>]/g, "") : ""
  }
}

function chipShortCode(name) {
  switch (name) {
    case "wildcard": return "WC"
    case "freehit": return "FH"
    case "bboost": return "BB"
    case "3xc": return "TC"
    default: return "?"
  }
}

// FPL grants one of each chip per half-season (bootstrap-static's `chips`
// list carries two windows per name — start_event/stop_event — normally
// split around gameweek 19/20). A chip not used within its window is lost,
// not carried over, so "available" always means "within the window that
// covers (or is next after) the current gameweek, and not already used in
// that specific window."
var CHIP_TYPES = [
  { name: "wildcard", label: "Wildcard" },
  { name: "freehit", label: "Free Hit" },
  { name: "bboost", label: "Bench Boost" },
  { name: "3xc", label: "Triple Captain" }
]

function chipWindowsFor(bootstrapChips, name) {
  if (!bootstrapChips) return []
  var out = []
  for (var i = 0; i < bootstrapChips.length; i++) {
    var c = bootstrapChips[i]
    if (c && c.name === name && c.start_event && c.stop_event) out.push({ start: c.start_event, stop: c.stop_event })
  }
  out.sort(function(a, b) { return a.start - b.start })
  return out
}

function chipUsedInWindow(historyChips, name, window) {
  if (!historyChips) return null
  for (var i = 0; i < historyChips.length; i++) {
    var h = historyChips[i]
    if (h && h.name === name && h.event >= window.start && h.event <= window.stop) return h.event
  }
  return null
}

// One row per chip type: { name, label, code, status, usedEvent } where
// status is "available" | "used" | "unknown" (data not loaded yet). Only two
// real states are shown — whether this half-season's chip has been played —
// since a chip that simply hasn't opened yet (e.g. Wildcard/Free Hit before
// gameweek 2) reads the same to a manager as "still have it, not used it":
// there's nothing to distinguish from "Ready" until they actually play it.
// Recomputes cleanly across the gameweek-20-ish reset because the window
// lookup always re-derives from the current gameweek rather than caching a
// single season-long "has this chip" flag.
function chipStatuses(bootstrapChips, historyChips, currentEventId) {
  var out = []
  for (var i = 0; i < CHIP_TYPES.length; i++) {
    var type = CHIP_TYPES[i]
    var code = chipShortCode(type.name)
    var windows = chipWindowsFor(bootstrapChips, type.name)
    if (windows.length === 0 || !currentEventId) {
      out.push({ name: type.name, label: type.label, code: code, status: "unknown", usedEvent: null })
      continue
    }
    var window = null
    for (var w = 0; w < windows.length; w++) {
      if (currentEventId <= windows[w].stop) { window = windows[w]; break }
    }
    if (!window) window = windows[windows.length - 1]
    var usedEvent = chipUsedInWindow(historyChips, type.name, window)
    out.push({ name: type.name, label: type.label, code: code, status: usedEvent !== null ? "used" : "available", usedEvent: usedEvent })
  }
  return out
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function formatDeadline(iso) {
  if (!iso) return ""
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[d.getDay()] + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// League deltas come straight from the API's own last-gameweek snapshot
// (`entry_last_rank`) rather than anything computed client-side, so they
// stay meaningful across a single poll interval instead of being noise.
function classicLeagues(entryData) {
  if (!entryData || !entryData.leagues || !entryData.leagues.classic) return []
  var list = entryData.leagues.classic
  var out = []
  for (var i = 0; i < list.length; i++) {
    var l = list[i]
    if (!l) continue
    var rank = l.entry_rank
    var lastRank = l.entry_last_rank
    var delta = (lastRank && lastRank > 0 && rank) ? (lastRank - rank) : 0
    out.push({
      id: l.id,
      name: l.name || "League",
      rank: rank,
      totalEntries: l.rank_count,
      delta: delta
    })
  }
  return out
}

// "Overall" isn't a real entry in `leagues.classic[]` — it's synthesized
// here as a sentinel id so the Settings tab can show/hide it through the
// same one list as real leagues, matching how the FPL app treats it.
function leaguesForSettings(entryData) {
  var out = [{ id: "overall", name: "Overall" }]
  var real = classicLeagues(entryData)
  for (var i = 0; i < real.length; i++) out.push({ id: real[i].id, name: real[i].name })
  return out
}

// The most recent *completed* gameweek in `/entry/{id}/history/`'s
// `current[]` list — the baseline LiveFPL-style rank-movement compares the
// live overall rank against. Returns null for gameweek 1 (nothing to
// compare against yet) or before the history fetch has landed.
function previousHistoryEntry(history, currentEventId) {
  if (!history || !currentEventId) return null
  var best = null
  for (var i = 0; i < history.length; i++) {
    var h = history[i]
    if (h && h.event < currentEventId && (!best || h.event > best.event)) best = h
  }
  return best
}

function indexById(list) {
  var out = {}
  if (!list) return out
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (item && item.id !== undefined) out[item.id] = item
  }
  return out
}

function elementTypeShort(elementTypesById, typeId) {
  var t = elementTypesById[typeId]
  return t ? t.singular_name_short : ""
}

// One row per squad pick, sorted into the starting XI (position 1-11) and
// bench (12-15) by the caller via `onBench`. Each player's own live points
// come from the /event/{id}/live/ endpoint; multiplying by `multiplier`
// (which FPL itself sets to 2/3 for captain/triple-captain, or 0 for an
// unused bench spot) is the "properly calculated" captain contribution —
// no separate vice-captain fallback logic is needed because FPL already
// resolves that into `multiplier` once it detects the captain didn't play.
function squadRows(picksData, elementsById, teamsById, elementTypesById, liveElementsById) {
  if (!picksData || !picksData.picks) return []
  var rows = []
  var picks = picksData.picks
  for (var i = 0; i < picks.length; i++) {
    var p = picks[i]
    if (!p) continue
    var el = elementsById[p.element]
    var team = el ? teamsById[el.team] : null
    var live = liveElementsById[p.element]
    var livePoints = (live && live.stats) ? live.stats.total_points : null
    var contribution = (livePoints !== null && livePoints !== undefined) ? livePoints * p.multiplier : null
    rows.push({
      element: p.element,
      name: el ? el.web_name : ("Player " + p.element),
      teamShort: team ? team.short_name : "",
      teamId: el ? el.team : null,
      typeShort: el ? elementTypeShort(elementTypesById, el.element_type) : "",
      position: p.position,
      isCaptain: !!p.is_captain,
      isViceCaptain: !!p.is_vice_captain,
      multiplier: p.multiplier,
      livePoints: livePoints,
      contribution: contribution,
      // This gameweek's price move in tenths (from bootstrap's
      // cost_change_event): +1 = rose £0.1m, -1 = fell, 0 = unmoved.
      priceDelta: el ? (el.cost_change_event || 0) : 0,
      onBench: p.position > 11
    })
  }
  rows.sort(function(a, b) { return a.position - b.position })
  return rows
}

// Sum of bench players' raw live points (not multiplier-adjusted — bench
// points are "what they scored", not "what they'd have contributed"). Used
// as a live-updating alternative to entry_history.points_on_bench, which
// lags the same way entry_history.points does. Returns null (not 0) when no
// bench row has live data yet, so the caller can fall back cleanly instead
// of flashing a false "0 on bench".
function sumBenchPoints(rows) {
  if (!rows || rows.length === 0) return null
  var total = 0
  var hasAny = false
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!r.onBench) continue
    if (r.livePoints === null || r.livePoints === undefined) continue
    hasAny = true
    total += r.livePoints
  }
  return hasAny ? total : null
}

// ---- price moves ---------------------------------------------------------
// bootstrap-static's elements carry `cost_change_event` in tenths of a
// million: +1 = rose £0.1m this gameweek, -1 = fell. 0 = unmoved. This is
// the change that has *already happened*, not a prediction.

function formatPriceDelta(tenths) {
  if (!tenths) return ""
  var v = Number(tenths)
  if (!isFinite(v) || v === 0) return ""
  return (v > 0 ? "▲" : "▼") + " £0." + Math.abs(v) + "m"
}

// ---- fixtures / FDR ------------------------------------------------------
// The official FDR is a fixed 1-5 scale shown as a green→red spectrum on
// every FPL tool, so these five colors are domain-standard, not theme
// tokens — the plugin stays theme-derived everywhere else.
var FDR_COLORS = {
  1: "#22c55e",
  2: "#84cc16",
  3: "#eab308",
  4: "#f97316",
  5: "#ef4444"
}

function fdrColor(difficulty) {
  var c = FDR_COLORS[difficulty]
  return c || "#6b7280"
}

// Dark text on the three lighter steps, light text on orange/red — keeps
// every pill readable on both dark and light Omarchy themes.
function fdrTextColor(difficulty) {
  return difficulty >= 4 ? "#ffffff" : "#1a1a1a"
}

// Normalized fixture row: { id, teamH, teamA, shortH, shortA, scoreH,
// scoreA, started, finished, finishedProvisional, minutes, kickoffTime,
// difficultyH, difficultyA, stats }. Team short names are resolved from
// bootstrap's teamsById; a missing entry (API ordering race) just leaves
// them blank until the next refresh resolves it. `stats` is passed through
// raw — it drives the expandable match review (scorers, assists, cards).
function parseFixtures(list, teamsById) {
  if (!list) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var f = list[i]
    if (!f || f.team_h === undefined || f.team_a === undefined) continue
    var th = teamsById[f.team_h]
    var ta = teamsById[f.team_a]
    out.push({
      id: f.id,
      teamH: f.team_h,
      teamA: f.team_a,
      shortH: th ? th.short_name : "?",
      shortA: ta ? ta.short_name : "?",
      scoreH: f.team_h_score,
      scoreA: f.team_a_score,
      started: !!f.started,
      finished: !!f.finished,
      // finished_provisional flips at the final whistle; `finished` waits
      // for FPL's full bonus verification (often an hour later). Liveness
      // is judged on the provisional flag so a full-time game never keeps
      // pulsing as "in play".
      finishedProvisional: !!f.finished_provisional,
      minutes: f.minutes || 0,
      kickoffTime: f.kickoff_time || "",
      difficultyH: f.team_h_difficulty || 3,
      difficultyA: f.team_a_difficulty || 3,
      stats: f.stats || []
    })
  }
  out.sort(function(a, b) {
    if (a.kickoffTime !== b.kickoffTime) return a.kickoffTime < b.kickoffTime ? -1 : 1
    return a.id - b.id
  })
  return out
}

// Fixtures from `list` involving any team in `teamIds` (the manager's squad
// teams) — used for the "next up for your squad" section.
function fixturesForTeams(list, teamIds) {
  if (!list || !teamIds) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var f = list[i]
    if (f && (teamIds[f.teamH] || teamIds[f.teamA])) out.push(f)
  }
  return out
}

// Score cell for a fixture row: the actual score once play has started
// (kept for in-play *and* finished — the finished check comes first so a
// final result never falls back to a minute badge), otherwise the kickoff
// time. Minutes render separately via fixtureMinuteText.
function fixtureScoreText(f) {
  if (!f) return ""
  if (f.started || f.finished) {
    var h = f.scoreH !== null && f.scoreH !== undefined ? f.scoreH : "-"
    var a = f.scoreA !== null && f.scoreA !== undefined ? f.scoreA : "-"
    return h + " – " + a
  }
  return formatDeadline(f.kickoffTime)
}

// In-play minute badge ("67'", "HT"). Empty once FPL marks the fixture
// finished (the final score is the whole story then) and for kickoff-time
// rows.
function fixtureMinuteText(f) {
  if (!f || !f.started || f.finished) return ""
  if (f.minutes === 45) return "HT"
  return f.minutes + "'"
}

// True while the score cell should read as a live in-play score (accent
// colored) rather than a kickoff time or final result. Judged on
// `finished_provisional` — the final-whistle flag — not `finished`, which
// waits for bonus verification and kept full-time games pulsing. Always
// returns a strict boolean; QML bool bindings reject undefined.
function fixtureIsLive(f) {
  if (!f) return false
  return !!f.started && !f.finishedProvisional
}

// Whether any fixture in a parsed list is in play right now — drives the
// fast live-scores poll while the popup is open.
function anyLiveFixtures(list) {
  if (!list) return false
  for (var i = 0; i < list.length; i++) {
    if (fixtureIsLive(list[i])) return true
  }
  return false
}

// Match review lines for the expandable fixture row: per-team goal lines
// with the assisting player in parentheses. Own goals are attributed to the
// team that BENEFITS (FPL files the OG entry under the scorer's own side),
// and FPL's curious "assist" on an own goal is shown with it — e.g.
// "Donnarumma OG (Yeremy)". The stats array carries no goal↔assist links,
// so pairing only happens when the per-goal counts line up (FPL lists
// entries in event order); otherwise scorers and assists get separate
// lines rather than a guessed pairing. Returns [] until kickoff.
function fixtureGoalLines(f, elementsById) {
  if (!f || !f.stats || !f.started) return []
  function named(entries) {
    var out = []
    if (entries) {
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        if (!e || !e.value) continue
        var el = elementsById ? elementsById[e.element] : null
        out.push({ name: el ? el.web_name : "Player " + e.element, v: e.value })
      }
    }
    return out
  }
  function findStat(identifier, side) {
    for (var i = 0; i < f.stats.length; i++) {
      var s = f.stats[i]
      if (s && s.identifier === identifier) return side === 0 ? s.h : s.a
    }
    return null
  }
  function slot(p) {
    return p.name + (p.og ? " OG" : "") + (p.v > 1 ? " ×" + p.v : "")
  }
  // Expand value-counted entries into one slot per event: [{name, v:2}]
  // becomes [{name}, {name}] — the per-goal lists pairing needs.
  function expanded(list, og) {
    var out = []
    for (var i = 0; i < list.length; i++) {
      for (var n = 0; n < list[i].v; n++) out.push({ name: list[i].name, og: !!og })
    }
    return out
  }
  // Render the paired scorer/assister list, merging consecutive identical
  // pairs: "Haaland ×2 (Foden ×2), Cherki (Gvardiol, Semenyo)".
  function pairText(scorers, assists) {
    var parts = []
    var i = 0
    while (i < scorers.length) {
      var j = i
      var assisters = []
      while (j < scorers.length && scorers[j].name === scorers[i].name && scorers[j].og === scorers[i].og) {
        assisters.push(assists[j] ? assists[j].name : "")
        j++
      }
      var count = j - i
      var scorerText = scorers[i].name + (scorers[i].og ? " OG" : "") + (count > 1 ? " ×" + count : "")
      var aText = ""
      var seen = []
      for (var a = 0; a < assisters.length; a++) {
        if (assisters[a] !== "" && seen.indexOf(assisters[a]) < 0) seen.push(assisters[a])
      }
      if (seen.length === 1) {
        aText = seen[0] + (assisters.length > 1 ? " ×" + assisters.length : "")
      } else if (seen.length > 1) {
        var named2 = []
        for (var b = 0; b < assisters.length; b++) {
          if (assisters[b] !== "") named2.push(assisters[b])
        }
        aText = named2.join(", ")
      }
      parts.push(scorerText + (aText !== "" ? " (" + aText + ")" : ""))
      i = j
    }
    return parts.join(", ")
  }
  var lines = []
  for (var side = 0; side < 2; side++) {
    var team = side === 0 ? f.shortH : f.shortA
    var goals = named(findStat("goals_scored", side))
    // Own goals credited to this team were scored by the other side's player.
    var ogs = named(findStat("own_goals", 1 - side))
    var assists = named(findStat("assists", side))
    if (goals.length === 0 && ogs.length === 0) {
      if (assists.length > 0) {
        var assistParts = []
        for (var ai = 0; ai < assists.length; ai++) assistParts.push(slot(assists[ai]))
        lines.push({ team: team, text: "assists: " + assistParts.join(", ") })
      }
      continue
    }
    var scorers = goals.concat(ogs.map(function(p) { return { name: p.name, v: p.v, og: true } }))
    var expandedScorers = expanded(goals, false).concat(expanded(ogs, true))
    var expandedAssists = expanded(assists, false)
    if (expandedScorers.length === expandedAssists.length) {
      lines.push({ team: team, text: pairText(expandedScorers, expandedAssists) })
    } else {
      var scorerParts = []
      for (var sp = 0; sp < scorers.length; sp++) scorerParts.push(slot(scorers[sp]))
      lines.push({ team: team, text: scorerParts.join(", ") })
      if (assists.length > 0) {
        var assistParts2 = []
        for (var aj = 0; aj < assists.length; aj++) assistParts2.push(slot(assists[aj]))
        lines.push({ team: team, text: "assists: " + assistParts2.join(", ") })
      }
    }
  }
  var pens = []
  for (var ps = 0; ps < 2; ps++) {
    var missed = named(findStat("penalties_missed", ps))
    for (var m = 0; m < missed.length; m++) pens.push((ps === 0 ? f.shortH : f.shortA) + "  " + slot(missed[m]))
  }
  if (pens.length > 0) lines.push({ team: "", text: "Missed penalty: " + pens.join(", ") })
  return lines
}


// Goal involvements by the manager's own squad players across the current
// gameweek's fixtures — the Overview hero's "your players" feed. One entry
// per player per fixture: { name, fixture, goals, assists }, sorted by
// goals then assists. Only started fixtures are considered.
function squadGoalEvents(fixtures, squadPlayerIds, elementsById) {
  if (!fixtures || !squadPlayerIds) return []
  var out = {}
  for (var i = 0; i < fixtures.length; i++) {
    var f = fixtures[i]
    if (!f || !f.started || !f.stats) continue
    var label = f.shortH + " " + (f.scoreH !== null && f.scoreH !== undefined ? f.scoreH : "-")
      + "\u2013" + (f.scoreA !== null && f.scoreA !== undefined ? f.scoreA : "-") + " " + f.shortA
    for (var st = 0; st < f.stats.length; st++) {
      var stat = f.stats[st]
      if (!stat || (stat.identifier !== "goals_scored" && stat.identifier !== "assists")) continue
      var sides = [stat.h, stat.a]
      for (var side = 0; side < 2; side++) {
        var entries = sides[side]
        if (!entries) continue
        for (var e = 0; e < entries.length; e++) {
          var entry = entries[e]
          if (!entry || !entry.value || !squadPlayerIds[entry.element]) continue
          var el = elementsById ? elementsById[entry.element] : null
          var key = entry.element + ":" + f.id
          if (!out[key]) out[key] = {
            name: el ? el.web_name : "Player " + entry.element,
            fixture: label, goals: 0, assists: 0
          }
          if (stat.identifier === "goals_scored") out[key].goals += entry.value
          else out[key].assists += entry.value
        }
      }
    }
  }
  var list = []
  for (var k in out) list.push(out[k])
  list.sort(function(a, b) {
    if (b.goals !== a.goals) return b.goals - a.goals
    if (b.assists !== a.assists) return b.assists - a.assists
    return a.name < b.name ? -1 : 1
  })
  return list
}

// The gameweek where FPL resets the half-season chip allowance — the start
// of the second window (each chip type gets one). 0 when the season has
// only one window so far.
function chipResetEvent(bootstrapChips) {
  if (!bootstrapChips) return 0
  var reset = 0
  for (var i = 0; i < bootstrapChips.length; i++) {
    var c = bootstrapChips[i]
    if (!c || !c.name || !c.start_event || !c.stop_event) continue
    var windows = chipWindowsFor(bootstrapChips, c.name)
    if (windows.length >= 2) {
      var start = windows[1].start
      if (reset === 0 || start < reset) reset = start
    }
  }
  return reset
}

// ---- deadline countdown --------------------------------------------------
// Coarse "in 2d 4h"-style countdown for the next deadline. Returns "" for
// invalid input or a deadline already passed (the caller just hides it).

function formatTimeUntil(iso, nowMs) {
  if (!iso) return ""
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var ms = d.getTime() - (nowMs !== undefined ? nowMs : Date.now())
  if (ms <= 0) return ""
  var totalMinutes = Math.floor(ms / 60000)
  var days = Math.floor(totalMinutes / 1440)
  var hours = Math.floor((totalMinutes % 1440) / 60)
  var minutes = totalMinutes % 60
  if (days >= 2) return days + "d " + hours + "h"
  if (days >= 1) return days + "d " + hours + "h " + minutes + "m"
  if (hours >= 1) return hours + "h " + minutes + "m"
  return minutes + "m"
}
