import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var config: AppConfig
  let destination: SettingsDestination
  let onBack: () -> Void
  let onQuit: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button(action: onBack) {
          Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("Back to Home")
        .accessibilityLabel("Back to Home")
        .accessibilityIdentifier("backToHomeButton")
        Text("Settings")
          .font(.system(size: 16, weight: .semibold))
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 10)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            PulseSection(title: "General", symbol: "slider.horizontal.3") {
              generalContent
            }
            .id(SettingsDestination.general)

            PulseSection(title: "Providers", symbol: "square.stack") {
              Text("More AI providers are coming soon. Codex is the only connected source today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .id(SettingsDestination.providers)

            PulseSection(title: "Tasks", symbol: "checklist") {
              Text("Obsidian connection is coming soon. No notes are read or changed yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .id(SettingsDestination.tasks)

            PulseSection(title: "About", symbol: "info.circle") {
              aboutContent
            }
            .id(SettingsDestination.about)

            Button("Quit Pulse", action: onQuit)
              .accessibilityIdentifier("quitPulseButton")
              .padding(.horizontal, 4)
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
          proxy.scrollTo(destination, anchor: .top)
        }
      }
    }
  }

  private var generalContent: some View {
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
    }
    .font(.subheadline)
  }

  private var aboutContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(versionText)
        .font(.subheadline)
      Text("Codex menu icon artwork: codex-usage-status (MIT).")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let noticesURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
        Button("Open third-party notices") {
          NSWorkspace.shared.open(noticesURL)
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.medium))
      } else {
        Text("Third-party notices are unavailable in this build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var versionText: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    guard let version, !version.isEmpty else {
      return "Development build"
    }
    return "Version \(version)"
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
