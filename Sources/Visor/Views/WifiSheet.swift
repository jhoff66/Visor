import SwiftUI

struct WifiSheet: View {
  /// Dispositivo selecionado (usado para "Ativar Wi-Fi neste celular", que exige USB).
  let usbDevice: Device?
  @EnvironmentObject var store: DeviceStore
  @Environment(\.dismiss) private var dismiss

  @State private var connectAddress = ""
  @State private var pairAddress = ""
  @State private var pairCode = ""
  @State private var pairedConnectAddress = ""
  @State private var message: String?
  @State private var messageIsError = false
  @State private var busy = false
  @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: "wifi.recent") ?? []

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Conectar por Wi-Fi").font(.title3.weight(.semibold))
        Spacer()
        if busy { ProgressView().controlSize(.small) }
        Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      .padding([.horizontal, .top], 20)
      .padding(.bottom, 8)

      Form {
        Section("Pelo cabo USB") {
          Button("Ativar Wi-Fi neste celular") { enableOnUSB() }
            .disabled(busy || usbDevice == nil || usbDevice?.isWifi == true || usbDevice?.isReady == false)
          Text(usbHint).font(.caption).foregroundStyle(.secondary)
        }

        Section("Conectar por IP") {
          HStack {
            TextField("IP:porta", text: $connectAddress, prompt: Text("192.168.0.20:5555"))
              .textFieldStyle(.roundedBorder)
              .onSubmit { connect(connectAddress) }
            Button("Conectar") { connect(connectAddress) }
              .disabled(busy || connectAddress.trimmingCharacters(in: .whitespaces).isEmpty)
          }
          if !recents.isEmpty {
            ForEach(recents, id: \.self) { address in
              HStack {
                Text(address).font(.system(.body, design: .monospaced))
                Spacer()
                Button("Reconectar") { connect(address) }.disabled(busy)
                Button { forget(address) } label: { Image(systemName: "xmark") }
                  .buttonStyle(.borderless)
                  .help("Esquecer este endereço")
              }
            }
          }
        }

        Section("Parear (Android 11 ou mais novo)") {
          Text("No celular: Opções do desenvolvedor, Depuração sem fio, Parear dispositivo com código.")
            .font(.caption).foregroundStyle(.secondary)
          TextField("IP:porta de pareamento", text: $pairAddress, prompt: Text("192.168.0.20:37123"))
            .textFieldStyle(.roundedBorder)
          TextField("Código de 6 dígitos", text: $pairCode, prompt: Text("123456"))
            .textFieldStyle(.roundedBorder)
          Button("Parear") { pair() }
            .disabled(busy || pairAddress.trimmingCharacters(in: .whitespaces).isEmpty || pairCode.count < 6)
          TextField("IP:porta de conexão (tela principal da Depuração sem fio)", text: $pairedConnectAddress,
                    prompt: Text("192.168.0.20:40455"))
            .textFieldStyle(.roundedBorder)
          Button("Conectar após parear") { connect(pairedConnectAddress) }
            .disabled(busy || pairedConnectAddress.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .formStyle(.grouped)

      if let message {
        Text(message)
          .font(.callout)
          .foregroundStyle(messageIsError ? Color.red : Color.green)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 24)
          .padding(.bottom, 12)
          .textSelection(.enabled)
      }
    }
    .frame(width: 520, height: 620)
  }

  private var usbHint: String {
    if usbDevice == nil { return "Selecione na lista um celular ligado por USB." }
    if usbDevice?.isWifi == true { return "O dispositivo selecionado já está por Wi-Fi." }
    return "Com o celular no USB, o app descobre o IP, ativa a porta 5555 e conecta."
  }

  private func report(_ text: String, error: Bool) {
    message = text
    messageIsError = error
  }

  private func remember(_ address: String) {
    recents.removeAll { $0 == address }
    recents.insert(address, at: 0)
    recents = Array(recents.prefix(6))
    UserDefaults.standard.set(recents, forKey: "wifi.recent")
  }

  private func forget(_ address: String) {
    recents.removeAll { $0 == address }
    UserDefaults.standard.set(recents, forKey: "wifi.recent")
  }

  private func normalized(_ address: String) -> String {
    let a = address.trimmingCharacters(in: .whitespaces)
    return a.contains(":") ? a : a + ":5555"
  }

  private func enableOnUSB() {
    guard let usbDevice else { return }
    busy = true
    report("Ativando o modo TCP/IP…", error: false)
    Task {
      do {
        let address = try await ADB.enableTCPIP(serial: usbDevice.serial)
        remember(address)
        await store.refresh()
        report("Conectado em \(address). Já pode desplugar o cabo.", error: false)
      } catch {
        report(error.localizedDescription, error: true)
      }
      busy = false
    }
  }

  private func connect(_ raw: String) {
    let address = normalized(raw)
    busy = true
    report("Conectando em \(address)…", error: false)
    Task {
      do {
        let text = try await ADB.connect(address)
        remember(address)
        await store.refresh()
        report(text, error: false)
      } catch {
        report(error.localizedDescription, error: true)
      }
      busy = false
    }
  }

  private func pair() {
    busy = true
    report("Pareando…", error: false)
    Task {
      do {
        let text = try await ADB.pair(pairAddress.trimmingCharacters(in: .whitespaces), code: pairCode)
        report(text + " Agora informe o IP:porta de conexão e conecte.", error: false)
      } catch {
        report(error.localizedDescription, error: true)
      }
      busy = false
    }
  }
}
