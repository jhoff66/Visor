import SwiftUI

struct MenuBarView: View {
  @EnvironmentObject var devices: DeviceStore
  @EnvironmentObject var sessions: SessionStore
  @EnvironmentObject var presets: PresetStore
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    if devices.devices.isEmpty {
      Text("Nenhum dispositivo")
    } else {
      ForEach(devices.devices) { device in
        let running = sessions.isRunning(device.serial)
        Button {
          if running {
            sessions.stop(serial: device.serial)
          } else {
            sessions.start(device: device, options: presets.preset(for: device.serial).options)
          }
        } label: {
          Text("\(running ? "Parar" : "Espelhar") — \(device.name) (\(device.connectionLabel))")
        }
        .disabled(!device.isReady)
      }
    }
    Divider()
    Button("Abrir janela") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("Sair") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
