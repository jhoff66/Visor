import AppKit
import Foundation

struct Notice: Identifiable, Equatable {
  let id = UUID()
  var text: String
  var isError: Bool
}

@MainActor
final class DeviceStore: ObservableObject {
  static let shared = DeviceStore()

  @Published private(set) var devices: [Device] = []
  @Published private(set) var loaded = false
  @Published private(set) var adbProblem: String?
  @Published var notice: Notice?
  @Published var busyText: String?

  /// Verdadeiro se fomos nós que iniciamos o servidor do adb.
  private(set) var startedServerOurselves = false
  private var pollTask: Task<Void, Never>?

  func start() {
    guard pollTask == nil else { return }
    pollTask = Task { [weak self] in
      guard let self else { return }
      if !Toolchain.isAvailable {
        self.adbProblem = "Os binários do scrcpy/adb não foram encontrados dentro do app."
        self.loaded = true
        return
      }
      self.startedServerOurselves = !Toolchain.adbServerAlreadyRunning()
      do { try await ADB.startServer() } catch { self.adbProblem = error.localizedDescription }
      while !Task.isCancelled {
        await self.refresh()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }

  func refresh() async {
    do {
      let list = try await ADB.devices()
      if list != devices { devices = list }
      adbProblem = nil
    } catch {
      adbProblem = error.localizedDescription
    }
    loaded = true
  }

  func device(serial: String) -> Device? { devices.first { $0.serial == serial } }

  // MARK: Avisos

  func announce(_ text: String, error: Bool = false) {
    let n = Notice(text: text, isError: error)
    notice = n
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 7_000_000_000)
      if self?.notice?.id == n.id { self?.notice = nil }
    }
  }

  private func stamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
    return f.string(from: Date())
  }

  static func safeFileName(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  }

  // MARK: Ações rápidas

  func screenshot(_ device: Device) async {
    busyText = "Capturando a tela…"
    defer { busyText = nil }
    let r = await Runner.run(Toolchain.adb, ["-s", device.serial, "exec-out", "screencap", "-p"],
                             env: Toolchain.environment, timeout: 30)
    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    guard r.ok, r.stdout.count > 8, Array(r.stdout.prefix(4)) == png else {
      announce("Não foi possível capturar a tela: \(r.launchError ?? r.message)", error: true)
      return
    }
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
    let file = desktop.appendingPathComponent("\(Self.safeFileName(device.name)) \(stamp()).png")
    do {
      try r.stdout.write(to: file)
      NSWorkspace.shared.activateFileViewerSelecting([file])
      announce("Print salvo na Mesa: \(file.lastPathComponent)")
    } catch {
      announce("Não foi possível salvar o print: \(error.localizedDescription)", error: true)
    }
  }

  func install(_ apk: URL, on device: Device) async {
    busyText = "Instalando \(apk.lastPathComponent)…"
    defer { busyText = nil }
    do {
      let r = try await ADB.run(["-s", device.serial, "install", "-r", apk.path], timeout: 300)
      if r.ok && r.out.contains("Success") {
        announce("\(apk.lastPathComponent) instalado em \(device.name).")
      } else {
        announce("Falha ao instalar: \(r.message)", error: true)
      }
    } catch {
      announce("Falha ao instalar: \(error.localizedDescription)", error: true)
    }
  }

  func push(_ file: URL, on device: Device) async {
    busyText = "Enviando \(file.lastPathComponent)…"
    defer { busyText = nil }
    do {
      let r = try await ADB.run(["-s", device.serial, "push", file.path, "/sdcard/Download/"], timeout: 900)
      if r.ok {
        announce("\(file.lastPathComponent) enviado para a pasta Download do celular.")
      } else {
        announce("Falha ao enviar: \(r.message)", error: true)
      }
    } catch {
      announce("Falha ao enviar: \(error.localizedDescription)", error: true)
    }
  }

  /// Arrastar e soltar: .apk instala, qualquer outra coisa vai para /sdcard/Download/.
  func handleDrop(_ urls: [URL], on device: Device) async {
    guard device.isReady else {
      announce("O dispositivo não está pronto (\(device.stateLabel)).", error: true)
      return
    }
    for url in urls {
      if url.pathExtension.lowercased() == "apk" {
        await install(url, on: device)
      } else {
        await push(url, on: device)
      }
    }
  }

  func disconnect(_ device: Device) async {
    do {
      try await ADB.disconnect(device.serial)
      SessionStore.shared.stop(serial: device.serial)
      await refresh()
      announce("\(device.name) desconectado.")
    } catch {
      announce("Falha ao desconectar: \(error.localizedDescription)", error: true)
    }
  }
}
