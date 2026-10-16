import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in DeviceStore.shared.start() }
  }

  /// O app continua na barra de menus mesmo sem janela.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      SessionStore.shared.stopAll()
      if UserDefaults.standard.bool(forKey: "killAdbOnQuit"), DeviceStore.shared.startedServerOurselves {
        _ = Toolchain.runSync(Toolchain.adb, ["kill-server"])
      }
    }
  }
}

@main
struct VisorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  init() {
    let args = CommandLine.arguments
    if args.contains("--check") { Toolchain.runCheckAndExit() }
    if let i = args.firstIndex(of: "--snapshot") {
      Snapshot.runAndExit(folder: i + 1 < args.count ? args[i + 1] : "snapshots")
    }
  }

  var body: some Scene {
    Window("Visor", id: "main") {
      MainView()
        .environmentObject(DeviceStore.shared)
        .environmentObject(SessionStore.shared)
        .environmentObject(PresetStore.shared)
        .frame(minWidth: 900, minHeight: 560)
    }
    .defaultSize(width: 1100, height: 760)

    MenuBarExtra("Visor", systemImage: "iphone.gen3") {
      MenuBarView()
        .environmentObject(DeviceStore.shared)
        .environmentObject(SessionStore.shared)
        .environmentObject(PresetStore.shared)
    }

    Settings {
      SettingsView()
        .environmentObject(PresetStore.shared)
    }
  }
}

struct SettingsView: View {
  @EnvironmentObject var presets: PresetStore
  @AppStorage("killAdbOnQuit") private var killAdbOnQuit = false

  var body: some View {
    Form {
      Section("Geral") {
        Toggle("Encerrar o servidor adb ao sair (se o app o iniciou)", isOn: $killAdbOnQuit)
        Text("Encerrar o servidor desfaz as conexões por Wi-Fi.").font(.caption).foregroundStyle(.secondary)
      }
      Section("Presets") {
        Button("Recolocar presets prontos") { presets.restoreBuiltIn() }
      }
      Section("scrcpy embutido") {
        LabeledContent("Versão", value: Toolchain.scrcpyVersion)
        LabeledContent("Arquitetura", value: Toolchain.archName)
        LabeledContent("Pasta") {
          Text(Toolchain.directory.path).font(.caption).textSelection(.enabled)
        }
        LabeledContent("Gravações") {
          Button("Mostrar no Finder") {
            let dir = SessionStore.recordingsFolder
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 420)
  }
}
