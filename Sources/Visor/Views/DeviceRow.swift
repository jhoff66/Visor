import SwiftUI

struct DeviceRow: View {
  let device: Device
  @EnvironmentObject var sessions: SessionStore
  @EnvironmentObject var store: DeviceStore
  @State private var dropTargeted = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: device.isWifi ? "wifi" : "cable.connector")
        .frame(width: 22)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(device.name).font(.body.weight(.medium)).lineLimit(1)
          if sessions.isRunning(device.serial) {
            Circle().fill(.green).frame(width: 7, height: 7)
              .help("Espelhando")
          }
        }
        Text(device.serial).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 4)
      if !device.isReady {
        Text(device.stateLabel)
          .font(.caption2.weight(.medium))
          .padding(.horizontal, 6).padding(.vertical, 2)
          .background(Color.orange.opacity(0.18), in: Capsule())
          .foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 3)
    .background(dropTargeted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
    .dropDestination(for: URL.self) { urls, _ in
      Task { await store.handleDrop(urls.filter { $0.isFileURL }, on: device) }
      return true
    } isTargeted: { dropTargeted = $0 }
  }
}
