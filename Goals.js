.pragma library

// Pure helpers for goal-tracker. No QtQuick items here so BarWidget,
// Panel and Heatmap can share one implementation.

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

var EFFORTS = ["light", "steady", "intense"]

function cleanEffort(value) {
  var s = String(value || "").toLowerCase()
  return EFFORTS.indexOf(s) !== -1 ? s : "steady"
}

function keyOf(d) {
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function todayKeyOf(now) {
  return keyOf(now || new Date())
}

// Local-midnight Date for a "yyyy-MM-dd" key. Never `new Date(key)`,
// which parses as UTC midnight and shifts the day west of Greenwich.
function dateOfKey(key) {
  var parts = String(key || "").split("-")
  if (parts.length !== 3) return null
  var y = Number(parts[0]), m = Number(parts[1]), d = Number(parts[2])
  if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null
  if (m < 1 || m > 12 || d < 1 || d > 31) return null
  return new Date(y, m - 1, d)
}

function isValidDateKey(key) {
  var d = dateOfKey(key)
  return d !== null && keyOf(d) === String(key)
}

function addDaysKey(key, delta) {
  var d = dateOfKey(key)
  if (!d) return ""
  return keyOf(new Date(d.getFullYear(), d.getMonth(), d.getDate() + delta))
}

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function logValue(log, key) {
  if (!log || typeof log !== "object") return 0
  return Math.max(0, Math.floor(num(log[key], 0)))
}

// GitHub-style intensity from completion ratio value/target:
// 0 -> L0, (0, .34) -> L1, [.34, .67) -> L2, [.67, 1) -> L3, >= 1 -> L4.
function levelFor(value, target) {
  var t = num(target, 0)
  if (!(t > 0)) return 0
  var r = num(value, 0) / t
  if (!(r > 0)) return 0
  if (r >= 1) return 4
  if (r >= 0.67) return 3
  if (r >= 0.34) return 2
  return 1
}

// Consecutive days meeting target, ending today (or yesterday if today
// is still open) — same rule as commit-tracker History.streaks: a run
// that ended yesterday is still "current".
function streak(log, target, todayKey) {
  var t = num(target, 0)
  if (!(t > 0)) return 0
  var cursor = String(todayKey || "")
  if (!(logValue(log, cursor) >= t)) cursor = addDaysKey(cursor, -1)
  var n = 0
  var guard = 0
  while (guard < 3000 && cursor !== "" && logValue(log, cursor) >= t) {
    n++
    cursor = addDaysKey(cursor, -1)
    guard++
  }
  return n
}

// Days array oldest -> newest ending on todayKey, sized for `weeks`
// Sunday-aligned columns: (weeks-1)*7 + weekday offset + 1.
function buildDays(log, todayKey, weeks) {
  var w = Math.max(1, Math.min(53, Math.round(num(weeks, 26)) || 26))
  var today = dateOfKey(todayKey) || new Date()
  var endKey = keyOf(today)
  var offset = (today.getDay() + 7) % 7 // Sunday == 0, like github.com
  var count = (w - 1) * 7 + offset + 1
  var out = []
  for (var i = count - 1; i >= 0; i--) {
    var k = addDaysKey(endKey, -i)
    out.push({ date: k, value: logValue(log, k) })
  }
  return out
}

function sanitizeGoal(g) {
  if (!g || typeof g !== "object") return null
  var target = Math.max(1, Math.floor(num(g.target, 0)))
  if (!(target > 0)) return null
  var name = String(g.name || "").trim().slice(0, 60)
  if (name === "") return null
  var unit = String(g.unit || "").trim().slice(0, 24) || "units"
  var startDate = isValidDateKey(g.startDate) ? String(g.startDate) : ""
  var endDate = isValidDateKey(g.endDate) ? String(g.endDate) : ""
  var archivedAt = isValidDateKey(g.archivedAt) ? String(g.archivedAt) : ""
  var why = String(g.why || "").trim().slice(0, 140)
  var log = {}
  if (g.log && typeof g.log === "object") {
    for (var k in g.log) {
      if (isValidDateKey(k)) {
        var v = Math.max(0, Math.floor(num(g.log[k], 0)))
        if (v > 0) log[k] = Math.min(v, 1000000)
      }
    }
  }
  return {
    id: String(g.id || "").trim().slice(0, 64) || slugId(name),
    name: name,
    target: target,
    unit: unit,
    startDate: startDate,
    endDate: endDate,
    archived: g.archived === true,
    archivedAt: archivedAt,
    effort: cleanEffort(g.effort),
    why: why,
    log: log
  }
}

function slugId(name) {
  var s = String(name || "goal").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  if (s === "") s = "goal"
  return s.slice(0, 40) + "-" + String(Date.now() % 100000)
}

// Parse goals.json text into { activeId, goals }. Never throws.
function parseFile(raw) {
  var empty = { activeId: "", goals: [] }
  var text = String(raw || "").trim()
  if (text === "") return empty
  var data = null
  try { data = JSON.parse(text) } catch (e) { return empty }
  if (!data || typeof data !== "object") return empty
  var list = data.goals
  if (!(list instanceof Array)) {
    // Also accept a bare array for hand-edited files.
    if (data instanceof Array) list = data
    else return empty
  }
  var goals = []
  var seen = {}
  for (var i = 0; i < list.length && goals.length < 64; i++) {
    var g = sanitizeGoal(list[i])
    if (!g) continue
    if (seen[g.id]) g.id = g.id + "-" + goals.length
    seen[g.id] = true
    goals.push(g)
  }
  var activeId = String(data.activeId || "")
  var ok = false
  for (var j = 0; j < goals.length; j++) if (goals[j].id === activeId) ok = true
  if (!ok) activeId = goals.length > 0 ? goals[0].id : ""
  return { activeId: activeId, goals: goals }
}

function findGoal(goals, id) {
  for (var i = 0; i < goals.length; i++) {
    if (goals[i] && goals[i].id === id) return goals[i]
  }
  return goals.length > 0 ? goals[0] : null
}

function liveGoals(goals) {
  var out = []
  for (var i = 0; i < goals.length; i++) {
    if (goals[i] && goals[i].archived !== true) out.push(goals[i])
  }
  return out
}

function archivedGoals(goals) {
  var out = []
  for (var i = 0; i < goals.length; i++) {
    if (goals[i] && goals[i].archived === true) out.push(goals[i])
  }
  return out
}

// Active goal for the bar: the selected id when it is still live,
// otherwise the first live goal, otherwise null (all archived/empty).
function findLive(goals, id) {
  var live = liveGoals(goals)
  for (var i = 0; i < live.length; i++) {
    if (live[i].id === id) return live[i]
  }
  return live.length > 0 ? live[0] : null
}

// Days from todayKey until endDateKey (inclusive of neither end: plain
// date difference). Empty/unparseable end -> -1 (open-ended). Past -> <= 0.
function daysLeft(endDateKey, todayKey) {
  var end = dateOfKey(endDateKey)
  var today = dateOfKey(todayKey)
  if (!end || !today) return -1
  return Math.round((end - today) / 86400000)
}

function daysLeftLabel(endDateKey, todayKey) {
  var n = daysLeft(endDateKey, todayKey)
  if (n < 0 && !isValidDateKey(endDateKey)) return ""
  if (n < 0) return "ended"
  if (n === 0) return "last day"
  return n + (n === 1 ? " day left" : " days left")
}

// Compact twin of daysLeftLabel for the panel header subtitle,
// where "44 days left" would elide the streak.
function daysLeftShort(endDateKey, todayKey) {
  var n = daysLeft(endDateKey, todayKey)
  if (n < 0 && !isValidDateKey(endDateKey)) return ""
  if (n < 0) return "ended"
  if (n === 0) return "last day"
  return n + "d left"
}

// Ellipsize for fixed slots (bar label). Never returns "".
function clampName(name, max) {
  var s = String(name || "").trim()
  var m = Math.max(4, Math.floor(num(max, 16)))
  if (s === "") return "Goal"
  if (s.length <= m) return s
  return s.slice(0, m - 1).trimEnd() + "…"
}

function progressRatio(value, target) {
  var t = num(target, 0)
  if (!(t > 0)) return 0
  return Math.max(0, Math.min(1, num(value, 0) / t))
}

// Seed shown on first run so the heatmap is not empty.
function seedGoals(todayKey) {
  var end = dateOfKey(todayKey) || new Date()
  var endKey = keyOf(end)
  var startKey = addDaysKey(endKey, -29)
  var log = {}
  // Two demo weeks with a realistic spread across all 5 tiers.
  var demo = [0, 4, 10, 14, 20, 22, 8, 0, 20, 6, 16, 20, 25, 3]
  for (var i = 0; i < demo.length; i++) {
    var v = demo[i]
    if (v > 0) log[addDaysKey(endKey, -(demo.length - 1 - i))] = v
  }
  return {
    activeId: "read",
    goals: [{
      id: "read",
      name: "Read",
      target: 20,
      unit: "pages",
      startDate: startKey,
      endDate: addDaysKey(endKey, 60),
      log: log
    }]
  }
}
