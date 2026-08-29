import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "kiryuuki.oma-pad"
  ipcTarget: "kiryuuki.oma-pad"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Active View Tab: "workspaces" | "rules" | "apps"
  property string activeTab: "workspaces"

  // Data state from reactive state file
  property var stateDoc: ({ version: 1, entries: [], workspaces: [], installedApps: [], totalPinned: 0, totalRunningWindows: 0 })
  readonly property var workspacesList: stateDoc && stateDoc.workspaces ? stateDoc.workspaces : []
  readonly property var entriesList: stateDoc && stateDoc.entries ? stateDoc.entries : []
  readonly property var installedAppsList: stateDoc && stateDoc.installedApps ? stateDoc.installedApps : []

  property string statusNotice: ""
  property string appSearchQuery: ""

  // Form / Pinning State
  property var pickedApp: null
  property int targetWorkspace: 1
  property bool flagLaunchAtBoot: false
  property bool flagSilent: false

  // Pinned rule inline editing ID
  property string editingRuleMatch: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    runEngine(["--sync"])
  }

  onOpenedChanged: {
    if (root.opened) {
      stateFile.reload()
      refresh()
    }
  }

  // =========================================================================
  // FILE WATCHER & PROCESSES
  // =========================================================================
  FileView {
    id: stateFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/launchpad-state.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.stateDoc = Model.parseState(text())
    }
    onLoadFailed: {
      root.stateDoc = Model.parseState("")
      root.refresh()
    }
    onFileChanged: reload()
  }

  Process {
    id: engineProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/launchpad_engine.py", "--sync"]
    onExited: {
      stateFile.reload()
    }
  }

  function runEngine(args) {
    engineProcess.command = ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/launchpad_engine.py"].concat(args)
    engineProcess.running = true
  }

  // Dedicated Launch Helper Process
  Process {
    id: launchProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/launch_helper.py"]
  }

  function launchApp(cmd, targetWs) {
    if (!cmd) return
    var wsStr = targetWs !== undefined ? String(targetWs) : "1"
    launchProcess.command = [
      "/usr/bin/python3",
      (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/launch_helper.py",
      cmd,
      wsStr
    ]
    launchProcess.running = true
    showNotice(qsTr("Launching ") + cmd + " (WS " + wsStr + ")...")
  }

  function pinCurrentLayout() {
    runEngine(["--pin-current-windows"])
    showNotice(qsTr("Pinned all active windows to their current workspaces!"))
  }

  function pinWindow(className, title, wsId, atBoot) {
    var args = [
      "--pin-window",
      "--class-name", className,
      "--app-title", title || className,
      "--workspace", String(wsId),
      "--command", className.toLowerCase()
    ]
    if (atBoot) args.push("--launch-at-boot")
    runEngine(args)
    showNotice(qsTr("Pinned ") + className + qsTr(" to WS ") + wsId)
  }

  function toggleRuleBoot(matchPattern) {
    runEngine(["--toggle-boot", matchPattern])
    showNotice(qsTr("Toggled boot launch for ") + matchPattern)
  }

  function setRuleWorkspace(matchPattern, newWs) {
    runEngine(["--set-workspace", matchPattern, "--workspace", String(newWs)])
    root.editingRuleMatch = ""
    showNotice(qsTr("Assigned ") + matchPattern + qsTr(" to WS ") + newWs)
  }

  function deleteRule(matchPattern) {
    runEngine(["--delete-rule", matchPattern])
    showNotice(qsTr("Removed rule for ") + matchPattern)
  }

  function applyNow() {
    runEngine(["--apply-now"])
    showNotice(qsTr("Repositioning open windows..."))
  }

  function reloadRules() {
    runEngine(["--sync"])
    showNotice(qsTr("Reloaded Hyprland rules!"))
  }

  function showNotice(msg) {
    root.statusNotice = msg
    noticeTimer.restart()
  }

  Timer {
    id: noticeTimer
    interval: 3500
    onTriggered: root.statusNotice = ""
  }

  // Filtered Apps search via Model
  readonly property var searchFilteredApps: Model.filterApps(root.installedAppsList, root.appSearchQuery)

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
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "1") root.activeTab = "workspaces"
        else if (t === "2") root.activeTab = "rules"
        else if (t === "3") root.activeTab = "apps"
        else if (t === "r" || t === "R") root.reloadRules()
        else if (t === "p" || t === "P") root.pinCurrentLayout()
        else if (t === "m" || t === "M") root.applyNow()
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
                text: "\uf135"
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

            // Quick Pin All Action
            BorderSurface {
              implicitHeight: Style.space(26)
              implicitWidth: pinAllTxt.implicitWidth + Style.space(12)
              radius: Style.cornerRadius
              color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
              borderSpec: Border.controlSpec("normal", "#10B981", Color.accent)

              Text {
                id: pinAllTxt
                anchors.centerIn: parent
                text: "󰐃 Pin Current Layout"
                color: "#10B981"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pinCurrentLayout()
              }
            }

            PanelActionButton {
              iconText: "󰵱"
              tooltipText: qsTr("Reposition all open windows to assigned workspaces (M)")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.applyNow()
            }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: qsTr("Sync rules & reload Hyprland (R)")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.reloadRules()
            }
          }

          // ------------------ SEGMENTED VIEW TABS ------------------
          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: [
                { key: "workspaces", label: "Live Workspaces (" + root.workspacesList.length + ")", icon: "󰖲" },
                { key: "rules", label: "Pinned Rules (" + root.entriesList.length + ")", icon: "\uf135" },
                { key: "apps", label: "Add / Search Apps (" + root.installedAppsList.length + ")", icon: "󰘔" }
              ]

              delegate: Rectangle {
                id: tabBtn
                required property var modelData
                readonly property bool active: root.activeTab === tabBtn.modelData.key

                Layout.fillWidth: true
                implicitHeight: Style.space(32)
                radius: Style.cornerRadius
                color: tabBtn.active ? Color.accent : (tabHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent")
                border.width: 1
                border.color: tabBtn.active ? Color.accent : Qt.darker(root.contentForeground, 2.2)

                HoverHandler { id: tabHover }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: tabBtn.modelData.icon
                    color: tabBtn.active ? "white" : (tabHover.hovered ? root.contentForeground : Qt.darker(root.contentForeground, 1.6))
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: tabBtn.modelData.label
                    color: tabBtn.active ? "white" : (tabHover.hovered ? root.contentForeground : Qt.darker(root.contentForeground, 1.6))
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: tabBtn.active
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activeTab = tabBtn.modelData.key
                }
              }
            }
          }

          // =================================================================
          // TAB 1: LIVE WORKSPACES OVERVIEW
          // =================================================================
          Column {
            visible: root.activeTab === "workspaces"
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.workspacesList

              BorderSurface {
                id: wsCard
                required property var modelData
                readonly property bool hasWindows: Boolean(wsCard.modelData.windows && wsCard.modelData.windows.length > 0)

                width: parent.width
                implicitHeight: wsCol.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: wsCard.hasWindows ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04) : "transparent"
                borderSpec: Border.controlSpec("normal", wsCard.hasWindows ? Color.accent : Qt.darker(root.contentForeground, 2.4), Color.accent)

                Column {
                  id: wsCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)

                  // Workspace Header
                  RowLayout {
                    width: parent.width

                    Rectangle {
                      implicitWidth: wsBadgeTxt.implicitWidth + Style.space(10)
                      implicitHeight: Style.space(20)
                      radius: Style.space(3)
                      color: Color.accent

                      Text {
                        id: wsBadgeTxt
                        anchors.centerIn: parent
                        text: "WORKSPACE " + wsCard.modelData.id
                        color: "white"
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Text {
                      text: wsCard.hasWindows ? (" · " + wsCard.modelData.windows.length + " active window(s)") : " · Empty"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: "+ Pin an app here"
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.targetWorkspace = wsCard.modelData.id
                          root.activeTab = "apps"
                        }
                      }
                    }
                  }

                  // Open Windows Inside this Workspace
                  Repeater {
                    model: wsCard.modelData.windows || []

                    delegate: BorderSurface {
                      id: winRow
                      required property var modelData
                      readonly property bool isPinned: Boolean(winRow.modelData.isPinned)

                      width: wsCol.width
                      implicitHeight: Style.space(34)
                      radius: Style.cornerRadius
                      color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
                      borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.2), Color.accent)

                      RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(4)
                        spacing: Style.space(6)

                        Text {
                          text: "󰖲"
                          color: winRow.isPinned ? "#10B981" : Color.accent
                          font.pixelSize: Style.font.caption
                        }

                        Column {
                          Layout.fillWidth: true
                          spacing: 1

                          Text {
                            width: parent.width
                            text: (winRow.modelData.class || "Window") + (winRow.modelData.title ? (" — " + winRow.modelData.title) : "")
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            elide: Text.ElideRight
                          }
                        }

                        // Pinned Indicator / 1-Click Pin Button
                        Rectangle {
                          id: winPinBtn
                          implicitWidth: pinBtnTxt.implicitWidth + Style.space(12)
                          implicitHeight: Style.space(22)
                          radius: Style.space(3)
                          color: winRow.isPinned ? Qt.rgba(0.06, 0.72, 0.51, 0.15) : (winPinHover.hovered ? Qt.lighter(Color.accent, 1.1) : Color.accent)

                          HoverHandler { id: winPinHover }

                          Text {
                            id: pinBtnTxt
                            anchors.centerIn: parent
                            text: winRow.isPinned ? "✓ Pinned" : "󰐃 Remember / Pin"
                            color: winRow.isPinned ? "#10B981" : "white"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (!winRow.isPinned) {
                                root.pinWindow(winRow.modelData.class, winRow.modelData.class, wsCard.modelData.id, false)
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
          }

          // =================================================================
          // TAB 2: PINNED RULES LIST (WITH INLINE EDIT & BOOT TOGGLE)
          // =================================================================
          Column {
            visible: root.activeTab === "rules"
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: root.entriesList.length === 0
              width: parent.width
              text: qsTr("No apps pinned to workspaces yet. Pin running windows from 'Live Workspaces' or search from 'Add / Search Apps'!")
              color: Qt.darker(root.contentForeground, 2.0)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(20)
              bottomPadding: Style.space(20)
            }

            Repeater {
              model: root.entriesList

              BorderSurface {
                id: ruleCard
                required property var modelData
                readonly property string rMatch: String(ruleCard.modelData.match || ruleCard.modelData.id || "")
                readonly property bool isEditingWs: root.editingRuleMatch === ruleCard.rMatch
                readonly property bool isBoot: Boolean(ruleCard.modelData.launchAtBoot)

                width: parent.width
                implicitHeight: rCardCol.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: ruleHover.hovered
                  ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  : Style.hoverFillFor(root.contentForeground, root.contentForeground)
                borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                HoverHandler { id: ruleHover }

                Column {
                  id: rCardCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    // Workspace Badge (Click to Edit Workspace inline)
                    Rectangle {
                      id: wsBadgeBtn
                      implicitWidth: ruleWsTxt.implicitWidth + Style.space(10)
                      implicitHeight: Style.space(24)
                      radius: Style.cornerRadius
                      color: Color.accent

                      Text {
                        id: ruleWsTxt
                        anchors.centerIn: parent
                        text: "WS " + (ruleCard.modelData.workspace !== undefined ? ruleCard.modelData.workspace : "?")
                        color: "white"
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.editingRuleMatch = (root.editingRuleMatch === ruleCard.rMatch ? "" : ruleCard.rMatch)
                        }
                      }
                    }

                    Column {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        width: parent.width
                        text: ruleCard.modelData.id || ruleCard.modelData.match || ""
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Row {
                        spacing: Style.space(6)
                        Text {
                          text: "match: " + (ruleCard.modelData.match || "")
                          color: Qt.darker(root.contentForeground, 1.8)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                        }

                        // Interactive Boot Toggle Button
                        Rectangle {
                          id: bootToggleBtn
                          width: bootTag.implicitWidth + Style.space(10)
                          height: Style.space(16)
                          radius: Style.space(3)
                          color: ruleCard.isBoot ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                          border.width: 1
                          border.color: ruleCard.isBoot ? "#10B981" : Qt.darker(root.contentForeground, 2.2)

                          HoverHandler { id: bootHover }

                          Text {
                            id: bootTag
                            anchors.centerIn: parent
                            text: ruleCard.isBoot ? "󰄲 Boot: ON" : "󰄱 Boot: OFF"
                            color: ruleCard.isBoot ? "#10B981" : Qt.darker(root.contentForeground, 1.8)
                            font.pixelSize: Style.font.caption
                            font.bold: ruleCard.isBoot
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root.toggleRuleBoot(ruleCard.rMatch)
                            }
                          }
                        }
                      }
                    }

                    // Edit WS Button
                    Rectangle {
                      width: Style.space(28)
                      height: Style.space(28)
                      radius: Style.cornerRadius
                      color: ruleCard.isEditingWs ? Color.accent : (editHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent")

                      Text {
                        anchors.centerIn: parent
                        text: "󰏫"
                        color: ruleCard.isEditingWs ? "white" : (editHover.hovered ? Color.accent : Qt.darker(root.contentForeground, 1.8))
                        font.pixelSize: Style.font.bodySmall
                      }

                      HoverHandler { id: editHover }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.editingRuleMatch = (root.editingRuleMatch === ruleCard.rMatch ? "" : ruleCard.rMatch)
                        }
                      }
                    }

                    // Launch Button with Tooltip
                    Rectangle {
                      id: launchBtn
                      visible: Boolean(ruleCard.modelData.command)
                      width: Style.space(28)
                      height: Style.space(28)
                      radius: Style.cornerRadius
                      color: rLaunchHover.hovered ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                      Text {
                        anchors.centerIn: parent
                        text: "󰐊"
                        color: rLaunchHover.hovered ? "white" : Color.accent
                        font.pixelSize: Style.font.bodySmall
                      }

                      HoverHandler { id: rLaunchHover }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchApp(ruleCard.modelData.command || ruleCard.modelData.match, ruleCard.modelData.workspace)
                      }
                    }

                    // Delete Button with Tooltip
                    Rectangle {
                      id: delBtn
                      width: Style.space(28)
                      height: Style.space(28)
                      radius: Style.cornerRadius
                      color: rDelHover.hovered ? "#EF4444" : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: "󰆴"
                        color: rDelHover.hovered ? "white" : Qt.darker(root.contentForeground, 2.0)
                        font.pixelSize: Style.font.bodySmall
                      }

                      HoverHandler { id: rDelHover }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deleteRule(ruleCard.rMatch)
                      }
                    }
                  }

                  // Inline Workspace Selector (shown when editing)
                  Column {
                    visible: ruleCard.isEditingWs
                    width: parent.width
                    spacing: 2

                    Text {
                      text: qsTr("Assign to Workspace:")
                      color: Color.accent
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
                          id: inlineWsBtn
                          required property int modelData
                          readonly property bool active: ruleCard.modelData.workspace === inlineWsBtn.modelData

                          Layout.fillWidth: true
                          implicitHeight: Style.space(24)
                          radius: Style.cornerRadius
                          color: inlineWsBtn.active ? Color.accent : "transparent"
                          border.width: 1
                          border.color: inlineWsBtn.active ? Color.accent : Qt.darker(root.contentForeground, 2.2)

                          Text {
                            anchors.centerIn: parent
                            text: String(inlineWsBtn.modelData)
                            color: inlineWsBtn.active ? "white" : Qt.darker(root.contentForeground, 1.6)
                            font.pixelSize: Style.font.caption
                            font.bold: inlineWsBtn.active
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setRuleWorkspace(ruleCard.rMatch, inlineWsBtn.modelData)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // =================================================================
          // TAB 3: ADD / SEARCH INSTALLED APPS (FEATURE 2)
          // =================================================================
          Column {
            visible: root.activeTab === "apps"
            width: parent.width
            spacing: Style.space(8)

            // Search Bar
            BorderSurface {
              width: parent.width
              implicitHeight: Style.space(36)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
              borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(6)

                Text {
                  text: "🔍"
                  font.pixelSize: Style.font.bodySmall
                }

                TextInput {
                  id: appSearchBox
                  Layout.fillWidth: true
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  selectByMouse: true
                  clip: true
                  onTextChanged: root.appSearchQuery = text

                  Text {
                    visible: appSearchBox.text === "" && !appSearchBox.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Type to search installed apps (e.g. Zen, Ghostty, Code, Discord)...")
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  visible: root.appSearchQuery !== ""
                  text: "✕"
                  color: Qt.darker(root.contentForeground, 1.8)
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.appSearchQuery = ""
                      appSearchBox.text = ""
                    }
                  }
                }
              }
            }

            // Selected App Pinning Controls (shown when an app is clicked from the list)
            BorderSurface {
              visible: root.pickedApp !== null
              width: parent.width
              implicitHeight: pickCol.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
              borderSpec: Border.controlSpec("selected", Color.accent, Color.accent)

              Column {
                id: pickCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width

                  Text {
                    text: "✓ SELECTED: " + (root.pickedApp ? (root.pickedApp.name || "").toUpperCase() : "")
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    text: "Cancel"
                    color: Qt.darker(root.contentForeground, 1.8)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.pickedApp = null
                    }
                  }
                }

                // Workspace Buttons 1..10
                RowLayout {
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                    delegate: Rectangle {
                      id: targetWsBtn
                      required property int modelData
                      readonly property bool active: root.targetWorkspace === targetWsBtn.modelData

                      Layout.fillWidth: true
                      implicitHeight: Style.space(28)
                      radius: Style.cornerRadius
                      color: targetWsBtn.active ? Color.accent : "transparent"
                      border.width: 1
                      border.color: targetWsBtn.active ? Color.accent : Qt.darker(root.contentForeground, 2.2)

                      Text {
                        anchors.centerIn: parent
                        text: String(targetWsBtn.modelData)
                        color: targetWsBtn.active ? "white" : Qt.darker(root.contentForeground, 1.6)
                        font.pixelSize: Style.font.caption
                        font.bold: targetWsBtn.active
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.targetWorkspace = targetWsBtn.modelData
                      }
                    }
                  }
                }

                // Toggles Row
                RowLayout {
                  width: parent.width
                  spacing: Style.space(12)

                  Row {
                    spacing: Style.space(6)
                    BorderSurface {
                      implicitWidth: Style.space(16)
                      implicitHeight: Style.space(16)
                      radius: Style.space(3)
                      color: root.flagLaunchAtBoot ? Color.accent : "transparent"
                      borderSpec: Border.controlSpec("normal", root.flagLaunchAtBoot ? Color.accent : Qt.darker(root.contentForeground, 1.8), Color.accent)
                      Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "white"
                        visible: root.flagLaunchAtBoot
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.flagLaunchAtBoot = !root.flagLaunchAtBoot
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
                      implicitWidth: Style.space(16)
                      implicitHeight: Style.space(16)
                      radius: Style.space(3)
                      color: root.flagSilent ? Color.accent : "transparent"
                      borderSpec: Border.controlSpec("normal", root.flagSilent ? Color.accent : Qt.darker(root.contentForeground, 1.8), Color.accent)
                      Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "white"
                        visible: root.flagSilent
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.flagSilent = !root.flagSilent
                      }
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: qsTr("Silent Pinning")
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Item { Layout.fillWidth: true }

                  BorderSurface {
                    implicitWidth: Style.space(110)
                    implicitHeight: Style.space(26)
                    radius: Style.cornerRadius
                    color: Color.accent
                    borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)

                    Text {
                      anchors.centerIn: parent
                      text: qsTr("Save & Pin App")
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (!root.pickedApp) return
                        var m = root.pickedApp.match || root.pickedApp.id
                        var name = root.pickedApp.name || m
                        var cmd = root.pickedApp.command || m
                        root.pinWindow(m, name, root.targetWorkspace, root.flagLaunchAtBoot)
                        root.pickedApp = null
                        root.activeTab = "workspaces"
                      }
                    }
                  }
                }
              }
            }

            // Search Results List
            Text {
              text: qsTr("Installed Applications (Click to select & assign workspace):")
              color: Qt.darker(root.contentForeground, 1.8)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.searchFilteredApps

              BorderSurface {
                id: appSearchRow
                required property var modelData
                readonly property bool isSelected: Boolean(root.pickedApp && (root.pickedApp.id === appSearchRow.modelData.id || root.pickedApp.name === appSearchRow.modelData.name))

                width: parent.width
                implicitHeight: Style.space(38)
                radius: Style.cornerRadius
                color: appSearchRow.isSelected
                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                  : (appSearchHover.hovered ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : Style.hoverFillFor(root.contentForeground, root.contentForeground))
                borderSpec: Border.controlSpec(appSearchRow.isSelected ? "selected" : "normal", appSearchRow.isSelected ? Color.accent : Qt.darker(root.contentForeground, 2.2), Color.accent)

                HoverHandler { id: appSearchHover }

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(8)

                  Text {
                    text: appSearchRow.isSelected ? "✓" : "󰀵"
                    color: appSearchRow.isSelected ? "#10B981" : Color.accent
                    font.pixelSize: Style.font.caption
                    font.bold: appSearchRow.isSelected
                  }

                  Text {
                    Layout.fillWidth: true
                    text: appSearchRow.modelData.name || appSearchRow.modelData.id
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: appSearchRow.isSelected
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "match: " + (appSearchRow.modelData.match || "")
                    color: Qt.darker(root.contentForeground, 1.8)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Rectangle {
                    implicitWidth: pinTagTxt.implicitWidth + Style.space(12)
                    implicitHeight: Style.space(22)
                    radius: Style.space(3)
                    color: appSearchRow.isSelected ? "#10B981" : (appSearchHover.hovered ? Qt.lighter(Color.accent, 1.1) : Color.accent)

                    Text {
                      id: pinTagTxt
                      anchors.centerIn: parent
                      text: appSearchRow.isSelected ? "✓ Selected" : "Select"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.pickedApp = appSearchRow.modelData
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
