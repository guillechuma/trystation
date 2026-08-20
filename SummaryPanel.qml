import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TryModel.js" as TryModel

Panel {
  id: root
  moduleName: "io.github.guillechuma.trystation"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/trystation.py")).replace(/^file:\/\//, ""))
  readonly property string triesPath: String(setting("triesPath", "~/Work/tries"))

  property var sessions: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool loading: false
  property bool createMode: false
  property string statusText: "READY"
  property bool statusError: false

  readonly property color contentForeground: bar ? bar.barForeground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeSession: recentModel.count > 0 && selectedIndex >= 0 && selectedIndex < recentModel.count
    ? recentModel.get(selectedIndex) : null

  function open() {
    root.createMode = false
    searchField.text = ""
    root.controller.show()
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.createMode = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function openCreate() {
    if (!root.opened) root.controller.show()
    root.createMode = true
    createField.text = ""
    Qt.callLater(function() { createField.forceActiveFocus() })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (listProc.running) return
    root.loading = true
    root.statusText = "SCANNING…"
    root.statusError = false
    listProc.command = [root.helperPath, "list", "--path", root.triesPath]
    listProc.running = true
  }

  function applyListing(raw) {
    var listing = TryModel.parseListing(raw)
    root.sessions = listing.sessions
    root.rebuildRecent()
    root.loading = false
    root.statusText = listing.sessions.length + " " + (listing.sessions.length === 1 ? "TRY" : "TRIES") + " AVAILABLE"
    root.statusError = false
  }

  function rebuildRecent(preferredId) {
    var selectedId = preferredId || (root.activeSession ? String(root.activeSession.sessionId) : "")
    var rows = TryModel.fuzzyFiltered(root.sessions, root.filterText, 5)
    recentModel.clear()
    var restoredIndex = -1
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      recentModel.append({
        sessionId: String(row.id || ""),
        title: String(row.title || row.name || "Untitled"),
        sessionPath: String(row.path || ""),
        modified: Number(row.modified || 0),
        git: row.git === true,
        changes: Number(row.changes || 0),
        groupName: String(row.group || ""),
        language: String(row.language || "Folder"),
        icon: String(row.icon || "󰉋"),
        pinned: row.pinned === true,
        graduated: row.graduated === true
      })
      if (String(row.id || "") === selectedId) restoredIndex = i
    }
    if (recentModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = restoredIndex >= 0 ? restoredIndex : Math.min(root.selectedIndex, recentModel.count - 1)
  }

  function setPinState(sessionId, value) {
    for (var i = 0; i < root.sessions.length; i++) {
      if (String(root.sessions[i].id) === String(sessionId))
        root.sessions[i].pinned = value
    }
    root.sessions = TryModel.sortedSessions(root.sessions)
    root.rebuildRecent(String(sessionId))
  }

  function togglePinAt(index) {
    if (index < 0 || index >= recentModel.count || pinProc.running) return
    var row = recentModel.get(index)
    pinProc.sessionId = String(row.sessionId)
    pinProc.sessionPath = String(row.sessionPath)
    pinProc.previousValue = row.pinned
    pinProc.nextValue = !row.pinned
    root.setPinState(pinProc.sessionId, pinProc.nextValue)
    root.statusText = pinProc.nextValue ? "PINNING TRY…" : "UNPINNING TRY…"
    root.statusError = false
    pinProc.command = [root.helperPath, "set-pin", "--root", root.triesPath,
                       "--session", pinProc.sessionPath,
                       "--pinned", pinProc.nextValue ? "true" : "false"]
    pinProc.running = true
  }

  function toggleSelectedPin() {
    root.togglePinAt(root.selectedIndex)
  }

  function moveSelection(delta) {
    if (recentModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + recentModel.count) % recentModel.count
    recentList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function openSelected() {
    if (!root.activeSession) return
    var path = root.activeSession.sessionPath
    root.close()
    Quickshell.execDetached(["omarchy-launch-editor", path])
  }

  function openSelectedTerminal() {
    if (!root.activeSession) return
    root.openTerminalAt(root.selectedIndex)
  }

  function openTerminalAt(index) {
    if (index < 0 || index >= recentModel.count) return
    var path = recentModel.get(index).sessionPath
    root.close()
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + path])
  }

  function openLibrary() {
    root.close()
    if (root.hostWidget && typeof root.hostWidget.openLibrary === "function")
      root.hostWidget.openLibrary()
  }

  function submitCreate() {
    if (!createField.text.trim() || createProc.running) return
    createProc.command = [root.helperPath, "create", "--path", root.triesPath, "--name", createField.text]
    root.statusText = "WRITING…"
    root.statusError = false
    createProc.running = true
  }

  ListModel { id: recentModel }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    stderr: StdioCollector { id: listError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyListing(listOutput.text)
      else {
        root.loading = false
        root.statusText = listError.text.trim() || "SCAN FAILED"
        root.statusError = true
      }
    }
  }

  Process {
    id: createProc
    stdout: StdioCollector { id: createOutput; waitForEnd: true }
    stderr: StdioCollector { id: createError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var createdPath = ""
        try {
          var result = JSON.parse(createOutput.text)
          createdPath = String(result.path || "")
        } catch (e) {}

        if (createdPath) {
          root.close()
          Quickshell.execDetached(["omarchy-launch-editor", createdPath])
        } else {
          root.createMode = false
          root.statusText = "TRY CREATED, BUT ITS PATH WAS NOT RETURNED"
          root.statusError = true
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      } else {
        var detail = createError.text.trim()
        try {
          var parsed = JSON.parse(detail)
          detail = parsed.error || detail
        } catch (e) {}
        root.statusText = detail || "CREATE FAILED"
        root.statusError = true
        Qt.callLater(function() { createField.forceActiveFocus() })
      }
    }
  }

  Process {
    id: pinProc
    property string sessionId: ""
    property string sessionPath: ""
    property bool previousValue: false
    property bool nextValue: false
    stderr: StdioCollector { id: pinError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.statusText = pinProc.nextValue ? "TRY PINNED" : "TRY UNPINNED"
        root.statusError = false
      } else {
        root.setPinState(pinProc.sessionId, pinProc.previousValue)
        var detail = pinError.text.trim()
        try {
          var parsed = JSON.parse(detail)
          detail = parsed.error || detail
        } catch (e) {}
        root.statusText = detail || "COULD NOT UPDATE PIN"
        root.statusError = true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(summaryColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: createField.activeFocus || searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.openSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var slot = Number(text)
        if (slot >= 1 && slot <= 5) root.openTerminalAt(slot - 1)
        else if (text === "/") searchField.forceActiveFocus()
        else if (text === "p" || text === "P") root.toggleSelectedPin()
        else if (text === "n" || text === "N") root.openCreate()
        else if (text === "o" || text === "O") root.openLibrary()
        else if (text === "t" || text === "T") root.openSelectedTerminal()
        else if (text === "r" || text === "R") root.refresh()
      }

      Column {
        id: summaryColumn
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          height: Style.space(36)

          Column {
            width: parent.width - refreshButton.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              text: "TRY//STATION"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1.5
            }

            Text {
              text: root.statusText
              color: root.statusError ? Color.urgent : (root.loading ? Qt.darker(root.contentForeground, 1.5) : Color.accent)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.7
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PanelActionButton {
            id: refreshButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰑐"
            tooltipText: "Refresh"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.refresh()
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Fuzzy search tries…  /"
          foreground: root.contentForeground
          onTextChanged: {
            root.filterText = text
            root.selectedIndex = 0
            root.rebuildRecent()
          }
          onAccepted: root.openSelected()
          Keys.onEscapePressed: {
            if (text) text = ""
            keyCatcher.forceActiveFocus()
          }
          Keys.onDownPressed: {
            root.moveSelection(1)
            keyCatcher.forceActiveFocus()
          }
        }

        ListView {
          id: recentList
          width: parent.width
          height: recentModel.count > 0 ? recentModel.count * Style.space(58) + Math.max(0, recentModel.count - 1) * spacing : Style.space(92)
          model: recentModel
          spacing: Style.space(4)
          clip: true
          interactive: false

          delegate: CursorSurface {
            id: row
            required property int index
            required property string sessionId
            required property string title
            required property string sessionPath
            required property int modified
            required property bool git
            required property int changes
            required property string groupName
            required property string language
            required property string icon
            required property bool pinned
            required property bool graduated

            readonly property bool selectedRow: index === root.selectedIndex
            width: ListView.view.width
            height: Style.space(58)
            hasCursor: selectedRow
            foreground: root.contentForeground
            accent: Color.accent

            Text {
              id: shortcutNumber
              anchors.left: parent.left
              anchors.leftMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              text: String(row.index + 1)
              color: row.selectedRow ? Color.accent : Qt.darker(root.contentForeground, 1.7)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              id: rowIcon
              anchors.left: shortcutNumber.right
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              text: row.icon
              color: row.selectedRow ? Color.accent : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.iconLarge
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              anchors.left: rowIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: pinAction.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Row {
                width: parent.width
                Text {
                  width: parent.width - ageText.width
                  text: row.title
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: row.selectedRow
                  elide: Text.ElideRight
                }
                Text {
                  id: ageText
                  text: TryModel.relativeTime(row.modified)
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                text: (row.groupName ? row.groupName.toUpperCase() + "  ·  " : "")
                  + row.language + "  ·  "
                  + (row.graduated ? "GRADUATED" : (row.git ? (row.changes ? "DIRTY ×" + row.changes : "CLEAN") : "SCRATCH"))
                color: row.changes ? Color.urgent : Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Item {
              id: pinAction
              width: Style.space(34)
              height: parent.height
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              visible: row.pinned || row.selectedRow
              z: 2

              Text {
                anchors.centerIn: parent
                text: row.pinned ? "󰐃" : "󰤱"
                color: row.pinned ? Color.accent : Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                anchors.fill: parent
                enabled: !pinProc.running
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = row.index
                onClicked: root.togglePinAt(row.index)
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = row.index
              onClicked: {
                root.selectedIndex = row.index
                root.openSelected()
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: recentModel.count === 0
          spacing: Style.space(6)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)

          Text {
            width: parent.width
            text: root.filterText ? "[ NO MATCHING TRIES ]" : "[ NO TRIES YET ]"
            color: Color.accent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            width: parent.width
            text: root.filterText ? "Try another fuzzy search." : "Give your next idea a home."
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }
        }

        BorderSurface {
          width: parent.width
          height: root.createMode ? Style.space(92) : 0
          visible: root.createMode
          color: Util.alpha(root.contentForeground, 0.035)
          borderSpec: Border.flat(Util.alpha(root.contentForeground, 0.14), Style.normalBorderWidth)
          radius: Style.cornerRadius

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(7)

            TextField {
              id: createField
              width: parent.width
              placeholderText: "Name your new try…"
              foreground: root.contentForeground
              onAccepted: root.submitCreate()
              Keys.onEscapePressed: {
                root.createMode = false
                keyCatcher.forceActiveFocus()
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(6)
              Button {
                text: "CANCEL"
                foreground: root.contentForeground
                verticalPadding: Style.space(4)
                onClicked: {
                  root.createMode = false
                  keyCatcher.forceActiveFocus()
                }
              }
              Button {
                text: "CREATE & OPEN"
                bordered: true
                foreground: root.contentForeground
                accent: Color.accent
                verticalPadding: Style.space(4)
                onClicked: root.submitCreate()
              }
            }
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "NEW TRY"
            iconText: "+"
            bordered: true
            foreground: root.contentForeground
            accent: Color.accent
            onClicked: root.openCreate()
          }

          Item {
            width: parent.width - parent.children[0].width - libraryButton.width - parent.spacing * 2
            height: 1
          }

          Button {
            id: libraryButton
            text: "OPEN LIBRARY"
            iconText: "󰈙"
            foreground: root.contentForeground
            onClicked: root.openLibrary()
          }
        }

        Text {
          width: parent.width
          text: "1–5 TERMINAL  ·  / SEARCH  ·  P PIN  ·  ENTER EDIT  ·  N NEW  ·  O LIBRARY"
          color: Qt.darker(root.contentForeground, 1.7)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
