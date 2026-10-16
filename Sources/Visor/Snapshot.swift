import AppKit
import SwiftUI

/// `Visor --snapshot <pasta>`: desenha a janela com dados de mentira e salva PNGs, sem adb nem timers.
@MainActor
enum Snapshot {
  private nonisolated static let pocoSerial = "192.168.8.22:5555"
  private nonisolated static let galaxySerial = "R58T10XK4QD"

  nonisolated static func runAndExit(folder: String) -> Never {
    MainActor.assumeIsolated { runAll(folder: folder) }
    exit(0)
  }

  private static func runAll(folder: String) {
    let dir = URL(fileURLWithPath: folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSApplication.shared.setActivationPolicy(.prohibited)

    func shot(_ name: String, dark: Bool, width: CGFloat = 1180, height: CGFloat = 860,
              mirroring: Bool = false, selection: String = pocoSerial, noThumbnail: Bool = false) {
      let env = makeStores(mirroring: mirroring, noThumbnail: noThumbnail)
      let file = dir.appendingPathComponent(name + ".png")
      let ok = render(env, selection: selection, dark: dark, size: NSSize(width: width, height: height), to: file)
      print(ok ? "ok  \(file.path)" : "ERRO \(name)")
    }

    shot("detail-light", dark: false)
    shot("detail-dark", dark: true)
    shot("detail-mirroring", dark: false, mirroring: true)
    shot("detail-narrow", dark: false, width: 900, height: 760)
    // Variantes extras: página inteira, estados sem prévia e não autorizado.
    shot("full-light", dark: false, height: 1500)
    shot("full-dark", dark: true, height: 1500)
    shot("full-narrow", dark: false, width: 900, height: 1900)
    shot("detail-mirroring-dark", dark: true, mirroring: true)
    shot("detail-unauthorized", dark: false, selection: galaxySerial)
    shot("detail-nothumb", dark: true, noThumbnail: true)
    // A barra lateral (NSOutlineView) não sai no cacheDisplay; as linhas vão num quadro à parte.
    for dark in [false, true] {
      let env = makeStores(mirroring: true, noThumbnail: false)
      let rows = VStack(alignment: .leading, spacing: 10) {
        ForEach(env.devices.devices) { DeviceRow(device: $0) }
      }
      .padding(16).frame(width: 240, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor))
      .environmentObject(env.devices).environmentObject(env.sessions)
      let name = dark ? "sidebar-dark" : "sidebar-light"
      let file = dir.appendingPathComponent(name + ".png")
      print(renderView(AnyView(rows), dark: dark, size: NSSize(width: 240, height: 130), to: file) ? "ok  \(file.path)" : "ERRO \(name)")
    }
  }

  private struct Env {
    let devices: DeviceStore
    let sessions: SessionStore
    let presets: PresetStore
  }

  private static func makeStores(mirroring: Bool, noThumbnail: Bool) -> Env {
    let poco = Device(serial: pocoSerial, state: "device", model: "POCO_C65", product: "ruby",
                      info: DeviceInfo(marketName: "POCO C65", brand: "POCO", androidVersion: "15",
                                       battery: 84, charging: false, screenSize: CGSize(width: 720, height: 1600)))
    let galaxy = Device(serial: galaxySerial, state: "unauthorized", model: "Galaxy_A54", product: "a54x")
    let devices = DeviceStore()
    devices.loadMock(devices: [poco, galaxy])
    if !noThumbnail { devices.setMockThumbnail(fakeHomeScreen(), serial: pocoSerial) }

    let sessions = SessionStore()
    let presets = PresetStore(ephemeral: true)
    if mirroring { sessions.setMockRunning(pocoSerial, options: presets.preset(for: pocoSerial).options) }
    return Env(devices: devices, sessions: sessions, presets: presets)
  }

  /// Gradiente com retângulos imitando uma tela inicial.
  private static func fakeHomeScreen() -> NSImage {
    let size = NSSize(width: 252, height: 560)
    let img = NSImage(size: size)
    img.lockFocus()
    NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.45, alpha: 1),
                        NSColor(red: 0.55, green: 0.32, blue: 0.78, alpha: 1),
                        NSColor(red: 0.16, green: 0.20, blue: 0.52, alpha: 1)])!
      .draw(in: NSRect(origin: .zero, size: size), angle: -90)
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 90, y: 505, width: 72, height: 6), xRadius: 3, yRadius: 3).fill()
    let palette: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemTeal, .systemYellow, .systemIndigo, .systemRed]
    for row in 0..<5 {
      for col in 0..<4 {
        palette[(row * 4 + col) % palette.count].withAlphaComponent(0.92).setFill()
        let r = NSRect(x: 18 + CGFloat(col) * 58, y: 430 - CGFloat(row) * 76, width: 44, height: 44)
        NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11).fill()
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 8, y: r.minY - 12, width: 28, height: 4), xRadius: 2, yRadius: 2).fill()
      }
    }
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: 12, y: 18, width: 228, height: 62), xRadius: 22, yRadius: 22).fill()
    for i in 0..<4 {
      palette[(i * 2 + 1) % palette.count].setFill()
      NSBezierPath(roundedRect: NSRect(x: 26 + CGFloat(i) * 54, y: 28, width: 42, height: 42), xRadius: 11, yRadius: 11).fill()
    }
    img.unlockFocus()
    return img
  }

  private static func render(_ env: Env, selection: String, dark: Bool, size: NSSize, to url: URL) -> Bool {
    let root = MainView(initialSelection: selection)
      .environmentObject(env.devices)
      .environmentObject(env.sessions)
      .environmentObject(env.presets)
      .frame(width: size.width, height: size.height)
    return renderView(AnyView(root), dark: dark, size: size, to: url)
  }

  private static func renderView(_ root: AnyView, dark: Bool, size: NSSize, to url: URL) -> Bool {
    let hosting = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = hosting
    window.setFrame(NSRect(origin: NSPoint(x: -20000, y: -20000), size: window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size), display: false)
    window.orderBack(nil)
    window.makeKey()

    // Deixa o SwiftUI montar e calcular o layout.
    for _ in 0..<6 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.25))
      hosting.layoutSubtreeIfNeeded()
    }

    // Captura a moldura inteira (barra de título e barra de ferramentas incluídas).
    let target = window.contentView?.superview ?? hosting
    guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return false }
    target.cacheDisplay(in: target.bounds, to: rep)
    window.orderOut(nil)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
  }
}
