.pragma library

// Raw FPL "Fantasy" headline SVG (lion mark + wordmark), embedded so it can be
// recolored to the theme's foreground at runtime — see headlineSvgDataUri().
var FPL_HEADLINE_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="453" height="104" viewBox="0 0 453 104"><path fill="#37003C" d="M14.616562 7.93010475C17.2559993 9.1695844 19.7212401 10.755045 21.9482465 12.6453022 21.7227217 11.5736664 20.9057261 6.34837034 20.4248901 3.09917067 22.854601 4.81378791 28.5097425 8.74454794 30.3479826 10.0262243 31.1096608 7.6771987 33.730855 0 33.730855 0 33.730855 0 38.4626212 7.71577759 39.2711065 9.00174052 40.2583095 7.96011055 45.9177061 1.62031329 47.3814899 0 47.6282907 3.64784818 47.9644503 8.86885769 48.0410437 9.65329507 49.7771569 7.29275354 51.8259026 5.18275834 54.130214 3.38208251 52.5557954 6.50697243 51.8068828 10.8192348 51.4664679 14.2827616 40.7926673 11.2796783 29.3710353 12.6833891 19.7270397 18.1835159 18.6249467 14.8400122 16.9015966 10.6777789 14.616562 7.93010475ZM71.7126403 73.7671203 68.4276371 70.102126C67.4872411 80.0083271 62.6746264 88.4228112 53.8238407 94.2868022L52.4792021 88.9414829C44.9687998 94.4111119 32.0798431 97.9432234 21.0121057 91.6462916 22.3822754 84.5820686 23.6035137 77.4235416 20.9823194 68.8504554 14.8548524 78.413733 9.42523576 82.138739 9.42523576 82.138739 5.28919551 75.1345276 5.65939664 61.0746662 6.89340042 56.9381521L0 59.1114294C0 54.396232 3.37861724 44.3657211 8.26357013 38.7417766L3.95732246 38.0473566 3.95732246 38.0473566C6.87650719 32.0407286 11.2164296 26.8489079 16.5952232 22.9287191L16.5952232 22.9287191C14.9910183 25.5006449 14.9654872 31.7847171 19.6717223 34.1808947 17.6717851 30.6573563 17.4334948 26.3022285 19.5142804 24.0432203 21.5950661 21.7842121 25.1055941 22.5472167 27.352332 24.3132725 26.6842679 22.3457492 24.7311378 19.8681273 21.820591 19.7009521L21.820591 19.7009521C27.5187347 16.7503825 33.8344371 15.2145669 40.2412887 15.2214911 41.4838029 15.2214911 42.7107147 15.2772396 43.9220241 15.3886898L43.9220241 15.3886898C45.8538783 16.1688406 48.6878318 18.9122282 50.0111945 20.6139858 49.9988376 19.0793195 49.6516434 17.5661629 48.9942052 16.1817002 56.1854686 17.9391829 59.6321688 20.8968976 61.0491456 22.3157434 61.3427534 25.4406333 62.274639 27.3181392 63.5043876 30.2972867 61.1768011 27.6653492 55.321666 23.4388177 52.5302643 22.4100474 52.5302643 22.4100474 52.3004843 25.1234291 51.3430676 26.4308248 45.7815402 22.3843281 43.0454559 21.3727039 43.0454559 21.3727039 36.9350097 22.2300125 33.0117287 24.6261901 30.8798808 26.4908364L32.7351416 28.0811439C29.0544062 29.2256509 26.662992 32.414839 26.662992 32.414839 26.662992 32.414839 29.9522503 32.9377972 29.9522503 32.9377972 29.9522503 32.9377972 29.6203459 36.795686 34.4201951 39.2218694 38.526449 41.2922697 44.4411568 38.7203439 50.0069393 40.970779 46.3432247 36.7142417 43.8284101 34.8110166 43.8284101 34.8110166 43.0113529 34.641457 42.1814123 34.5425069 41.347637 34.5152451 40.0710813 34.5152451 38.1690134 34.7767242 36.0754622 33.9579945 35.0034307 33.495767 33.9739446 32.9392191 32.9989631 32.2948158 34.7481651 30.6161306 36.9457916 29.4883629 39.3221687 29.0499026 41.4855465 29.7075734 43.5320452 30.7058121 45.3858079 32.0076174 46.340026 30.9887833 47.644438 30.3754696 49.0325019 30.2930001 49.0325019 30.2930001 47.1900066 32.0076174 47.7559462 34.1508889 49.7290487 35.9907912 51.5945353 37.9444501 53.3430047 40.0020203 56.3216345 38.3645608 62.7384542 38.7417766 64.0575617 40.2849321 62.3852738 38.0987951 59.9683285 36.2727278 58.100302 34.7124261 57.8747772 33.8936963 55.8365434 31.0345721 55.4918734 30.773093 56.8415406 31.2398001 58.0875806 31.9678874 59.1598432 32.9163645 59.8253594 32.0296705 60.7785346 31.4062235 61.8533756 31.1545953 62.7464878 31.9337793 63.2883539 33.0440541 63.3554561 34.2323332 63.0311711 34.6324129 62.635798 34.9681948 62.1895353 35.2225247L65.3213517 38.6517592 65.6362355 36.1998565C72.8402644 46.5947236 76.7805661 58.6313366 71.7126403 73.7671203ZM58.0960469 51.3827922 58.0960469 46.0117537C56.3197297 45.3581775 54.6568118 44.4265618 53.1685421 43.2512199 48.0623196 44.0313708 41.87528 49.2095149 41.87528 49.2095149 41.87528 49.2095149 43.9688312 53.204573 46.2496106 57.5125489 50.2622505 58.0697995 56.1684479 52.9645266 58.0917917 51.3827922L58.0960469 51.3827922ZM63.2320557 61.1218181C62.8600416 59.5410305 62.120622 58.0718616 61.0746767 56.835275L57.0918231 56.9338655C57.0918231 56.9338655 51.7175239 61.5890513 48.4367759 61.6962149 48.4367759 61.6962149 50.2452297 65.082584 51.1515842 66.8400667 52.960038 66.4457047 56.1344064 65.0097127 57.410962 63.5137092 57.9518869 65.4652173 58.1831034 67.4906114 58.0960469 69.5148696 59.8832247 68.4432338 62.3639979 65.6055422 63.2278005 61.1218181L63.2320557 61.1218181ZM64.8703021 43.4698336C63.7119048 44.4613453 62.468813 45.3478196 61.1555252 46.1189173L61.1555252 51.5113885C62.5980331 53.1274153 64.0150098 54.4691032 65.0788062 56.9038597 67.1042744 53.2560115 66.7213078 47.8806865 64.8660469 43.4698336L64.8703021 43.4698336ZM247.753734 53.4622366 247.753734 82.7965634 235.200236 82.7965634 235.200236 54.8190351C235.200236 46.6868315 231.341578 42.5262691 224.854747 42.5262691 217.510436 42.5262691 212.386996 47.7516607 212.386996 58.6919219L212.386996 82.7965634 199.807774 82.7965634 199.807774 31.5130156 211.019317 31.5130156 212.275524 37.7044821C215.951252 33.0587354 220.977511 30.7358229 227.354299 30.7358229 239.826337 30.7143937 247.753734 39.5249965 247.753734 53.4622366ZM273.070813 16.6783992 273.070813 31.5130156 291.339411 31.5130156 291.339411 42.6207298 273.070813 42.6207298 273.070813 64.5957128C273.070813 69.3187455 275.291684 71.7575478 280.029258 71.7575478 283.038885 71.673238 285.985935 70.8772834 288.629776 69.4346745L292.788551 79.9885057C288.423751 82.3476345 283.540021 83.5784693 278.580118 83.5694728 267.364287 83.5694728 260.504452 77.0816938 260.504452 66.4376956L260.504452 42.6207298 252.2898 42.6207298 252.2898 31.5130156 260.495878 31.5130156 260.495878 16.6783992 273.070813 16.6783992ZM348.554723 31.5130156 348.554723 82.7965634 337.34318 82.7965634 336.086973 76.8884788C332.228316 81.0533349 326.418893 83.5694232 319.751991 83.5694232 305.350624 83.5694232 295.103746 72.6291621 295.103746 57.1419085 295.103746 41.5559006 305.350624 30.7143937 319.751991 30.7143937 326.418893 30.7143937 332.219741 33.230482 336.086973 37.3953381L337.34318 31.5130156 348.554723 31.5130156ZM335.988363 57.6485611 335.988363 56.6781925C335.988363 47.4854534 329.128528 42.3545225 321.779929 42.3545225 313.565277 42.3545225 307.670106 48.7434976 307.670106 57.1633768 307.670106 65.583256 313.565277 71.9722311 321.779929 71.9722311 329.12424 71.9507628 335.988363 66.8241255 335.988363 57.6270927L335.988363 57.6485611ZM360.503698 68.296853C364.215522 71.2585526 368.808872 72.8936617 373.554535 72.9425997 378.270671 72.9425997 381.091779 71.3925862 381.091779 68.5845286 381.091779 60.4566187 356.156278 64.0375362 356.156278 46.2231156 356.156278 37.0303765 363.792132 30.735862 375.196608 30.735862 381.657137 30.6840068 387.961902 32.7214076 393.173663 36.5451922L386.974087 45.9139716C383.299788 43.0114534 379.141013 41.3626856 374.969376 41.3626856 370.797739 41.3626856 368.688339 43.0114534 368.688339 45.3343267 368.688339 52.8825917 393.62384 49.3016742 393.62384 67.5969854 393.62384 77.0816938 385.50351 83.5694232 373.228693 83.5694232 366.368857 83.5694232 359.791991 81.7317342 354.865771 78.5372466L360.503698 68.296853ZM453 31.5130156 431.640188 85.6990816C426.225206 99.4388131 418.589352 103.994393 407.279199 103.994393 405.482973 104.039635 403.69033 103.810883 401.962827 103.315994L403.6049 90.8300126C404.688705 91.0360107 405.790244 91.1338128 406.893333 91.1219819 412.895689 91.1219819 416.557126 89.3787535 418.975218 83.4706689L395.977621 31.5130156 409.993121 31.5130156 425.749305 68.0091773 439.28033 31.5130156 453 31.5130156ZM102.055124 28.1983054 102.055124 43.6855589 131.535265 43.6855589 131.535265 55.8838643 102.055124 55.8838643 102.055124 82.7965634 89 82.7965634 89 16 135.110954 16 135.110954 28.1983054 102.055124 28.1983054ZM190.881413 31.5130156 190.881413 82.7965634 179.665583 82.7965634 178.409376 76.8884788C174.550718 81.0533349 168.745583 83.5694232 162.074393 83.5694232 147.673027 83.5694232 137.426148 72.6291621 137.426148 57.1419085 137.426148 41.5559006 147.673027 30.7143937 162.074393 30.7143937 168.745583 30.7143937 174.542144 33.230482 178.409376 37.3953381L179.665583 31.5130156 190.881413 31.5130156ZM178.315053 57.6485611 178.315053 56.6781925C178.315053 47.4854534 171.455218 42.3545225 164.102332 42.3545225 155.88768 42.3545225 149.992509 48.7434976 149.992509 57.1633768 149.992509 65.583256 155.88768 71.9722311 164.102332 71.9722311 171.450931 71.9507628 178.315053 66.8241255 178.315053 57.6270927L178.315053 57.6485611Z"/></svg>'

var FPL_HEADLINE_ASPECT = 453 / 104

function colorToHex(color) {
  function channel(v) {
    var n = Math.max(0, Math.min(255, Math.round(v * 255)))
    var s = n.toString(16)
    return s.length === 1 ? "0" + s : s
  }
  return "#" + channel(color.r) + channel(color.g) + channel(color.b)
}

function headlineSvgDataUri(color) {
  var recolored = FPL_HEADLINE_SVG.replace('fill="#37003C"', 'fill="' + colorToHex(color) + '"')
  return "data:image/svg+xml;utf8," + encodeURIComponent(recolored)
}


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
    default: return code ? String(code) : ""
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
      typeShort: el ? elementTypeShort(elementTypesById, el.element_type) : "",
      position: p.position,
      isCaptain: !!p.is_captain,
      isViceCaptain: !!p.is_vice_captain,
      multiplier: p.multiplier,
      livePoints: livePoints,
      contribution: contribution,
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
