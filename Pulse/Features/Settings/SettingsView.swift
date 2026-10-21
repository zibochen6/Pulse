import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var config: AppConfig
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var updates: UpdateController
  let destination: SettingsDestination
  let onBack: () -> Void
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }
  /// Aggregates every Settings surface that can hold keyboard focus — the tag
  /// editor and both API key fields — so one control blurring cannot release
  /// the popover's dismissal suspension while another still has the caret.
  @StateObject private var editing = PulseEditingRegistry()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button(action: onBack) {
          Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PulseIconButtonStyle())
        .help("Back to Home")
        .accessibilityLabel("Back to Home")
        .accessibilityIdentifier("backToHomeButton")
        Text("Settings")
          .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
        Spacer()
      }
      // Same toolbar metrics as Home and Usage: switching pages must not make
      // the header jump.
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.top, 6)
      .padding(.bottom, 4)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            PulseSection(title: "General", symbol: "slider.horizontal.3") {
              generalContent
            }
            .id(SettingsDestination.general)

            PulseSection(title: "Providers", symbol: "square.stack") {
              providerContent
            }
            .id(SettingsDestination.providers)

            PulseSection(title: "Tasks", symbol: "checklist") {
              tasksContent
            }
            .id(SettingsDestination.tasks)

            PulseSection(title: "Updates", symbol: "arrow.triangle.2.circlepath") {
              updatesContent
            }
            .id(SettingsDestination.updates)

            PulseSection(title: "About", symbol: "info.circle") {
              aboutContent
            }
            .id(SettingsDestination.about)

            Button("Quit Pulse", action: onQuit)
              .buttonStyle(PulseActionButtonStyle())
              .accessibilityIdentifier("quitPulseButton")
              .padding(.horizontal, 4)
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
          proxy.scrollTo(destination, anchor: .top)
          vipConfiguration.refresh()
          deepSeekConfiguration.refresh()
        }
      }
    }
    // One aggregation point: Settings reports a single editing bit no matter
    // which of its fields currently holds focus.
    .onChange(of: editing.isEditing) { onTaskEditingChanged($0) }
    .onDisappear {
      editing.clear()
      onTaskEditingChanged(false)
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
    .toggleStyle(.switch)
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
        .buttonStyle(PulseActionButtonStyle())
        .font(.caption.weight(.medium))
      } else {
        Text("Third-party notices are unavailable in this build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var providerContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      ProviderCredentialForm(
        configuration: vipConfiguration, name: "88VIP", fieldIdentifier: "vipAPIKeyField",
        actionIdentifier: "VIP",
        onCredentialsChanged: onVIPCredentialsChanged,
        onEditingChanged: { editing.set(source: "vipAPIKeyField", editing: $0) }
      ) { VIPProviderIcon(size: 18) }
      Divider()
      ProviderCredentialForm(
        configuration: deepSeekConfiguration, name: "DeepSeek",
        fieldIdentifier: "deepSeekAPIKeyField", actionIdentifier: "DeepSeek",
        onCredentialsChanged: onDeepSeekCredentialsChanged,
        onEditingChanged: { editing.set(source: "deepSeekAPIKeyField", editing: $0) }
      ) { DeepSeekProviderIcon(size: 18) }

      Text("More AI providers are coming soon.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  /// Update settings show the verified status the controller owns; the view only
  /// dispatches intents and never performs a check or install itself.
  private var updatesContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Pulse \(updates.currentVersionText)")
          .font(.system(size: 13, weight: .medium))
        Spacer()
        if updates.isBusy { ProgressView().controlSize(.mini) }
      }
      Toggle(
        "Check for updates automatically",
        isOn: Binding(
          get: { updates.automaticChecksEnabled },
          set: { updates.automaticChecksEnabled = $0 })
      )
      .toggleStyle(.switch)
      .disabled(!updates.isUpdateSupported)
      .accessibilityIdentifier("automaticUpdatesToggle")

      Text(updates.statusText)
        .font(.caption)
        .foregroundStyle(statusColor)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("updateStatusText")

      HStack(spacing: 8) {
        Button("Check Now") {
          Task { await updates.checkForUpdates() }
        }
        .disabled(updates.isBusy || !updates.isUpdateSupported)
        .accessibilityIdentifier("checkForUpdatesButton")

        if updates.canRestartToUpdate {
          Button("Restart to Update") { updates.restartToUpdate() }
            .accessibilityIdentifier("restartToUpdateButton")
        }
        if updates.offeredRelease != nil, !updates.canRestartToUpdate {
          Button("Skip This Version") { updates.skipOfferedRelease() }
            .disabled(updates.isBusy)
            .accessibilityIdentifier("skipUpdateVersionButton")
        }
        Spacer(minLength: 0)
      }
      .buttonStyle(PulseActionButtonStyle())
      .font(.caption.weight(.medium))

      if let release = updates.offeredRelease, let pageURL = release.pageURL {
        Button("Release notes") { NSWorkspace.shared.open(pageURL) }
          .buttonStyle(.borderless)
          .font(.caption.weight(.medium))
          .accessibilityIdentifier("updateReleaseNotesButton")
      }
    }
    .font(.subheadline)
  }

  private var statusColor: Color {
    if case .failed = updates.phase { return .red }
    return .secondary
  }

  /// Task settings own the tag vocabulary only. Creating, completing and
  /// deleting tasks stays on Home so the popover never becomes a second editor.
  private var tasksContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      LocalTagSettingsView(
        controller: localTasks,
        onEditingChanged: { editing.set(source: "tagEditor", editing: $0) })
      Text(
        "Tasks live in Pulse only. Add them on Home, mark them done to dim them, set"
          + " “Repeat daily” for a task that comes back each day, or hover a row to delete it."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
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

/// Tracks which Settings surfaces currently hold keyboard focus and exposes one
/// aggregated bit for the popover's dismissal suspension.
///
/// The naive version passes each field's focus straight through: focus moves
/// from tag editor → API key, the editor reports `false`, and the popover is
/// free to close with a caret still in the key field. Counting sources removes
/// that race, and `clear()` makes leaving the page unconditionally safe.
@MainActor
final class PulseEditingRegistry: ObservableObject {
  @Published private(set) var isEditing = false
  private var sources = Set<String>()

  func set(source: String, editing: Bool) {
    if editing {
      sources.insert(source)
    } else {
      sources.remove(source)
    }
    isEditing = !sources.isEmpty
  }

  func clear() {
    sources.removeAll()
    isEditing = false
  }
}
