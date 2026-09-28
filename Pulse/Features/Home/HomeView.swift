import SwiftUI

struct HomeView: View {
  @ObservedObject var config: AppConfig
  let onQuit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "waveform.path")
          .foregroundStyle(.tint)
        Text("Pulse")
          .font(.title2.bold())
        Spacer()
      }

      PulseSection(title: "Usage", symbol: "chart.bar") {
        Text("AI usage is not connected yet.")
          .foregroundStyle(.secondary)
      }

      PulseSection(title: "Tasks", symbol: "checklist") {
        Text("Tasks are not connected yet.")
          .foregroundStyle(.secondary)
      }

      PulseSection(title: "Settings", symbol: "gearshape") {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            "Launch at login",
            isOn: Binding(
              get: { config.launchAtLoginRequested },
              set: { config.setLaunchAtLogin($0) }
            )
          )
          Text(loginItemMessage)
            .font(.caption)
            .foregroundStyle(.secondary)

          if let error = config.loginItemError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }

          Toggle(
            "Show Pulse name in menu bar",
            isOn: Binding(
              get: { config.showMenuBarLabel },
              set: { config.setShowMenuBarLabel($0) }
            )
          )

          Divider()
          Button("Quit Pulse", action: onQuit)
            .accessibilityIdentifier("quitPulseButton")
        }
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .frame(width: 360)
  }

  private var loginItemMessage: String {
    switch config.loginItemStatus {
    case .enabled:
      "Enabled in macOS Login Items."
    case .requiresApproval:
      "Approve Pulse in System Settings > General > Login Items."
    case .notRegistered:
      "Not enabled in macOS Login Items."
    case .notFound:
      "macOS cannot locate this app for login. Try an installed build."
    }
  }
}
