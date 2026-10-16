import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DeviceDetailView: View {
  let device: Device
  var onWifi: () -> Void = {}
  @EnvironmentObject var store: DeviceStore
  @EnvironmentObject var sessions: SessionStore
  @EnvironmentObject var presets: PresetStore

  @State private var importing: ImportKind?
  @State private var renaming = false
  @State private var newName = ""
  @State private var creating = false
  @State private var dropTargeted = false

  private enum ImportKind: Identifiable {
    case apk, file
    var id: Int { self == .apk ? 0 : 1 }
  }

  var body: some View {
    SessionContent(device: device, session: sessions.session(for: device.serial), onWifi: onWifi,
                   importing: $importing, renaming: $renaming, newName: $newName,
                   creating: $creating, dropTargeted: $dropTargeted)
  }

  // Conteúdo separado para observar a sessão do dispositivo.
  private struct SessionContent: View {
    let device: Device
    @ObservedObject var session: Session
    let onWifi: () -> Void
    @Binding var importing: ImportKind?
    @Binding var renaming: Bool
    @Binding var newName: String
    @Binding var creating: Bool
    @Binding var dropTargeted: Bool

    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var sessions: SessionStore
    @EnvironmentObject var presets: PresetStore
    @State private var logOpen = false

    private var current: Preset { presets.preset(for: device.serial) }
    private var mirroring: Bool { sessions.isRunning(device.serial) }

    private var optionsBinding: Binding<Options> {
      Binding(get: { presets.preset(for: device.serial).options },
              set: { presets.update(options: $0, of: presets.preset(for: device.serial).id) })
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          heroCard
          statusMessages
          configuration
          logCard
        }
        .frame(maxWidth: 860)
        .padding(24)
        .frame(maxWidth: .infinity)
      }
      .task(id: "\(device.serial)|\(device.isReady)|\(mirroring)") {
        await store.watch(serial: device.serial, mirroring: mirroring)
      }
      .onChange(of: session.errorSummary) { _, new in if new != nil { logOpen = true } }
      .overlay {
        if dropTargeted {
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(Color.accentColor.opacity(0.08))
            .overlay(Text("Solte aqui: .apk instala, outros arquivos vão para Download").font(.headline))
            .padding(8)
            .allowsHitTesting(false)
        }
      }
      .dropDestination(for: URL.self) { urls, _ in
        Task { await store.handleDrop(urls.filter { $0.isFileURL }, on: device) }
        return true
      } isTargeted: { dropTargeted = $0 }
      .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                    allowedContentTypes: importing == .apk ? [UTType(filenameExtension: "apk") ?? .data] : [.item]) { result in
        let kind = importing
        importing = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
          if kind == .apk { await store.install(url, on: device) } else { await store.push(url, on: device) }
          if scoped { url.stopAccessingSecurityScopedResource() }
        }
      }
      .alert("Renomear preset", isPresented: $renaming) {
        TextField("Nome", text: $newName)
        Button("Cancelar", role: .cancel) {}
        Button("Salvar") { presets.rename(current.id, to: newName) }
      }
      .alert("Novo preset", isPresented: $creating) {
        TextField("Nome", text: $newName)
        Button("Cancelar", role: .cancel) {}
        Button("Criar") {
          let name = newName.trimmingCharacters(in: .whitespaces)
          guard !name.isEmpty else { return }
          let p = presets.add(name: name, options: current.options)
          presets.select(p.id, for: device.serial)
        }
      } message: {
        Text("Cria um preset com as opções atuais.")
      }
    }

    // MARK: Cartão do dispositivo

    private var mockupMode: PhoneMockup.Mode {
      switch device.state {
      case "device": return mirroring ? .mirroring : .idle
      case "unauthorized": return .blocked(symbol: "lock.fill", text: "Não autorizado")
      case "offline": return .blocked(symbol: "wifi.exclamationmark", text: "Offline")
      default: return .blocked(symbol: "exclamationmark.triangle.fill", text: device.stateLabel)
      }
    }

    private var heroCard: some View {
      HStack(alignment: .center, spacing: 28) {
        PhoneMockup(image: store.thumbnail[device.serial], aspect: device.info?.aspect ?? 9.0 / 20.0, mode: mockupMode)
        heroInfo
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    /// Nome grande sem repetir a marca quando ele já começa com ela ("POCO C65" vira "C65").
    private var bigName: String {
      let name = device.name
      if let brand = device.info?.brand, !brand.isEmpty,
         name.lowercased().hasPrefix(brand.lowercased() + " ") {
        let rest = name.dropFirst(brand.count).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { return rest }
      }
      return name
    }

    private var heroInfo: some View {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          if let brand = device.info?.brand, !brand.isEmpty {
            Text(brand.uppercased())
              .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
          }
          Text(bigName)
            .font(.system(size: 30, weight: .bold))
            .lineLimit(2).minimumScaleFactor(0.7)
            .textSelection(.enabled)
        }
        chips
        mainAction
        tiles
        Text("Arraste um .apk ou arquivo para cá para instalar ou enviar.")
          .font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
      FlowLayout(spacing: 8, lineSpacing: 8) {
        Chip(symbol: device.isWifi ? "wifi" : "cable.connector", text: device.connectionDetail)
        if !device.isReady {
          Chip(symbol: "exclamationmark.triangle.fill", text: device.stateLabel, tint: .orange)
        }
        if let b = device.info?.battery {
          Chip(symbol: batterySymbol(b, charging: device.info?.charging ?? false), text: "\(b)%")
        }
        if let v = device.info?.androidVersion, !v.isEmpty {
          Chip(symbol: "apps.iphone", text: "Android \(v)")
        }
        if let s = device.info?.screenLabel {
          Chip(symbol: "arrow.up.left.and.arrow.down.right", text: s)
        }
      }
    }

    private func batterySymbol(_ level: Int, charging: Bool) -> String {
      if charging { return "battery.100.bolt" }
      switch level {
      case ..<13: return "battery.0"
      case ..<38: return "battery.25"
      case ..<63: return "battery.50"
      case ..<88: return "battery.75"
      default: return "battery.100"
      }
    }

    private var mainAction: some View {
      HStack(spacing: 14) {
        if mirroring {
          Button { session.stop() } label: {
            Label("Parar", systemImage: "stop.fill").frame(minWidth: 180)
          }
          .buttonStyle(.borderedProminent).tint(.red).controlSize(.extraLarge)
        } else {
          Button { sessions.start(device: device, options: current.options) } label: {
            Label("Espelhar", systemImage: "play.fill").frame(minWidth: 180)
          }
          .buttonStyle(.borderedProminent).controlSize(.extraLarge)
          .disabled(!device.isReady)
        }
        Text("Preset: \(current.name)")
          .font(.callout).foregroundStyle(.secondary).lineLimit(1)
      }
    }

    private var tiles: some View {
      FlowLayout(spacing: 8, lineSpacing: 8) {
        ActionTile(title: "Print", symbol: "camera", enabled: device.isReady) {
          Task { await store.screenshot(device) }
        }
        ActionTile(title: "Instalar APK", symbol: "shippingbox", enabled: device.isReady) { importing = .apk }
        ActionTile(title: "Enviar arquivo", symbol: "paperplane", enabled: device.isReady) { importing = .file }
        if let rec = session.lastRecording {
          ActionTile(title: "Gravação", symbol: "film", enabled: true) {
            NSWorkspace.shared.activateFileViewerSelecting([rec])
          }
        }
        ActionTile(title: "Wi-Fi", symbol: "wifi", enabled: device.isReady, action: onWifi)
        if device.isWifi {
          ActionTile(title: "Desconectar", symbol: "wifi.slash", enabled: true) {
            Task { await store.disconnect(device) }
          }
        }
      }
    }

    // MARK: Avisos

    @ViewBuilder
    private var statusMessages: some View {
      VStack(alignment: .leading, spacing: 10) {
        if device.state == "unauthorized" {
          warning("Aceite a depuração USB no celular. Desbloqueie a tela e toque em Permitir na janela que aparece.")
        } else if device.state == "offline" {
          warning("O dispositivo está offline. Tente desplugar e plugar o cabo, ou reconectar o Wi-Fi.")
        }
        if let error = session.errorSummary {
          VStack(alignment: .leading, spacing: 4) {
            Label("O scrcpy encerrou com erro", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
          }
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }

    private func warning(_ text: String) -> some View {
      Label(text, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Configuração

    private var configuration: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("Configuração").font(.title3.weight(.semibold))
        presetChips
        OptionsCards(options: optionsBinding, deviceName: device.name)
        configFooter
      }
    }

    private var presetChips: some View {
      FlowLayout(spacing: 8, lineSpacing: 8) {
        ForEach(presets.presets) { p in
          let selected = p.id == current.id
          Button { presets.select(p.id, for: device.serial) } label: {
            Text(p.name)
              .font(.callout.weight(selected ? .semibold : .regular))
              .padding(.horizontal, 14).padding(.vertical, 6)
              .foregroundStyle(selected ? Color.white : Color.primary)
              .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
        }
        Button { newName = ""; creating = true } label: {
          Image(systemName: "plus")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Novo preset com estas opções…")

        Menu {
          Button("Novo preset com estas opções…") { newName = ""; creating = true }
          Button("Renomear…") { newName = current.name; renaming = true }
          Button("Duplicar") {
            let p = presets.add(name: current.name + " cópia", options: current.options)
            presets.select(p.id, for: device.serial)
          }
          Divider()
          Button("Apagar", role: .destructive) { presets.delete(current.id) }
          Button("Recolocar presets prontos") { presets.restoreBuiltIn() }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
      }
    }

    @ViewBuilder
    private var configFooter: some View {
      if mirroring, let started = session.startedOptions, started != current.options {
        HStack(spacing: 10) {
          Label("As mudanças ainda não estão valendo no espelhamento atual.", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption).foregroundStyle(.secondary)
          Button("Reiniciar espelhamento para aplicar") { restart() }
            .controlSize(.small)
        }
      } else {
        Text("As mudanças valem na próxima vez que você espelhar.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }

    private func restart() {
      let options = current.options
      session.stop()
      Task {
        for _ in 0..<50 where session.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
        sessions.start(device: device, options: options)
      }
    }

    // MARK: Log

    private var logCard: some View {
      DisclosureGroup(isExpanded: $logOpen) {
        LogView(session: session).padding(.top, 8)
      } label: {
        Text("Log do scrcpy").font(.headline)
      }
      .padding(16)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
  }
}

/// Cápsula pequena com ícone e texto.
private struct Chip: View {
  let symbol: String
  let text: String
  var tint: Color?

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.callout)
      .foregroundStyle(tint ?? Color.primary)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(tint.map { $0.opacity(0.16) } ?? Color.primary.opacity(0.08), in: Capsule())
  }
}

/// Botão quadrado com ícone em cima e legenda embaixo.
private struct ActionTile: View {
  let title: String
  let symbol: String
  let enabled: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 17, weight: .regular))
        Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
      }
      .frame(width: 72, height: 60)
      .background(Color.primary.opacity(hovering && enabled ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
    .onHover { hovering = $0 }
  }
}
