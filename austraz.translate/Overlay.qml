import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string phase: "prompt"
  property string sourcePath: ""
  property string sourceText: ""
  property string resultText: ""
  property string screenName: ""
  property int cursorX: 0
  property int cursorY: 0

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: home + "/.config/omarchy/plugins/austraz.translate"
  readonly property string translateBin: pluginDir + "/bin/omarchy-llm-translate"
  readonly property string captureScript: pluginDir + "/capture-primary.sh"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int pad: Style.spacing.popupPadding
  readonly property int previewWidth: Style.space(240)

  function pickScreen(name) {
    var screens = Quickshell.screens && Quickshell.screens.values ? Quickshell.screens.values : Quickshell.screens
    if (!screens) return null
    var i
    if (name) {
      for (i = 0; i < screens.length; i++) {
        if (screens[i] && screens[i].name === name) return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.screenName = payload.screen || ""
    root.cursorX = Number(payload.x) || 0
    root.cursorY = Number(payload.y) || 0
    root.phase = "prompt"
    root.resultText = ""
    root.sourceText = payload.text || ""
    root.sourcePath = payload.file || ""
    if (root.sourcePath) sourceFile.reload()

    panel.screen = root.pickScreen(root.screenName)
    root.opened = true
    hideTimer.interval = 8000
    hideTimer.restart()
  }

  function close() {
    hideTimer.stop()
    work.running = false
    root.opened = false
    root.phase = "prompt"
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "austraz.translate")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function startTranslate() {
    if (root.phase === "working") return
    if (!root.sourcePath && !root.sourceText) return
    root.phase = "working"
    hideTimer.stop()
    work.running = true
  }

  function activate() {
    if (root.phase === "prompt") {
      root.startTranslate()
      return
    }
    if (root.phase === "done" && root.resultText)
      Quickshell.execDetached(["bash", "-lc", "printf '%s' \"$1\" | wl-copy", "bash", root.resultText])
    root.dismiss()
  }

  Timer {
    id: hideTimer
    interval: 8000
    onTriggered: root.dismiss()
  }

  FileView {
    id: sourceFile
    path: root.sourcePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      var next = text()
      if (next && !root.sourceText) root.sourceText = next
    }
  }

  Process {
    running: true
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--primary", "--type", "text", "--watch", root.captureScript]
  }

  Process {
    id: work
    stdinEnabled: !root.sourcePath
    stdout: StdioCollector {
      id: workOut
      waitForEnd: true
    }
    command: root.sourcePath
      ? [root.translateBin, "--file", root.sourcePath, "--stdout"]
      : [root.translateBin, "--stdout"]
    onStarted: {
      if (!root.sourcePath && root.sourceText) {
        write(root.sourceText)
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      var out = String(workOut.text || "").replace(/^\s+|\s+$/g, "")
      if (exitCode === 0 && out.length > 0) {
        root.resultText = out
        root.phase = "done"
        hideTimer.interval = 12000
        hideTimer.restart()
      } else if (exitCode === 2) {
        root.phase = "busy"
        hideTimer.interval = 4000
        hideTimer.restart()
      } else {
        root.phase = "error"
        hideTimer.interval = 4000
        hideTimer.restart()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "austraz-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }

    BorderSurface {
      id: card
      color: root.background
      borderSpec: root.borderSpec
      radius: root.cornerRadius
      padding: root.pad
      width: inner.implicitWidth + root.pad * 2 + card.borderLeft + card.borderRight
      height: inner.implicitHeight + root.pad * 2 + card.borderTop + card.borderBottom
      x: {
        var maxX = Math.max(Style.gapsOut, panel.width - width - Style.gapsOut)
        return Math.round(Math.min(Math.max(Style.gapsOut, root.cursorX + 10), maxX))
      }
      y: {
        var above = root.cursorY - height - 12
        var maxY = Math.max(Style.gapsOut, panel.height - height - Style.gapsOut)
        if (above >= Style.gapsOut) return Math.round(above)
        return Math.round(Math.min(Math.max(Style.gapsOut, root.cursorY + 16), maxY))
      }

      Column {
        id: inner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: card.borderTop + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: Style.spacing.sm

        Button {
          id: actionBtn
          text: root.phase === "working" ? "Traduction…"
            : root.phase === "busy" ? "NPU occupé"
            : root.phase === "error" ? "Échec"
            : root.phase === "done" ? "Copié — FR ↔ EN"
            : "FR ↔ EN"
          iconText: "󰗊"
          iconSpinning: root.phase === "working"
          bordered: true
          enabled: root.phase !== "working"
          onClicked: root.activate()
        }

        Text {
          visible: root.phase === "prompt" && root.sourceText.length > 0
          text: root.sourceText.replace(/\s+/g, " ").slice(0, 72) + (root.sourceText.length > 72 ? "…" : "")
          textFormat: Text.PlainText
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
          width: Math.max(actionBtn.implicitWidth, root.previewWidth)
        }

        Text {
          visible: root.phase === "done" && root.resultText.length > 0
          text: root.resultText
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          width: Math.max(actionBtn.implicitWidth, root.previewWidth)
          maximumLineCount: 12
          elide: Text.ElideRight
        }
      }
    }
  }
}
