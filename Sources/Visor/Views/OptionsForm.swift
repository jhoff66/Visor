import AppKit
import SwiftUI

/// Cartão de uma seção de opções: ícone colorido no estilo Ajustes do sistema e as linhas dentro.
struct OptionCard<Content: View>: View {
  let icon: String
  let color: Color
  let title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        Text(title).font(.headline)
      }
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
  }
}

private struct ToggleRow: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    HStack {
      Text(title)
      Spacer(minLength: 8)
      Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
  }
}

private struct PickRow<Control: View>: View {
  let title: String
  @ViewBuilder var control: Control

  var body: some View {
    HStack {
      Text(title)
      Spacer(minLength: 8)
      control
    }
  }
}

private struct Note: View {
  let symbol: String
  let text: String
  var tint: Color = .secondary

  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol)
    }
    .font(.caption)
    .foregroundStyle(tint)
  }
}

/// Todos os cartões de opções, na grade adaptativa.
struct OptionsCards: View {
  @Binding var options: Options
  let deviceName: String

  private let sizes = [0, 1920, 1600, 1280, 1024, 800]

  var body: some View {
    CardGrid(minimum: 300, spacing: 16) {
      quality
      sound
      screen
      control
      window
      recording
      camera
      advanced
    }
  }

  private var quality: some View {
    OptionCard(icon: "sparkles.tv", color: .blue, title: "Qualidade") {
      PickRow(title: "Resolução") {
        Picker("Resolução", selection: $options.maxSize) {
          ForEach(sizes, id: \.self) { Text($0 == 0 ? "Original" : "\($0) px").tag($0) }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
      }
      Divider()
      PickRow(title: "Bitrate (Mbps)") {
        Picker("Bitrate", selection: $options.bitRateMbps) {
          ForEach([4, 8, 16, 32], id: \.self) { Text("\($0)").tag($0) }
        }
        .labelsHidden().pickerStyle(.segmented).fixedSize()
      }
      Divider()
      PickRow(title: "FPS máximo") {
        Picker("FPS máximo", selection: $options.maxFps) {
          Text("30").tag(30)
          Text("60").tag(60)
          Text("120").tag(120)
          Text("Livre").tag(0)
        }
        .labelsHidden().pickerStyle(.segmented).fixedSize()
      }
      Divider()
      PickRow(title: "Codec") {
        Picker("Codec", selection: $options.codec) {
          ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden().pickerStyle(.segmented).fixedSize()
      }
      Text("Wi-Fi: prefira 1024 e 4–8 Mbps.").font(.caption).foregroundStyle(.secondary)
    }
  }

  private var sound: some View {
    OptionCard(icon: "speaker.wave.2.fill", color: .pink, title: "Som") {
      ToggleRow(title: "Áudio do celular", isOn: $options.audio)
      Text("O som do celular toca no Mac (Android 11 ou mais novo).").font(.caption).foregroundStyle(.secondary)
    }
  }

  private var screen: some View {
    OptionCard(icon: "iphone.gen3", color: .green, title: "Tela do celular") {
      ToggleRow(title: "Desligar a tela do celular", isOn: $options.turnScreenOff)
      Divider()
      ToggleRow(title: "Manter acordado", isOn: $options.stayAwake)
      Divider()
      ToggleRow(title: "Mostrar toques", isOn: $options.showTouches)
    }
    .disabled(options.camera)
  }

  private var control: some View {
    OptionCard(icon: "cursorarrow.click.2", color: .orange, title: "Controle") {
      ToggleRow(title: "Só visualizar, sem controle", isOn: $options.viewOnly)
      Group {
        Divider()
        ToggleRow(title: "Teclado físico (uhid)", isOn: $options.physicalKeyboard)
        Divider()
        ToggleRow(title: "Mouse físico (uhid)", isOn: $options.physicalMouse)
      }
      .disabled(options.camera || options.viewOnly)
      if options.physicalMouse && !options.camera && !options.viewOnly {
        Note(symbol: "info.circle", text: "O mouse fica preso na janela. Aperte ⌘ para soltar.", tint: .orange)
      }
      Note(symbol: "questionmark.circle",
           text: "Xiaomi, Redmi e POCO: se o clique não funcionar, ligue teclado e mouse físico.")
    }
    .disabled(options.camera)
  }

  private var window: some View {
    OptionCard(icon: "macwindow", color: .purple, title: "Janela") {
      ToggleRow(title: "Sempre no topo", isOn: $options.alwaysOnTop)
      Divider()
      ToggleRow(title: "Sem borda", isOn: $options.borderless)
      Divider()
      ToggleRow(title: "Tela cheia", isOn: $options.fullscreen)
    }
  }

  private var recording: some View {
    OptionCard(icon: "record.circle", color: .red, title: "Gravação") {
      ToggleRow(title: "Gravar em ~/Movies/Visor", isOn: $options.record)
      Button {
        let dir = SessionStore.recordingsFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
      } label: {
        Label("Abrir pasta", systemImage: "folder")
      }
      .controlSize(.small)
    }
  }

  private var camera: some View {
    OptionCard(icon: "camera.fill", color: Color(red: 0.42, green: 0.52, blue: 0.62), title: "Câmera") {
      ToggleRow(title: "Usar a câmera do celular (Android 12+)", isOn: $options.camera)
      if options.camera {
        Divider()
        PickRow(title: "Lente") {
          Picker("Câmera", selection: $options.cameraFacing) {
            ForEach(CameraFacing.allCases) { Text($0.label).tag($0) }
          }
          .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
      }
    }
  }

  private var commandPreview: String {
    let record = options.record ? "~/Movies/Visor/gravação.mp4" : nil
    let args = options.arguments(windowTitle: deviceName, recordPath: record)
      .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
    return (["scrcpy"] + args).joined(separator: " ")
  }

  private var advanced: some View {
    OptionCard(icon: "terminal", color: Color(white: 0.45), title: "Avançado") {
      Text("Argumentos extras").font(.callout)
      TextField("Argumentos extras", text: $options.extraArguments, prompt: Text("ex.: --crop=1080:1500:0:0"))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
      Text("Comando que será executado").font(.caption).foregroundStyle(.secondary)
      Text(commandPreview)
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }
}
