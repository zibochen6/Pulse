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

  private struct TaskMeasurement: Equatable {
    let vault: URL?
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
  var quickCopy: QuickCopyController?
  var onQuickCopyEditingChanged: (Bool) -> Void = { _ in }
  var onPopoverLayoutChanged: ((PopoverLayout) -> Void)?
  @State private var hidesUpdateBanner = false
  @State private var homeToolbarHeight: CGFloat = 0
  @State private var homeFooterHeight: CGFloat = 0
  @State private var taskMeasurement: TaskMeasurement?

  static func sizeForTasks(chrome: CGFloat, tasks: CGFloat?) -> NSSize {
    guard chrome > 0, let tasks else { return popoverSize }
    return NSSize(width: popoverSize.width, height: min(popoverSize.height, ceil(chrome + tasks)))
  }

  private var popoverLayout: PopoverLayout {
    let vault = todayBridge?.vaultURL
    let stagedVersion = updates.stagedRelease?.version
    let size: NSSize
    if onPopoverLayoutChanged != nil,
      pages.page == .home, hidesUpdateBanner || stagedVersion == nil,
      homeToolbarHeight > 0, homeFooterHeight > 0,
      let measurement = taskMeasurement, measurement.vault == vault
    {
      size = Self.sizeForTasks(
        chrome: homeToolbarHeight + homeFooterHeight, tasks: measurement.height)
    } else {
      size = Self.popoverSize
    }
    return PopoverLayout(page: pages.page, vault: vault, stagedVersion: stagedVersion, size: size)
  }

  var body: some View {
    let layout = popoverLayout
    let isHome = pages.page == .home
    let measureHome = isHome && onPopoverLayoutChanged != nil
    let paperOpacity = PulseDesignTokens.paperOpacity(
      transparencyPercent: hasNativeBackdrop ? config.effectiveWindowTransparencyPercent : 0)
    VStack(spacing: 0) {
      toolbar
        .onGeometryChange(for: CGFloat?.self) { geometry in
          measureHome ? ceil(geometry.size.height) : nil
        } action: { height in
          if let height { homeToolbarHeight = height }
        }
      PopoverContentTransition(page: pages.page) {
        Group {
          switch pages.page {
          case .clipTask:
            if let clips { ClipDetailView(clips: clips) { onOpenSettings(.clips, nil) } }
          case .home: homeContent
          case .aiOverview: aiSurface(.overview)
          case .usage(let provider): usageContent(provider)
          case .tagManagement: tagManagement
          case .quickCopy:
            if let quickCopy {
              QuickCopyView(controller: quickCopy, onEditingChanged: onQuickCopyEditingChanged)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(PulseDesignTokens.ink)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
        isHome ? ["tasksRegion": $0] : [:]
      }
      if isHome {
        homeFooter
          .onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
          } action: { height in
            if measureHome { homeFooterHeight = height }
          }
      }
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
        homeDate
      } else {
        Button {
          pages.goBack()
        } label: {
          Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PulseIconButtonStyle(circular: true)).help(backTitle)
        .accessibilityLabel(backTitle)
        .accessibilityIdentifier(backIdentifier)
        Text(pageTitle)
          .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .bold))
          .pulseContentFeedback(pageTitle)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
      }
      if pages.page == .home {
        if let clips {
          ClipHomeButton(
            clips: clips, open: { pages.showClipTask() },
            configure: { onOpenSettings(.clips, nil) })
        }
        HomeFocusButton(timer: focusTimer)
        if quickCopy != nil { quickCopyShortcut }
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
    .frame(minHeight: pages.page == .home ? 36 : 48)
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 4)
  }

  private var homeDate: some View {
    TimelineView(.everyMinute) { timeline in
      Text(timeline.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(PulseDesignTokens.muted)
        .fixedSize(horizontal: true, vertical: false)
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var quickCopyShortcut: some View {
    Button { pages.showQuickCopy() } label: {
      HStack(spacing: 5) {
        Image(systemName: "doc.on.doc")
          .frame(width: 14)
          .accessibilityHidden(true)
        Text("Copy")
      }
    }
    .buttonStyle(PulseActionButtonStyle(emphasis: .toolbar()))
    .help("Quick Copy")
    .accessibilityLabel("Quick Copy")
    .accessibilityIdentifier("openQuickCopyButton")
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["openQuickCopyButton": $0]
    }
  }

  private var pageTitle: String {
    switch pages.page {
    case .clipTask: PulseLocalization.string("Recording edits")
    case .home: "Pulse"
    case .aiOverview: PulseLocalization.string("AI services")
    case .usage(let provider): provider.name
    case .tagManagement: PulseLocalization.string("All tags")
    case .quickCopy: PulseLocalization.string("Quick Copy")
    }
  }

  private var backTitle: String {
    if case .usage = pages.page { return PulseLocalization.string("Back to AI services") }
    return PulseLocalization.string("Back to Home")
  }

  private var backIdentifier: String {
    if case .usage = pages.page { return "backToAIOverviewButton" }
    return "backToHomeButton"
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
            onTodayHeight: measureTasks)
        } else {
          LocalTasksView(
            controller: localTasks, presentation: localPresentation,
            onEditingChanged: onTaskEditingChanged, onManageTags: { pages.showTagManagement() },
            onContentHeight: { measureTasks(vault: nil, height: $0) })
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("tasksRegion")
    }
  }

  private func measureTasks(vault: URL?, height: CGFloat?) {
    guard onPopoverLayoutChanged != nil, vault == todayBridge?.vaultURL else { return }
    let measurement = height.map { TaskMeasurement(vault: vault, height: $0) }
    if measurement != taskMeasurement { taskMeasurement = measurement }
  }

  private var homeFooter: some View {
    VStack(spacing: 0) {
      if let clips {
        ClipResultLink(clips: clips) { pages.showClipTask() }
      }
      aiSurface(.footer)
    }
  }

  private func aiSurface(_ surface: HomeAIServiceSurface.Placement) -> some View {
    HomeAIServiceSurface(
      placement: surface, config: config, usage: usage, vipUsage: vipUsage,
      deepSeekUsage: deepSeekUsage, antigravityUsage: antigravityUsage,
      deepSeekConfiguration: deepSeekConfiguration, vipConfiguration: vipConfiguration,
      onOpenOverview: { pages.showAIOverview() }, onOpenUsage: { pages.showUsage($0) },
      onManageProviders: { onOpenSettings(.providers, $0) })
  }

  private func usageContent(_ provider: ProviderID) -> some View {
    let (controller, configuration): (UsageController, APIKeyConfiguration?) =
      switch provider {
      case .codex: (usage, nil)
      case .antigravity: (antigravityUsage, nil)
      case .vip: (vipUsage, vipConfiguration)
      case .deepSeek: (deepSeekUsage, deepSeekConfiguration)
      }
    let configure = { onOpenSettings(.providers, provider) }
    return ScrollView {
      Group {
        if let configuration {
          CredentialUsageDetail(
            provider: provider, usage: controller, configuration: configuration,
            onAddProvider: configure)
        } else {
          UsageView(usage: controller, provider: provider, onAddProvider: configure)
        }
      }
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.bottom, PulseDesignTokens.contentInset)
    }
    .accessibilityIdentifier("usageDetailRegion")
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
      HStack(spacing: 5) {
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
    .buttonStyle(PulseActionButtonStyle(emphasis: .toolbar(isActive: timer.isRunning)))
    .help(timer.isRunning ? PulseLocalization.string("Cancel") : startTitle)
    .accessibilityIdentifier("focusTimerButton")
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["focusTimerButton": $0]
    }
  }
}

private struct HomeAIServiceSurface: View {
  enum Placement { case footer, overview }

  let placement: Placement
  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var antigravityUsage: UsageController
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  let onOpenOverview: () -> Void
  let onOpenUsage: (ProviderID) -> Void
  let onManageProviders: (ProviderID?) -> Void

  var body: some View {
    let providers = config.enabledUsageProviders.map(presentation(for:))
    switch placement {
    case .footer:
      if let service = ProviderUsagePresentation.homeSummary(in: providers) { footer(service) }
    case .overview:
      ScrollView {
        AIUsageOverviewView(
          providers: providers, onOpenProvider: onOpenUsage,
          onConfigureProvider: { onManageProviders($0) }, onManage: { onManageProviders(nil) }
        )
        .padding(.horizontal, PulseDesignTokens.contentInset)
        .padding(.bottom, PulseDesignTokens.contentInset)
      }
      .accessibilityIdentifier("aiOverviewRegion")
    }
  }

  private func presentation(for provider: ProviderID) -> ProviderUsagePresentation {
    switch provider {
    case .codex: display(.codex, usage)
    case .vip: display(.vip, vipUsage, configuration: vipConfiguration)
    case .deepSeek: display(.deepSeek, deepSeekUsage, configuration: deepSeekConfiguration)
    case .antigravity: display(.antigravity, antigravityUsage)
    }
  }

  private func display(
    _ provider: ProviderID, _ controller: UsageController, configuration: APIKeyConfiguration? = nil
  ) -> ProviderUsagePresentation {
    ProviderUsagePresentation(
      provider: provider, usage: controller, isConfigured: configuration?.hasAPIKey ?? true,
      configurationError: configuration?.errorMessage)
  }

  private func footer(_ service: ProviderUsagePresentation) -> some View {
    let attention = service.attentionPriority > 0
    let paper = attention ? PulseDesignTokens.butterPaper : PulseDesignTokens.secondarySurface
    let summary = service.compactText
    return Button(action: onOpenOverview) {
      HStack(spacing: 7) {
        Text("AI services")
          .foregroundStyle(PulseDesignTokens.muted)
          .fixedSize()
        Spacer(minLength: 4)
        Text(summary)
          .monospacedDigit()
          .lineLimit(1)
          .truncationMode(.tail)
          .pulseContentFeedback(summary)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(PulseDesignTokens.muted)
          .accessibilityHidden(true)
      }
      .font(.system(size: PulseDesignTokens.caption, weight: .semibold))
      .padding(.horizontal, 10)
      .frame(height: 34)
    }
    .buttonStyle(PulseProviderStatusStyle(paper: paper))
    .accessibilityLabel("AI services")
    .accessibilityValue(summary)
    .help(summary)
    .accessibilityIdentifier("openAIOverviewButton")
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["openAIOverviewButton": $0]
    }
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.bottom, 8)
  }
}

private struct CredentialUsageDetail: View {
  let provider: ProviderID
  let usage: UsageController
  @ObservedObject var configuration: APIKeyConfiguration
  let onAddProvider: () -> Void

  var body: some View {
    UsageView(
      usage: usage, provider: provider, isConfigured: configuration.hasAPIKey,
      configurationError: configuration.errorMessage, onAddProvider: onAddProvider)
  }
}
