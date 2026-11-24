import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 400, height: 520)

  struct PopoverLayout: Equatable {
    let page: PopoverPage
    let vault: URL?
    let stagedVersion: UpdateVersion?
    let size: NSSize
  }

  private struct TodayMeasurement: Equatable {
    let vault: URL
    let height: CGFloat
  }

  @ObservedObject var config: AppConfig
  @Environment(\.pulseHasNativeBackdrop) private var hasNativeBackdrop
  let usage: UsageController
  let vipUsage: UsageController
  let deepSeekUsage: UsageController
  let deepSeekConfiguration: DeepSeekConfiguration
  let vipConfiguration: VIPConfiguration
  let localTasks: LocalTaskController
  @ObservedObject var updates: UpdateController
  @ObservedObject var pages: PopoverPageController
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }
  var localPresentation = LocalTaskPresentation()
  var onOpenSettings: (SettingsDestination?, ProviderID?) -> Void = { _, _ in }
  var onRestartRequested: () -> Void = {}
  var clips: ClipController?
  var focusTimer = FocusTimerController()
  var antigravityUsage = UsageController(provider: InactiveSettingsProvider())
  var todayBridge: TodayTaskBridge?
  var todayPresentation = TodayTaskPresentation()
  var onPopoverLayoutChanged: ((PopoverLayout) -> Void)?
  @State private var hidesUpdateBanner = false
  @State private var homeHeaderHeight: CGFloat = 0
  @State private var todayMeasurement: TodayMeasurement?

  static func sizeForToday(header: CGFloat, tasks: CGFloat?) -> NSSize {
    guard header > 0, let tasks else { return popoverSize }
    return NSSize(width: popoverSize.width, height: min(popoverSize.height, ceil(header + tasks)))
  }

  private var popoverLayout: PopoverLayout {
    let vault = todayBridge?.vaultURL
    let stagedVersion = updates.stagedRelease?.version
    let size: NSSize
    if onPopoverLayoutChanged != nil,
      pages.page == .home, hidesUpdateBanner || stagedVersion == nil,
      let measurement = todayMeasurement, measurement.vault == vault
    {
      size = Self.sizeForToday(header: homeHeaderHeight, tasks: measurement.height)
    } else {
      size = Self.popoverSize
    }
    return PopoverLayout(page: pages.page, vault: vault, stagedVersion: stagedVersion, size: size)
  }

  var body: some View {
    let layout = popoverLayout
    let paperOpacity = PulseDesignTokens.paperOpacity(
      transparencyPercent: hasNativeBackdrop ? config.effectiveWindowTransparencyPercent : 0)
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        toolbar
        if pages.page == .home, let clips { ClipResultLink(clips: clips) { pages.showClipTask() } }
        HomeProviderStrip(
          config: config, usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
          antigravityUsage: antigravityUsage, deepSeekConfiguration: deepSeekConfiguration,
          vipConfiguration: vipConfiguration, onOpenUsage: { pages.showUsage($0) },
          onOpenSettings: { onOpenSettings(.providers, $0) }
        )
      }
      .background {
        if pages.page == .home, onPopoverLayoutChanged != nil {
          GeometryReader { geometry in
            Color.clear
              .onAppear { homeHeaderHeight = geometry.size.height }
              .onChange(of: geometry.size.height) { homeHeaderHeight = $0 }
          }
        }
      }
      PopoverContentTransition(page: pages.page) {
        Group {
          switch pages.page {
          case .clipTask:
            if let clips { ClipDetailView(clips: clips) { onOpenSettings(.clips, nil) } }
          case .home: homeContent
          case .usage(let provider): usageContent(provider)
          case .tagManagement: tagManagement
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(PulseDesignTokens.ink)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(
      width: layout.size.width,
      height: onPopoverLayoutChanged == nil ? layout.size.height : nil
    )
    .onAppear { onPopoverLayoutChanged?(layout) }
    .onChange(of: layout) { onPopoverLayoutChanged?($0) }
    .background(PulseDesignTokens.background.opacity(paperOpacity))
    .environment(\.pulsePaperOpacity, paperOpacity)
    .foregroundStyle(PulseDesignTokens.ink)
    .tint(PulseDesignTokens.accent)
    .clipped()
  }

  private var toolbar: some View {
    HStack(alignment: .center, spacing: 6) {
      if pages.page == .home {
        homeTitle.pulseStatusAppearance()
      } else {
        Button {
          pages.showHome()
        } label: {
          Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PulseIconButtonStyle(circular: true)).help("Back to Home")
        .accessibilityLabel("Back to Home").accessibilityIdentifier("backToHomeButton")
        Text(pageTitle)
          .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .bold))
          .pulseContentFeedback(pageTitle)
          .pulseStatusAppearance()
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 0)
      if pages.page == .home {
        if let clips {
          ClipHomeButton(
            clips: clips, open: { pages.showClipTask() },
            configure: { onOpenSettings(.clips, nil) })
        }
        HomeFocusButton(timer: focusTimer)
      }
      Button {
        onOpenSettings(nil, nil)
      } label: {
        Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
          .frame(width: 32, height: 32)
      }
      .buttonStyle(PulseIconButtonStyle(circular: true)).help("Settings")
      .accessibilityLabel("Open Settings").accessibilityIdentifier("openSettingsButton")
      .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
        ["openSettingsButton": $0]
      }
    }
    .frame(minHeight: 48)
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 4)
  }

  private var homeTitle: some View {
    VStack(alignment: .leading, spacing: 1) {
      TimelineView(.everyMinute) { timeline in
        Text(timeline.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(PulseDesignTokens.muted)
          .lineLimit(1)
      }
      HStack(spacing: 6) {
        PulseBrandMark(size: 24)
        PulseMarkedTitle(title: "Pulse")
      }
      .fixedSize()
    }
  }

  private var pageTitle: String {
    switch pages.page {
    case .clipTask: PulseLocalization.string("Recording edits")
    case .home: "Pulse"
    case .usage(let provider): provider.name
    case .tagManagement: PulseLocalization.string("All tags")
    }
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      if !hidesUpdateBanner, let release = updates.stagedRelease {
        PulseUpdateBanner(
          version: release.version.description, onRestart: onRestartRequested,
          onDismiss: { hidesUpdateBanner = true })
      }
      Group {
        if let todayBridge {
          HomeTaskLists(
            bridge: todayBridge, presentation: todayPresentation,
            localTasks: localTasks, localPresentation: localPresentation,
            onEditingChanged: onTaskEditingChanged, onManageTags: { pages.showTagManagement() },
            onTodayHeight: { vault, height in
              guard vault == todayBridge.vaultURL else { return }
              let measurement = vault.flatMap { source in
                height.map { TodayMeasurement(vault: source, height: $0) }
              }
              if measurement != todayMeasurement { todayMeasurement = measurement }
            })
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
    let idleTitle = PulseLocalization.string("Focus")
    let startTitle = PulseLocalization.string("Focus 30 min")
    let indicator: (symbol: String, color: Color) =
      if timer.isRunning {
        ("stop.circle.fill", PulseDesignTokens.accent)
      } else if timer.justCompleted {
        ("checkmark", PulseDesignTokens.success)
      } else {
        ("timer", .secondary)
      }
    Button {
      if timer.isRunning {
        timer.cancel()
      } else {
        timer.start()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: indicator.symbol)
          .frame(width: 14)
          .foregroundStyle(indicator.color)
          .pulseContentFeedback(indicator.symbol)
          .accessibilityHidden(true)
        ZStack(alignment: .leading) {
          // Keep the toolbar stable when the label becomes a countdown.
          Text(idleTitle).hidden().accessibilityHidden(true)
          Text("00:00").hidden().accessibilityHidden(true)
          if timer.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
              let seconds = timer.remainingSeconds
              let countdown = String(format: "%02d:%02d", seconds / 60, seconds % 60)
              Text(countdown)
                .accessibilityLabel(PulseLocalization.format("%@ · Cancel", countdown))
            }
          } else {
            Text(idleTitle)
              .accessibilityLabel(
                timer.justCompleted ? PulseLocalization.string("Focus complete") : startTitle)
          }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .buttonStyle(PulseActionButtonStyle(emphasis: .focusTimer(isRunning: timer.isRunning)))
    .help(timer.isRunning ? PulseLocalization.string("Cancel") : startTitle)
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
      if config.vipBalanceEnabled {
        VIPStatusSummary(state: vipUsage.state, isConfigured: vipConfiguration.hasAPIKey) {
          if vipConfiguration.hasAPIKey {
            vipUsage.requestRefresh()
            onOpenUsage(.vip)
          } else {
            onOpenSettings(.vip)
          }
        }
      }
      if config.deepSeekBalanceEnabled {
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
      }
      if config.antigravityEnabled {
        AntigravityStatusSummary(state: antigravityUsage.state) {
          onOpenUsage(.antigravity)
        }
      }
    }
  }
}
