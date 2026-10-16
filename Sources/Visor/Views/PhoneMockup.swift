import AppKit
import SwiftUI

/// Celular desenhado em SwiftUI, com a prévia da tela dentro.
struct PhoneMockup: View {
  enum Mode: Equatable {
    case idle
    case mirroring
    case blocked(symbol: String, text: String)
  }

  let image: NSImage?
  /// Largura / altura da tela do celular.
  let aspect: CGFloat
  var mode = Mode.idle
  var height: CGFloat = 300

  private let bezel: CGFloat = 7
  @State private var pulse = false

  private var screenSize: CGSize {
    let h = height - bezel * 2
    return CGSize(width: (h * aspect).rounded(), height: h)
  }

  var body: some View {
    let screen = screenSize
    ZStack {
      RoundedRectangle(cornerRadius: 34, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
      RoundedRectangle(cornerRadius: 34, style: .continuous)
        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

      screenContent(screen)
        .frame(width: screen.width, height: screen.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
          Circle().fill(.black).frame(width: 9, height: 9).padding(.top, 10)
        }
    }
    .frame(width: screen.width + bezel * 2, height: height)
    .overlay(alignment: .trailing) { sideButtons }
    .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    .accessibilityLabel("Prévia da tela do celular")
  }

  // Volume e power: dois filetes na borda direita.
  private var sideButtons: some View {
    VStack(spacing: 0) {
      Capsule().fill(Color(white: 0.2)).frame(width: 3, height: 44).padding(.bottom, 28)
      Capsule().fill(Color(white: 0.2)).frame(width: 3, height: 28)
    }
    .offset(x: 2.5, y: -44)
  }

  @ViewBuilder
  private func screenContent(_ size: CGSize) -> some View {
    ZStack {
      if let image {
        Image(nsImage: image).resizable().scaledToFill()
          .frame(width: size.width, height: size.height).clipped()
      } else {
        LinearGradient(colors: [Color(red: 0x78 / 255, green: 0xB3 / 255, blue: 1),
                                Color(red: 0x3A / 255, green: 0x5F / 255, blue: 0xDB / 255)],
                       startPoint: .top, endPoint: .bottom)
        Image(systemName: "iphone.gen3")
          .font(.system(size: size.width * 0.42, weight: .light))
          .foregroundStyle(.white.opacity(0.55))
      }

      switch mode {
      case .idle:
        EmptyView()
      case .mirroring:
        Color.black.opacity(0.55)
        VStack(spacing: 8) {
          HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 8, height: 8)
              .opacity(pulse ? 0.35 : 1)
            Text("Espelhando").font(.callout.weight(.semibold))
          }
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(.black.opacity(0.35), in: Capsule())
          .overlay(Capsule().stroke(.white.opacity(0.2)))
          Text("A tela está na janela do scrcpy")
            .font(.caption2).multilineTextAlignment(.center).opacity(0.85)
            .padding(.horizontal, 10)
        }
        .foregroundStyle(.white)
        .onAppear {
          withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
      case .blocked(let symbol, let text):
        Color(white: 0.28)
        VStack(spacing: 10) {
          Image(systemName: symbol).font(.system(size: 30, weight: .regular))
          Text(text).font(.caption.weight(.medium)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 10)
      }
    }
  }
}
