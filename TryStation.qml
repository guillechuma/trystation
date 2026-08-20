import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TryModel.js" as TryModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var hostWidget: null
  readonly property bool opened: stationWindow.visible
  readonly property string pluginId: "io.github.guillechuma.trystation"
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/trystation.py")).replace(/^file:\/\//, ""))
  readonly property string homePath: Quickshell.env("HOME")

  property string triesPath: homePath + "/Work/tries"
  property var sessions: []
  property var groupNames: []
  property string filterText: ""
  property string selectedGroup: ""
  property int selectedIndex: 0
  property bool loading: false
  property string message: ""
  property bool messageError: false
  property bool createOpen: false
  property bool deleteOpen: false
  property bool draftPinned: false
  property var groupSuggestions: []
  property int groupSuggestionIndex: -1
  property bool closingFromHost: false

  readonly property color background: Color.background
  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dimForeground: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: Style.font.family
  readonly property var activeSession: displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count
    ? displayModel.get(selectedIndex) : null

  function open(payloadJson) {
    var payload = TryModel.parsePayload(payloadJson)
    if (payload.path) root.triesPath = String(payload.path)
    root.closingFromHost = false
    stationWindow.visible = true
    root.refresh()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.closingFromHost = true
    root.createOpen = false
    root.deleteOpen = false
    stationWindow.visible = false
    root.closingFromHost = false
  }

  function requestClose() {
    if (root.hostWidget && typeof root.hostWidget.closeLibrary === "function")
      root.hostWidget.closeLibrary()
    else if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    else
      stationWindow.visible = false
  }

  function refresh() {
    if (!root.helperPath || listProc.running) return
    root.loading = true
    root.message = "SCANNING TRIES…"
    root.messageError = false
    listProc.command = [root.helperPath, "list", "--path", root.triesPath]
    listProc.running = true
  }

  function applyListing(raw) {
    var listing = TryModel.parseListing(raw)
    if (listing.path) root.triesPath = listing.path
    root.sessions = listing.sessions
    root.groupNames = TryModel.groups(root.sessions)
    root.loading = false
    root.message = listing.exists ? (listing.sessions.length + " TRIES ONLINE") : "TRY DIRECTORY WILL BE CREATED WITH YOUR FIRST IDEA"
    root.messageError = false
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = TryModel.filtered(root.sessions, root.filterText, root.selectedGroup)
    var selectedId = root.activeSession ? String(root.activeSession.sessionId) : ""
    displayModel.clear()
    var restore = -1
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        sessionId: String(row.id || ""),
        name: String(row.name || ""),
        title: String(row.title || row.name || "Untitled"),
        sessionPath: String(row.path || ""),
        created: String(row.created || ""),
        modified: Number(row.modified || 0),
        git: row.git === true,
        worktree: row.worktree === true,
        branch: String(row.branch || ""),
        changes: Number(row.changes || 0),
        remote: String(row.remote || ""),
        language: String(row.language || "Folder"),
        icon: String(row.icon || "󰉋"),
        readme: String(row.readme || ""),
        groupName: String(row.group || ""),
        note: String(row.note || ""),
        pinned: row.pinned === true,
        graduated: row.graduated === true,
        target: String(row.target || "")
      })
      if (String(row.id || "") === selectedId) restore = i
    }
    if (displayModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = restore >= 0 ? restore : Math.min(root.selectedIndex, displayModel.count - 1)
    root.syncDraft()
    Qt.callLater(function() {
      if (displayModel.count > 0) sessionList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function updateGroupSuggestions() {
    var needle = groupField.text.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.groupNames.length; i++) {
      var group = String(root.groupNames[i] || "")
      if (!group || group.toLowerCase() === needle) continue
      if (!needle || group.toLowerCase().indexOf(needle) !== -1) out.push(group)
      if (out.length >= 6) break
    }
    root.groupSuggestions = out
    root.groupSuggestionIndex = out.length > 0 ? 0 : -1
    if (groupField.activeFocus && out.length > 0) groupPopup.open()
    else groupPopup.close()
  }

  function applyGroupSuggestion(index) {
    if (index < 0 || index >= root.groupSuggestions.length) return
    groupField.text = root.groupSuggestions[index]
    groupPopup.close()
    groupField.forceActiveFocus()
    groupField.cursorPosition = groupField.text.length
  }

  function syncDraft() {
    var row = root.activeSession
    if (!row) {
      groupField.text = ""
      noteField.text = ""
      root.draftPinned = false
      return
    }
    groupField.text = row.groupName
    noteField.text = row.note
    root.draftPinned = row.pinned
    root.updateGroupSuggestions()
  }

  function setPinState(sessionId, value) {
    for (var i = 0; i < displayModel.count; i++) {
      if (String(displayModel.get(i).sessionId) === String(sessionId))
        displayModel.setProperty(i, "pinned", value)
    }
    for (var j = 0; j < root.sessions.length; j++) {
      if (String(root.sessions[j].id) === String(sessionId))
        root.sessions[j].pinned = value
    }
    if (root.activeSession && String(root.activeSession.sessionId) === String(sessionId))
      root.draftPinned = value
  }

  function togglePin() {
    var row = root.activeSession
    if (!row || pinProc.running) return
    pinProc.sessionId = row.sessionId
    pinProc.previousValue = row.pinned
    pinProc.nextValue = !row.pinned
    root.setPinState(pinProc.sessionId, pinProc.nextValue)
    root.message = pinProc.nextValue ? "PINNING TRY…" : "UNPINNING TRY…"
    root.messageError = false
    pinProc.command = [root.helperPath, "set-pin", "--root", root.triesPath,
                       "--session", row.sessionPath, "--pinned", pinProc.nextValue ? "true" : "false"]
    pinProc.running = true
  }

  function selectIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.selectedIndex = index
    root.syncDraft()
    sessionList.positionViewAtIndex(index, ListView.Contain)
  }

  function moveSelection(delta) {
    if (displayModel.count === 0) return
    root.selectIndex((root.selectedIndex + delta + displayModel.count) % displayModel.count)
  }

  function setGroup(group) {
    root.selectedGroup = group
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function startCreate() {
    root.createOpen = true
    createField.text = ""
    Qt.callLater(function() { createField.forceActiveFocus() })
  }

  function submitCreate() {
    if (!createField.text.trim() || actionProc.running) return
    root.createOpen = false
    root.runAction(["create", "--path", root.triesPath, "--name", createField.text], "TRY CREATED")
  }

  function saveMetadata() {
    var row = root.activeSession
    if (!row || actionProc.running) return
    var args = ["set-meta", "--root", root.triesPath, "--session", row.sessionPath,
                "--group", groupField.text, "--note", noteField.text]
    if (root.draftPinned) args.push("--pinned")
    root.runAction(args, "TRY DETAILS SAVED")
  }

  function requestTrash() {
    if (!root.activeSession) return
    deleteConfirm.selectedIndex = 0
    root.deleteOpen = true
  }

  function confirmTrash() {
    var row = root.activeSession
    root.deleteOpen = false
    if (!row) return
    root.runAction(["trash", "--root", root.triesPath, "--session", row.sessionPath], "MOVED TO TRASH")
  }

  function runAction(args, successMessage) {
    if (!root.helperPath || actionProc.running) return
    actionProc.successMessage = successMessage
    actionProc.command = [root.helperPath].concat(args)
    root.message = "WRITING…"
    root.messageError = false
    actionProc.running = true
  }

  function openTerminal() {
    if (!root.activeSession) return
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + root.activeSession.sessionPath])
  }

  function openEditor() {
    if (!root.activeSession) return
    Quickshell.execDetached(["omarchy-launch-editor", root.activeSession.sessionPath])
  }

  function openFiles() {
    if (!root.activeSession) return
    Quickshell.execDetached(["nautilus", "--new-window", root.activeSession.sessionPath])
  }

  function copyPath() {
    if (!root.activeSession) return
    Quickshell.execDetached(["wl-copy", root.activeSession.sessionPath])
    root.message = "PATH COPIED"
    root.messageError = false
  }

  ListModel { id: displayModel }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    stderr: StdioCollector { id: listError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyListing(listOutput.text)
      else {
        root.loading = false
        root.message = listError.text.trim() || "COULD NOT READ TRY DIRECTORY"
        root.messageError = true
      }
    }
  }

  Process {
    id: actionProc
    property string successMessage: "DONE"
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.message = successMessage
        root.messageError = false
        root.refresh()
      } else {
        var detail = actionError.text.trim()
        try {
          var parsed = JSON.parse(detail)
          detail = parsed.error || detail
        } catch (e) {}
        root.message = detail || "OPERATION FAILED"
        root.messageError = true
      }
    }
  }

  Process {
    id: pinProc
    property string sessionId: ""
    property bool previousValue: false
    property bool nextValue: false
    stderr: StdioCollector { id: pinError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.message = pinProc.nextValue ? "TRY PINNED" : "TRY UNPINNED"
        root.messageError = false
      } else {
        root.setPinState(pinProc.sessionId, pinProc.previousValue)
        var detail = pinError.text.trim()
        try {
          var parsed = JSON.parse(detail)
          detail = parsed.error || detail
        } catch (e) {}
        root.message = detail || "COULD NOT UPDATE PIN"
        root.messageError = true
      }
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: {
      if (!actionProc.running && !pinProc.running
          && !groupField.activeFocus && !noteField.activeFocus)
        root.refresh()
    }
  }

  FloatingWindow {
    id: stationWindow
    title: "TryStation"
    visible: false
    color: root.background
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(780, 540)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && !root.hostWidget
          && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId)
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.createOpen || root.deleteOpen || groupField.activeFocus || noteField.activeFocus || searchField.activeFocus) return
        if (event.key === Qt.Key_Escape) {
          root.requestClose(); event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveSelection(-1); event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.openEditor(); event.accepted = true
        } else if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) {
          root.startCreate(); event.accepted = true
        } else if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) {
          root.refresh(); event.accepted = true
        } else if (event.key === Qt.Key_Slash) {
          searchField.forceActiveFocus(); event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(12)

        Row {
          width: parent.width
          height: Style.space(54)
          spacing: Style.space(14)

          Column {
            width: parent.width - newButton.width - refreshButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "TRY//STATION"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              font.bold: true
              font.letterSpacing: 2
            }

            Text {
              width: parent.width
              text: "EPHEMERAL IDEA WORKBENCH  ·  " + TryModel.pathLabel(root.triesPath, root.homePath)
              color: root.dimForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              elide: Text.ElideMiddle
            }
          }

          Button {
            id: refreshButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰑐"
            tooltipText: "Rescan tries (Ctrl+R)"
            foreground: root.foreground
            onClicked: root.refresh()
          }

          Button {
            id: newButton
            anchors.verticalCenter: parent.verticalCenter
            text: "NEW TRY"
            iconText: "+"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            onClicked: root.startCreate()
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: Util.alpha(root.foreground, 0.18)
        }

        Row {
          width: parent.width
          height: Style.space(34)
          spacing: Style.space(8)

          TextField {
            id: searchField
            width: Math.min(Style.space(330), parent.width * 0.42)
            height: parent.height
            placeholderText: "Search tries, groups, languages…"
            foreground: root.foreground
            onTextChanged: {
              root.filterText = text
              root.selectedIndex = 0
              root.rebuildDisplay()
            }
            Keys.onEscapePressed: {
              if (text) text = ""
              else root.requestClose()
            }
            Keys.onDownPressed: {
              root.moveSelection(1)
              searchField.focus = false
            }
          }

          Controls.ScrollView {
            width: parent.width - searchField.width - parent.spacing
            height: parent.height
            clip: true
            Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOff
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AsNeeded

            Row {
              spacing: Style.space(6)

              Button {
                text: "ALL"
                selected: root.selectedGroup === ""
                foreground: root.foreground
                accent: root.accent
                verticalPadding: Style.space(5)
                onClicked: root.setGroup("")
              }

              Repeater {
                model: root.groupNames
                Button {
                  required property string modelData
                  text: modelData.toUpperCase()
                  selected: root.selectedGroup === modelData
                  foreground: root.foreground
                  accent: root.accent
                  verticalPadding: Style.space(5)
                  onClicked: root.setGroup(modelData)
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          height: parent.height - Style.space(54) - Style.spacing.hairline - Style.space(34) - parent.spacing * 3 - statusBar.height
          spacing: Style.space(14)

          BorderSurface {
            width: Math.min(Style.space(390), parent.width * 0.42)
            height: parent.height
            color: Util.alpha(root.foreground, 0.025)
            borderSpec: Border.flat(Util.alpha(root.foreground, 0.14), Style.normalBorderWidth)
            radius: Style.cornerRadius
            padding: Style.space(8)

            ListView {
              id: sessionList
              anchors.fill: parent
              anchors.topMargin: parent.contentTopInset
              anchors.rightMargin: parent.contentRightInset
              anchors.bottomMargin: parent.contentBottomInset
              anchors.leftMargin: parent.contentLeftInset
              model: displayModel
              clip: true
              spacing: Style.space(5)
              boundsBehavior: Flickable.StopAtBounds

              delegate: BorderSurface {
                id: sessionRow
                required property int index
                required property string title
                required property string sessionPath
                required property string language
                required property string icon
                required property int modified
                required property bool git
                required property int changes
                required property string branch
                required property string groupName
                required property bool pinned
                required property bool graduated

                readonly property bool selectedRow: index === root.selectedIndex
                width: ListView.view.width
                height: Style.space(72)
                color: selectedRow ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                borderSpec: selectedRow ? Border.controlSpec("hover-cursor", root.foreground, root.accent) : Border.none()
                radius: Style.cornerRadius

                Text {
                  id: tryIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: sessionRow.pinned ? "󰐃" : sessionRow.icon
                  color: sessionRow.selectedRow ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                  width: Style.space(30)
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  anchors.left: tryIcon.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Row {
                    width: parent.width
                    Text {
                      width: parent.width - ageLabel.width
                      text: sessionRow.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: sessionRow.selectedRow
                      elide: Text.ElideRight
                    }
                    Text {
                      id: ageLabel
                      text: TryModel.relativeTime(sessionRow.modified)
                      color: root.dimForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    width: parent.width
                    text: (sessionRow.groupName ? sessionRow.groupName.toUpperCase() + "  ·  " : "")
                      + sessionRow.language + "  ·  "
                      + (sessionRow.graduated ? "GRADUATED" : (sessionRow.git ? (sessionRow.changes ? "DIRTY ×" + sessionRow.changes : "CLEAN") : "SCRATCH"))
                    color: sessionRow.changes ? root.urgent : root.dimForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.5
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectIndex(sessionRow.index)
                  onClicked: root.selectIndex(sessionRow.index)
                  onDoubleClicked: root.openEditor()
                }
              }
            }

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(40)
              spacing: Style.space(10)
              visible: displayModel.count === 0

              Text {
                width: parent.width
                text: root.sessions.length === 0 ? "[ EMPTY DRIVE ]" : "[ NO MATCHES ]"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
                horizontalAlignment: Text.AlignHCenter
              }
              Text {
                width: parent.width
                text: root.sessions.length === 0 ? "Create a try and give that idea a home." : "Change the search or group filter."
                color: root.dimForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          BorderSurface {
            width: parent.width - parent.children[0].width - parent.spacing
            height: parent.height
            color: Util.alpha(root.foreground, 0.018)
            borderSpec: Border.flat(Util.alpha(root.foreground, 0.14), Style.normalBorderWidth)
            radius: Style.cornerRadius
            padding: Style.space(18)

            Column {
              id: detailColumn
              anchors.fill: parent
              anchors.topMargin: parent.contentTopInset
              anchors.rightMargin: parent.contentRightInset
              anchors.bottomMargin: parent.contentBottomInset
              anchors.leftMargin: parent.contentLeftInset
              spacing: Style.space(12)
              visible: root.activeSession !== null

              Row {
                width: parent.width
                height: Style.space(48)
                spacing: Style.space(12)

                Text {
                  width: Style.space(42)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.activeSession ? root.activeSession.icon : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  width: parent.width - Style.space(42) - pinButton.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: root.activeSession ? root.activeSession.title : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: root.activeSession ? TryModel.pathLabel(root.activeSession.sessionPath, root.homePath) : ""
                    color: root.dimForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                Button {
                  id: pinButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: root.draftPinned ? "󰐃" : "󰤱"
                  text: root.draftPinned ? "PINNED" : "PIN"
                  selected: root.draftPinned
                  foreground: root.foreground
                  accent: root.accent
                  enabled: !pinProc.running
                  opacity: enabled ? 1 : 0.55
                  onClicked: root.togglePin()
                }
              }

              Rectangle { width: parent.width; height: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.14) }

              Grid {
                id: quickActions
                width: parent.width
                columns: width < Style.space(520) ? 2 : 4
                spacing: Style.space(8)
                height: childrenRect.height
                readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                Button { width: quickActions.cellWidth; text: "TERMINAL"; iconText: ""; bordered: true; foreground: root.foreground; onClicked: root.openTerminal() }
                Button { width: quickActions.cellWidth; text: "EDITOR"; iconText: "󰨞"; bordered: true; foreground: root.foreground; onClicked: root.openEditor() }
                Button { width: quickActions.cellWidth; text: "FILES"; iconText: "󰉋"; bordered: true; foreground: root.foreground; onClicked: root.openFiles() }
                Button { width: quickActions.cellWidth; text: "COPY PATH"; iconText: "󰆏"; bordered: true; foreground: root.foreground; onClicked: root.copyPath() }
              }

              Row {
                width: parent.width
                height: Style.space(56)
                spacing: Style.space(10)

                InfoCell {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: "STACK"
                  value: root.activeSession ? root.activeSession.language : ""
                }
                InfoCell {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: "GIT"
                  value: root.activeSession ? TryModel.statusLabel(root.activeSession) : ""
                  alert: root.activeSession && root.activeSession.changes > 0
                }
                InfoCell {
                  width: (parent.width - parent.spacing * 2) / 3
                  label: "BRANCH"
                  value: root.activeSession && root.activeSession.branch ? root.activeSession.branch : "—"
                }
              }

              Text {
                text: "TRY DETAILS"
                color: root.dimForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              Item {
                width: parent.width
                height: groupField.implicitHeight

                TextField {
                  id: groupField
                  anchors.fill: parent
                  placeholderText: "Group (type a new one or choose an existing group)"
                  foreground: root.foreground
                  rightPadding: Style.space(34)
                  onTextChanged: root.updateGroupSuggestions()
                  onActiveFocusChanged: {
                    if (activeFocus) root.updateGroupSuggestions()
                    else groupPopup.close()
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Down && root.groupSuggestions.length > 0) {
                      root.groupSuggestionIndex = Math.min(root.groupSuggestions.length - 1, root.groupSuggestionIndex + 1)
                      groupPopup.open()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Up && groupPopup.opened) {
                      root.groupSuggestionIndex = Math.max(0, root.groupSuggestionIndex - 1)
                      event.accepted = true
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && groupPopup.opened) {
                      root.applyGroupSuggestion(root.groupSuggestionIndex)
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      if (groupPopup.opened) groupPopup.close()
                      else root.syncDraft()
                      event.accepted = true
                    }
                  }
                }

                Text {
                  anchors.right: groupField.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: groupField.verticalCenter
                  text: "󰅀"
                  color: root.dimForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Controls.Popup {
                  id: groupPopup
                  x: 0
                  y: groupField.height + Style.space(3)
                  width: groupField.width
                  height: Math.min(root.groupSuggestions.length, 6) * Style.space(36) + Style.spacing.hairline * 2
                  padding: Style.spacing.hairline
                  closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

                  background: BorderSurface {
                    color: Color.popups.background
                    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
                    radius: Style.cornerRadius
                  }

                  contentItem: ListView {
                    id: groupSuggestionList
                    model: root.groupSuggestions
                    clip: true
                    spacing: 0
                    currentIndex: root.groupSuggestionIndex

                    delegate: Rectangle {
                      required property int index
                      required property string modelData
                      width: ListView.view.width
                      height: Style.space(36)
                      color: index === root.groupSuggestionIndex
                        ? Style.hoverFillFor(root.foreground, root.accent)
                        : "transparent"

                      Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(10)
                        text: parent.modelData
                        color: parent.index === root.groupSuggestionIndex
                          ? Style.hoverStateColor(root.foreground, root.accent)
                          : Color.popups.text
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.groupSuggestionIndex = parent.index
                        onClicked: root.applyGroupSuggestion(parent.index)
                      }
                    }
                  }
                }
              }

              BorderSurface {
                width: parent.width
                height: Math.max(Style.space(82), detailColumn.height - y - actionsRow.implicitHeight - detailColumn.spacing)
                color: Util.alpha(root.foreground, 0.025)
                borderSpec: Border.controlSpec(noteField.activeFocus ? "focus" : "normal", root.foreground, root.accent)
                radius: Style.cornerRadius

                Controls.TextArea {
                  id: noteField
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: root.foreground
                  selectionColor: Style.selectionFillFor(root.foreground, root.accent)
                  selectedTextColor: root.foreground
                  placeholderText: root.activeSession && root.activeSession.readme
                    ? root.activeSession.readme : "What are you trying? Leave a note for future you…"
                  placeholderTextColor: root.dimForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: TextEdit.Wrap
                  background: null
                  Keys.onEscapePressed: root.syncDraft()
                }
              }

              Row {
                id: actionsRow
                width: parent.width
                spacing: Style.space(8)
                Button {
                  text: "SAVE DETAILS"
                  iconText: "󰆓"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  enabled: !pinProc.running && !actionProc.running
                  opacity: enabled ? 1 : 0.55
                  onClicked: root.saveMetadata()
                }
                Item { width: parent.width - parent.children[0].width - trashButton.width - parent.spacing * 2; height: 1 }
                Button {
                  id: trashButton
                  text: "TRASH"
                  iconText: "󰆴"
                  foreground: root.urgent
                  accent: root.urgent
                  onClicked: root.requestTrash()
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.activeSession === null
              text: "SELECT A TRY"
              color: root.dimForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.letterSpacing: 1
            }
          }
        }

        Row {
          id: statusBar
          width: parent.width
          height: Style.space(22)

          Text {
            width: parent.width * 0.72
            text: (root.loading ? "◌  " : "●  ") + root.message
            color: root.messageError ? root.urgent : (root.loading ? root.dimForeground : root.accent)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
            elide: Text.ElideRight
          }
          Text {
            width: parent.width * 0.28
            text: "↑↓ SELECT  ·  ENTER EDIT  ·  / SEARCH"
            color: root.dimForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.createOpen
        color: Util.alpha(root.background, 0.82)
        z: 50

        MouseArea { anchors.fill: parent; onClicked: root.createOpen = false }

        BorderSurface {
          width: Math.min(parent.width - Style.space(40), Style.space(440))
          height: Style.space(190)
          anchors.centerIn: parent
          color: root.background
          borderSpec: Border.flat(root.accent, Style.normalBorderWidth)
          radius: Style.cornerRadius
          padding: Style.space(20)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            anchors.fill: parent
            anchors.topMargin: parent.contentTopInset
            anchors.rightMargin: parent.contentRightInset
            anchors.bottomMargin: parent.contentBottomInset
            anchors.leftMargin: parent.contentLeftInset
            spacing: Style.space(14)

            Text {
              text: "CREATE NEW TRY"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1
            }
            TextField {
              id: createField
              width: parent.width
              placeholderText: "redis connection pool"
              foreground: root.foreground
              onAccepted: root.submitCreate()
              Keys.onEscapePressed: root.createOpen = false
            }
            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              Button { text: "CANCEL"; foreground: root.foreground; onClicked: root.createOpen = false }
              Button { text: "CREATE"; bordered: true; foreground: root.foreground; accent: root.accent; onClicked: root.submitCreate() }
            }
          }
        }
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        opened: root.deleteOpen
        z: 60
        message: "Move “" + (root.activeSession ? root.activeSession.title : "this try") + "” to trash?"
        confirmText: "Trash"
        background: root.background
        foreground: root.foreground
        scrim: Util.alpha(root.background, 0.82)
        selectedBackground: Util.alpha(root.foreground, 0.08)
        selectedText: root.urgent
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.deleteOpen = false
        onConfirmed: root.confirmTrash()
      }
    }
  }

  component InfoCell: BorderSurface {
    id: cell
    property string label: ""
    property string value: ""
    property bool alert: false

    height: Style.space(56)
    color: Util.alpha(root.foreground, 0.025)
    borderSpec: Border.flat(Util.alpha(root.foreground, 0.11), Style.normalBorderWidth)
    radius: Style.cornerRadius

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(3)
      Text {
        text: cell.label
        color: root.dimForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }
      Text {
        width: parent.width
        text: cell.value
        color: cell.alert ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }
}
