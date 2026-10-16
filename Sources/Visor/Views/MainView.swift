import SwiftUI

struct MainView: View {
  @EnvironmentObject var store: DeviceStore
  @EnvironmentObject var sessions: SessionStore
  @State private var selection: String?
  @State private var showWifi = false

  init(initialSelection: String? = nil) {
    _selection = State(initialValue: initialSelection)
  }

  private var selected: Device? {
    store.devices.first { $0.serial == selection } ?? store.devices.first
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
    } detail: {
      if let device = selected {
        DeviceDetailView(device: device, onWifi: { showWifi = true })
          .id(device.serial)
      } else {
        HelpView(problem: store.adbProblem, loaded: store.loaded)
      }
    }
    .toolbar {
      ToolbarItem {
        Button { showWifi = true } label: { Label("Wi-Fi", systemImage: "wifi") }
          .help("Conectar um celular por Wi-Fi")
      }
    }
    .sheet(isPresented: $showWifi) { WifiSheet(usbDevice: selected) }
    .overlay(alignment: .bottom) { banner }
    .animation(.default, value: store.notice)
    .animation(.default, value: store.busyText)
  }

  private var sidebar: some View {
    List(selection: Binding(get: { selected?.serial }, set: { selection = $0 })) {
      Section("Dispositivos") {
        ForEach(store.devices) { device in
          DeviceRow(device: device).tag(device.serial)
        }
      }
      if store.devices.isEmpty {
        Text(store.loaded ? "Nenhum dispositivo" : "Procurando…")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var banner: some View {
    if let busy = store.busyText {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(busy)
      }
      .padding(.horizontal, 14).padding(.vertical, 9)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().stroke(.separator))
      .padding(.bottom, 16)
    } else if let notice = store.notice {
      HStack(spacing: 8) {
        Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(notice.isError ? Color.orange : Color.green)
        Text(notice.text).textSelection(.enabled)
        Button { store.notice = nil } label: { Image(systemName: "xmark") }
          .buttonStyle(.borderless)
      }
      .padding(.horizontal, 14).padding(.vertical, 9)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().stroke(.separator))
      .padding(.bottom, 16)
      .frame(maxWidth: 640)
    }
  }
}

/// Tela de ajuda quando não há nenhum dispositivo.
struct HelpView: View {
  let problem: String?
  let loaded: Bool

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "iphone.gen3.radiowaves.left.and.right")
        .font(.system(size: 44))
        .foregroundStyle(.secondary)
      Text(loaded ? "Nenhum celular encontrado" : "Procurando celulares…")
        .font(.title2.weight(.semibold))
      if let problem {
        Text(problem).foregroundStyle(.red).multilineTextAlignment(.center)
      }
      VStack(alignment: .leading, spacing: 8) {
        step(1, "No celular, abra Configurações, Sobre o telefone e toque 7 vezes em Número da versão para liberar as Opções do desenvolvedor.")
        step(2, "Em Opções do desenvolvedor, ative a Depuração USB.")
        step(3, "Ligue o cabo USB no Mac e, no celular, escolha Transferência de arquivos se ele perguntar.")
        step(4, "Aceite a janela \"Permitir depuração USB?\" no celular.")
        step(5, "Para usar sem cabo, clique em Wi-Fi na barra de ferramentas.")
      }
      .frame(maxWidth: 460)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("\(n)").font(.callout.weight(.semibold)).foregroundStyle(.secondary).frame(width: 16)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
  }
}
