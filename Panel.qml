import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Goals.js" as Goals

// Goal Tracker popup, TickTick-style rhythm: full-width title block,
// symmetric action rows (equal halves, never clipped), button-free
// goal rows, a dedicated action bar for the selected goal, archive.
// BarWidget.qml owns the store and hands itself over as `hostWidget`.
Panel {
  id: root
  moduleName: "io.github.adriansalvadorekomo.goal-tracker"
  ipcTarget: "io.github.adriansalvadorekomo.goal-tracker"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var goals: hostWidget ? hostWidget.goals : []
  readonly property var liveGoals: hostWidget ? hostWidget.liveGoals : []
  readonly property var archivedGoals: hostWidget ? hostWidget.archivedGoals : []
  readonly property var activeGoal: hostWidget ? hostWidget.activeGoal : null
  readonly property bool storeReady: hostWidget ? hostWidget.storeReady === true : false

  // Goal under inspection. "" follows the active goal, then the first
  // archived one, so the panel always has something selected and the
  // action bar below always has a target.
  property string viewId: ""

  readonly property var shownGoal: {
    if (viewId !== "") {
      var g = Goals.findGoal(root.goals, viewId)
      if (g) return g
    }
    if (root.activeGoal) return root.activeGoal
    return root.archivedGoals.length > 0 ? root.archivedGoals[0] : null
  }
  readonly property bool shownArchived: shownGoal && shownGoal.archived === true
  readonly property int shownValue: shownGoal && shownGoal.log ? Goals.logValue(shownGoal.log, root.todayKey) : 0
  readonly property int shownTarget: shownGoal ? shownGoal.target : 0
  readonly property string shownUnit: shownGoal ? String(shownGoal.unit) : ""
  readonly property int shownStreak: shownGoal ? Goals.streak(shownGoal.log, shownTarget, root.todayKey) : 0

  readonly property string todayKey: hostWidget ? hostWidget.todayKey : ""

  property string selectedDate: ""
  property string formError: ""
  property string deleteArmId: ""
  property string formEffort: "steady"

  // Keyboard cursor over the live goal list: visible only once a key is
  // pressed; mouse hover keeps it in sync (first-party idiom).
  property bool cursorActive: false
  property int cursor: -1
  onGoalsChanged: {
    if (cursor >= root.liveGoals.length) cursor = root.liveGoals.length - 1
    if (viewId !== "" && !Goals.findGoal(root.goals, viewId)) viewId = ""
  }

  readonly property color fg: Color.popups.text
  readonly property color muted: Util.alpha(fg, 0.6)

  function open() { root.controller.show() }
  function openFromHotkey() { root.controller.show() }
  function close() {
    selectedDate = ""
    formError = ""
    viewId = ""
    disarm()
    cursor = -1
    cursorActive = false
    root.controller.hide()
  }
  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Live goals become active; archived goals are only inspected.
  // Archiving keeps the inspect view so Restore is one click away.
  function selectGoal(id) {
    disarm()
    var g = Goals.findGoal(root.goals, id)
    if (g && g.archived === true) {
      viewId = id
      return
    }
    viewId = ""
    if (root.hostWidget) root.hostWidget.setActive(id)
  }

  function disarm() {
    deleteArmId = ""
    disarmTimer.stop()
  }

  function armDelete(id) {
    deleteArmId = id
    disarmTimer.restart()
  }

  function confirmDelete(id) {
    disarm()
    if (viewId === id) viewId = ""
    if (root.hostWidget) root.hostWidget.deleteGoal(id)
    if (cursor >= root.liveGoals.length) cursor = root.liveGoals.length - 1
  }

  function deletePressed(id) {
    if (root.deleteArmId === id) root.confirmDelete(id)
    else root.armDelete(id)
  }

  function archivePressed() {
    if (!root.shownGoal) return
    disarm()
    if (root.hostWidget) root.hostWidget.archiveGoal(root.shownGoal.id)
  }

  function restorePressed() {
    if (!root.shownGoal) return
    var id = root.shownGoal.id
    disarm()
    if (root.hostWidget) root.hostWidget.unarchiveGoal(id)
    root.selectGoal(id)
  }

  function archiveToggle() {
    var id = cursorId()
    if (id === "") id = root.shownGoal ? root.shownGoal.id : ""
    if (id === "") return
    var g = Goals.findGoal(root.goals, id)
    if (g && g.archived === true) {
      if (root.hostWidget) root.hostWidget.unarchiveGoal(id)
      root.selectGoal(id)
    } else {
      cursorActive = true
      root.syncCursorKeepActive(id)
      if (root.hostWidget) root.hostWidget.archiveGoal(id)
    }
  }

  function moveCursor(delta) {
    var count = root.liveGoals.length
    if (count === 0) { cursor = -1; return }
    disarm()
    cursorActive = true
    if (cursor < 0) cursor = delta > 0 ? 0 : count - 1
    else cursor = Math.max(0, Math.min(count - 1, cursor + delta))
  }

  function cursorToFirst() { cursorActive = true; disarm(); cursor = root.liveGoals.length > 0 ? 0 : -1 }
  function cursorToLast() { cursorActive = true; disarm(); cursor = root.liveGoals.length - 1 }

  function cursorId() {
    if (cursor < 0 || cursor >= root.liveGoals.length) return ""
    return root.liveGoals[cursor].id
  }

  function isCursorOn(id) {
    return cursorActive && cursorId() === id
  }

  function syncCursor(id) {
    cursorActive = false
    for (var i = 0; i < root.liveGoals.length; i++) {
      if (root.liveGoals[i].id === id) { cursor = i; return }
    }
  }

  function syncCursorKeepActive(id) {
    for (var i = 0; i < root.liveGoals.length; i++) {
      if (root.liveGoals[i].id === id) { cursor = i; return }
    }
  }

  function activateCursor() {
    var id = cursorId()
    if (id === "") return
    if (root.deleteArmId === id) root.confirmDelete(id)
    else root.selectGoal(id)
  }

  function deleteKey() {
    var id = cursorId()
    if (id === "") id = root.shownGoal ? root.shownGoal.id : ""
    if (id === "") return
    if (root.deleteArmId === id) root.confirmDelete(id)
    else {
      cursorActive = true
      root.syncCursorKeepActive(id)
      root.armDelete(id)
    }
  }

  function submitForm() {
    if (!hostWidget) return
    var target = Math.floor(Number(targetField.text) || 0)
    if (!(target >= 1)) {
      formError = "Set a daily target of at least 1."
      return
    }
    var start = String(startField.text || "").trim() || root.todayKey
    var end = String(endField.text || "").trim() || Goals.addDaysKey(root.todayKey, 90)
    if (!Goals.isValidDateKey(start) || !Goals.isValidDateKey(end)) {
      formError = "Dates must look like 2026-09-30."
      return
    }
    if (end < start) {
      formError = "End date is before the start date."
      return
    }
    var err = hostWidget.addGoal(nameField.text, target, unitField.text, start, end, formEffort, whyField.text)
    if (err !== "") {
      formError = err
      return
    }
    formError = ""
    nameField.text = ""
    unitField.text = ""
    targetField.text = ""
    formEffort = "steady"
    whyField.text = ""
    startField.text = ""
    endField.text = ""
    keyCatcher.forceActiveFocus()
  }

  readonly property string paceText: {
    if (!root.shownGoal) return ""
    if (root.shownArchived) return "archived"
    if (!Goals.isValidDateKey(root.shownGoal.endDate)) return ""
    return Goals.daysLeftLabel(root.shownGoal.endDate, root.todayKey)
  }

  function formatDate(dateString) {
    if (!dateString) return ""
    var parts = dateString.split("-")
    if (parts.length !== 3) return dateString
    var y = Number(parts[0])
    var m = Number(parts[1]) - 1 // JS months are 0-indexed
    var d = Number(parts[2])
    var date = new Date(y, m, d)
    if (isNaN(date.getTime())) return dateString

    // Format like "Fri 2 Oct 2026"
    var locale = Qt.locale("en_US")
    var dayName = locale.dayName(date.getDay(), Locale.ShortFormat) // Fri
    var dayNum = date.getDate() // 2 (no leading zero)
    var monthName = locale.monthName(date.getMonth(), Locale.ShortFormat) // Oct
    var year = date.getFullYear() // 2026
    return dayName + " " + dayNum + " " + monthName + " " + year
  }

  readonly property string statusText: {
    var day = heatmap.hoveredDay
    if (day) {
      var v = Number(day.value) || 0
      var formattedDate = formatDate(day.date)
      return formattedDate + "  ·  " + v + " / " + root.shownTarget + " " + root.shownUnit
    }
    if (root.selectedDate !== "") {
      var sv = root.shownGoal && root.shownGoal.log ? Goals.logValue(root.shownGoal.log, root.selectedDate) : 0
      var formattedDate = formatDate(root.selectedDate)
      return formattedDate + "  ·  " + sv + " / " + root.shownTarget + " " + root.shownUnit
    }
    return "Hover the graph · click a day to inspect"
  }

  Timer {
    id: disarmTimer
    interval: 3000
    onTriggered: root.disarm()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // contentWidth spans the whole card (padding + border included),
    // so the heatmap's content width needs those added on top —
    // otherwise the card comes out narrower than the graph and the
    // right-anchored legend gets clipped (the "Mo" bug).
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(360), heatmap.implicitWidth)
      + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || unitField.activeFocus || targetField.activeFocus
        || whyField.activeFocus || startField.activeFocus || endField.activeFocus
      onCloseRequested: {
        if (root.deleteArmId !== "") root.disarm()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy > 0 ? 1 : -1) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(t) {
        if (t === "+") {
          if (root.hostWidget) root.hostWidget.logToday(1)
        } else if (t === "-") {
          if (root.hostWidget) root.hostWidget.unlogToday(1)
        } else if (t === "g") root.cursorToFirst()
        else if (t === "G") root.cursorToLast()
        else if (t === "d" || t === "x") root.deleteKey()
        else if (t === "a") root.archiveToggle()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: Math.max(scroll.width, heatmap.implicitWidth)
          spacing: Style.space(12)

          // ---- title block, full width ----
          Column {
            width: parent.width
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              text: root.shownGoal ? root.shownGoal.name : "Goal Tracker"
              textFormat: Text.PlainText
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Text {
              width: parent.width
              text: !root.storeReady ? "Loading…" :
                (root.shownGoal ? (root.shownValue + " / " + root.shownTarget + " " + root.shownUnit + " today"
                  + (root.shownStreak > 0 ? "  ·  " + root.shownStreak + "-day streak" : "")
                  + (root.paceText !== "" ? "  ·  " + root.paceText : "")) : "No goals yet")
              textFormat: Text.PlainText
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }

          // ---- stepper: two equal halves, centered short labels ----
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: minusBtn
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignVCenter
              text: "- 1"
              bordered: true
              enabled: root.shownGoal !== null && !root.shownArchived && root.shownValue > 0
              foreground: root.fg
              fontSize: Style.font.body
              tooltipText: "Remove 1 from today (-)"
              onClicked: if (root.hostWidget) root.hostWidget.unlogToday(1)
            }

            Button {
              id: logBtn
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignVCenter
              text: "+ 1"
              bordered: true
              enabled: root.shownGoal !== null && !root.shownArchived
              foreground: root.fg
              fontSize: Style.font.body
              tooltipText: root.shownArchived ? "Archived — restore to log" : "Log 1 for today (+)"
              onClicked: if (root.hostWidget) root.hostWidget.logToday(1)
            }
          }

          // ---- live goal selector: TickTick rows, no buttons inside ----
          PanelSectionHeader {
            text: root.liveGoals.length > 0 ? "GOALS (" + root.liveGoals.length + ")" : "GOALS"
            foreground: root.fg
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.liveGoals.length > 0

            Repeater {
              model: root.liveGoals

              Rectangle {
                id: goalRow
                required property var modelData
                readonly property bool selected: root.shownGoal && !root.shownArchived && modelData.id === root.shownGoal.id
                readonly property bool cursorOn: root.isCursorOn(modelData.id)
                readonly property int gv: modelData.log ? Goals.logValue(modelData.log, root.todayKey) : 0
                readonly property bool gmet: gv >= modelData.target
                readonly property real ratio: Goals.progressRatio(gv, modelData.target)
                readonly property bool ended: Goals.isValidDateKey(modelData.endDate) && Goals.daysLeft(modelData.endDate, root.todayKey) < 0

                width: parent.width
                height: Math.max(Style.space(36), goalInner.implicitHeight + Style.space(16))
                radius: Style.space(6)
                color: (goalHover.containsMouse || goalRow.selected || goalRow.cursorOn)
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"
                border.width: (goalRow.selected || goalRow.cursorOn) ? 1 : 0
                border.color: goalRow.selected
                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
                  : Util.alpha(root.fg, 0.4)

                Row {
                  id: goalInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(8)
                  spacing: Style.space(10)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: goalRow.gmet ? "✓" : "●"
                    color: goalRow.gmet ? Color.accent : root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Style.space(50), parent.width - Style.space(24) - progressLabel.implicitWidth - parent.spacing * 2)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: goalRow.modelData.name + (goalRow.ended ? "  ·  ended" : "")
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: goalRow.selected
                  }

                  Text {
                    id: progressLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: goalRow.gv + " / " + goalRow.modelData.target + " " + goalRow.modelData.unit
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                // GitHub-green progress underline.
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.bottomMargin: Style.space(8)
                  height: Style.space(4)
                  radius: height / 2
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

                  Rectangle {
                    width: Math.max(0, Math.min(parent.width, parent.width * goalRow.ratio))
                    height: parent.height
                    radius: parent.radius
                    color: heatmap.colorFor(Goals.levelFor(goalRow.gv, goalRow.modelData.target))
                  }
                }

                MouseArea {
                  id: goalHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) root.syncCursor(goalRow.modelData.id)
                  onClicked: root.selectGoal(goalRow.modelData.id)
                }
              }
            }
          }

          // ---- action bar for the selected goal: equal halves ----
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.shownGoal !== null

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.shownArchived ? "ARCHIVED — RESTORE OR DELETE" : "SELECTED GOAL"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Button {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                visible: !root.shownArchived
                text: "Archive"
                bordered: true
                foreground: root.fg
                fontSize: Style.font.bodySmall
                tooltipText: "Archive this goal (a)"
                onClicked: root.archivePressed()
              }

              Button {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                visible: root.shownArchived
                text: "Restore"
                bordered: true
                foreground: Color.accent
                fontSize: Style.font.bodySmall
                tooltipText: "Move back to goals (a)"
                onClicked: root.restorePressed()
              }

              Button {
                id: deleteBtn
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                text: root.deleteArmId !== "" && root.shownGoal && root.deleteArmId === root.shownGoal.id ? "Sure?" : "Delete"
                bordered: true
                foreground: root.deleteArmId !== "" && root.shownGoal && root.deleteArmId === root.shownGoal.id ? Color.accent : root.fg
                fontSize: Style.font.bodySmall
                tooltipText: "Delete this goal (d)"
                onClicked: if (root.shownGoal) root.deletePressed(root.shownGoal.id)
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.liveGoals.length === 0 && root.archivedGoals.length === 0
            text: root.storeReady ? "No goals yet — add your first below." : "Loading…"
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // ---- archived goals: dimmed rows, click to inspect ----
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.archivedGoals.length > 0

            PanelSectionHeader {
              text: "ARCHIVED (" + root.archivedGoals.length + ")"
              foreground: root.fg
            }

            Repeater {
              model: root.archivedGoals

              Rectangle {
                id: archRow
                required property var modelData
                readonly property bool selected: root.shownArchived && root.shownGoal && modelData.id === root.shownGoal.id

                width: parent.width
                height: Style.space(32)
                radius: Style.space(6)
                color: (archHover.containsMouse || archRow.selected)
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
                border.width: archRow.selected ? 1 : 0
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▪"
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(24) - parent.spacing
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: archRow.modelData.name
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                }

                MouseArea {
                  id: archHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectGoal(archRow.modelData.id)
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }

          // ---- heatmap ----
          Heatmap {
            id: heatmap
            log: root.shownGoal && root.shownGoal.log ? root.shownGoal.log : ({})
            target: Math.max(1, root.shownTarget)
            todayKey: root.todayKey
            weeks: 26
            selectedDate: root.selectedDate
            surface: Color.popups.background
            ink: root.fg
            onDayClicked: function(date) { root.selectedDate = root.selectedDate === date ? "" : date }
          }

          // ---- status + legend: anchored pair, never a squeezed layout.
          // (The legend's swatch Repeater settles after the first layout
          // pass, so a RowLayout sibling would spill it past the edge.)
          Item {
            width: parent.width
            implicitHeight: Math.max(statusLine.implicitHeight, legend.implicitHeight)

            Text {
              id: statusLine
              anchors.left: parent.left
              anchors.right: legend.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: root.statusText
              textFormat: Text.PlainText
              color: root.muted
              elide: Text.ElideRight
              maximumLineCount: 1
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              id: legend
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Less"
                textFormat: Text.PlainText
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: 5

                Rectangle {
                  required property int index
                  anchors.verticalCenter: parent.verticalCenter
                  width: heatmap.cellSize
                  height: heatmap.cellSize
                  radius: heatmap.radius
                  color: heatmap.colorFor(index)
                  border.width: 1
                  border.color: heatmap.borderFor()
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "More"
                textFormat: Text.PlainText
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }

          // ---- new objective: one rail row per SMART dimension ----
          PanelSectionHeader { text: "NEW OBJECTIVE"; foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(10)

            // S — Specific: what exactly will you achieve?
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Text {
                Layout.preferredWidth: Style.space(20)
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "S"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: nameField
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                verticalPadding: Style.space(6)
                placeholderText: "Objective — e.g. Read 20 pages every day"
                foreground: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onAccepted: root.submitForm()
              }
            }

            // M — Measurable: daily target + unit, plain Row with
            // explicit widths (deterministic; no layout circularity).
            Row {
              id: mRow
              width: parent.width
              spacing: Style.space(10)

              Text {
                width: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "M"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Column {
                id: targetCol
                width: Style.space(90)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  text: "TARGET"
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  id: targetField
                  width: parent.width
                  verticalPadding: Style.space(6)
                  placeholderText: "e.g. 20"
                  inputMethodHints: Qt.ImhDigitsOnly
                  foreground: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  onAccepted: root.submitForm()
                }
              }

              Column {
                width: parent.width - Style.space(20) - targetCol.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  text: "UNIT"
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  id: unitField
                  width: parent.width
                  verticalPadding: Style.space(6)
                  placeholderText: "e.g. pages, km, sessions"
                  foreground: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  onAccepted: root.submitForm()
                }
              }
            }

            // A — Achievable: calibrate the pace in one tap.
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Text {
                Layout.preferredWidth: Style.space(20)
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "A"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: [
                  { value: "light", label: "Light", tip: "Easy pace" },
                  { value: "steady", label: "Steady", tip: "Sustainable pace" },
                  { value: "intense", label: "Intense", tip: "Stretch pace" }
                ]

                Button {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  Layout.alignment: Qt.AlignVCenter
                  text: modelData.label
                  bordered: true
                  selected: root.formEffort === modelData.value
                  foreground: root.fg
                  fontSize: Style.font.bodySmall
                  tooltipText: modelData.tip
                  onClicked: root.formEffort = modelData.value
                }
              }
            }

            // R — Relevant: why it matters (optional).
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Text {
                Layout.preferredWidth: Style.space(20)
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "R"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: whyField
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                verticalPadding: Style.space(6)
                placeholderText: "e.g. To stay sharp for exams (optional)"
                foreground: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onAccepted: root.submitForm()
              }
            }

            // T — Time-bound: start and deadline, plain Row with explicit
            // halves (same reason: no width bindings inside layouts).
            Row {
              id: tRow
              width: parent.width
              spacing: Style.space(10)

              Text {
                width: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "T"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Column {
                width: Math.floor((parent.width - Style.space(20) - parent.spacing * 2) / 2)
                spacing: Style.space(4)

                Text {
                  text: "START"
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  id: startField
                  width: parent.width
                  verticalPadding: Style.space(6)
                  placeholderText: "YYYY-MM-DD"
                  foreground: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  onAccepted: root.submitForm()
                }
              }

              Column {
                width: Math.floor((parent.width - Style.space(20) - parent.spacing * 2) / 2)
                spacing: Style.space(4)

                Text {
                  text: "END"
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  id: endField
                  width: parent.width
                  verticalPadding: Style.space(6)
                  placeholderText: "YYYY-MM-DD"
                  foreground: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  onAccepted: root.submitForm()
                }
              }
            }

            Text {
              id: formErrorText
              width: parent.width
              visible: root.formError !== ""
              text: root.formError
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Button {
              id: addBtn
              width: parent.width
              text: "Create Objective"
              bordered: true
              foreground: root.fg
              fontSize: Style.font.body
              verticalPadding: Style.space(10)
              onClicked: root.submitForm()
            }
          }
        }
      }
    }
  }
}