import Foundation

enum VideoCodec: String, Codable, CaseIterable, Identifiable {
  case h264, h265, av1
  var id: String { rawValue }
  var label: String { rawValue.uppercased() }
}

enum CameraFacing: String, Codable, CaseIterable, Identifiable {
  case back, front
  var id: String { rawValue }
  var label: String { self == .back ? "Traseira" : "Frontal" }
}

/// Opções do scrcpy que o usuário escolhe na interface. Salvas dentro de cada preset.
struct Options: Codable, Equatable {
  var maxSize = 0            // 0 = original
  var bitRateMbps = 8
  var maxFps = 0             // 0 = sem limite
  var codec = VideoCodec.h264
  var audio = true
  var turnScreenOff = false
  var stayAwake = false
  var showTouches = false
  var alwaysOnTop = false
  var borderless = false
  var fullscreen = false
  var viewOnly = false
  var physicalKeyboard = false
  var physicalMouse = false
  var record = false
  var camera = false
  var cameraFacing = CameraFacing.back
  var extraArguments = ""

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
    maxSize = v(.maxSize, 0)
    bitRateMbps = v(.bitRateMbps, 8)
    maxFps = v(.maxFps, 0)
    codec = v(.codec, .h264)
    audio = v(.audio, true)
    turnScreenOff = v(.turnScreenOff, false)
    stayAwake = v(.stayAwake, false)
    showTouches = v(.showTouches, false)
    alwaysOnTop = v(.alwaysOnTop, false)
    borderless = v(.borderless, false)
    fullscreen = v(.fullscreen, false)
    viewOnly = v(.viewOnly, false)
    physicalKeyboard = v(.physicalKeyboard, false)
    physicalMouse = v(.physicalMouse, false)
    record = v(.record, false)
    camera = v(.camera, false)
    cameraFacing = v(.cameraFacing, .back)
    extraArguments = v(.extraArguments, "")
  }

  /// Argumentos do scrcpy (sem o `-s serial`). Todas as flags existem no `scrcpy --help` da v5.0.1.
  func arguments(windowTitle: String, recordPath: String?) -> [String] {
    var a: [String] = ["--window-title=\(windowTitle)"]

    if camera {
      a += ["--video-source=camera", "--camera-facing=\(cameraFacing.rawValue)"]
    }
    if maxSize > 0 { a.append("--max-size=\(maxSize)") }
    a.append("--video-bit-rate=\(bitRateMbps)M")
    if maxFps > 0 { a.append("--max-fps=\(maxFps)") }
    a.append("--video-codec=\(codec.rawValue)")
    if !audio { a.append("--no-audio") }

    // Opções que dependem de controle do aparelho não valem para câmera nem para "só visualizar".
    let controllable = !camera && !viewOnly
    if viewOnly && !camera { a.append("--no-control") }
    if controllable {
      if turnScreenOff { a.append("--turn-screen-off") }
      if stayAwake { a.append("--stay-awake") }
      if showTouches { a.append("--show-touches") }
      if physicalKeyboard { a.append("--keyboard=uhid") }
      if physicalMouse { a.append("--mouse=uhid") }
    }

    if alwaysOnTop { a.append("--always-on-top") }
    if borderless { a.append("--window-borderless") }
    if fullscreen { a.append("--fullscreen") }
    if let recordPath { a.append("--record=\(recordPath)") }

    a += Options.splitArguments(extraArguments)
    return a
  }

  /// Divide texto livre em argumentos, respeitando aspas simples, duplas e barra invertida.
  static func splitArguments(_ text: String) -> [String] {
    var result: [String] = []
    var current = ""
    var hasToken = false
    var quote: Character?
    var escaping = false
    for ch in text {
      if escaping { current.append(ch); escaping = false; hasToken = true; continue }
      if ch == "\\" && quote != "'" { escaping = true; continue }
      if let q = quote {
        if ch == q { quote = nil } else { current.append(ch) }
        continue
      }
      if ch == "\"" || ch == "'" { quote = ch; hasToken = true; continue }
      if ch.isWhitespace {
        if hasToken { result.append(current); current = ""; hasToken = false }
        continue
      }
      current.append(ch)
      hasToken = true
    }
    if hasToken { result.append(current) }
    return result
  }
}
