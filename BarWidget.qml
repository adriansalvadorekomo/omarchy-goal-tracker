import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Goals.js" as Goals

// Goal Tracker bar slot. Owns the JSON store so every monitor shares one
// source of truth; Panel.qml (loaded below) only presents it.
BarWidget {
  id: root
  moduleName: "omasmartg.goal-tracker"

  // ---- store ----
  property var goals: []
  property string activeId: ""
  property bool storeReady: false
  property bool _seeded: false

  readonly property var liveGoals: Goals.liveGoals(root.goals)
  readonly property var archivedGoals: Goals.archivedGoals(root.goals)
  readonly property var activeGoal: Goals.findLive(root.goals, root.activeId)
  readonly property int todayTarget: activeGoal ? activeGoal.target : 0
  readonly property string todayUnit: activeGoal ? String(activeGoal.unit) : ""
  readonly property string activeName: activeGoal ? String(activeGoal.name) : "Goals"
  // The bar slot is shared with every other widget: cap the label so a
  // `leetcode-hard-problems` goal cannot crowd its neighbors. Full name
  // stays in the tooltip.
  readonly property string shortName: Goals.clampName(activeName, 16)
  readonly property int todayValue: {
    if (!activeGoal || !activeGoal.log) return 0
    return Goals.logValue(activeGoal.log, root.todayKey)
  }
  readonly property bool met: todayTarget > 0 && todayValue >= todayTarget
  readonly property int currentStreak: {
    if (!activeGoal) return 0
    return Goals.streak(activeGoal.log, todayTarget, root.todayKey)
  }

  readonly property string displayText: activeGoal ? shortName + (met ? "  ✓" : "  ●") : "○  Goals"
  readonly property string tooltipText: {
    if (!activeGoal) return "Goal Tracker — click to add a goal"
    var s = activeName + "\n" + todayValue + " / " + todayTarget + " " + todayUnit + " today"
    if (currentStreak > 0) s += "\n" + currentStreak + "-day streak"
    s += "\nClick to open • middle-click to log +1"
    return s
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
  readonly property string todayKey: Qt.formatDate(clock.date, "yyyy-MM-dd")

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/goal-tracker"
  readonly property string filePath: stateDir + "/goals.json"

  function applyText(raw) {
    var parsed = Goals.parseFile(raw)
    // A valid-but-empty file means the user deleted every goal on
    // purpose: respect it. Seeding happens only for a missing file
    // (first run), via seedFresh() below.
    root.goals = parsed.goals
    root.activeId = parsed.activeId
    root.storeReady = true
  }

  function seedFresh() {
    if (root._seeded) return
    root._seeded = true
    var seed = Goals.seedGoals(root.todayKey)
    root.goals = seed.goals
    root.activeId = seed.activeId
    root.storeReady = true
    persist()
  }

  function persist() {
    if (!root.storeReady) return
    var data = { activeId: root.activeId, goals: root.goals }
    goalsFile.setText(JSON.stringify(data, null, 2) + "\n")
  }

  function touchGoal(id, mut) {
    var next = []
    for (var i = 0; i < root.goals.length; i++) {
      var g = root.goals[i]
      if (g.id === id) {
        var copy = { id: g.id, name: g.name, target: g.target, unit: g.unit,
          startDate: g.startDate, endDate: g.endDate, log: Object.assign({}, g.log),
          archived: g.archived === true, archivedAt: g.archivedAt || "",
          effort: g.effort || "steady", why: g.why || "" }
        mut(copy)
        var clean = Goals.sanitizeGoal(copy)
        next.push(clean || g)
      } else {
        next.push(g)
      }
    }
    root.goals = next
    saveDebounce.restart()
  }

  // Peers converge through FileView watchChanges after persist();
  // no broadcast here: reloading our own just-written state would
  // clobber it with the still-stale file.

  function logToday(amount) {
    if (!activeGoal) return
    var n = Math.max(1, Math.floor(Number(amount) || 1))
    touchGoal(activeGoal.id, function(g) {
      var k = root.todayKey
      g.log[k] = Goals.logValue(g.log, k) + n
    })
  }

  function unlogToday(amount) {
    if (!activeGoal) return
    var n = Math.max(1, Math.floor(Number(amount) || 1))
    touchGoal(activeGoal.id, function(g) {
      var k = root.todayKey
      g.log[k] = Math.max(0, Goals.logValue(g.log, k) - n)
      if (g.log[k] === 0) delete g.log[k]
    })
  }

  function deleteGoal(id) {
    var next = []
    for (var i = 0; i < root.goals.length; i++) {
      if (root.goals[i].id !== id) next.push(root.goals[i])
    }
    if (next.length === root.goals.length) return
    root.goals = next
    var ok = false
    for (var j = 0; j < next.length; j++) if (next[j].id === root.activeId) ok = true
    if (!ok) root.activeId = next.length > 0 ? next[0].id : ""
    saveDebounce.restart()
  }

  function archiveGoal(id) {
    var wasActive = activeGoal && activeGoal.id === id
    touchGoal(id, function(g) {
      g.archived = true
      g.archivedAt = root.todayKey
    })
    // The bar only shows live goals: move on when archiving the active one.
    if (wasActive) {
      var live = Goals.liveGoals(root.goals)
      root.activeId = live.length > 0 ? live[0].id : ""
      saveDebounce.restart()
    }
  }

  function unarchiveGoal(id) {
    touchGoal(id, function(g) {
      g.archived = false
      g.archivedAt = ""
    })
    if (!activeGoal) {
      root.activeId = id
      saveDebounce.restart()
    }
  }

  function setActive(id) {
    for (var i = 0; i < root.goals.length; i++) {
      if (root.goals[i].id === id) {
        root.activeId = id
        saveDebounce.restart()
        return
      }
    }
  }

  function addGoal(name, target, unit, startDate, endDate, effort, why) {
    var g = Goals.sanitizeGoal({
      id: "", name: name, target: target, unit: unit,
      startDate: startDate, endDate: endDate, log: {},
      effort: effort, why: why
    })
    if (!g) return "Give the goal a name and a target of at least 1."
    for (var i = 0; i < root.goals.length; i++) {
      if (root.goals[i].id === g.id) g.id = g.id + "-" + root.goals.length
    }
    var next = root.goals.concat([g])
    root.goals = next
    root.activeId = g.id
    saveDebounce.restart()
    return ""
  }

  Timer {
    id: saveDebounce
    interval: 300
    onTriggered: root.persist()
  }

  FileView {
    id: goalsFile
    path: root.filePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyText(text())
    onFileChanged: reload()
    onLoadFailed: root.seedFresh()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  Component.onCompleted: mkdirProc.running = true

  // ---- panel plumbing (ticktick pattern) ----
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function focusedInstance() {
    if (root.bar && typeof root.bar.findPanelWidget === "function") {
      var item = root.bar.findPanelWidget(root.moduleName)
      if (item) return item
    }
    return root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    target: "omasmartg.goal-tracker"

    function open(): void { root.focusedInstance().open() }
    function close(): void { root.focusedInstance().close() }
    function show(): void { root.focusedInstance().open() }
    function hide(): void { root.focusedInstance().close() }
    function toggle(): void { root.focusedInstance().togglePanel() }
    function log(amount: string): void { root.focusedInstance().logToday(Number(amount) || 1) }
    function unlog(amount: string): void { root.focusedInstance().unlogToday(Number(amount) || 1) }
    function select(id: string): void { root.focusedInstance().setActive(String(id || "")) }
    function archive(id: string): void {
      var w = root.focusedInstance()
      var g = w.activeGoal
      w.archiveGoal(String(id || (g ? g.id : "")))
    }
    function unarchive(id: string): void {
      var w = root.focusedInstance()
      var g = w.activeGoal
      var target = String(id || (g ? g.id : ""))
      w.unarchiveGoal(target)
      w.setActive(target)
    }
    function remove(id: string): void {
      var w = root.focusedInstance()
      var g = w.activeGoal
      w.deleteGoal(String(id || (g ? g.id : "")))
    }
    function add(name: string, target: string, unit: string, start: string, end: string, effort: string, why: string): string {
      var w = root.focusedInstance()
      var s = String(start || "").trim() || w.todayKey
      var e = String(end || "").trim() || Goals.addDaysKey(w.todayKey, 90)
      if (!Goals.isValidDateKey(s) || !Goals.isValidDateKey(e)) return "Dates must look like 2026-09-30."
      if (e < s) return "End date is before the start date."
      return w.addGoal(String(name || ""), Math.floor(Number(target) || 0), String(unit || ""),
        s, e, String(effort || "steady"), String(why || ""))
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    tooltipText: root.tooltipText
    active: false
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.logToday(1)
      else root.togglePanel()
    }
  }
}
