import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var config: AppConfig
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var tasks: DashboardTaskController
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var taskSource: TaskSourceConfiguration
  @ObservedObject var dashboardPicker: DashboardFilePicker
  let destination: SettingsDestination
  let onBack: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onSelectDashboardFile: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }

  @State private var vipAPIKey = ""

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
              providerContent
            }
            .id(SettingsDestination.providers)

            PulseSection(title: "Tasks", symbol: "checklist") {
              tasksContent
            }
            .id(SettingsDestination.tasks)

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
      HStack(spacing: 8) {
        VIPProviderIcon(size: 18)
        Text("88VIP")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(vipConfiguration.hasAPIKey ? "Connected" : "Not connected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      SecureField("88VIP API key", text: $vipAPIKey)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("vipAPIKeyField")

      HStack(spacing: 10) {
        Button(vipConfiguration.hasAPIKey ? "Replace key" : "Save key") {
          guard vipConfiguration.save(apiKey: vipAPIKey) else { return }
          vipAPIKey = ""
          onVIPCredentialsChanged()
        }
        .disabled(vipAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .accessibilityIdentifier("saveVIPAPIKeyButton")

        if vipConfiguration.hasAPIKey {
          Button("Remove key", role: .destructive) {
            guard vipConfiguration.removeAPIKey() else { return }
            vipAPIKey = ""
            onVIPCredentialsChanged()
          }
          .accessibilityIdentifier("removeVIPAPIKeyButton")
        }
      }
      .buttonStyle(PulseActionButtonStyle())
      .font(.caption.weight(.medium))

      if let errorMessage = vipConfiguration.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Your API key is stored only in macOS Keychain.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("More AI providers are coming soon.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var tasksContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Task source")
          .font(.subheadline.weight(.medium))
        Picker(
          "Task source",
          selection: Binding(
            get: { taskSource.source },
            set: { taskSource.setSource($0) }
          )
        ) {
          Text("Built-in tasks").tag(TaskSource.local)
          Text("Obsidian Dashboard").tag(TaskSource.apex)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityIdentifier("taskSourcePicker")
      }
      Text("Each source keeps its own tasks. Switching never merges or deletes them.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if taskSource.source == .local {
        LocalTagSettingsView(controller: localTasks, onEditingChanged: onTaskEditingChanged)
      }
      Divider()
      HStack(spacing: 8) {
        Image(systemName: "checklist")
          .foregroundStyle(.secondary)
        Text("Apex Dashboard")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(dashboardConnectionStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Add tasks or change their completion in Pulse. Click task text to open the Dashboard in Obsidian."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        Button(
          dashboardPicker.isSelecting
            ? "Opening file chooser…"
            : tasks.configuration.hasDashboardSelection
              ? "Choose another file" : "Select Dashboard File"
        ) {
          onSelectDashboardFile()
        }
        .buttonStyle(PulseActionButtonStyle())
        .font(.caption.weight(.medium))
        .accessibilityIdentifier("selectDashboardFileButton")
        .disabled(dashboardPicker.isSelecting)

        if tasks.configuration.hasDashboardSelection {
          Button("Refresh") { tasks.requestRefresh() }
            .disabled(tasks.isRefreshing)
            .buttonStyle(PulseActionButtonStyle())
            .font(.caption.weight(.medium))
            .accessibilityIdentifier("refreshDashboardButton")
          Button("Remove", role: .destructive) {
            tasks.removeDashboard()
          }
          .buttonStyle(PulseActionButtonStyle())
          .font(.caption.weight(.medium))
          .accessibilityIdentifier("removeDashboardFileButton")
        }
      }

      if let error = dashboardPicker.errorMessage ?? dashboardConnectionError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else if case .loaded(let dashboard) = tasks.state {
        Text(dashboard.fileURL.lastPathComponent)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if taskSource.source == .local && tasks.configuration.hasDashboardSelection {
        Text("Choose Obsidian Dashboard under Task source to show this file's tasks on Home.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var dashboardConnectionStatus: String {
    switch tasks.state {
    case .notConfigured: "Not connected"
    case .loading: tasks.isRefreshing ? "Loading…" : "Not loaded"
    case .loaded: "Connected"
    case .fileMissing: "File unavailable"
    case .permissionDenied: "Cannot read"
    case .readError, .parseError: "Connection error"
    }
  }

  private var dashboardConnectionError: String? {
    switch tasks.state {
    case .readError(let message), .parseError(let message): message
    case .permissionDenied:
      "Pulse cannot read this Dashboard. Select the file again to restore access."
    case .fileMissing: "The Dashboard was moved or deleted. Choose its current location."
    default: nil
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
