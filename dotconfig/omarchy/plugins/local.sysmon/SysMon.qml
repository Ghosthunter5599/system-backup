import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "local.sysmon"

  property string labelText: " --%  󰰠 --%"
  property string tooltipContent: "Loading System Info..."

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["python3", "/home/b47m4n/.config/omarchy/plugins/local.sysmon/system_info.py"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.labelText = data.text || ""
          root.tooltipContent = data.tooltip || ""
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!proc.running) proc.running = true
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.labelText
    tooltipText: root.tooltipContent
    onPressed: function(b) {
      if (root.bar) root.bar.run("omarchy-launch-or-focus-tui 'btop'")
    }

    Component.onCompleted: {
      for (var i = 0; i < children.length; i++) {
        if (children[i].font !== undefined) {
          children[i].font.bold = true
          children[i].font.weight = Font.Bold
        }
      }
    }
  }
}
