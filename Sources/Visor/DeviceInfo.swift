import CoreGraphics
import Foundation

/// Dados extras do celular, lidos com uma única chamada `adb shell`.
struct DeviceInfo: Hashable {
  var marketName: String
  var brand: String
  var androidVersion: String
  var battery: Int?
  var charging = false
  var screenSize: CGSize?

  /// Proporção largura/altura da tela (9:20 se ainda não souber).
  var aspect: CGFloat {
    guard let s = screenSize, s.width > 0, s.height > 0 else { return 9.0 / 20.0 }
    return s.width / s.height
  }

  var screenLabel: String? {
    guard let s = screenSize else { return nil }
    return "\(Int(s.width)) × \(Int(s.height))"
  }

  private static let separator = "@@VISOR@@"

  /// Os seis comandos juntos, separados por uma linha marcadora.
  static var shellCommand: String {
    [
      "getprop ro.product.marketname",
      "getprop ro.product.vendor.marketname",
      "settings get global device_name",
      "getprop ro.product.brand",
      "getprop ro.build.version.release",
      "dumpsys battery",
      "wm size",
    ].joined(separator: "; echo \(separator); ")
  }

  static func parse(_ text: String, fallbackName: String) -> DeviceInfo {
    let parts = text.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
    func usable(_ s: String) -> String? { (s.isEmpty || s == "null") ? nil : s }

    let market = usable(part(0)) ?? usable(part(1)) ?? usable(part(2)) ?? fallbackName
    var brand = part(3)
    if brand == brand.lowercased() { brand = brand.capitalized }

    var info = DeviceInfo(marketName: market, brand: brand, androidVersion: part(4))
    for raw in part(5).split(whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("level:") { info.battery = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) }
      if line.hasPrefix("status:") { info.charging = line.dropFirst(7).trimmingCharacters(in: .whitespaces) == "2" }
    }
    // "Physical size: 720x1600" (e, se houver, "Override size:", que é o tamanho em uso).
    var size: CGSize?
    for raw in part(6).split(whereSeparator: \.isNewline) {
      let line = String(raw)
      guard let colon = line.firstIndex(of: ":") else { continue }
      let dims = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).split(separator: "x")
      guard dims.count == 2, let w = Double(dims[0]), let h = Double(dims[1]) else { continue }
      if size == nil || line.hasPrefix("Override") { size = CGSize(width: w, height: h) }
    }
    info.screenSize = size
    return info
  }
}

extension ADB {
  static func info(for device: Device) async -> DeviceInfo? {
    guard let r = try? await run(["-s", device.serial, "shell", DeviceInfo.shellCommand], timeout: 15), r.ok else { return nil }
    let fallback = (device.model ?? device.serial).replacingOccurrences(of: "_", with: " ")
    return DeviceInfo.parse(String(decoding: r.stdout, as: UTF8.self), fallbackName: fallback)
  }
}
