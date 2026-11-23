import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 400, height: 520)

  let config: AppConfig
  let usage: UsageController
  let vipUsage: UsageController
  let deepSeekUsage: UsageController
  let deepSeekConfiguration: DeepSeekConfiguration
  let vipConfiguration: VIPConfiguration
  let localTasks: LocalTaskController
  let updates: UpdateController
  @ObservedObject var pages: PopoverPageController
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }
  var localPresentation = LocalTaskPresentation()
  var onOpenSettings: (SettingsDestination?, ProviderID?) -> Void = { _, _ in }
  var onRestartRequested: () -> Void = {}
  var focusTimer = FocusTimerController()
  var antigravityUsage = UsageController(provider: InactiveSettingsProvider())
  var todayBridge: TodayTaskBridge?
  var todayPresentation = TodayTaskPresentation()
  @State private var hidesUpdateBanner = false

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      HomeProviderStrip(
        config: config, usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
        antigravityUsage: antigravityUsage, deepSeekConfiguration: deepSeekConfiguration,
        vipConfiguration: vipConfiguration, onOpenUsage: { pages.showUsage($0) },
        onOpenSettings: { onOpenSettings(.providers, $0) }
      )
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
            .frame(width: PulseDesignTokens.brandMarkSize, height: PulseDesignTokens.brandMarkSize)
            .background(
              PulseDesignTokens.selectedFill,
              in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
          Text("Pulse").font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
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
        Text(pageTitle).font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
      }
      Spacer(minLength: 0)
      if pages.page == .home {
        HomeFocusButton(timer: focusTimer)
      }
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
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 12)
  }

  private var pageTitle: String {
    switch pages.page {
    case .home: "Pulse"
    case .usage(let provider): provider.name
    case .tagManagement: PulseLocalization.string("All tags")
    }
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      if !hidesUpdateBanner {
        HomeUpdateBanner(
          updates: updates, onRestart: onRestartRequested,
          onDismiss: { hidesUpdateBanner = true })
      }
      Group {
        if let todayBridge {
          HomeTaskLists(
            bridge: todayBridge, presentation: todayPresentation,
            localTasks: localTasks, localPresentation: localPresentation,
            onEditingChanged: onTaskEditingChanged, onManageTags: { pages.showTagManagement() })
        } else {
          LocalTasksView(
            controller: localTasks, presentation: localPresentation,
            onEditingChanged: onTaskEditingChanged, onManageTags: { pages.showTagManagement() })
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("tasksRegion")
    }
  }

  private func usageContent(_ provider: ProviderID) -> some View {
    ScrollView {
      UsageView(
        usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
        antigravityUsage: antigravityUsage,
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

private struct HomeFocusButton: View {
  @ObservedObject var timer: FocusTimerController

  var body: some View {
    let idleTitle = PulseLocalization.string("Focus 30 min")
    Button {
      if timer.isRunning {
        timer.cancel()
      } else {
        timer.start()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: timer.isRunning ? "stop.circle.fill" : "timer")
          .frame(width: 14)
          .foregroundStyle(timer.isRunning ? PulseDesignTokens.accent : Color.secondary)
          .accessibilityHidden(true)
        ZStack(alignment: .leading) {
          // Both localized labels reserve space, including the cancel action.
          Text(idleTitle).hidden().accessibilityHidden(true)
          Text(PulseLocalization.format("%@ · Cancel", "00:00"))
            .hidden().accessibilityHidden(true)
          if timer.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
              let seconds = timer.remainingSeconds
              let countdown = String(format: "%02d:%02d", seconds / 60, seconds % 60)
              Text(PulseLocalization.format("%@ · Cancel", countdown))
            }
          } else {
            Text(idleTitle)
          }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .buttonStyle(PulseActionButtonStyle(emphasis: .focusTimer(isRunning: timer.isRunning)))
    .accessibilityIdentifier("focusTimerButton")
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["focusTimerButton": $0]
    }
  }
}

private struct HomeProviderStrip: View {
  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var antigravityUsage: UsageController
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  let onOpenUsage: (ProviderID) -> Void
  let onOpenSettings: (ProviderID) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ViewThatFits(in: .horizontal) {
        providerRow
        ScrollView(.horizontal) { providerRow }
      }
      .frame(height: 32)
      .padding(.bottom, 8)
      Rectangle().fill(PulseDesignTokens.border).frame(height: 1)
        .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
          ["providerDivider": $0]
        }
    }
    .padding(.horizontal, PulseDesignTokens.contentInset)
  }

  private var providerRow: some View {
    ProviderStatusLayout {
      AIStatusSummary(state: usage.state) {
        usage.requestRefresh()
        onOpenUsage(.codex)
      }
      VIPStatusSummary(state: vipUsage.state, isConfigured: vipConfiguration.hasAPIKey) {
        if vipConfiguration.hasAPIKey {
          vipUsage.requestRefresh()
          onOpenUsage(.vip)
        } else {
          onOpenSettings(.vip)
        }
      }
      DeepSeekStatusSummary(
        state: deepSeekUsage.state, isConfigured: deepSeekConfiguration.hasAPIKey
      ) {
        if deepSeekConfiguration.hasAPIKey {
          deepSeekUsage.requestRefresh()
          onOpenUsage(.deepSeek)
        } else {
          onOpenSettings(.deepSeek)
        }
      }
      if config.antigravityEnabled {
        AntigravityStatusSummary(state: antigravityUsage.state) {
          onOpenUsage(.antigravity)
        }
      }
    }
  }
}

private struct HomeUpdateBanner: View {
  @ObservedObject var updates: UpdateController
  let onRestart: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    if let release = updates.stagedRelease {
      PulseUpdateBanner(
        version: release.version.description, onRestart: onRestart, onDismiss: onDismiss
      )
    }
  }
}
