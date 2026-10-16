import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DeviceDetailView: View {
  let device: Device
  @EnvironmentObject var store: DeviceStore
  @EnvironmentObject var sessions: SessionStore
  @EnvironmentObject var presets: PresetStore

  private enum Tab: String, CaseIterable, Identifiable {
    case options = "Opções", log = "Log"
    var id: String { rawValue }
  }

  @State private var tab = Tab.options
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
    SessionContent(device: device, session: sessions.session(for: device.serial),
                   tab: $tab, importing: $importing, renaming: $renaming, newName: $newName,
                   creating: $creating, dropTargeted: $dropTargeted)
  }

  // Conteúdo separado para observar a sessão do dispositivo.
  private struct SessionContent: View {
    let device: Device
    @ObservedObject var session: Session
    @Binding var tab: Tab
    @Binding var importing: ImportKind?
    @Binding var renaming: Bool
    @Binding var newName: String
    @Binding var creating: Bool
    @Binding var dropTargeted: Bool

    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var sessions: SessionStore
    @EnvironmentObject var presets: PresetStore

    private var current: Preset { presets.preset(for: device.serial) }

    private var optionsBinding: Binding<Options> {
      Binding(get: { presets.preset(for: device.serial).options },
              set: { presets.update(options: $0, of: presets.preset(for: device.serial).id) })
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        header
        statusMessages
        actions
        Divider()
        presetBar
        Picker("", selection: $tab) {
          ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 220)

        switch tab {
        case .options:
          OptionsForm(options: optionsBinding)
          Text("As mudanças valem na próxima vez que você espelhar.")
            .font(.caption).foregroundStyle(.secondary)
        case .log:
          LogView(session: session)
        }
      }
      .padding(20)
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

    private var header: some View {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(device.name).font(.title.weight(.semibold))
          Text("\(device.serial)  ·  \(device.connectionLabel)  ·  \(device.stateLabel)")
            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Spacer()
      }
    }

    @ViewBuilder
    private var statusMessages: some View {
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

    private func warning(_ text: String) -> some View {
      Label(text, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
      HStack(spacing: 10) {
        if session.isRunning {
          Button { session.stop() } label: { Label("Parar", systemImage: "stop.fill").frame(minWidth: 90) }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        } else {
          Button { sessions.start(device: device, options: current.options) } label: {
            Label("Espelhar", systemImage: "play.fill").frame(minWidth: 90)
          }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(!device.isReady)
        }

        Button { Task { await store.screenshot(device) } } label: { Label("Print", systemImage: "camera") }
          .disabled(!device.isReady)
        Button { importing = .apk } label: { Label("Instalar APK…", systemImage: "square.and.arrow.down") }
          .disabled(!device.isReady)
        Button { importing = .file } label: { Label("Enviar arquivo…", systemImage: "paperplane") }
          .disabled(!device.isReady)

        if let rec = session.lastRecording {
          Button { NSWorkspace.shared.activateFileViewerSelecting([rec]) } label: {
            Label("Mostrar gravação", systemImage: "film")
          }
        }
        if device.isWifi {
          Button { Task { await store.disconnect(device) } } label: { Label("Desconectar", systemImage: "wifi.slash") }
        }
        Spacer()
      }
    }

    private var presetBar: some View {
      HStack {
        Text("Preset").foregroundStyle(.secondary)
        Picker("Preset", selection: Binding(get: { current.id }, set: { presets.select($0, for: device.serial) })) {
          ForEach(presets.presets) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .frame(maxWidth: 220)

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
        .fixedSize()
        Spacer()
      }
    }
  }
}
