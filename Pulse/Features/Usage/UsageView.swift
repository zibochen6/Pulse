import SwiftUI

struct AIUsageOverviewView: View {
  let providers: [ProviderUsagePresentation]
  let onOpenProvider: (ProviderID) -> Void
  let onConfigureProvider: (ProviderID) -> Void
  let onManage: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if providers.isEmpty {
        Text("No enabled AI services")
          .foregroundStyle(PulseDesignTokens.muted)
          .padding(12)
      }

      ForEach(providers, id: \.provider) { presentation in
        UsageOverviewCard(presentation: presentation) {
          if presentation.requiresConfiguration {
            onConfigureProvider(presentation.provider)
          } else {
            onOpenProvider(presentation.provider)
          }
        }
      }

      Button("Manage AI services", action: onManage)
        .buttonStyle(PulseActionButtonStyle())
        .accessibilityIdentifier("manageAIUsageButton")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.system(size: PulseDesignTokens.footnote))
    .foregroundStyle(PulseDesignTokens.ink)
  }
}

private struct UsageOverviewCard: View {
  let presentation: ProviderUsagePresentation
  let action: () -> Void

  private var provider: ProviderID { presentation.provider }
  private var description: String {
    PulseLocalization.format(
      presentation.requiresConfiguration ? "Configure %@" : "Open %@ usage details", provider.name)
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          UsageProviderIcon(provider: provider)
          Text(provider.name)
            .font(.system(size: PulseDesignTokens.label, weight: .semibold))
          Spacer(minLength: 4)
          if presentation.isRefreshing && presentation.updatedAt != nil {
            Text("Refreshing…")
              .font(.system(size: PulseDesignTokens.caption))
              .foregroundStyle(PulseDesignTokens.muted)
          }
          if presentation.requiresConfiguration {
            Image(systemName: "gearshape")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(PulseDesignTokens.muted)
              .accessibilityHidden(true)
          } else {
            Image(systemName: "chevron.right")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(PulseDesignTokens.muted)
              .accessibilityHidden(true)
          }
        }
        UsageReadingStatus(presentation: presentation)
        UsageMetrics(presentation: presentation, showsDetails: false)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerLarge))
    }
    .buttonStyle(
      PulseProviderStatusStyle(
        paper: provider.dashboardPaper, radius: PulseDesignTokens.cornerLarge)
    )
    .help(description)
    .accessibilityHint(description)
    .accessibilityIdentifier(provider.overviewButtonID)
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      [provider.overviewButtonID: $0]
    }
  }
}

struct UsageView: View {
  @ObservedObject var usage: UsageController
  let provider: ProviderID
  var isConfigured = true
  var configurationError: String? = nil
  let onAddProvider: () -> Void

  var body: some View {
    let presentation = ProviderUsagePresentation(
      provider: provider, usage: usage, isConfigured: isConfigured,
      configurationError: configurationError)

    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          UsageProviderIcon(provider: provider)
          Text(
            LocalizedStringKey(provider == .codex || provider == .antigravity ? "Usage" : "Balance")
          )
          .font(.system(size: PulseDesignTokens.label, weight: .semibold))
          Spacer()
          if isConfigured {
            UsageRefreshButton(
              provider: provider, refreshStartedAt: usage.refreshStartedAt,
              showsRetry: presentation.showsRetry
            ) { usage.requestRefresh() }
          }
        }

        UsageReadingStatus(presentation: presentation, showsReason: true)
        UsageMetrics(presentation: presentation, showsDetails: true)
        UsageUpdatedAt(presentation: presentation)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .pulsePaper(provider.dashboardPaper)

      Button(
        LocalizedStringKey(
          presentation.requiresConfiguration ? "Open Providers settings" : "Manage connection"),
        action: onAddProvider
      )
      .buttonStyle(PulseActionButtonStyle())
      .accessibilityIdentifier("addProviderButton")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.system(size: PulseDesignTokens.footnote))
    .foregroundStyle(PulseDesignTokens.ink)
  }
}

private struct UsageReadingStatus: View {
  let presentation: ProviderUsagePresentation
  var showsReason = false

  var body: some View {
    if let status = presentation.statusText {
      VStack(alignment: .leading, spacing: 4) {
        if presentation.attentionPriority > 0 || presentation.status == .partial {
          Label(status, systemImage: "exclamationmark.circle")
            .foregroundStyle(
              presentation.attentionPriority > 1
                ? PulseDesignTokens.destructive : PulseDesignTokens.warning)
        } else {
          Text(status).foregroundStyle(PulseDesignTokens.muted)
        }

        if showsReason {
          if let reason = presentation.statusReason {
            reasonText(reason)
          }
          ForEach(Array(presentation.partialFailureReasons.enumerated()), id: \.offset) {
            _, reason in
            reasonText(reason)
          }
        }
      }
      .font(.system(size: PulseDesignTokens.caption))
      .fixedSize(horizontal: false, vertical: true)
      .pulseContentFeedback(status)
    }
  }

  private func reasonText(_ reason: String) -> some View {
    Text(reason).foregroundStyle(PulseDesignTokens.muted)
  }
}

private struct UsageMetrics: View {
  let presentation: ProviderUsagePresentation
  let showsDetails: Bool
  @Environment(\.locale) private var locale

  var body: some View {
    if !presentation.quotaWindows.isEmpty {
      VStack(alignment: .leading, spacing: showsDetails ? 8 : 6) {
        ForEach(Array(presentation.quotaWindows.enumerated()), id: \.offset) { index, window in
          if showsDetails && index > 0 { Divider() }
          UsageQuotaRow(window: window, showsProgress: showsDetails)
        }
      }
    }

    if presentation.isUnlimited {
      UsageValueRow(
        title: PulseLocalization.string("Balance"), value: PulseLocalization.string("Unlimited"))
    }

    ForEach(presentation.moneyReadings.filter { $0.kind == .balance || showsDetails }) { reading in
      UsageValueRow(title: title(for: reading), value: reading.value)
    }

    if showsDetails {
      if presentation.provider == .vip && !presentation.isUnlimited
        && presentation.balances.isEmpty && presentation.updatedAt != nil
      {
        UsageValueRow(
          title: PulseLocalization.string("Remaining"),
          value: PulseLocalization.string("Data unavailable"))
      }

      if let expiry = presentation.accessExpiry {
        UsageValueRow(
          title: PulseLocalization.string("Access until"),
          value: expiry.formatted(
            .dateTime.month(.abbreviated).day().year().hour().minute().locale(locale)))
      }
    }
  }

  private func title(for reading: ProviderUsagePresentation.MoneyReading) -> String {
    switch reading.kind {
    case .balance:
      if presentation.provider == .deepSeek {
        return PulseLocalization.format("Total balance (%@)", reading.currency)
      }
      return PulseLocalization.format(
        "%@ (%@)", PulseLocalization.string("Remaining"), reading.currency)
    case .allowance:
      return PulseLocalization.format(
        "%@ (%@)", PulseLocalization.string("Limit"), reading.currency)
    case .used:
      return PulseLocalization.format("%@ (%@)", PulseLocalization.string("Used"), reading.currency)
    }
  }
}

private struct UsageQuotaRow: View {
  let window: QuotaWindow
  let showsProgress: Bool
  @Environment(\.locale) private var locale
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    let percentage =
      window.percentageText.map { PulseLocalization.format("%@ left", $0) }
      ?? PulseLocalization.string("Remaining unavailable")
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(window.displayName)
          .font(.system(size: PulseDesignTokens.caption))
          .foregroundStyle(PulseDesignTokens.muted)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Text(percentage)
          .font(.system(size: PulseDesignTokens.footnote, weight: .semibold))
          .monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.trailing)
          .pulseContentFeedback(percentage)
      }

      if showsProgress, let fraction = window.remainingFraction {
        ProgressView(value: fraction)
          .progressViewStyle(.linear)
          .tint(fraction == 0 ? PulseDesignTokens.warning : PulseDesignTokens.accent)
          .animation(reduceMotion ? nil : PulseDesignTokens.feedbackAnimation, value: fraction)
          .accessibilityHidden(true)
      }

      Text(
        window.resetsAt.map {
          PulseLocalization.format(
            "Resets %@",
            $0.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale)))
        } ?? PulseLocalization.string("Reset time unavailable")
      )
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(PulseDesignTokens.muted)
      .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Keep the full number readable when either column cannot share a line.
private struct UsageValueRow: View {
  let title: String
  let value: String

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        label.fixedSize()
        Spacer(minLength: 8)
        reading.fixedSize()
      }
      VStack(alignment: .leading, spacing: 3) {
        label
        reading
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var label: some View {
    Text(title)
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(PulseDesignTokens.muted)
  }

  private var reading: some View {
    Text(value)
      .font(.system(size: PulseDesignTokens.footnote, weight: .semibold))
      .monospacedDigit()
      .pulseContentFeedback(value)
  }
}

private struct UsageUpdatedAt: View {
  let presentation: ProviderUsagePresentation
  @Environment(\.locale) private var locale

  var body: some View {
    if let updatedAt = presentation.updatedAt {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(
          PulseLocalization.format(
            "Updated %@",
            updatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
          )
        )
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if presentation.isRefreshing {
          Text("Refreshing…")
        }
      }
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(PulseDesignTokens.muted)
    }
  }
}

private struct UsageProviderIcon: View {
  let provider: ProviderID

  var body: some View {
    switch provider {
    case .codex: CodexProviderIcon(size: 16)
    case .vip: VIPProviderIcon(size: 16)
    case .deepSeek: DeepSeekProviderIcon(size: 16)
    case .antigravity: AntigravityProviderIcon(size: 16)
    }
  }
}

/// The label keeps its geometry while refreshing. The busy glyph owns its
/// delay, so completing or leaving this detail page cancels that delay.
private struct UsageRefreshButton: View {
  let provider: ProviderID
  let refreshStartedAt: ContinuousClock.Instant?
  let showsRetry: Bool
  let action: () -> Void

  var body: some View {
    let isRefreshing = refreshStartedAt != nil
    let title = PulseLocalization.string(
      isRefreshing ? provider.refreshingHelp : provider.refreshHelp)
    Button(action: action) {
      HStack(spacing: 6) {
        PulseBusyGlyph(isBusy: isRefreshing, startedAt: refreshStartedAt) {
          Image(systemName: "arrow.clockwise")
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        Text(LocalizedStringKey(showsRetry ? "Retry" : "Refresh"))
      }
      .frame(minWidth: 66)
    }
    .buttonStyle(PulseActionButtonStyle())
    .disabled(isRefreshing)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityIdentifier(provider.refreshButtonID)
  }
}

extension ProviderID {
  fileprivate var overviewButtonID: String {
    switch self {
    case .codex: "openUsageButton"
    case .vip: "openVIPUsageButton"
    case .deepSeek: "openDeepSeekUsageButton"
    case .antigravity: "openAntigravityUsageButton"
    }
  }

  fileprivate var refreshButtonID: String {
    switch self {
    case .codex: "refreshCodexUsageButton"
    case .vip: "refreshVIPUsageButton"
    case .deepSeek: "refreshDeepSeekUsageButton"
    case .antigravity: "refreshAntigravityUsageButton"
    }
  }

  fileprivate var refreshHelp: String {
    switch self {
    case .codex: "Refresh Codex usage"
    case .vip: "Refresh 88VIP balance"
    case .deepSeek: "Refresh DeepSeek balance"
    case .antigravity: "Refresh Gemini quotas"
    }
  }

  fileprivate var refreshingHelp: String {
    switch self {
    case .codex: "Refreshing Codex usage"
    case .vip: "Refreshing 88VIP balance"
    case .deepSeek: "Refreshing DeepSeek balance"
    case .antigravity: "Refreshing Gemini quotas"
    }
  }
}
