import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "kiryuuki.oma-pad"
  ipcTarget: "kiryuuki.oma-pad"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var launchpadDoc: null
  readonly property var entriesList: launchpadDoc && launchpadDoc.entries ? launchpadDoc.entries : []
  property var availableApps: []

  property bool addFormOpen: false
  property string statusNotice: ""
  property string appSearchFilter: ""

  // Form selection state
  property string selectedAppName: ""
  property string selectedAppMatch: ""
  property string selectedAppCommand: ""
  property int selectedWorkspace: 1
  property bool selectedLaunchAtBoot: false
  property bool selectedSilent: false
  property bool showAdvancedFields: false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.addFormOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    configFile.reload()
    loadAppsProcess.running = true
  }

  // =========================================================================
  // FILE WATCHER & PROCESSES
  // =========================================================================
  FileView {
    id: configFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/launchpad.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.launchpadDoc = JSON.parse(text())
      } catch (e) {
        root.launchpadDoc = { version: 1, entries: [] }
      }
    }
    onFileChanged: reload()
  }

  // Process: Load installed .desktop applications + running windows
  Process {
    id: loadAppsProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/list_apps.py"]
    stdout: StdioCollector {
      id: appsOut
      waitForEnd: true
      onStreamFinished: {
        try {
          root.availableApps = JSON.parse(appsOut.text)
        } catch (e) {
          root.availableApps = []
        }
      }
    }
  }

  // Process: Generate Hyprland Lua rules & reload
  Process {
    id: generateProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/generate.py"]
    onExited: {
      configFile.reload()
      showNotice(qsTr("Hyprland rules reloaded!"))
    }
  }

  // Process: Apply window rules immediately
  Process {
    id: applyNowProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/apply_now.py"]
    onExited: {
      showNotice(qsTr("Open windows repositioned!"))
    }
  }

  // Process: Save Config
  Process {
    id: saveProcess
    property var actionArgs: []
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/save_config.py"].concat(actionArgs)
    onExited: {
      generateProcess.running = true
      root.addFormOpen = false
      root.resetForm()
    }
  }

  // Process: Launch App
  Process {
    id: launchAppProcess
    property string cmdToRun: ""
    command: ["bash", "-c", cmdToRun]
  }

  function launchApp(cmd) {
    if (!cmd) return
    launchAppProcess.cmdToRun = cmd + " &"
    launchAppProcess.running = true
    showNotice(qsTr("Launching ") + cmd + "...")
  }

  function saveRule(appId, match, cmd, ws, boot, silent) {
    var args = [
      "--id", appId,
      "--match", match,
      "--command", cmd,
      "--workspace", String(ws),
    ]
    if (boot) args.push("--launch-at-boot")
    if (silent) args.push("--silent")
    saveProcess.actionArgs = args
    saveProcess.running = true
  }

  function deleteRule(match) {
    saveProcess.actionArgs = ["--delete", match]
    saveProcess.running = true
  }

  function selectApp(app) {
    root.selectedAppName = app.name || app.id
    root.selectedAppMatch = app.match || app.id
    root.selectedAppCommand = app.command || app.id
  }

  function resetForm() {
    root.selectedAppName = ""
    root.selectedAppMatch = ""
    root.selectedAppCommand = ""
    root.appSearchFilter = ""
    root.selectedWorkspace = 1
    root.selectedLaunchAtBoot = false
    root.selectedSilent = false
    root.showAdvancedFields = false
  }

  function showNotice(msg) {
    root.statusNotice = msg
    noticeTimer.restart()
  }

  Timer {
    id: noticeTimer
    interval: 3000
    onTriggered: root.statusNotice = ""
  }

  // Filtered Apps List for App Selector
  readonly property var filteredApps: {
    if (!root.availableApps) return []
    var q = root.appSearchFilter.toLowerCase().trim()
    if (!q) return root.availableApps.slice(0, 15)
    return root.availableApps.filter(function(a) {
      return (a.name && a.name.toLowerCase().indexOf(q) !== -1) ||
             (a.match && a.match.toLowerCase().indexOf(q) !== -1) ||
             (a.command && a.command.toLowerCase().indexOf(q) !== -1)
    }).slice(0, 20)
  }

  Component.onCompleted: refresh()

  // =========================================================================
  // PANEL UI
  // =========================================================================
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") generateProcess.running = true
        else if (t === "a" || t === "A") {
          root.addFormOpen = !root.addFormOpen
          if (!root.addFormOpen) root.resetForm()
        }
        else if (t === "m" || t === "M") applyNowProcess.running = true
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: mainColumn.width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: mainColumn
          width: scrollArea.width
          spacing: Style.space(10)

          // ------------------ HEADER ROW ------------------
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Row {
              spacing: Style.space(6)
              Text {
                text: "󰀵"
                color: Color.accent
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: qsTr("OMAPAD")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 1
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              visible: root.statusNotice !== ""
              text: root.statusNotice
              color: "#87c095"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            PanelActionButton {
              iconText: "󰵱"
              tooltipText: "Reposition open windows now (M)"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: applyNowProcess.running = true
            }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Apply rules & reload Hyprland (R)"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: generateProcess.running = true
            }

            PanelActionButton {
              iconText: root.addFormOpen ? "✕" : "+"
              tooltipText: root.addFormOpen ? "Cancel" : "Pin App Rule (A)"
              foreground: root.addFormOpen ? Color.accent : root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: {
                root.addFormOpen = !root.addFormOpen
                if (!root.addFormOpen) root.resetForm()
              }
            }
          }

          // ------------------ ADD APP FORM ------------------
          BorderSurface {
            visible: root.addFormOpen
            width: parent.width
            implicitHeight: formCol.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
            borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)

            Column {
              id: formCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: qsTr("PIN APPLICATION TO WORKSPACE")
                color: Color.accent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              // ---------------- STEP 1: APP SELECTOR ----------------
              Column {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: qsTr("1. Select Application")
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                // Selected App Banner (if chosen)
                BorderSurface {
                  visible: root.selectedAppMatch !== ""
                  width: parent.width
                  implicitHeight: Style.space(32)
                  radius: Style.cornerRadius
                  color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                  borderSpec: Border.controlSpec("normal", "#10B981", Color.accent)

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(6)
                    spacing: Style.space(6)

                    Text {
                      text: "✓"
                      color: "#10B981"
                      font.bold: true
                    }

                    Text {
                      Layout.fillWidth: true
                      text: root.selectedAppName + " (match: " + root.selectedAppMatch + ")"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      text: qsTr("Change")
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedAppMatch = ""
                      }
                    }
                  }
                }

                // App Search Input & List (shown when no app selected or searching)
                Column {
                  visible: root.selectedAppMatch === ""
                  width: parent.width
                  spacing: Style.space(4)

                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(32)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: Style.space(4)
                      spacing: Style.space(6)

                      Text {
                        text: "🔍"
                        font.pixelSize: Style.font.caption
                      }

                      TextInput {
                        id: searchInp
                        Layout.fillWidth: true
                        text: root.appSearchFilter
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        selectByMouse: true
                        clip: true
                        onTextChanged: root.appSearchFilter = text

                        Text {
                          visible: searchInp.text === "" && !searchInp.activeFocus
                          anchors.verticalCenter: parent.verticalCenter
                          text: qsTr("Search apps (e.g. Zen, Kitty, Code, Discord)...")
                          color: Qt.darker(root.contentForeground, 2.0)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  // Apps List
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Math.min(Style.space(140), appListCol.implicitHeight + Style.space(6))
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.2), Color.accent)

                    Flickable {
                      anchors.fill: parent
                      anchors.margins: Style.space(4)
                      contentWidth: appListCol.width
                      contentHeight: appListCol.implicitHeight
                      clip: true

                      Column {
                        id: appListCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                          model: root.filteredApps

                          delegate: Rectangle {
                            id: appItem
                            required property var modelData
                            width: appListCol.width
                            implicitHeight: Style.space(26)
                            radius: Style.space(3)
                            color: itemHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent"

                            HoverHandler { id: itemHover }

                            RowLayout {
                              anchors.fill: parent
                              anchors.margins: Style.space(4)
                              spacing: Style.space(6)

                              Text {
                                text: appItem.modelData.isRunning ? "󰖲" : "󰀵"
                                color: appItem.modelData.isRunning ? "#87c095" : Color.accent
                                font.pixelSize: Style.font.caption
                              }

                              Text {
                                Layout.fillWidth: true
                                text: appItem.modelData.name || appItem.modelData.id
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: Boolean(appItem.modelData.isRunning)
                                elide: Text.ElideRight
                              }

                              Text {
                                text: "match: " + (appItem.modelData.match || "")
                                color: Qt.darker(root.contentForeground, 2.0)
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                              }
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.selectApp(appItem.modelData)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // ---------------- STEP 2: WORKSPACE SELECTOR ----------------
              Column {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: qsTr("2. Assign to Workspace")
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                    delegate: Rectangle {
                      id: wsBtn
                      required property int modelData
                      readonly property bool active: root.selectedWorkspace === wsBtn.modelData

                      Layout.fillWidth: true
                      implicitHeight: Style.space(30)
                      radius: Style.cornerRadius
                      color: wsBtn.active ? Color.accent : (wsHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent")
                      border.width: 1
                      border.color: wsBtn.active ? Color.accent : Qt.darker(root.contentForeground, 2.2)

                      HoverHandler { id: wsHover }

                      Text {
                        anchors.centerIn: parent
                        text: String(wsBtn.modelData)
                        color: wsBtn.active ? "white" : Qt.darker(root.contentForeground, 1.6)
                        font.pixelSize: Style.font.bodySmall
                        font.bold: wsBtn.active
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedWorkspace = wsBtn.modelData
                      }
                    }
                  }
                }
              }

              // ---------------- STEP 3: TOGGLES ----------------
              RowLayout {
                width: parent.width
                spacing: Style.space(12)

                Row {
                  spacing: Style.space(6)
                  BorderSurface {
                    implicitWidth: Style.space(18)
                    implicitHeight: Style.space(18)
                    radius: Style.space(3)
                    color: root.selectedLaunchAtBoot ? Color.accent : "transparent"
                    borderSpec: Border.controlSpec("normal", root.selectedLaunchAtBoot ? Color.accent : Qt.darker(root.contentForeground, 1.8), Color.accent)
                    Text {
                      anchors.centerIn: parent
                      text: "✓"
                      color: "white"
                      visible: root.selectedLaunchAtBoot
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectedLaunchAtBoot = !root.selectedLaunchAtBoot
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Auto-Launch at Boot")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  spacing: Style.space(6)
                  BorderSurface {
                    implicitWidth: Style.space(18)
                    implicitHeight: Style.space(18)
                    radius: Style.space(3)
                    color: root.selectedSilent ? Color.accent : "transparent"
                    borderSpec: Border.controlSpec("normal", root.selectedSilent ? Color.accent : Qt.darker(root.contentForeground, 1.8), Color.accent)
                    Text {
                      anchors.centerIn: parent
                      text: "✓"
                      color: "white"
                      visible: root.selectedSilent
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectedSilent = !root.selectedSilent
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Silent Pinning (no focus pull)")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: root.showAdvancedFields ? qsTr("Hide Advanced ▲") : qsTr("Edit Match / Exec ▼")
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAdvancedFields = !root.showAdvancedFields
                  }
                }
              }

              // Optional Advanced Inputs
              Column {
                visible: root.showAdvancedFields
                width: parent.width
                spacing: Style.space(4)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  BorderSurface {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(28)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    TextInput {
                      anchors.fill: parent
                      anchors.margins: Style.space(4)
                      text: root.selectedAppMatch
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      selectByMouse: true
                      clip: true
                      onTextChanged: root.selectedAppMatch = text
                    }
                  }

                  BorderSurface {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(28)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    TextInput {
                      anchors.fill: parent
                      anchors.margins: Style.space(4)
                      text: root.selectedAppCommand
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      selectByMouse: true
                      clip: true
                      onTextChanged: root.selectedAppCommand = text
                    }
                  }
                }
              }

              // ---------------- ACTION BUTTONS ----------------
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Item { Layout.fillWidth: true }

                BorderSurface {
                  implicitWidth: Style.space(60)
                  implicitHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                  Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    color: Qt.darker(root.contentForeground, 1.8)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.addFormOpen = false
                      root.resetForm()
                    }
                  }
                }

                BorderSurface {
                  implicitWidth: Style.space(100)
                  implicitHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: Color.accent
                  borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)

                  Text {
                    anchors.centerIn: parent
                    text: qsTr("Save & Apply")
                    color: "white"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var m = root.selectedAppMatch.trim() || root.selectedAppName.trim()
                      if (!m) {
                        root.showNotice(qsTr("Please select an application first!"))
                        return
                      }
                      var name = root.selectedAppName.trim() || m
                      var cmd = root.selectedAppCommand.trim() || m
                      root.saveRule(name, m, cmd, root.selectedWorkspace, root.selectedLaunchAtBoot, root.selectedSilent)
                    }
                  }
                }
              }
            }
          }

          // ------------------ EMPTY STATE ------------------
          Text {
            visible: root.entriesList.length === 0 && !root.addFormOpen
            width: parent.width
            text: qsTr("No apps pinned to workspaces yet. Click '+' above to pin apps!")
            color: Qt.darker(root.contentForeground, 2.0)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(20)
            bottomPadding: Style.space(20)
          }

          // ------------------ PINNED APPS REPEATER ------------------
          Repeater {
            model: root.entriesList

            BorderSurface {
              id: appRow
              required property var modelData

              width: root.width
              implicitHeight: Style.space(42)
              radius: Style.cornerRadius
              color: rowHover.hovered
                ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                : Style.hoverFillFor(root.contentForeground, root.contentForeground)
              borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

              HoverHandler { id: rowHover }

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(8)

                // Workspace Badge
                Rectangle {
                  implicitWidth: wsText.implicitWidth + Style.space(12)
                  implicitHeight: Style.space(24)
                  radius: Style.cornerRadius
                  color: Color.accent

                  Text {
                    id: wsText
                    anchors.centerIn: parent
                    text: "WS " + (appRow.modelData.workspace !== undefined ? appRow.modelData.workspace : "?")
                    color: "white"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                // App Info
                Column {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    width: parent.width
                    text: appRow.modelData.id || appRow.modelData.match || ""
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Row {
                    spacing: Style.space(6)
                    Text {
                      text: "match: " + (appRow.modelData.match || "")
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                      visible: Boolean(appRow.modelData.launchAtBoot)
                      width: bootBadge.implicitWidth + Style.space(6)
                      height: Style.space(14)
                      radius: Style.space(3)
                      color: Qt.rgba(0.06, 0.72, 0.51, 0.2)

                      Text {
                        id: bootBadge
                        anchors.centerIn: parent
                        text: "󰄲 Boot"
                        color: "#10B981"
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }

                // Launch Button
                Rectangle {
                  visible: Boolean(appRow.modelData.command)
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: launchHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "󰐊"
                    color: launchHover.hovered ? Color.accent : Qt.darker(root.contentForeground, 1.6)
                    font.pixelSize: Style.font.bodySmall
                  }

                  HoverHandler { id: launchHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchApp(appRow.modelData.command)
                  }
                }

                // Delete Button
                Rectangle {
                  visible: rowHover.hovered
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "󰆴"
                    color: delHover.hovered ? "#EF4444" : Qt.darker(root.contentForeground, 2.0)
                    font.pixelSize: Style.font.bodySmall
                  }

                  HoverHandler { id: delHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.deleteRule(appRow.modelData.match || appRow.modelData.id)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
