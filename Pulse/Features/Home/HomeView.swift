import AppKit
import SwiftUI

enum SettingsDestination: Hashable {
  case general
  case providers
  case tasks
  case about
}

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  let onQuit: () -> Void

  @State private var settingsDestination: SettingsDestination?

  init(
    config: AppConfig,
    usage: UsageController,
    onQuit: @escaping () -> Void,
    initialDestination: SettingsDestination? = nil
  ) {
    self.config = config
    self.usage = usage
    self.onQuit = onQuit
    _settingsDestination = State(initialValue: initialDestination)
  }

  var body: some View {
    Group {
      if let settingsDestination {
        SettingsView(
          config: config,
          destination: settingsDestination,
          onBack: { self.settingsDestination = nil },
          onQuit: onQuit
        )
      } else {
        homeContent
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // Cover the entire hosting surface with an adaptive opaque color.
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var homeContent: some View {
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
          Button {
            settingsDestination = .general
          } label: {
            Image(systemName: "gearshape")
              .font(.system(size: 15, weight: .medium))
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.borderless)
          .help("Settings")
          .accessibilityLabel("Open Settings")
          .accessibilityIdentifier("openSettingsButton")
        }
        .padding(.bottom, 2)

        PulseSection(title: "Usage", symbol: "chart.bar") {
          UsageView(usage: usage, onAddProvider: { settingsDestination = .providers })
        }

        PulseSection(title: "Tasks", symbol: "checklist") {
          TasksView(onConnect: { settingsDestination = .tasks })
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
