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
    VStack(spacing: 0) {
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
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Label("Usage", systemImage: "chart.bar")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ScrollView {
          UsageView(usage: usage, onAddProvider: { settingsDestination = .providers })
            .padding(.trailing, 3)
        }
        .frame(height: 128)
        .accessibilityIdentifier("usageRegion")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      VStack(alignment: .leading, spacing: 0) {
        Label("Tasks", systemImage: "checklist")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)
          .padding(.top, 14)

        TasksView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
      .accessibilityIdentifier("tasksRegion")

      Divider()

      Button {
        settingsDestination = .tasks
      } label: {
        HStack(spacing: 9) {
          Image(systemName: "link.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
          Text("Connect Obsidian")
            .font(.subheadline.weight(.medium))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("connectObsidianButton")
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }
}
