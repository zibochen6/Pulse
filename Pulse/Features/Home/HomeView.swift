import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 400, height: 520)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var updates: UpdateController
  @ObservedObject var pages: PopoverPageController
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }
  @ObservedObject var localPresentation = LocalTaskPresentation()
  var onOpenSettings: (SettingsDestination?, ProviderID?) -> Void = { _, _ in }
  var onRestartRequested: () -> Void = {}
  @State private var hidesUpdateBanner = false

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      statusStrip
      PopoverContentTransition(page: pages.page) {
        Group {
          switch pages.page {
          case .home: homeContent
          case .usage(let provider): usageContent(provider)
          case .tagManagement: tagManagement
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulseDesignTokens.background)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    .background(PulseDesignTokens.background)
    .tint(PulseDesignTokens.accent)
    .clipped()
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      if pages.page == .home {
        HStack(spacing: 8) {
          Image(systemName: "waveform.path")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PulseDesignTokens.accent)
            .frame(width: 28, height: 28)
            .background(
              PulseDesignTokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          Text("Pulse").font(.system(size: 17, weight: .semibold))
        }
      } else {
        Button {
          pages.showHome()
        } label: {
          Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PulseIconButtonStyle()).help("Back to Home")
        .accessibilityLabel("Back to Home").accessibilityIdentifier("backToHomeButton")
        Text(pageTitle).font(.system(size: 16, weight: .semibold))
      }
      Spacer(minLength: 0)
      Button {
        onOpenSettings(nil, nil)
      } label: {
        Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
          .frame(width: 32, height: 32)
      }
      .buttonStyle(PulseIconButtonStyle()).help("Settings")
      .accessibilityLabel("Open Settings").accessibilityIdentifier("openSettingsButton")
      .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
        ["openSettingsButton": $0]
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
  }

  private var pageTitle: String {
    switch pages.page {
    case .home: "Pulse"
    case .usage(let provider): provider.name
    case .tagManagement: PulseLocalization.string("All tags")
    }
  }

  private var statusStrip: some View {
    VStack(spacing: 0) {
      ProviderStatusLayout {
        AIStatusSummary(state: usage.state) {
          usage.requestRefresh()
          pages.showUsage(.codex)
        }
        VIPStatusSummary(state: vipUsage.state, isConfigured: vipConfiguration.hasAPIKey) {
          if vipConfiguration.hasAPIKey {
            vipUsage.requestRefresh()
            pages.showUsage(.vip)
          } else {
            onOpenSettings(.providers, .vip)
          }
        }
        DeepSeekStatusSummary(
          state: deepSeekUsage.state, isConfigured: deepSeekConfiguration.hasAPIKey
        ) {
          if deepSeekConfiguration.hasAPIKey {
            deepSeekUsage.requestRefresh()
            pages.showUsage(.deepSeek)
          } else {
            onOpenSettings(.providers, .deepSeek)
          }
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 12)
      Rectangle().fill(PulseDesignTokens.border).frame(height: 1).padding(.horizontal, 16)
    }
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      if let release = updates.stagedRelease, !hidesUpdateBanner {
        PulseUpdateBanner(
          version: release.version.description, onRestart: onRestartRequested,
          onDismiss: { hidesUpdateBanner = true })
      }
      LocalTasksView(
        controller: localTasks, presentation: localPresentation,
        onEditingChanged: onTaskEditingChanged,
        onManageTags: { pages.showTagManagement() }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("tasksRegion")
    }
  }

  private func usageContent(_ provider: ProviderID) -> some View {
    ScrollView {
      UsageView(
        usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
        onAddProvider: { onOpenSettings(.providers, provider) }, provider: provider
      )
      .padding(16)
    }.accessibilityIdentifier("usageDetailRegion")
  }

  private var tagManagement: some View {
    Group {
      LocalTagSettingsView(
        controller: localTasks, presentation: localPresentation,
        onEditingChanged: onTaskEditingChanged,
        onReturnToDraft: { pages.showHome() },
        onSelectTag: { id in
          localPresentation.selectedFilter = id.map(LocalTaskFilter.tag) ?? .untagged
          pages.showHome()
        }
      )
      .padding(16)
    }
  }
}
