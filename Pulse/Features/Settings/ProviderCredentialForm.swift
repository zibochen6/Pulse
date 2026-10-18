import SwiftUI

struct ProviderCredentialForm<Icon: View>: View {
  @ObservedObject var configuration: APIKeyConfiguration
  let name: String
  let fieldIdentifier: String
  let actionIdentifier: String
  let onCredentialsChanged: () -> Void
  @ViewBuilder let icon: () -> Icon
  @State private var apiKey = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        icon()
        Text(name).font(.subheadline.weight(.semibold))
        Spacer()
        Text(configuration.hasAPIKey ? "Connected" : "Not connected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      SecureField("\(name) API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(fieldIdentifier)
      HStack(spacing: 10) {
        Button(configuration.hasAPIKey ? "Replace key" : "Save key") {
          guard configuration.save(apiKey: apiKey) else { return }
          apiKey = ""
          onCredentialsChanged()
        }
        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .accessibilityIdentifier("save\(actionIdentifier)APIKeyButton")
        if configuration.hasAPIKey {
          Button("Remove key", role: .destructive) {
            guard configuration.removeAPIKey() else { return }
            apiKey = ""
            onCredentialsChanged()
          }
          .accessibilityIdentifier("remove\(actionIdentifier)APIKeyButton")
        }
      }
      .buttonStyle(PulseActionButtonStyle())
      .font(.caption.weight(.medium))
      if let errorMessage = configuration.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Your API key is stored only in macOS Keychain.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .onAppear { configuration.refresh() }
  }
}
