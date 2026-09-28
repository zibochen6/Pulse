import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  let onQuit: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "waveform.path")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          Text("Pulse")
            .font(.system(size: 16, weight: .semibold))
          Spacer()
        }
        .padding(.bottom, 4)

        PulseSection(title: "Usage", symbol: "chart.bar") {
          UsageView(usage: usage)
        }

        PulseSection(title: "Tasks", symbol: "checklist") {
          Text("Not connected yet")
            .font(.subheadline)
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

            if config.launchAtLoginRequested {
              Text(loginItemMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = config.loginItemError {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
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
          .font(.subheadline)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // NSPopover's default material exposes windows behind a transparent hosting
    // view. Cover the entire content area with an adaptive, opaque system color.
    .background(Color(nsColor: .windowBackgroundColor))
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
