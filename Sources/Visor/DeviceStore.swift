import AppKit
import Foundation
import ImageIO

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
  @Published private(set) var info: [String: DeviceInfo] = [:]
  @Published private(set) var thumbnail: [String: NSImage] = [:]

  private var loadingInfo: Set<String> = []
  private var capturing: Set<String> = []

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
      var list = try await ADB.devices()
      for i in list.indices { list[i].info = info[list[i].serial] }
      if list != devices { devices = list }
      adbProblem = nil
      // Lê o nome comercial uma vez por dispositivo pronto, para a barra lateral.
      for d in list where d.isReady && info[d.serial] == nil {
        Task { [weak self] in await self?.loadInfo(d) }
      }
    } catch {
      adbProblem = error.localizedDescription
    }
    loaded = true
  }

  /// Dados de mentira para o modo --snapshot: sem adb e sem timers.
  func loadMock(devices: [Device]) {
    self.devices = devices
    for d in devices { if let i = d.info { info[d.serial] = i } }
    loaded = true
  }

  func setMockThumbnail(_ image: NSImage, serial: String) { thumbnail[serial] = image }

  func device(serial: String) -> Device? { devices.first { $0.serial == serial } }

  // MARK: Informações e prévia da tela

  func loadInfo(_ device: Device) async {
    guard !loadingInfo.contains(device.serial) else { return }
    loadingInfo.insert(device.serial)
    defer { loadingInfo.remove(device.serial) }
    guard let loaded = await ADB.info(for: device) else { return }
    setInfo(loaded, serial: device.serial)
  }

  private func setInfo(_ value: DeviceInfo, serial: String) {
    if info[serial] != value { info[serial] = value }
    if let i = devices.firstIndex(where: { $0.serial == serial }), devices[i].info != value { devices[i].info = value }
  }

  /// Captura a tela e guarda uma miniatura. Falhou: mantém a última imagem.
  func refreshThumbnail(serial: String) async {
    guard !capturing.contains(serial) else { return }
    capturing.insert(serial)
    defer { capturing.remove(serial) }
    guard let png = await Self.captureScreen(serial: serial, timeout: 12) else { return }
    let image = await Task.detached(priority: .utility) { Self.makeThumbnail(png, height: 560) }.value
    if let image { thumbnail[serial] = image }
  }

  /// A janela do Visor está visível (não minimizada nem coberta)?
  static var windowVisible: Bool {
    NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) && $0.canBecomeMain }
  }

  /// Roda enquanto o dispositivo está selecionado: atualiza dados a cada 30 s e a prévia a cada 4 s
  /// (só quando a janela está visível e a tela não está sendo espelhada).
  func watch(serial: String, mirroring: Bool) async {
    var lastInfo = Date.distantPast
    while !Task.isCancelled {
      guard let device = device(serial: serial), device.isReady else { return }
      if Date().timeIntervalSince(lastInfo) >= 30 {
        await loadInfo(device)
        lastInfo = Date()
      }
      if !mirroring && Self.windowVisible { await refreshThumbnail(serial: serial) }
      try? await Task.sleep(nanoseconds: 4_000_000_000)
    }
  }

  /// PNG da tela via `adb exec-out screencap -p`, ou nil se falhar.
  nonisolated static func captureScreen(serial: String, timeout: TimeInterval) async -> Data? {
    let r = await Runner.run(Toolchain.adb, ["-s", serial, "exec-out", "screencap", "-p"],
                             env: Toolchain.environment, timeout: timeout)
    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    guard r.ok, r.stdout.count > 8, Array(r.stdout.prefix(4)) == png else { return nil }
    return r.stdout
  }

  /// Reduz o PNG para a altura pedida (em pixels).
  nonisolated static func makeThumbnail(_ data: Data, height: CGFloat) -> NSImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: height,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
  }

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
    guard let png = await Self.captureScreen(serial: device.serial, timeout: 30) else {
      announce("Não foi possível capturar a tela.", error: true)
      return
    }
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
    let file = desktop.appendingPathComponent("\(Self.safeFileName(device.name)) \(stamp()).png")
    do {
      try png.write(to: file)
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
