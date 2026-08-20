function parsePayload(raw) {
  try {
    var value = JSON.parse(String(raw || "{}"))
    return value && typeof value === "object" ? value : {}
  } catch (e) {
    return {}
  }
}

function parseListing(raw) {
  try {
    var value = JSON.parse(String(raw || "{}"))
    return {
      path: String(value.path || ""),
      exists: value.exists === true,
      sessions: Array.isArray(value.sessions) ? value.sessions : []
    }
  } catch (e) {
    return { path: "", exists: false, sessions: [] }
  }
}

function relativeTime(timestamp, nowSeconds) {
  var seconds = Math.max(0, Number(nowSeconds || Date.now() / 1000) - Number(timestamp || 0))
  if (seconds < 60) return "just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d ago"
  var weeks = Math.floor(days / 7)
  if (weeks < 8) return weeks + "w ago"
  return Math.floor(days / 30) + "mo ago"
}

function searchText(session) {
  return [session.title, session.name, session.group, session.note, session.language,
          session.branch, session.remote].join(" ").toLowerCase()
}

function filtered(sessions, query, group) {
  var values = Array.isArray(sessions) ? sessions : []
  var needle = String(query || "").trim().toLowerCase()
  var selectedGroup = String(group || "")
  var out = []
  for (var i = 0; i < values.length; i++) {
    var row = values[i]
    if (selectedGroup && String(row.group || "") !== selectedGroup) continue
    if (needle && searchText(row).indexOf(needle) === -1) continue
    out.push(row)
  }
  return out
}

function fuzzyTokenScore(text, token) {
  var value = String(text || "").toLowerCase()
  var needle = String(token || "").toLowerCase()
  if (!needle) return 0

  var exact = value.indexOf(needle)
  if (exact >= 0) return exact

  var score = 20
  var previous = -1
  var cursor = 0
  for (var i = 0; i < needle.length; i++) {
    var found = value.indexOf(needle.charAt(i), cursor)
    if (found < 0) return Number.POSITIVE_INFINITY
    if (previous >= 0) score += found - previous - 1
    if (found === 0 || /[\s._/-]/.test(value.charAt(found - 1))) score -= 2
    previous = found
    cursor = found + 1
  }
  return score
}

function fuzzyScore(session, query) {
  var terms = String(query || "").trim().toLowerCase().split(/\s+/).filter(Boolean)
  if (terms.length === 0) return 0
  var text = searchText(session)
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var score = fuzzyTokenScore(text, terms[i])
    if (!isFinite(score)) return Number.POSITIVE_INFINITY
    total += score
  }
  return total
}

function fuzzyFiltered(sessions, query, limit) {
  var values = Array.isArray(sessions) ? sessions : []
  var needle = String(query || "").trim()
  var maximum = Math.max(0, Number(limit || values.length))
  if (!needle) return values.slice(0, maximum)

  var ranked = []
  for (var i = 0; i < values.length; i++) {
    var score = fuzzyScore(values[i], needle)
    if (isFinite(score)) ranked.push({ row: values[i], score: score, order: i })
  }
  ranked.sort(function(a, b) {
    if (a.score !== b.score) return a.score - b.score
    if (!!a.row.pinned !== !!b.row.pinned) return a.row.pinned ? -1 : 1
    if (Number(a.row.modified || 0) !== Number(b.row.modified || 0))
      return Number(b.row.modified || 0) - Number(a.row.modified || 0)
    return a.order - b.order
  })
  return ranked.slice(0, maximum).map(function(entry) { return entry.row })
}

function sortedSessions(sessions) {
  var values = Array.isArray(sessions) ? sessions.slice() : []
  values.sort(function(a, b) {
    if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1
    var modified = Number(b.modified || 0) - Number(a.modified || 0)
    if (modified !== 0) return modified
    return String(a.name || "").localeCompare(String(b.name || ""))
  })
  return values
}

function groups(sessions) {
  var values = Array.isArray(sessions) ? sessions : []
  var seen = {}
  var out = []
  for (var i = 0; i < values.length; i++) {
    var group = String(values[i].group || "").trim()
    if (!group || seen[group]) continue
    seen[group] = true
    out.push(group)
  }
  out.sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
  return out
}

function statusLabel(session) {
  if (!session) return ""
  if (session.graduated) return "GRADUATED"
  if (!session.git) return "SCRATCH"
  if (Number(session.changes || 0) > 0) return "DIRTY ×" + session.changes
  return "CLEAN"
}

function pathLabel(path, home) {
  var value = String(path || "")
  var base = String(home || "")
  return base && value.indexOf(base + "/") === 0 ? "~/" + value.slice(base.length + 1) : value
}

if (typeof module !== "undefined") {
  module.exports = {
    parsePayload: parsePayload,
    parseListing: parseListing,
    relativeTime: relativeTime,
    searchText: searchText,
    filtered: filtered,
    fuzzyTokenScore: fuzzyTokenScore,
    fuzzyScore: fuzzyScore,
    fuzzyFiltered: fuzzyFiltered,
    sortedSessions: sortedSessions,
    groups: groups,
    statusLabel: statusLabel,
    pathLabel: pathLabel
  }
}
