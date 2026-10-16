import SwiftUI

struct OptionsForm: View {
  @Binding var options: Options
  @State private var showAdvanced = false

  private let sizes = [0, 1920, 1600, 1280, 1024, 800]
  private let bitRates = [4, 8, 16, 32]
  private let fpsList = [0, 30, 60, 120]

  var body: some View {
    Form {
      Section("Vídeo") {
        Picker("Resolução máxima", selection: $options.maxSize) {
          ForEach(sizes, id: \.self) { Text($0 == 0 ? "Original" : "\($0) px").tag($0) }
        }
        Picker("Bitrate", selection: $options.bitRateMbps) {
          ForEach(bitRates, id: \.self) { Text("\($0) Mbps").tag($0) }
        }
        Picker("FPS máximo", selection: $options.maxFps) {
          ForEach(fpsList, id: \.self) { Text($0 == 0 ? "Sem limite" : "\($0) fps").tag($0) }
        }
        Picker("Codec", selection: $options.codec) {
          ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Áudio do celular", isOn: $options.audio)
      }

      Section("Tela do celular") {
        Toggle("Desligar a tela do celular", isOn: $options.turnScreenOff)
        Toggle("Manter acordado", isOn: $options.stayAwake)
        Toggle("Mostrar toques", isOn: $options.showTouches)
        Toggle("Só visualizar, sem controle", isOn: $options.viewOnly)
      }
      .disabled(options.camera)

      Section("Janela") {
        Toggle("Sempre no topo", isOn: $options.alwaysOnTop)
        Toggle("Sem borda", isOn: $options.borderless)
        Toggle("Tela cheia", isOn: $options.fullscreen)
      }

      Section("Gravação") {
        Toggle("Gravar em ~/Movies/Visor", isOn: $options.record)
      }

      Section {
        DisclosureGroup("Avançado", isExpanded: $showAdvanced) {
          Toggle("Teclado físico real (uhid)", isOn: $options.physicalKeyboard)
            .disabled(options.camera || options.viewOnly)
          Toggle("Mouse físico real (uhid)", isOn: $options.physicalMouse)
            .disabled(options.camera || options.viewOnly)
          Toggle("Usar a câmera do celular como fonte (Android 12+)", isOn: $options.camera)
          if options.camera {
            Picker("Câmera", selection: $options.cameraFacing) {
              ForEach(CameraFacing.allCases) { Text($0.label).tag($0) }
            }
          }
          TextField("Argumentos extras", text: $options.extraArguments, prompt: Text("ex.: --crop=1080:1500:0:0"))
            .textFieldStyle(.roundedBorder)
        }
      }
    }
    .formStyle(.grouped)
  }
}
