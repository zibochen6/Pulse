import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var config: AppConfig
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var updates: UpdateController
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var antigravityUsage: UsageController
  @ObservedObject var presentation: SettingsPresentation
  @ObservedObject var localPresentation: LocalTaskPresentation
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  let onRestartRequested: () -> Void
  let onReturnToDraft: () -> Void
  var onTaskEditingChanged: (Bool) -> Void
  var todayBridge: TodayTaskBridge?
  @StateObject private var editing = PulseEditingRegistry()

  init(
    config: AppConfig, deepSeekConfiguration: DeepSeekConfiguration,
    vipConfiguration: VIPConfiguration, localTasks: LocalTaskController,
    updates: UpdateController, destination: SettingsDestination? = nil,
    onBack: @escaping () -> Void = {},
    onDeepSeekCredentialsChanged: @escaping () -> Void,
    onVIPCredentialsChanged: @escaping () -> Void, onQuit: @escaping () -> Void,
    onTaskEditingChanged: @escaping (Bool) -> Void = { _ in },
    usage: UsageController? = nil, vipUsage: UsageController? = nil,
    deepSeekUsage: UsageController? = nil, antigravityUsage: UsageController? = nil,
    presentation: SettingsPresentation? = nil,
    localPresentation: LocalTaskPresentation? = nil,
    onRestartRequested: @escaping () -> Void = {},
    onReturnToDraft: @escaping () -> Void = {},
    todayBridge: TodayTaskBridge? = nil
  ) {
    self.config = config
    self.deepSeekConfiguration = deepSeekConfiguration
    self.vipConfiguration = vipConfiguration
    self.localTasks = localTasks
    self.updates = updates
    self.usage = usage ?? UsageController(provider: InactiveSettingsProvider())
    self.vipUsage = vipUsage ?? UsageController(provider: InactiveSettingsProvider())
    self.deepSeekUsage = deepSeekUsage ?? UsageController(provider: InactiveSettingsProvider())
    self.antigravityUsage =
      antigravityUsage ?? UsageController(provider: InactiveSettingsProvider())
    self.presentation = presentation ?? SettingsPresentation(destination: destination ?? .general)
    self.localPresentation = localPresentation ?? LocalTaskPresentation()
    self.onDeepSeekCredentialsChanged = onDeepSeekCredentialsChanged
    self.onVIPCredentialsChanged = onVIPCredentialsChanged
    self.onQuit = onQuit
    self.onTaskEditingChanged = onTaskEditingChanged
    self.onRestartRequested = onRestartRequested
    self.onReturnToDraft = onReturnToDraft
    self.todayBridge = todayBridge
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(PulseDesignTokens.border).frame(width: 1)
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          Text(presentation.destination.title).font(.system(size: 24, weight: .semibold))
          Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        if presentation.destination == .tasks {
          tasksContent.padding(.horizontal, 24).padding(.bottom, 24)
        } else {
          ScrollViewReader { proxy in
            ScrollView {
              Group {
                switch presentation.destination {
                case .general: generalContent
                case .providers: providerContent
                case .tasks: tasksContent
                case .updates: updatesContent
                case .about: aboutContent
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .task(id: presentation.revealRequest) {
              await Task.yield()
              if presentation.destination == .providers, let provider = presentation.focusedProvider
              {
                proxy.scrollTo(provider, anchor: .top)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(
      width: SettingsWindowController.contentSize.width,
      height: SettingsWindowController.contentSize.height
    )
    .background(PulseDesignTokens.background)
    .tint(PulseDesignTokens.accent)
    .onAppear {
      config.refreshLoginItemStatus()
      vipConfiguration.refresh()
      deepSeekConfiguration.refresh()
      if todayBridge?.isEnabled != true { Task { await localTasks.refresh() } }
    }
    .onChange(of: editing.isEditing) { onTaskEditingChanged($0) }
    .onDisappear {
      editing.clear()
      onTaskEditingChanged(false)
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: "waveform.path").font(.system(size: 20, weight: .semibold))
          .foregroundStyle(PulseDesignTokens.accent)
          .frame(width: 36, height: 36)
          .background(
            PulseDesignTokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        Text("Pulse").font(.system(size: 20, weight: .semibold))
      }.padding(.bottom, 24)
      ForEach(SettingsDestination.allCases) { destination in
        Button {
          presentation.destination = destination
        } label: {
          HStack(spacing: 10) {
            Image(systemName: destination.symbol).frame(width: 18)
            Text(destination.title)
            Spacer(minLength: 0)
          }
          .font(
            .system(size: 13, weight: presentation.destination == destination ? .semibold : .medium)
          )
          .padding(.horizontal, 12).frame(height: 40)
          .foregroundStyle(
            presentation.destination == destination ? PulseDesignTokens.accent : Color.primary
          )
          .background(
            presentation.destination == destination
              ? PulseDesignTokens.accent.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(presentation.destination == destination ? .isSelected : [])
        .accessibilityIdentifier("settingsCategory.\(destination.rawValue)")
      }
      Spacer()
      Text("A little more clarity.")
        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 12)
      Button("Quit Pulse", action: onQuit)
        .buttonStyle(.borderless).font(.system(size: 12))
        .padding(12).accessibilityIdentifier("quitPulseButton")
    }
    .padding(16).frame(width: 168)
    .background(PulseDesignTokens.secondarySurface)
  }

  private var subtitle: String {
    switch presentation.destination {
    case .general: PulseLocalization.string("Make Pulse feel at home on your Mac.")
    case .providers: PulseLocalization.string("Your services, connected on your terms.")
    case .tasks: PulseLocalization.string("A clear place for every thought.")
    case .updates: PulseLocalization.string("Keep your daily companion up to date.")
    case .about: PulseLocalization.string("AI usage and everyday tasks, quietly together.")
    }
  }

  private var generalContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      settingsCard {
        VStack(alignment: .leading, spacing: 16) {
          preferenceRow(
            "Launch at login", detail: "Keep Pulse ready when you start your day.",
            binding: Binding(
              get: { config.launchAtLoginRequested }, set: { config.setLaunchAtLogin($0) }))
          if config.launchAtLoginRequested {
            Text(loginItemMessage).font(.system(size: 12)).foregroundStyle(.secondary)
            if config.loginItemStatus == .requiresApproval {
              Button("Open Login Items settings") {
                if let url = URL(
                  string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                {
                  NSWorkspace.shared.open(url)
                }
              }.buttonStyle(PulseActionButtonStyle())
            }
          }
          if let error = config.loginItemError {
            Text(error).font(.system(size: 12)).foregroundStyle(PulseDesignTokens.destructive)
          }
          Divider()
          preferenceRow(
            "Show Pulse name in menu bar", detail: "Display the name beside your Codex usage.",
            binding: Binding(
              get: { config.showMenuBarLabel }, set: { config.setShowMenuBarLabel($0) }))
        }
      }
      Text("Appearance, language and reduced motion follow your Mac’s settings.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
    }
  }

  private var providerContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      settingsCard {
        HStack(spacing: 12) {
          CodexProviderIcon(size: 26)
          VStack(alignment: .leading, spacing: 4) {
            Text("Codex").font(.system(size: 15, weight: .semibold))
            Text(ProviderConnectionState.resolve(hasCredential: true, state: usage.state).title)
              .font(.system(size: 12)).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Check connection") { usage.requestRefresh() }
            .buttonStyle(PulseActionButtonStyle()).disabled(usage.isRefreshing)
        }
        Text("Uses the Codex account signed in on this Mac. No API key needed.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
        if case .failure(let message) = usage.state {
          Text(message).font(.system(size: 12)).foregroundStyle(PulseDesignTokens.warning)
        } else if case .unavailable(let message) = usage.state {
          Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
      }
      .id(ProviderID.codex)
      ProviderCredentialForm(
        configuration: vipConfiguration, usage: vipUsage, presentation: presentation,
        provider: .vip, fieldIdentifier: "vipAPIKeyField", actionIdentifier: "VIP",
        onCredentialsChanged: onVIPCredentialsChanged,
        onEditingChanged: { editing.set(source: "vipAPIKeyField", editing: $0) }
      ) { VIPProviderIcon(size: 26) }
      .id(ProviderID.vip)
      ProviderCredentialForm(
        configuration: deepSeekConfiguration, usage: deepSeekUsage, presentation: presentation,
        provider: .deepSeek, fieldIdentifier: "deepSeekAPIKeyField", actionIdentifier: "DeepSeek",
        onCredentialsChanged: onDeepSeekCredentialsChanged,
        onEditingChanged: { editing.set(source: "deepSeekAPIKeyField", editing: $0) }
      ) { DeepSeekProviderIcon(size: 26) }
      .id(ProviderID.deepSeek)
      antigravitySettings
        .id(ProviderID.antigravity)
    }
  }

  private var antigravitySettings: some View {
    let connection = ProviderConnectionState.resolve(
      hasCredential: config.antigravityEnabled, state: antigravityUsage.state)
    return settingsCard {
      HStack(spacing: 12) {
        AntigravityProviderIcon(size: 26)
        VStack(alignment: .leading, spacing: 4) {
          Text("Gemini · Antigravity").font(.system(size: 15, weight: .semibold))
          Text(connection.title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        if config.antigravityEnabled {
          Button("Check connection") { antigravityUsage.requestRefresh() }
            .buttonStyle(PulseActionButtonStyle())
            .disabled(antigravityUsage.isRefreshing)
            .accessibilityIdentifier("checkAntigravityConnection")
        }
      }
      Toggle(
        "Track Gemini model quotas",
        isOn: Binding(
          get: { config.antigravityEnabled }, set: { config.setAntigravityEnabled($0) })
      )
      .toggleStyle(.switch)
      .accessibilityIdentifier("antigravityUsageToggle")
      Text("Uses your local Antigravity sign-in.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
      if case .needsAttention(let message) = connection {
        Text(message).font(.system(size: 12)).foregroundStyle(PulseDesignTokens.warning)
      }
    }
  }

  @ViewBuilder private var tasksContent: some View {
    if let todayBridge {
      TodayTasksSettings(bridge: todayBridge, localSettings: localTagSettings)
    } else {
      localTagSettings
    }
  }

  private var localTagSettings: LocalTagSettingsView {
    LocalTagSettingsView(
      controller: localTasks, presentation: localPresentation,
      onEditingChanged: { editing.set(source: "tagEditor", editing: $0) },
      onReturnToDraft: onReturnToDraft)
  }

  private var updatesContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      settingsCard {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Pulse \(updates.currentVersionText)").font(.system(size: 16, weight: .semibold))
            Text(updates.statusText).font(.system(size: 12))
              .foregroundStyle(statusColor).fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("updateStatusText")
          }
          Spacer(minLength: 8)
          if updates.isBusy { ProgressView().controlSize(.small) }
        }
        HStack(spacing: 8) {
          if updates.canRestartToUpdate {
            Button("Restart and update", action: onRestartRequested)
              .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
              .accessibilityIdentifier("restartToUpdateButton")
          }
          Button(LocalizedStringKey(updates.isBusy ? "Checking…" : "Check for updates")) {
            Task { await updates.checkForUpdates() }
          }
          .buttonStyle(
            PulseActionButtonStyle(emphasis: updates.canRestartToUpdate ? .secondary : .primary)
          )
          .disabled(updates.isBusy || !updates.isUpdateSupported)
          .accessibilityIdentifier("checkForUpdatesButton")
        }
        if let release = updates.offeredRelease, let url = release.pageURL {
          HStack(spacing: 16) {
            Button("Release notes") { NSWorkspace.shared.open(url) }
              .accessibilityIdentifier("updateReleaseNotesButton")
            if !updates.canRestartToUpdate {
              Button("Skip this version") { updates.skipOfferedRelease() }.disabled(updates.isBusy)
                .accessibilityIdentifier("skipUpdateVersionButton")
            }
          }.buttonStyle(.borderless).font(.system(size: 12))
        }
      }
      settingsCard {
        preferenceRow(
          "Check for updates automatically",
          detail: "Verified updates install when you’re not working in Pulse.",
          binding: Binding(
            get: { updates.automaticChecksEnabled }, set: { updates.automaticChecksEnabled = $0 })
        )
        .disabled(!updates.isUpdateSupported).accessibilityIdentifier("automaticUpdatesToggle")
      }
    }
  }

  private var aboutContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      settingsCard {
        Text("Your day, in focus.").font(.system(size: 22, weight: .semibold))
        Text("AI usage at a glance. Thoughts turned into tasks. All close at hand.")
          .font(.system(size: 14)).foregroundStyle(.secondary)
        Text(versionText).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      settingsCard {
        Label("Local by design", systemImage: "lock.shield").font(
          .system(size: 14, weight: .semibold))
        Text(
          "Local tasks stay on this Mac. Synced tasks are saved in your Obsidian vault."
        )
        .font(.system(size: 13)).foregroundStyle(.secondary)
        Text("API keys stay in macOS Keychain. Pulse has no analytics.")
          .font(.system(size: 13)).foregroundStyle(.secondary)
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
          Button("Open third-party notices") { NSWorkspace.shared.open(url) }
            .buttonStyle(.borderless).font(.system(size: 12))
        }
      }
    }
  }

  private func preferenceRow(_ title: String, detail: String, binding: Binding<Bool>) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .medium))
        Text(LocalizedStringKey(detail)).font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      Toggle(LocalizedStringKey(title), isOn: binding).labelsHidden().toggleStyle(.switch)
    }
  }
  private var statusColor: Color {
    if case .failed = updates.phase { return PulseDesignTokens.destructive }
    return .secondary
  }
  private var versionText: String {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String
    else {
      return PulseLocalization.string("Development build")
    }
    return PulseLocalization.format("Version %@", version)
  }
  private var loginItemMessage: String {
    switch config.loginItemStatus {
    case .enabled: PulseLocalization.string("Enabled in macOS Login Items.")
    case .requiresApproval:
      PulseLocalization.string("Approve Pulse in System Settings > General > Login Items.")
    case .notRegistered: PulseLocalization.string("Not enabled in macOS Login Items.")
    case .notFound:
      PulseLocalization.string("macOS cannot locate this app for login. Try an installed build.")
    }
  }
}

private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
  VStack(alignment: .leading, spacing: 12, content: content)
    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    .background(PulseDesignTokens.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseDesignTokens.border, lineWidth: 1))
}

@MainActor
private struct TodayTasksSettings: View {
  @ObservedObject var bridge: TodayTaskBridge
  let localSettings: LocalTagSettingsView
  @State private var busy = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      settingsCard { connectionSettings }
      if !bridge.isEnabled { localSettings }
    }
  }

  private var connectionSettings: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Label("Obsidian Today Tasks", systemImage: "calendar")
            .font(.system(size: PulseDesignTokens.label, weight: .semibold))
            .foregroundStyle(.primary)
          if let vault = bridge.vaultURL {
            Text(vault.lastPathComponent)
              .lineLimit(1).truncationMode(.middle).help(vault.path)
              .accessibilityIdentifier("todayTasksVaultName")
            Text(bridge.connection.todayTaskMessage)
              .accessibilityIdentifier("todayTasksSettingsConnectionStatus")
            if bridge.pendingCount > 0 { Text(bridge.pendingStatus) }
          } else {
            Text("Sync Today Tasks from the Personal Dashboard on this Mac.")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .font(.system(size: PulseDesignTokens.caption)).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 4) {
          Button(
            LocalizedStringKey(bridge.vaultURL == nil ? "Choose vault…" : "Change vault…"),
            action: chooseVault
          )
          .buttonStyle(PulseActionButtonStyle()).accessibilityIdentifier("chooseTodayTasksVault")
          if bridge.vaultURL != nil {
            Button("Disconnect") { disconnect() }
              .font(.system(size: PulseDesignTokens.caption))
              .buttonStyle(.borderless)
              .accessibilityIdentifier("disconnectTodayTasksVault")
          }
        }
        .disabled(busy || bridge.hasPendingWrite)
      }
      if let errorMessage {
        PulseErrorBanner(message: errorMessage, accessibilityIdentifier: "todayTasksSettingsError")
        {
          Button("Dismiss") { self.errorMessage = nil }
        }
      }
    }
  }

  private func chooseVault() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.title = PulseLocalization.string("Choose an Obsidian vault")
    panel.prompt = PulseLocalization.string("Select vault")
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if let vault = bridge.vaultURL { panel.directoryURL = vault.deletingLastPathComponent() }
    busy = true
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window) { finishSelection($0, panel: panel) }
    } else {
      panel.begin { finishSelection($0, panel: panel) }
    }
  }

  private func finishSelection(_ response: NSApplication.ModalResponse, panel: NSOpenPanel) {
    guard response == .OK, let url = panel.url else {
      busy = false
      return
    }
    changeVault { try await bridge.connect(to: url) }
  }

  private func disconnect() {
    guard !busy else { return }
    busy = true
    changeVault { try await bridge.disconnect() }
  }

  private func changeVault(_ action: @escaping @MainActor () async throws -> Void) {
    errorMessage = nil
    Task {
      defer { busy = false }
      do {
        try await action()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
