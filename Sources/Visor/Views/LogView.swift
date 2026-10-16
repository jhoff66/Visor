import AppKit
import SwiftUI

struct LogView: View {
  @ObservedObject var session: Session

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Spacer()
        Button("Copiar tudo") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(session.log, forType: .string)
        }
        .disabled(session.log.isEmpty)
        Button("Limpar") { session.clearLog() }
          .disabled(session.log.isEmpty)
      }
      ScrollViewReader { proxy in
        ScrollView {
          Text(session.log.isEmpty ? "Sem saída ainda. Clique em Espelhar para começar." : session.log)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(session.log.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
          Color.clear.frame(height: 1).id("fim")
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .onChange(of: session.log) { _, _ in proxy.scrollTo("fim", anchor: .bottom) }
      }
      .frame(height: 220)
    }
  }
}
