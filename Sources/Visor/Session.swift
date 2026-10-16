import AppKit
import Foundation

/// Uma execução do scrcpy para um dispositivo.
@MainActor
final class Session: ObservableObject {
  let serial: String

  @Published private(set) var isRunning = false
  @Published private(set) var log = ""
  @Published private(set) var errorSummary: String?
  @Published private(set) var lastRecording: URL?

  var onStateChange: (() -> Void)?

  private var process: Process?
  private var stoppedByUser = false
  private static let maxLogLength = 200_000

  init(serial: String) { self.serial = serial }

  func start(arguments: [String], recording: URL?) {
    guard !isRunning else { return }
    errorSummary = nil
    stoppedByUser = false

    let p = Process()
    p.executableURL = Toolchain.scrcpy
    p.arguments = ["-s", serial] + arguments
    p.environment = Toolchain.environment
    p.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe

    append("\n$ scrcpy " + p.arguments!.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + "\n")

    pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      if d.isEmpty { h.readabilityHandler = nil; return }
      let text = String(decoding: d, as: UTF8.self)
      Task { @MainActor in self?.append(text) }
    }
    p.terminationHandler = { proc in
      let status = proc.terminationStatus
      let signaled = proc.terminationReason == .uncaughtSignal
      // Dá um instante para o restante da saída chegar ao log antes de resumir o erro.
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 300_000_000)
        self.finished(status: status, signaled: signaled, recording: recording)
      }
    }

    do {
      try p.run()
      process = p
      isRunning = true
      if recording != nil { lastRecording = nil }
      onStateChange?()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      errorSummary = "Não foi possível abrir o scrcpy: \(error.localizedDescription)"
      append(errorSummary! + "\n")
    }
  }

  func stop() {
    guard let p = process, p.isRunning else { return }
    stoppedByUser = true
    p.terminate()
    let pid = p.processIdentifier
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      if p.isRunning { kill(pid, SIGKILL) }
    }
  }

  func clearLog() { log = "" }

  private func append(_ text: String) {
    log += text
    if log.count > Self.maxLogLength { log = String(log.suffix(Self.maxLogLength / 2)) }
  }

  private func finished(status: Int32, signaled: Bool, recording: URL?) {
    process = nil
    isRunning = false
    if let recording, FileManager.default.fileExists(atPath: recording.path) { lastRecording = recording }
    append("\n[scrcpy encerrado com código \(status)]\n")
    if status != 0 && !stoppedByUser && !signaled {
      let lines = log.split(whereSeparator: \.isNewline).map(String.init)
        .filter { !$0.hasPrefix("[scrcpy encerrado") && !$0.hasPrefix("$ ") }
      let errors = lines.filter { $0.contains("ERROR") }
      let tail = (errors.isEmpty ? lines : errors).suffix(6)
      errorSummary = tail.joined(separator: "\n")
    }
    onStateChange?()
  }
}

@MainActor
final class SessionStore: ObservableObject {
  static let shared = SessionStore()

  @Published private(set) var runningSerials: Set<String> = []
  private var sessions: [String: Session] = [:]

  var anyRunning: Bool { !runningSerials.isEmpty }

  func session(for serial: String) -> Session {
    if let s = sessions[serial] { return s }
    let s = Session(serial: serial)
    s.onStateChange = { [weak self, weak s] in
      guard let self, let s else { return }
      if s.isRunning { self.runningSerials.insert(s.serial) } else { self.runningSerials.remove(s.serial) }
    }
    sessions[serial] = s
    return s
  }

  func isRunning(_ serial: String) -> Bool { runningSerials.contains(serial) }

  static var recordingsFolder: URL {
    FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Visor", isDirectory: true)
  }

  func start(device: Device, options: Options) {
    let s = session(for: device.serial)
    var recordURL: URL?
    if options.record {
      let f = DateFormatter()
      f.locale = Locale(identifier: "pt_BR")
      f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
      let dir = Self.recordingsFolder
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      recordURL = dir.appendingPathComponent("\(DeviceStore.safeFileName(device.name)) \(f.string(from: Date())).mp4")
    }
    let args = options.arguments(windowTitle: device.name, recordPath: recordURL?.path)
    s.start(arguments: args, recording: recordURL)
  }

  func stop(serial: String) { sessions[serial]?.stop() }

  func stopAll() { sessions.values.forEach { $0.stop() } }
}
