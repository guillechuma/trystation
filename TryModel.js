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
    groups: groups,
    statusLabel: statusLabel,
    pathLabel: pathLabel
  }
}
