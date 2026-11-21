import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  component ActionButton: Rectangle {
    id: button
    property string label: ""
    property bool selected: false
    property bool primary: false
    property bool enabledControl: true
    property real scaleFactor: 1
    signal activated()
    width: labelText.implicitWidth + 8 * scaleFactor
    height: labelText.implicitHeight + 8 * scaleFactor
    radius: 2 * scaleFactor
    opacity: enabledControl ? 1 : 0.48
    color: selected ? "#234638" : (pointer.containsMouse && enabledControl ? "#223039" : "transparent")
    border.width: 0
    Accessible.role: Accessible.Button
    Accessible.name: label
    Text {
      id: labelText
      anchors.centerIn: parent
      text: button.label
      color: button.selected || button.primary || (pointer.containsMouse && button.enabledControl) ? "#a7e8bc" : "#d7e2d5"
      font.family: Style.font.menuFamily
      font.pixelSize: 12 * button.scaleFactor
    }
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: labelText.implicitWidth
      height: Math.max(1, scaleFactor)
      color: "#a7e8bc"
      visible: button.enabledControl && (button.selected || pointer.containsMouse)
    }
    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabledControl
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }

  // Injected by omarchy-shell. All host interaction is limited to this plugin's lifecycle.
  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool commandMode: false
  property string commandKey: "m"
  property string shortcutLabel: "Ctrl+" + (commandKey === "space" ? "Space" : commandKey.toUpperCase())
  property bool captureBinding: false
  property string bindingMessage: ""
  property int pendingBinding: 0
  property bool globalPromptOpen: false
  property bool globalPromptYesSelected: false
  property bool promptedThisOpen: false
  property bool globalShortcutPrompted: false
  property bool installAfterPrompt: false
  property int pendingGlobalPrompt: 0
  property string globalShortcutStatus: ""
  property string hotkeyScriptPath: decodeURIComponent(Qt.resolvedUrl("scripts/install-hotkey.sh").toString().replace(/^file:\/\//, ""))
  property bool historyOpen: false
  property bool shareOpen: false
  property var historyRecords: []
  property string shareError: ""
  property bool graphAnimationEnabled: Quickshell.env("KEYRITUAL_REDUCED_MOTION") !== "1"
  property real graphProgress: 1
  property var state: ({})
  property string errorMessage: ""
  property string mode: "time"
  property int limit: 30
  property bool strict: false
  property bool punctuation: false
  property bool numbers: false
  property int serial: 0
  property int pendingStart: 0
  property int lastResponse: 0
  property bool patternEnabled: false
  property bool patternKnown: false
  property bool patternFallback: false
  property string patternError: ""
  property string patternNotice: ""
  property int pendingPatternClear: 0
  property var pendingPatternRequests: ({})
  property bool patternOwnsMainError: false

  property color background: "#111d22"
  property color foreground: "#d7e2d5"
  property color borderColor: "#46615f"
  property color scrim: "#77080e13"
  property color accent: "#a7e8bc"
  property color muted: "#779489"
  property color gridColor: "#223039"
  property color wrong: "#edaa77"
  property string fontFamily: Style.font.menuFamily
  // The marketplace clones this repository as a plugin; resolve its bundled engine beside this QML.
  property string binaryPath: Quickshell.env("KEYRITUAL_CORE") || decodeURIComponent(Qt.resolvedUrl("bin/keyritual-core").toString().replace(/^file:\/\//, ""))
  property real uiScale: Math.min(panel.width / 1280, panel.height / 720)
  property int cardWidth: Math.min(900 * uiScale, panel.width * 0.75)
  property int cardHeight: Math.min(panel.height * 0.8,
    Math.max(200 * uiScale,
      (state.phase === "finished" || state.phase === "failed" ? reflectContent.height : practiceContent.height) + 64 * uiScale))

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.mode === "time" || payload.mode === "words") mode = payload.mode
    if (payload.limit !== undefined && validLimit(mode, payload.limit)) limit = payload.limit
    if (typeof payload.strict === "boolean") strict = payload.strict
    if (typeof payload.punctuation === "boolean") punctuation = payload.punctuation
    if (typeof payload.numbers === "boolean") numbers = payload.numbers
    errorMessage = ""
    patternKnown = false
    pendingPatternRequests = ({})
    pendingPatternClear = 0
    patternOwnsMainError = false
    state = ({})
    commandMode = false
    captureBinding = false
    bindingMessage = ""
    globalPromptOpen = false
    globalPromptYesSelected = false
    promptedThisOpen = false
    globalShortcutStatus = ""
    historyOpen = false
    shareOpen = false
    opened = true
    if (engine.running) sendStart()
    else engine.running = true
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    commandMode = false
    captureBinding = false
    globalPromptOpen = false
    historyOpen = false
    shareOpen = false
    graphReveal.stop()
    engine.running = false
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.syfra3.keyritual")
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  function validLimit(nextMode, nextLimit) {
    return nextMode === "time" ? [15, 30, 60].indexOf(nextLimit) >= 0 : [10, 25, 50].indexOf(nextLimit) >= 0
  }

  function choose(nextMode, nextLimit) {
    mode = nextMode
    limit = nextLimit
    sendStart()
    keyCatcher.forceActiveFocus()
  }

  function nextMode() {
    mode = mode === "time" ? "words" : "time"
    limit = mode === "time" ? 30 : 25
    sendStart()
  }

  function nextLimit() {
    var choices = mode === "time" ? [15, 30, 60] : [10, 25, 50]
    limit = choices[(choices.indexOf(limit) + 1) % choices.length]
    sendStart()
  }

  function sendStart() {
    if (!engine.running) return
    state = ({})
    historyOpen = false
    shareOpen = false
    graphReveal.stop()
    graphProgress = 1
    errorMessage = ""
    patternOwnsMainError = false
    pendingStart = send({ type: "start", mode: mode, limit: limit, strict: strict, punctuation: punctuation, numbers: numbers })
    commandMode = false
  }

  function send(message) {
    if (!engine.running) return 0
    var next = { id: ++serial }
    for (var field in message) next[field] = message[field]
    engine.write(JSON.stringify(next) + "\n")
    return next.id
  }

  function patternAction(action) {
    var requestId = 0
    if (action === "status") requestId = root.send({ type: "get_pattern_practice" })
    else if (action === "enable") requestId = root.send({ type: "set_pattern_practice", enabled: true })
    else if (action === "disable") requestId = root.send({ type: "set_pattern_practice", enabled: false })
    else if (action === "clear") {
      root.patternNotice = ""
      requestId = root.send({ type: "clear_pattern_practice" })
      root.pendingPatternClear = requestId || 0
    }
    else if (action === "targeted" && root.patternEnabled && root.patternKnown !== false)
      root.send({ type: "start", mode: root.mode, limit: root.limit, strict: root.strict, punctuation: root.punctuation, numbers: root.numbers, targeted: true })
    if (requestId) {
      if (!root.pendingPatternRequests) root.pendingPatternRequests = ({})
      root.pendingPatternRequests[requestId] = action
    }
  }
  function patternResponse(message) {
    if (message.type === "pattern_practice") {
      root.patternEnabled = message.enabled === true
      root.patternKnown = true
      if (root.patternError && root.errorMessage === root.patternError && root.patternOwnsMainError !== false) root.errorMessage = ""
      root.patternOwnsMainError = false
      root.patternError = ""
      if (root.pendingPatternClear && message.id === root.pendingPatternClear) {
        root.patternNotice = "Pattern data cleared."
        root.pendingPatternClear = 0
      }
    }
    else if (message.type === "state") root.patternFallback = message.targeted === true && message.pattern_fallback === true
    else if (message.type === "error") {
      root.patternKnown = false
      root.patternError = message.message || "Pattern practice error"
      if (root.pendingPatternClear && message.id === root.pendingPatternClear) {
        root.pendingPatternClear = 0
        root.patternNotice = ""
      }
    }
  }
  function patternBehaviorEnd() {}

  function receive(line) {
    var message
    try { message = JSON.parse(line) } catch (e) { errorMessage = "Invalid response from Rust engine"; return }
    var patternRequest = root.pendingPatternRequests && root.pendingPatternRequests[message.id]
    if (patternRequest && (message.type === "pattern_practice" || message.type === "error")) {
      delete root.pendingPatternRequests[message.id]
      patternResponse(message)
      if (message.type === "error") {
        root.errorMessage = message.message || "Pattern practice error"
        root.patternOwnsMainError = true
      }
      return
    }
    if (message.id < pendingStart || message.id < lastResponse) return
    lastResponse = message.id
    if (typeof patternResponse === "function" && message.type === "state") patternResponse(message)
    if (message.type === "error") {
      var patternAccessError = message.code === "pattern_state_unavailable" || message.message === "Could not access pattern practice settings"
      root.patternOwnsMainError = patternAccessError
      if (patternAccessError) {
        root.patternKnown = false
        root.patternError = message.message || "Pattern practice settings unavailable"
      }
      if (message.id === pendingGlobalPrompt) {
        globalShortcutStatus = message.message || "Could not save shortcut decision"
        pendingGlobalPrompt = 0
      } else if (message.id === pendingBinding) bindingMessage = message.message || "Shortcut was not saved"
      else errorMessage = message.message || "Engine error"
    }
    else if (message.type === "preferences") {
      commandKey = message.command_key || "m"
      globalShortcutPrompted = message.global_shortcut_prompted === true
      bindingMessage = message.warning || (message.id === pendingBinding ? "Shortcut saved: " + shortcutLabel : "")
      if (message.id === pendingGlobalPrompt) {
        pendingGlobalPrompt = 0
        if (globalShortcutPrompted && installAfterPrompt) {
          installAfterPrompt = false
          globalShortcutStatus = "Verificando atajo y creando respaldo..."
          hotkeyInstall.running = true
        } else if (globalShortcutPrompted) {
          installAfterPrompt = false
          globalPromptOpen = false
        } else {
          installAfterPrompt = false
          globalShortcutStatus = "No se pudo guardar la decisión del atajo"
        }
      } else if (!globalShortcutPrompted && opened && !promptedThisOpen) {
        globalPromptYesSelected = false
        globalPromptOpen = true
        promptedThisOpen = true
      }
    }
    else if (message.type === "history") {
      historyRecords = message.records || []
      historyOpen = true
    }
    else if (message.type === "state") {
      var becameFinished = state.phase !== "finished" && message.phase === "finished"
      state = message
      if (becameFinished && graphAnimationEnabled && message.pace_wpm && message.pace_wpm.length > 1) {
        graphProgress = 0
        graphReveal.restart()
      }
    }
  }

  function answerGlobalShortcut(accepted) {
    if (!globalPromptOpen || pendingGlobalPrompt !== 0 || hotkeyInstall.running || !engine.running || globalShortcutPrompted) return
    installAfterPrompt = accepted
    globalShortcutStatus = "Guardando decisión..."
    pendingGlobalPrompt = send({ type: "set_shortcut_prompted", value: true })
  }

  function requestHistory() {
    if (engine.running) send({ type: "history" })
    else errorMessage = "History unavailable: engine stopped"
  }

  function shareText() {
    return "Keyritual: " + Math.round(state.wpm || 0) + " WPM, " + Math.round(state.accuracy || 0) + "% accuracy, " + mode + "/" + limit + (mode === "time" ? "s" : " words") + "."
  }

  function openXCompose() {
    var url = "https://twitter.com/intent/tweet?text=" + encodeURIComponent(shareText())
    if (!Qt.openUrlExternally(url)) shareError = "Could not open browser. No result was shared."
  }

  NumberAnimation {
    id: graphReveal
    target: root
    property: "graphProgress"
    from: 0
    to: 1
    duration: 600
  }

  function escapeHtml(character) {
    if (character === "&") return "&amp;"
    if (character === "<") return "&lt;"
    if (character === ">") return "&gt;"
    if (character === " ") return " " // Breakable spaces are required for word wrapping.
    return character
  }

  function promptHtml() {
    if (!state.prompt) return "&gt;_  WAITING FOR THE ENGINE..."
    var prompt = state.prompt
    var typed = state.typed || ""
    // Keep the full passage: the viewport follows the measured cursor, not a character slice.
    var correctColor = foreground.toString()
    var mutedColor = muted.toString()
    var errorColor = wrong.toString()
    var accentColor = accent.toString()
    var parts = []
    for (var i = 0; i < prompt.length; i++) {
      var character = i < typed.length ? typed[i] : prompt[i]
      var color = i < typed.length ? (typed[i] === prompt[i] ? correctColor : errorColor) : mutedColor
      var style = "color:" + color + ";"
      if (i === typed.length && state.phase !== "finished" && state.phase !== "failed")
        style += "background-color:" + accentColor + ";color:" + background.toString() + ";"
      parts.push("<span style='" + style + "'>" + escapeHtml(character) + "</span>")
    }
    return parts.join("")
  }

  Process {
    id: engine
    command: [root.binaryPath, "serve"]
    stdinEnabled: true
    stdout: SplitParser { onRead: line => root.receive(line) }
    stderr: SplitParser { onRead: line => console.warn("keyritual: " + line) }
    onStarted: { root.sendStart(); root.send({ type: "get_preferences" }); root.patternAction("status") }
    onExited: function(code, status) {
      if (root.opened) root.errorMessage = "Keyritual engine unavailable or stopped. Reinstall the plugin (x86_64 Linux/glibc required)."
    }
  }

  // Never starts on plugin load: only the dialog's accepted-and-saved decision starts this process.
  Process {
    id: hotkeyInstall
    command: ["bash", root.hotkeyScriptPath]
    stdout: SplitParser { onRead: line => root.globalShortcutStatus = line }
    stderr: SplitParser { onRead: line => root.globalShortcutStatus = line }
    onExited: function(code, status) {
      if (code !== 0 && root.globalShortcutStatus === "Verificando atajo y creando respaldo...")
        root.globalShortcutStatus = "No se pudo configurar el atajo; revisa ~/.config/hypr/bindings.lua"
    }
  }

  Timer {
    interval: 200
    running: root.opened && root.state.phase === "running"
    repeat: true
    onTriggered: root.send({ type: "tick" })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "keyritual"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    onVisibleChanged: {
      if (visible) Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
    }

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: { if (!root.globalPromptOpen && !hotkeyInstall.running) root.dismiss() } }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      color: root.background
      radius: 6
      border.color: root.borderColor
      border.width: 2

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }
      ActionButton {
        z: 10
        scaleFactor: root.uiScale
        x: card.width - width - 40 * root.uiScale
        y: 8 * root.uiScale
        label: "[ CLOSE ]"
        onActivated: { if (!root.globalPromptOpen && !hotkeyInstall.running) root.dismiss() }
      }

      Repeater {
        model: 4
        Item {
          width: 18 * root.uiScale
          height: width
          x: index % 2 === 0 ? 12 * root.uiScale : card.width - width - 12 * root.uiScale
          y: index < 2 ? 12 * root.uiScale : card.height - height - 12 * root.uiScale
          Rectangle {
            x: 0; y: index < 2 ? 0 : parent.height - height
            width: parent.width; height: 2 * root.uiScale; color: root.accent
          }
          Rectangle {
            x: index % 2 === 0 ? 0 : parent.width - width; y: 0
            width: 2 * root.uiScale; height: parent.height; color: root.accent
          }
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.globalPromptOpen) {
            if (root.pendingGlobalPrompt === 0 && !hotkeyInstall.running &&
                !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
              if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) root.globalPromptYesSelected = false
              else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) root.globalPromptYesSelected = true
              else if (event.key === Qt.Key_Escape || event.key === Qt.Key_N) {
                if (root.globalShortcutPrompted) root.globalPromptOpen = false
                else root.answerGlobalShortcut(false)
              } else if (event.key === Qt.Key_Y) root.answerGlobalShortcut(true)
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.globalShortcutPrompted) root.globalPromptOpen = false
                else root.answerGlobalShortcut(root.globalPromptYesSelected)
              }
            }
            event.accepted = true
            return
          }
          if (root.historyOpen || root.shareOpen) {
            if (event.key === Qt.Key_Escape) { root.historyOpen = false; root.shareOpen = false }
            event.accepted = true
            return
          }
          if (root.captureBinding) {
            if (event.key === Qt.Key_Escape) { root.captureBinding = false; root.bindingMessage = "Shortcut change cancelled" }
            else if (event.modifiers === Qt.ControlModifier && ((event.key >= Qt.Key_A && event.key <= Qt.Key_Z) || event.key === Qt.Key_Space)) {
              root.pendingBinding = root.send({ type: "set_command_key", key: event.key === Qt.Key_Space ? "space" : String.fromCharCode(event.key).toLowerCase() })
              root.captureBinding = false
              root.bindingMessage = "Saving shortcut..."
            } else root.bindingMessage = "Use Ctrl+letter or Ctrl+Space; Escape cancels"
            event.accepted = true
            return
          }
          if (event.modifiers === Qt.ControlModifier &&
              (root.commandKey === "space" ? event.key === Qt.Key_Space : event.key === root.commandKey.toUpperCase().charCodeAt(0))) {
            root.commandMode = !root.commandMode
            event.accepted = true
            return
          }
          if (root.commandMode) {
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            var command = (event.text || "").toLowerCase()
            if (command === "m") root.nextMode()
            else if (command === "t") root.nextLimit()
            else if (command === "s") { root.strict = !root.strict; root.sendStart() }
            else if (command === "p") { root.punctuation = !root.punctuation; root.sendStart() }
            else if (command === "n") { root.numbers = !root.numbers; root.sendStart() }
            else if (command === "r") root.sendStart()
            else if (command === "q") root.dismiss()
            else return
          }
          else if (event.key === Qt.Key_Tab || (root.state.phase === "finished" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter))) root.sendStart()
          else if (event.key === Qt.Key_Backspace) root.send({ type: "backspace" })
          else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) <= 126 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            root.send({ type: "key", text: event.text })
          else return
          event.accepted = true
        }
      }

      Flickable {
        visible: root.state.phase !== "finished" && root.state.phase !== "failed"
        x: 36 * root.uiScale
        y: 32 * root.uiScale
        width: card.width - x * 2
        height: card.height - y * 2
        contentHeight: practiceContent.height
        clip: true

        Column {
          id: practiceContent
          width: parent.width
          spacing: 10 * root.uiScale

        Text {
          visible: false
          text: "[02 / FIND YOUR RHYTHM]     [KEYRITUAL]   //   THE DAILY PRACTICE"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Flow {
          width: parent.width
          spacing: 10 * root.uiScale
          ActionButton {
            scaleFactor: root.uiScale
            label: root.commandMode ? "[ TYPING · " + root.shortcutLabel + " ]" : "[ COMMANDS · " + root.shortcutLabel + " ]"
            selected: root.commandMode
            onActivated: { root.commandMode = !root.commandMode; keyCatcher.forceActiveFocus() }
          }
          ActionButton {
            scaleFactor: root.uiScale
            label: root.captureBinding ? "[ CANCEL REBIND ]" : "[ REBIND SHORTCUT ]"
            selected: root.captureBinding
            onActivated: { root.captureBinding = !root.captureBinding; root.bindingMessage = root.captureBinding ? "Press Ctrl+letter or Ctrl+Space; Escape cancels" : "Shortcut change cancelled"; keyCatcher.forceActiveFocus() }
          }
          Text {
            text: root.commandMode ? "M MODE · T LIMIT · S STRICT · P PUNCT · N NUMBERS · R RESTART · Q QUIT" : "SESSION / PRACTICE · FOCUS: ACTIVE"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
            height: implicitHeight + 8 * root.uiScale; verticalAlignment: Text.AlignVCenter
          }
        }
        Text {
          visible: root.bindingMessage !== ""
          width: parent.width; text: root.bindingMessage
          color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
          wrapMode: Text.Wrap
        }
        Rectangle { width: parent.width; height: 1; color: root.borderColor }
        Flow {
          width: parent.width
          spacing: 10 * root.uiScale
          ActionButton {
            scaleFactor: root.uiScale; label: "[ M ] " + root.mode.toUpperCase(); selected: true
            onActivated: { root.nextMode(); keyCatcher.forceActiveFocus() }
          }
          ActionButton {
            scaleFactor: root.uiScale; label: "[ T ] " + root.limit + (root.mode === "time" ? " S" : " WORDS"); selected: true
            onActivated: { root.nextLimit(); keyCatcher.forceActiveFocus() }
          }
          ActionButton {
            scaleFactor: root.uiScale; label: "[ S ] " + (root.strict ? "STRICT" : "FORGIVING"); selected: root.strict
            onActivated: { root.strict = !root.strict; root.sendStart(); keyCatcher.forceActiveFocus() }
          }
          ActionButton {
            scaleFactor: root.uiScale; label: "[ P ] PUNCT " + (root.punctuation ? "ON" : "OFF"); selected: root.punctuation
            onActivated: { root.punctuation = !root.punctuation; root.sendStart(); keyCatcher.forceActiveFocus() }
          }
          ActionButton {
            scaleFactor: root.uiScale; label: "[ N ] NUMBERS " + (root.numbers ? "ON" : "OFF"); selected: root.numbers
            onActivated: { root.numbers = !root.numbers; root.sendStart(); keyCatcher.forceActiveFocus() }
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.borderColor }
        Text {
          width: parent.width; wrapMode: Text.Wrap
          text: "Optional coaching: consenting stores local counts of expected letters and pairs from practice, not typed text. Clear them any time. " + (!root.patternKnown ? "Collection status unavailable." : (root.patternEnabled ? "Collection enabled." : "Collection disabled.")) + (root.patternFallback ? " More practice is needed; using ordinary words." : "") + (root.patternError ? " " + root.patternError : "") + (root.patternNotice ? " " + root.patternNotice : "")
          color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
        }
        Flow {
          width: parent.width; spacing: 10 * root.uiScale
          ActionButton { scaleFactor: root.uiScale; label: "Targeted practice"; enabledControl: root.patternKnown && root.patternEnabled; onActivated: root.patternAction("targeted") }
          ActionButton { scaleFactor: root.uiScale; label: !root.patternKnown ? "Retry pattern status" : (root.patternEnabled ? "Disable pattern collection" : "Enable pattern collection"); onActivated: root.patternAction(!root.patternKnown ? "status" : (root.patternEnabled ? "disable" : "enable")) }
          ActionButton { scaleFactor: root.uiScale; label: "Clear pattern data"; enabledControl: root.patternKnown; onActivated: root.patternAction("clear") }
        }
        Text {
          visible: false
          width: parent.width
          text: "THE QUIET MOMENT  //  KEEP A STEADY RHYTHM"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Flickable {
          id: promptViewport
          width: parent.width
          height: 3 * promptMetrics.height
          contentHeight: Math.max(height, passage.contentHeight)
          clip: true
          interactive: false
          boundsBehavior: Flickable.StopAtBounds

          function alignCursor() {
            if (!root.state.prompt || root.errorMessage) { contentY = 0; return }
            var position = Math.min((root.state.typed || "").length, root.state.prompt.length)
            var cursor = passage.positionToRectangle(position)
            var line = promptMetrics.height
            contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), cursor.y - line))
          }
          onWidthChanged: Qt.callLater(alignCursor)
          onContentHeightChanged: Qt.callLater(alignCursor)

          FontMetrics { id: promptMetrics; font: passage.font }
          TextEdit {
            id: passage
            width: promptViewport.width
            height: contentHeight
            visible: !root.errorMessage
            text: root.promptHtml()
            textFormat: TextEdit.RichText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 28 * root.uiScale
            wrapMode: TextEdit.WordWrap
            readOnly: true
            activeFocusOnPress: false
            selectByMouse: false
            onTextChanged: Qt.callLater(promptViewport.alignCursor)
          }
          Text {
            objectName: "practiceError"
            width: promptViewport.width
            visible: !!root.errorMessage
            text: root.errorMessage
            textFormat: Text.PlainText
            color: root.wrong
            font.family: root.fontFamily
            font.pixelSize: 28 * root.uiScale
            wrapMode: Text.WordWrap
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onClicked: keyCatcher.forceActiveFocus() }
        }
        Rectangle { width: parent.width; height: 1; color: root.borderColor }
        Row {
          spacing: Math.max(18, Style.space(36))
          Text { text: (root.state.wpm || 0) + " WPM"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.title }
          Text { text: (root.state.accuracy === undefined ? 100 : root.state.accuracy) + "% ACC"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title }
          Text { text: root.mode === "time" ? Math.ceil((root.state.remaining_ms === undefined ? root.limit * 1000 : root.state.remaining_ms) / 1000) + " S LEFT" : (root.state.typed ? root.state.typed.trim().split(/\s+/).length : 0) + " / " + root.limit + " WORDS"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title }
        }
        Text {
          width: parent.width
          visible: false
          text: root.commandMode ? "COMMAND MODE  //  M MODE · T LIMIT · S STRICT · P PUNCT · N NUMBERS · R RESTART · Q QUIT · " + root.shortcutLabel.toUpperCase() + " RETURN" : "[ BACKSPACE ] CORRECT    [ TAB ] RESTART    [ " + root.shortcutLabel.toUpperCase() + " ] COMMANDS"
          color: root.commandMode ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
        ActionButton {
          scaleFactor: root.uiScale; label: "[ HISTORY ]"
          onActivated: { root.requestHistory(); keyCatcher.forceActiveFocus() }
        }
        }
      }

      Flickable {
        visible: root.state.phase === "finished" || root.state.phase === "failed"
        x: 36 * root.uiScale
        y: 32 * root.uiScale
        width: card.width - x * 2
        height: card.height - y * 2
        contentHeight: reflectContent.height
        clip: true

        Column {
          id: reflectContent
          width: parent.width
          spacing: 6 * root.uiScale

        Text {
          visible: false
          text: "[03 / THE AFTERGLOW]     [KEYRITUAL]   //   " + (root.state.phase === "failed" ? "SESSION ENDED" : "RITUAL COMPLETE")
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: ">_ SESSION / " + (root.state.phase === "failed" ? "MISSTEP" : "COMPLETE") + "                                      ✦ PERSONAL BEST " + (root.state.best_wpm || 0) + " WPM"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Rectangle { width: parent.width; height: 1; color: root.borderColor }
        Row {
          width: parent.width
          spacing: Math.max(32, parent.width * 0.15)
          Column {
            Text { text: String(root.state.wpm || 0); color: root.accent; font.family: root.fontFamily; font.pixelSize: 40 * root.uiScale; font.bold: true }
            Text { text: "WPM"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          }
          Column {
            Text { text: Math.round(root.state.accuracy || 0) + "%"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 40 * root.uiScale; font.bold: true }
            Text { text: "ACCURACY"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          }
          Column {
            Text { text: root.state.consistency === null || root.state.consistency === undefined ? "N/A" : root.state.consistency + "%"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 40 * root.uiScale; font.bold: true }
            Text { text: "CONSISTENCY"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.borderColor }
        Item {
          width: parent.width
          height: 125 * root.uiScale
          Text { x: 0; y: 0; text: "PACE OVER TIME // " + root.limit + (root.mode === "time" ? "S" : " WORDS"); color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale }
          Canvas {
            id: paceChart
            x: 0; y: 24 * root.uiScale
            width: parent.width * 0.65
            height: 82 * root.uiScale
            property var points: root.state.pace_wpm || []
            property var seconds: root.state.pace_seconds || []
            property real reveal: root.graphProgress
            onPointsChanged: requestPaint()
            onSecondsChanged: requestPaint()
            onRevealChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              ctx.strokeStyle = root.gridColor
              ctx.setLineDash([3, 5])
              for (var row = 1; row <= 2; row++) {
                ctx.beginPath(); ctx.moveTo(0, height * row / 3); ctx.lineTo(width, height * row / 3); ctx.stroke()
              }
              ctx.setLineDash([])
              if (points.length < 2) return
              var max = 1
              for (var j = 0; j < points.length; j++) max = Math.max(max, points[j])
              var span = Math.max(1, seconds[seconds.length - 1] - seconds[0])
              ctx.save()
              ctx.beginPath(); ctx.rect(0, 0, width * reveal, height); ctx.clip()
              ctx.strokeStyle = root.accent
              ctx.lineWidth = 2 * root.uiScale
              ctx.beginPath()
              for (var i = 0; i < points.length; i++) {
                var px = (seconds[i] - seconds[0]) / span * width
                var py = height - points[i] / max * (height - 8 * root.uiScale)
                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
              }
              ctx.stroke()
              ctx.restore()
            }
          }
          Image {
            width: 110 * root.uiScale; height: width
            anchors.right: parent.right
            anchors.top: parent.top
            source: Qt.resolvedUrl("keyritual-seal.png")
            fillMode: Image.PreserveAspectFit
          }
          Text { anchors.bottom: parent.bottom; text: root.state.pace_wpm && root.state.pace_wpm.length < 2 ? "NOT ENOUGH PACE SAMPLES" : "RAW " + (root.state.raw_wpm || 0) + " WPM / " + (root.state.mistakes || 0) + " MISTAKES"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale }
        }
        Text {
          width: parent.width
          text: root.state.previous_wpm === null || root.state.previous_wpm === undefined
            ? "NO PREVIOUS COMPARABLE SESSION"
            : "VS PREVIOUS SAME SETTINGS: " + (root.state.wpm - root.state.previous_wpm >= 0 ? "+" : "") + (root.state.wpm - root.state.previous_wpm) + " WPM  /  " + (root.state.accuracy - root.state.previous_accuracy >= 0 ? "+" : "") + (root.state.accuracy - root.state.previous_accuracy).toFixed(1) + " ACCURACY POINTS  /  ERRORS " + (root.state.previous_mistakes === null || root.state.previous_mistakes === undefined ? "N/A (OLDER SESSION)" : ((root.state.mistakes - root.state.previous_mistakes >= 0 ? "+" : "") + (root.state.mistakes - root.state.previous_mistakes)))
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 12 * root.uiScale
          wrapMode: Text.Wrap
        }
        Text {
          width: parent.width
          text: root.state.prior_average_wpm === null || root.state.prior_average_wpm === undefined
            ? "PRIOR 5 SAME SETTINGS: NO COMPARABLE SESSIONS"
            : "PRIOR 5 SAME SETTINGS: AVG " + root.state.prior_average_wpm + " WPM  /  AVG ERRORS " + (root.state.prior_average_errors === null || root.state.prior_average_errors === undefined ? "N/A (OLDER SESSIONS)" : root.state.prior_average_errors.toFixed(1))
          color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
          wrapMode: Text.Wrap
        }
        Flow {
          width: parent.width
          spacing: 10 * root.uiScale
          ActionButton { scaleFactor: root.uiScale; label: "[ HISTORY ]"; onActivated: { root.requestHistory(); keyCatcher.forceActiveFocus() } }
          ActionButton { scaleFactor: root.uiScale; label: "[ SHARE RESULT ]"; onActivated: { root.shareError = ""; root.shareOpen = true; keyCatcher.forceActiveFocus() } }
          ActionButton {
            scaleFactor: root.uiScale; label: "[ ANIMATION: " + (root.graphAnimationEnabled ? "ON" : "OFF") + " ]"; selected: root.graphAnimationEnabled
            onActivated: { root.graphAnimationEnabled = !root.graphAnimationEnabled; graphReveal.stop(); root.graphProgress = 1; keyCatcher.forceActiveFocus() }
          }
        }
        Text {
          visible: false
          text: "RAW " + (root.state.raw_wpm || 0) + " WPM    //    " + root.limit + (root.mode === "time" ? "S" : " WORDS") + "    //    " + (root.strict ? "STRICT" : "FORGIVING")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        ActionButton {
          scaleFactor: root.uiScale
          x: parent.width - width
          label: "[ ENTER ] TRY AGAIN"
          primary: true
          onActivated: { root.sendStart(); keyCatcher.forceActiveFocus() }
        }
        Text { visible: false; text: "LOCAL SESSION  //  REAL SCORES ONLY"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
        }
      }

      Rectangle {
        id: dialog
        visible: root.historyOpen || root.shareOpen
        z: 20
        anchors.fill: parent
        anchors.margins: 12 * root.uiScale
        radius: 5
        color: root.background
        border.color: root.borderColor
        border.width: 2
        MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }
        Flickable {
          x: 20 * root.uiScale; y: 18 * root.uiScale
          width: parent.width - x * 2
          height: parent.height - y * 2
          contentHeight: dialogContent.height
          clip: true
          Column {
            id: dialogContent
            width: parent.width
            spacing: 12 * root.uiScale
          Flow {
            width: parent.width
            spacing: 12 * root.uiScale
            Text { text: root.historyOpen ? "SESSION HISTORY / LATEST 20" : "SHARE RESULT / LOCAL PREVIEW"; color: root.accent; font.family: root.fontFamily; font.pixelSize: 16 * root.uiScale; font.bold: true; height: implicitHeight + 8 * root.uiScale; verticalAlignment: Text.AlignVCenter }
            ActionButton {
              scaleFactor: root.uiScale; label: "[ CLOSE ]"
              onActivated: { root.historyOpen = false; root.shareOpen = false; keyCatcher.forceActiveFocus() }
            }
          }
          Rectangle { width: parent.width; height: 1; color: root.borderColor }
          Text {
            visible: root.historyOpen
            text: "DATE / LOCAL TIME                    MODE          WPM     ACC      ERRORS"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
          }
          Flickable {
            visible: root.historyOpen
            width: parent.width
            height: Math.max(80 * root.uiScale, Math.min(240 * root.uiScale, dialog.height - 140 * root.uiScale))
            clip: true
            contentHeight: historyColumn.height
            Column {
              id: historyColumn
              width: parent.width
              spacing: 8 * root.uiScale
              Text { visible: root.historyRecords.length === 0; text: "NO COMPLETED SESSIONS YET"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale }
              Repeater {
                model: root.historyRecords
                Text {
                  width: historyColumn.width
                  text: {
                    var date = new Date(modelData.timestamp * 1000)
                    var dateText = isNaN(date.getTime()) ? "UNKNOWN DATE" : date.toLocaleString()
                    return dateText + "    " + String(modelData.mode).toUpperCase() + "/" + modelData.limit + "    " + modelData.wpm + " WPM    " + modelData.accuracy + "%    " + (modelData.mistakes === null || modelData.mistakes === undefined ? "—" : modelData.mistakes) + " ERRORS"
                  }
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
                  elide: Text.ElideRight
                }
              }
            }
          }
          Text {
            visible: root.shareOpen
            width: parent.width
            text: root.shareText()
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: 17 * root.uiScale
            wrapMode: Text.Wrap
          }
          Text {
            visible: root.shareOpen
            width: parent.width
            text: "Only the text above is sent to X when you click Open X compose. Review before posting."
            color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
            wrapMode: Text.Wrap
          }
          ActionButton {
            visible: root.shareOpen
            scaleFactor: root.uiScale; label: "[ OPEN X COMPOSE ]"; primary: true
            onActivated: root.openXCompose()
          }
          Text { visible: root.shareOpen && root.shareError !== ""; text: root.shareError; color: root.wrong; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale }
          }
        }
      }

      Rectangle {
        id: hotkeyDialog
        visible: root.globalPromptOpen
        z: 30
        anchors.fill: parent
        anchors.margins: 12 * root.uiScale
        color: root.background
        radius: 5
        border.color: root.borderColor
        border.width: 2
        MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }
        Flickable {
          x: 24 * root.uiScale; y: 22 * root.uiScale
          width: parent.width - x * 2
          height: parent.height - y * 2
          contentHeight: hotkeyContent.height
          clip: true
          Column {
            id: hotkeyContent
            width: parent.width
            spacing: 14 * root.uiScale
          Text { text: "¿Configurar atajo global para Keyritual?"; color: root.accent; font.family: root.fontFamily; font.bold: true; font.pixelSize: 18 * root.uiScale; width: parent.width; wrapMode: Text.Wrap }
          Text {
            width: parent.width
            text: "Super+Shift+K abrirá/cerrará Keyritual. Solo si aceptas, se agregará una línea a " + Quickshell.env("HOME") + "/.config/hypr/bindings.lua con respaldo. Si el atajo está ocupado, no se reemplazará."
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: 13 * root.uiScale
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            text: "Omarchy plugin add nunca ejecuta este script. [NO] no modifica Hyprland."
            color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            text: "←/↑ No · →/↓ Sí · Enter confirma · N/Escape rechaza · Y acepta"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
            wrapMode: Text.Wrap
          }
          Flow {
            width: parent.width
            spacing: 12 * root.uiScale
            ActionButton {
              scaleFactor: root.uiScale; label: "[ NO, GRACIAS / CERRAR ]"
              selected: !root.globalPromptYesSelected
              enabledControl: root.pendingGlobalPrompt === 0 && !hotkeyInstall.running
              onActivated: { if (root.globalShortcutPrompted) root.globalPromptOpen = false; else root.answerGlobalShortcut(false) }
            }
            ActionButton {
              scaleFactor: root.uiScale; label: "[ SÍ, AGREGAR ATAJO ]"
              selected: root.globalPromptYesSelected
              enabledControl: !root.globalShortcutPrompted && root.pendingGlobalPrompt === 0 && !hotkeyInstall.running
              onActivated: root.answerGlobalShortcut(true)
            }
          }
          Text {
            width: parent.width
            text: root.globalShortcutStatus
            visible: text !== ""
            color: root.wrong
            font.family: root.fontFamily; font.pixelSize: 12 * root.uiScale
            wrapMode: Text.Wrap
          }
          }
        }
      }
    }
  }
}
