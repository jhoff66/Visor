import Foundation

struct Preset: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var options: Options
}

@MainActor
final class PresetStore: ObservableObject {
  static let shared = PresetStore()

  @Published private(set) var presets: [Preset] = []
  private let storageKey = "presets.v1"
  private let selectionPrefix = "preset.selected."
  /// Em memória (modo --snapshot): não lê nem grava nas preferências do usuário.
  private let ephemeral: Bool
  private var memorySelection: [String: UUID] = [:]

  init(ephemeral: Bool) {
    self.ephemeral = ephemeral
    presets = Self.builtIn()
  }

  init() {
    ephemeral = false
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let saved = try? JSONDecoder().decode([Preset].self, from: data), !saved.isEmpty {
      presets = saved
    } else {
      presets = Self.builtIn()
      save()
    }
  }

  static func builtIn() -> [Preset] {
    var padrao = Options()
    padrao.audio = true

    var leve = Options()
    leve.maxSize = 1024
    leve.bitRateMbps = 4
    leve.maxFps = 30

    var gravacao = Options()
    gravacao.maxSize = 0
    gravacao.bitRateMbps = 16
    gravacao.maxFps = 60
    gravacao.record = true

    var apresentacao = Options()
    apresentacao.showTouches = true
    apresentacao.alwaysOnTop = true

    return [
      Preset(name: "Padrão", options: padrao),
      Preset(name: "Leve (Wi-Fi)", options: leve),
      Preset(name: "Gravação", options: gravacao),
      Preset(name: "Apresentação", options: apresentacao),
    ]
  }

  private func save() {
    if ephemeral { return }
    if let data = try? JSONEncoder().encode(presets) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }

  func preset(for serial: String) -> Preset {
    if ephemeral {
      if let id = memorySelection[serial], let p = presets.first(where: { $0.id == id }) { return p }
      return presets.first ?? Preset(name: "Padrão", options: Options())
    }
    if let s = UserDefaults.standard.string(forKey: selectionPrefix + serial),
       let id = UUID(uuidString: s), let p = presets.first(where: { $0.id == id }) {
      return p
    }
    return presets.first ?? Preset(name: "Padrão", options: Options())
  }

  func select(_ id: UUID, for serial: String) {
    if ephemeral { memorySelection[serial] = id; objectWillChange.send(); return }
    UserDefaults.standard.set(id.uuidString, forKey: selectionPrefix + serial)
    objectWillChange.send()
  }

  func update(options: Options, of id: UUID) {
    guard let i = presets.firstIndex(where: { $0.id == id }), presets[i].options != options else { return }
    presets[i].options = options
    save()
  }

  @discardableResult
  func add(name: String, options: Options) -> Preset {
    let p = Preset(name: name, options: options)
    presets.append(p)
    save()
    return p
  }

  func rename(_ id: UUID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return }
    presets[i].name = trimmed
    save()
  }

  func delete(_ id: UUID) {
    presets.removeAll { $0.id == id }
    if presets.isEmpty { presets = Self.builtIn() }
    save()
  }

  /// Recoloca os quatro presets prontos que não existirem mais (por nome).
  func restoreBuiltIn() {
    for p in Self.builtIn() where !presets.contains(where: { $0.name == p.name }) {
      presets.append(p)
    }
    save()
  }
}
