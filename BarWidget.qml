import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.guillechuma.trystation"

  readonly property string triesPath: String(setting("triesPath", "~/Work/tries"))
  readonly property bool opened: summaryLoader.item ? summaryLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: summaryLoader.item ? summaryLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (summaryLoader.item) summaryLoader.item.open()
  }

  function close() {
    if (summaryLoader.item) summaryLoader.item.close()
  }

  function toggleSummary() {
    if (summaryLoader.item) summaryLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (summaryLoader.item) summaryLoader.item.closeForPopoutSwitch()
  }

  function openLibrary() {
    root.close()
    libraryLoader.pendingPayload = JSON.stringify({ path: root.triesPath })
    if (libraryLoader.item) {
      libraryLoader.item.open(libraryLoader.pendingPayload)
      libraryLoader.pendingPayload = ""
    } else {
      libraryLoader.active = true
    }
  }

  function closeLibrary() {
    if (libraryLoader.item) libraryLoader.item.close()
    Qt.callLater(function() { libraryLoader.active = false })
  }

  function libraryClosed() {
    Qt.callLater(function() { libraryLoader.active = false })
  }

  function startCreate() {
    if (!summaryLoader.item) return
    summaryLoader.item.openCreate()
  }

  function injectChildren() {
    var summary = summaryLoader.item
    if (summary) {
      summary.bar = root.bar
      summary.settings = root.settings
      summary.anchorItem = button
      summary.hostWidget = root
    }

    var library = libraryLoader.item
    if (library) {
      library.hostWidget = root
      library.shell = root.bar && root.bar.shell ? root.bar.shell : null
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectChildren()
  onSettingsChanged: injectChildren()

  Loader {
    id: summaryLoader
    active: true
    source: Qt.resolvedUrl("SummaryPanel.qml")
    visible: false
    onLoaded: {
      root.injectChildren()
      Qt.callLater(root.injectChildren)
    }
  }

  Loader {
    id: libraryLoader
    property string pendingPayload: ""
    active: false
    source: Qt.resolvedUrl("TryStation.qml")
    visible: false
    onLoaded: {
      root.injectChildren()
      Qt.callLater(root.injectChildren)
      if (pendingPayload) {
        item.open(pendingPayload)
        pendingPayload = ""
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "T\nR\nY" : "TRY"
    fixedHeight: root.vertical ? Style.bar.iconSlot * 3 : -1
    horizontalMargin: 8.5
    tooltipText: "TryStation · left: summary · right: library · middle: new"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openLibrary()
      else if (buttonCode === Qt.MiddleButton) root.startCreate()
      else root.toggleSummary()
    }
  }
}
