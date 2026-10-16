import SwiftUI

struct DeviceRow: View {
  let device: Device
  @EnvironmentObject var sessions: SessionStore
  @EnvironmentObject var store: DeviceStore
  @State private var dropTargeted = false

  var body: some View {
    HStack(spacing: 10) {
      icon
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(device.name).font(.body.weight(.medium)).lineLimit(1)
          if sessions.isRunning(device.serial) {
            Circle().fill(.green).frame(width: 7, height: 7)
              .help("Espelhando")
          }
        }
        subtitle
      }
      Spacer(minLength: 4)
    }
    .padding(.vertical, 3)
    .background(dropTargeted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
    .dropDestination(for: URL.self) { urls, _ in
      Task { await store.handleDrop(urls.filter { $0.isFileURL }, on: device) }
      return true
    } isTargeted: { dropTargeted = $0 }
  }

  private var stateColor: Color {
    switch device.state {
    case "device": return .blue
    case "unauthorized": return .orange
    default: return .gray
    }
  }

  // Quadradinho com a cor do estado e o selo de Wi-Fi ou cabo no canto.
  private var icon: some View {
    Image(systemName: "iphone.gen3")
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
      .background(stateColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: device.isWifi ? "wifi" : "cable.connector")
          .font(.system(size: 7, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 13, height: 13)
          .background(Circle().fill(Color(white: 0.2)))
          .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
          .offset(x: 4, y: 4)
      }
      .padding(.trailing, 2)
  }

  @ViewBuilder
  private var subtitle: some View {
    if !device.isReady {
      Text("\(device.connectionLabel) · \(device.stateLabel)")
        .font(.caption).foregroundStyle(.orange).lineLimit(1)
    } else if let v = device.info?.androidVersion, !v.isEmpty {
      Text("\(device.connectionLabel) · Android \(v)")
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    } else {
      Text(device.serial).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
    }
  }
}
