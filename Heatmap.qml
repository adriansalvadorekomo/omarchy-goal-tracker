import QtQuick
import qs.Commons
import "Goals.js" as Goals

// GitHub-style contribution graph for one goal: one column per week,
// Sunday on top, oldest week left, today in the last column.
// Pure Repeater grid — no Canvas, no effects, no dependencies.
Item {
  id: root

  property var log: ({})
  property int target: 1
  property string todayKey: ""
  property int weeks: 26
  property string selectedDate: ""
  property color surface: Color.popups.background
  property color ink: Color.popups.text

  // Exact spec geometry.
  readonly property int cellSize: 10
  readonly property int gap: 2
  readonly property int radius: 2
  readonly property int pitch: cellSize + gap
  readonly property int labelGutter: Style.space(30)
  readonly property int monthRowHeight: Style.font.caption + Style.space(6)

  property int hoveredCell: -1
  readonly property var hoveredDay: dayAtCell(hoveredCell)

  signal dayClicked(string date)

  // --- GitHub Primer contribution palette (2025 default) ---
  readonly property var darkScale: ["#151b23", "#033a16", "#196c2e", "#2ea043", "#56d364"]
  readonly property var lightScale: ["#ebedf0", "#9be9a8", "#40c463", "#30a14e", "#216e39"]

  function isDark(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b < 0.5
  }

  function colorFor(level) {
    var l = Math.max(0, Math.min(4, Math.round(Number(level) || 0)))
    return (isDark(root.surface) ? root.darkScale : root.lightScale)[l]
  }

  function borderFor() {
    return isDark(root.surface) ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(27, 31, 35, 0.06)
  }

  function dateOf(key) {
    var parts = String(key).split("-")
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  }

  readonly property var days: Goals.buildDays(root.log, root.todayKey, root.weeks)

  // Empty cells before the first day so every column starts on Sunday.
  readonly property int leading: days.length > 0 ? (dateOf(days[0].date).getDay() + 7) % 7 : 0
  readonly property int colCount: Math.max(1, Math.ceil((leading + days.length) / 7))

  function dayAtCell(cell) {
    var i = cell - leading
    return cell >= 0 && i >= 0 && i < days.length ? days[i] : null
  }

  function cellAt(x, y) {
    var col = Math.floor(x / pitch)
    var row = Math.floor(y / pitch)
    if (col < 0 || col >= colCount || row < 0 || row > 6) return -1
    return col * 7 + row
  }

  function levelOf(day) {
    if (!day) return 0
    return Goals.levelFor(day.value, root.target)
  }

  // Month label over the first column reaching it; dropped when the next
  // label would crowd it. Same rule as github.com.
  readonly property var monthLabels: {
    var names = Qt.locale("en_US")
    var changes = []
    var lastMonth = -1
    for (var c = 0; c < colCount; c++) {
      var i = Math.max(0, c * 7 - leading)
      if (i >= days.length) break
      var month = dateOf(days[i].date).getMonth()
      if (month !== lastMonth) changes.push({ col: c, text: names.monthName(month, Locale.ShortFormat) })
      lastMonth = month
    }
    var out = []
    for (var k = 0; k < changes.length; k++)
      if (k === changes.length - 1 || changes[k + 1].col - changes[k].col >= 3) out.push(changes[k])
    return out
  }

  implicitWidth: labelGutter + colCount * pitch - gap
  implicitHeight: monthRowHeight + 7 * pitch - gap

  Repeater {
    model: root.monthLabels

    Text {
      required property var modelData
      x: root.labelGutter + modelData.col * root.pitch
      y: 0
      text: modelData.text
      textFormat: Text.PlainText
      color: Util.alpha(root.ink, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // Mon / Wed / Fri wherever they fall (Sunday start: rows 1, 3, 5).
  Repeater {
    model: 7

    Text {
      required property int index
      visible: index === 1 || index === 3 || index === 5
      x: 0
      y: root.monthRowHeight + index * root.pitch + (root.cellSize - height) / 2
      text: Qt.locale("en_US").dayName(index, Locale.ShortFormat)
      textFormat: Text.PlainText
      color: Util.alpha(root.ink, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    model: root.colCount * 7

    Rectangle {
      required property int index
      readonly property var day: root.dayAtCell(index)
      readonly property bool marked: day !== null && (day.date === root.selectedDate || index === root.hoveredCell)
      readonly property bool today: day !== null && day.date === root.todayKey

      visible: day !== null
      x: root.labelGutter + Math.floor(index / 7) * root.pitch
      y: root.monthRowHeight + (index % 7) * root.pitch
      width: root.cellSize
      height: root.cellSize
      radius: root.radius
      color: root.colorFor(root.levelOf(day))
      border.width: marked ? 1 : 0
      border.color: marked ? Util.alpha(root.ink, 0.85) : root.borderFor()

      // Enhanced visual feedback for today
      opacity: today ? 1.0 : 0.9

      // Subtle scale effect on hover
      scale: marked && !today ? 1.05 : 1.0

      Behavior on scale {
        NumberAnimation { duration: 100; easing.type: Easing.InOutQuad }
      }
      Behavior on opacity {
        NumberAnimation { duration: 100; easing.type: Easing.InOutQuad }
      }
    }
  }

  MouseArea {
    x: root.labelGutter
    y: root.monthRowHeight
    width: root.colCount * root.pitch
    height: 7 * root.pitch
    hoverEnabled: true
    cursorShape: root.hoveredDay ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPositionChanged: function(mouse) { root.hoveredCell = root.cellAt(mouse.x, mouse.y) }
    onExited: root.hoveredCell = -1
    onClicked: function(mouse) {
      var day = root.dayAtCell(root.cellAt(mouse.x, mouse.y))
      if (day) root.dayClicked(day.date)
    }
  }
}