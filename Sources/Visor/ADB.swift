import Foundation

struct ProcessResult {
  var status: Int32
  var stdout: Data
  var stderr: Data
  var timedOut = false
  var launchError: String?

  var out: String { String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
  var err: String { String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
  var ok: Bool { status == 0 && !timedOut && launchError == nil }
  /// Texto útil para mostrar ao usuário quando algo falhou.
  var message: String { [err, out].first(where: { !$0.isEmpty }) ?? "código \(status)" }
}

private final class DataBox: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
  var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

private final class FlagBox: @unchecked Sendable {
  private let lock = NSLock()
  private var flag = false
  func set() { lock.lock(); flag = true; lock.unlock() }
  var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

/// Executa um processo sem bloquear nenhuma thread de UI, com limite de tempo.
enum Runner {
  static func run(_ executable: URL, _ args: [String], env: [String: String]? = nil,
                  timeout: TimeInterval = 15, discardOutput: Bool = false) async -> ProcessResult {
    await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
      let p = Process()
      p.executableURL = executable
      p.arguments = args
      if let env { p.environment = env }
      p.standardInput = FileHandle.nullDevice

      let outBox = DataBox(), errBox = DataBox(), timedOut = FlagBox()
      let group = DispatchGroup()
      var pipes: [Pipe] = []

      if discardOutput {
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
      } else {
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        pipes = [o, e]
        for (pipe, box) in [(o, outBox), (e, errBox)] {
          group.enter()
          pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
              h.readabilityHandler = nil
              group.leave()
            } else {
              box.append(d)
            }
          }
        }
      }

      let finalPipes = pipes
      p.terminationHandler = { proc in
        DispatchQueue.global().async {
          // O daemon do adb pode herdar o pipe; não esperar o EOF para sempre.
          _ = group.wait(timeout: .now() + 1)
          for pipe in finalPipes { pipe.fileHandleForReading.readabilityHandler = nil }
          cont.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: outBox.value,
                                               stderr: errBox.value, timedOut: timedOut.value))
        }
      }

      do {
        try p.run()
      } catch {
        for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
        cont.resume(returning: ProcessResult(status: -1, stdout: Data(), stderr: Data(),
                                             launchError: error.localizedDescription))
        return
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        if p.isRunning {
          timedOut.set()
          p.terminate()
        }
      }
    }
  }
}

struct ADBError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct Device: Identifiable, Hashable {
  var serial: String
  var state: String
  var model: String?
  var product: String?

  var id: String { serial }
  var isReady: Bool { state == "device" }
  var isWifi: Bool { serial.contains(":") || serial.contains("_adb-tls-connect") }
  var connectionLabel: String { isWifi ? "Wi-Fi" : "USB" }
  var name: String {
    if let model, !model.isEmpty { return model.replacingOccurrences(of: "_", with: " ") }
    return serial
  }
  var stateLabel: String {
    switch state {
    case "device": return "Pronto"
    case "unauthorized": return "Não autorizado"
    case "offline": return "Offline"
    default: return state
    }
  }
}

enum ADB {
  /// Roda o adb embutido. Lança erro se o binário não abrir ou se estourar o tempo.
  @discardableResult
  static func run(_ args: [String], timeout: TimeInterval = 15, discardOutput: Bool = false) async throws -> ProcessResult {
    let r = await Runner.run(Toolchain.adb, args, env: Toolchain.environment, timeout: timeout, discardOutput: discardOutput)
    if let e = r.launchError { throw ADBError(message: "Não foi possível abrir o adb: \(e)") }
    if r.timedOut { throw ADBError(message: "O adb demorou demais para responder (\(Int(timeout)) s).") }
    return r
  }

  static func startServer() async throws {
    let r = try await run(["start-server"], timeout: 20, discardOutput: true)
    if !r.ok { throw ADBError(message: "Não foi possível iniciar o servidor do adb.") }
  }

  /// Parse de `adb devices -l`: `serial  estado  chave:valor ...`.
  static func parseDevices(_ text: String) -> [Device] {
    var list: [Device] = []
    for raw in text.split(whereSeparator: \.isNewline) {
      let line = String(raw)
      if line.hasPrefix("List of") || line.hasPrefix("*") { continue }
      let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
      guard tokens.count >= 2 else { continue }
      var device = Device(serial: tokens[0], state: tokens[1])
      for token in tokens.dropFirst(2) {
        guard let idx = token.firstIndex(of: ":") else { continue }
        let key = String(token[..<idx])
        let value = String(token[token.index(after: idx)...])
        if key == "model" { device.model = value }
        if key == "product" { device.product = value }
      }
      list.append(device)
    }
    return list
  }

  static func devices() async throws -> [Device] {
    let r = try await run(["devices", "-l"])
    guard r.ok else { throw ADBError(message: r.message) }
    return parseDevices(r.out)
  }

  // MARK: Wi-Fi

  /// IP do celular na rede, lido de `ip route` (campo `src`).
  static func ipAddress(serial: String) async throws -> String {
    let r = try await run(["-s", serial, "shell", "ip", "route"])
    guard r.ok else { throw ADBError(message: r.message) }
    let lines = r.out.split(whereSeparator: \.isNewline).map(String.init)
    func src(_ line: String) -> String? {
      let parts = line.split(separator: " ").map(String.init)
      guard let i = parts.firstIndex(of: "src"), i + 1 < parts.count else { return nil }
      return parts[i + 1]
    }
    if let ip = lines.filter({ $0.contains("wlan") }).compactMap(src).first { return ip }
    if let ip = lines.compactMap(src).first { return ip }
    throw ADBError(message: "O celular não parece estar conectado a uma rede Wi-Fi.")
  }

  static func connect(_ address: String) async throws -> String {
    let r = try await run(["connect", address], timeout: 20)
    let text = r.out + " " + r.err
    let lower = text.lowercased()
    if r.ok && lower.contains("connected") && !lower.contains("failed") && !lower.contains("cannot") {
      return r.out
    }
    throw ADBError(message: text.trimmingCharacters(in: .whitespaces))
  }

  static func pair(_ address: String, code: String) async throws -> String {
    let r = try await run(["pair", address, code], timeout: 20)
    let text = (r.out + " " + r.err).trimmingCharacters(in: .whitespaces)
    if r.ok && text.lowercased().contains("successfully paired") { return text }
    throw ADBError(message: text.isEmpty ? "Falha ao parear." : text)
  }

  static func enableTCPIP(serial: String, port: Int = 5555) async throws -> String {
    let ip = try await ipAddress(serial: serial)
    let r = try await run(["-s", serial, "tcpip", String(port)])
    guard r.ok else { throw ADBError(message: r.message) }
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    let address = "\(ip):\(port)"
    _ = try await connect(address)
    return address
  }

  static func disconnect(_ serial: String) async throws {
    let r = try await run(["disconnect", serial])
    if !r.ok { throw ADBError(message: r.message) }
  }
}
