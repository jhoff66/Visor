import Foundation

/// Caminhos e ambiente do adb e do scrcpy embutidos no app.
enum Toolchain {
  static let scrcpyVersion = "5.0.1"

  static var archName: String {
    #if arch(arm64)
    return "arm64"
    #else
    return "x86_64"
    #endif
  }

  static var directory: URL {
    let base = Bundle.main.resourceURL ?? URL(fileURLWithPath: Bundle.main.bundlePath)
    return base.appendingPathComponent("scrcpy-\(archName)", isDirectory: true)
  }

  static var adb: URL { directory.appendingPathComponent("adb") }
  static var scrcpy: URL { directory.appendingPathComponent("scrcpy") }
  static var server: URL { directory.appendingPathComponent("scrcpy-server") }

  static var isAvailable: Bool {
    let fm = FileManager.default
    return fm.isExecutableFile(atPath: adb.path) && fm.isExecutableFile(atPath: scrcpy.path)
      && fm.fileExists(atPath: server.path)
  }

  /// Ambiente para o adb e o scrcpy: aponta para os binários embutidos.
  static var environment: [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["ADB"] = adb.path
    env["SCRCPY_SERVER_PATH"] = server.path
    env["SCRCPY_ICON_DIR"] = directory.path
    env["PATH"] = directory.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
    return env
  }

  /// Execução síncrona, usada só pelo modo --check e ao encerrar o app.
  static func runSync(_ exe: URL, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    p.environment = environment
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
  }

  /// Verdadeiro se já existe um processo adb rodando (servidor iniciado por outra pessoa/app).
  static func adbServerAlreadyRunning() -> Bool {
    runSync(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-x", "adb"]).status == 0
  }

  /// Modo de diagnóstico: imprime caminhos e versões e sai, sem abrir janela.
  static func runCheckAndExit() -> Never {
    let alreadyRunning = adbServerAlreadyRunning()
    func line(_ s: String) { print(s) }
    func exists(_ u: URL) -> String { FileManager.default.fileExists(atPath: u.path) ? "ok" : "AUSENTE" }
    var failed = false

    line("Visor --check")
    line("arquitetura: \(archName)")
    line("pasta:       \(directory.path)")
    line("adb:         \(adb.path) [\(exists(adb))]")
    line("scrcpy:      \(scrcpy.path) [\(exists(scrcpy))]")
    line("server:      \(server.path) [\(exists(server))]")
    line("")

    let sv = runSync(scrcpy, ["--version"])
    line("$ scrcpy --version")
    line(sv.output.split(separator: "\n").prefix(1).joined(separator: "\n"))
    if sv.status != 0 { failed = true }
    line("")

    let av = runSync(adb, ["version"])
    line("$ adb version")
    line(av.output.split(separator: "\n").prefix(2).joined(separator: "\n"))
    if av.status != 0 { failed = true }
    line("")

    let dv = runSync(adb, ["devices", "-l"])
    line("$ adb devices -l")
    line(dv.output.trimmingCharacters(in: .whitespacesAndNewlines))
    if dv.status != 0 { failed = true }

    if !alreadyRunning { _ = runSync(adb, ["kill-server"]) }
    line("")
    line(failed ? "RESULTADO: falhou" : "RESULTADO: ok")
    exit(failed ? 1 : 0)
  }
}
