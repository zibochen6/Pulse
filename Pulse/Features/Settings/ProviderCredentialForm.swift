import SwiftUI

struct ProviderCredentialForm<Icon: View>: View {
  @ObservedObject var configuration: APIKeyConfiguration
  @ObservedObject var usage: UsageController
  @ObservedObject var presentation: SettingsPresentation
  let provider: ProviderID
  let fieldIdentifier: String
  let actionIdentifier: String
  let showBalance: Binding<Bool>
  let onCredentialsChanged: () -> Void
  var onEditingChanged: (Bool) -> Void = { _ in }
  @ViewBuilder let icon: () -> Icon
  @FocusState private var keyFocused: Bool

  private var connection: ProviderConnectionState {
    .resolve(
      hasCredential: configuration.hasAPIKey, configurationError: configuration.errorMessage,
      state: usage.state)
  }
  private var isExpanded: Bool { presentation.expandedProviders.contains(provider) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        icon().frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 4) {
          Text(provider.name).font(.system(size: 15, weight: .semibold))
          Label {
            Text(connection.title)
              .pulseContentFeedback(connection)
          } icon: {
            PulseBusyGlyph(isBusy: usage.isRefreshing, startedAt: usage.refreshStartedAt) {
              Image(systemName: statusSymbol)
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
          }
          .font(.system(size: 12)).foregroundStyle(statusColor)
          .accessibilityIdentifier("connectionStatus.\(provider.rawValue)")
        }
        Spacer()
        if !isExpanded {
          Button(LocalizedStringKey(configuration.hasAPIKey ? "Manage connection" : "Connect")) {
            presentation.beginEditing(provider)
            keyFocused = true
          }
          .buttonStyle(
            PulseActionButtonStyle(emphasis: configuration.hasAPIKey ? .secondary : .primary)
          )
          .accessibilityLabel("Configure \(provider.name)")
          .accessibilityIdentifier("configure\(actionIdentifier)Button")
        }
      }
      if case .needsAttention(let message) = connection {
        VStack(alignment: .leading, spacing: 8) {
          Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .pulseContentFeedback(message)
          if configuration.hasAPIKey {
            Button("Check connection") { usage.requestRefresh() }
              .buttonStyle(PulseActionButtonStyle()).disabled(usage.isRefreshing)
          }
        }
        .pulseStatusAppearance()
      }
      Toggle("Show balance in Pulse", isOn: showBalance)
        .toggleStyle(.switch)
        .accessibilityIdentifier("balanceUsageToggle.\(provider.rawValue)")
      if isExpanded {
        editor.pulseStatusAppearance()
      }
    }
    .padding(16)
    .pulsePaper()
    .onChange(of: keyFocused) { onEditingChanged($0) }
    .onDisappear { onEditingChanged(false) }
  }

  private var editor: some View {
    let editorID = presentation.editorID(for: provider)
    let binding = Binding<String>(
      get: { presentation.draft(for: provider) },
      set: { value in
        guard presentation.editorID(for: provider) == editorID,
          presentation.expandedProviders.contains(provider)
        else { return }
        presentation.setDraft(value, for: provider)
      })
    return VStack(alignment: .leading, spacing: 12) {
      SecureField("\(provider.name) API key", text: binding)
        .textFieldStyle(.roundedBorder).controlSize(.large)
        .focused($keyFocused).accessibilityIdentifier(fieldIdentifier)
      Text("Your API key is stored only in macOS Keychain.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Button("Save and verify") {
          guard configuration.save(apiKey: presentation.draft(for: provider)) else { return }
          keyFocused = false
          presentation.finishEditing(provider)
          onCredentialsChanged()
        }
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .disabled(
          presentation.draft(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .accessibilityIdentifier("save\(actionIdentifier)APIKeyButton")
        Button("Cancel") {
          keyFocused = false
          presentation.finishEditing(provider)
        }.buttonStyle(PulseActionButtonStyle())
        Spacer(minLength: 0)
        if configuration.hasAPIKey {
          Button("Disconnect", role: .destructive) {
            guard configuration.removeAPIKey() else { return }
            keyFocused = false
            presentation.finishEditing(provider)
            onCredentialsChanged()
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("remove\(actionIdentifier)APIKeyButton")
        }
      }
      .font(.system(size: 12, weight: .medium))
    }
  }

  private var statusSymbol: String {
    switch connection {
    case .connected: "checkmark.circle.fill"
    case .verifying: "arrow.triangle.2.circlepath"
    case .notConnected: "circle.dashed"
    case .needsAttention: "exclamationmark.circle"
    }
  }
  private var statusColor: Color {
    switch connection {
    case .connected: PulseDesignTokens.success
    case .needsAttention: PulseDesignTokens.warning
    case .notConnected, .verifying: .secondary
    }
  }
}
