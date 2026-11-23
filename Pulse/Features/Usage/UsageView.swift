import SwiftUI

struct UsageView: View {
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var antigravityUsage: UsageController
  let onAddProvider: () -> Void
  var provider: ProviderID? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if provider == nil || provider == .codex { codexContent }
      if provider == nil { Divider() }
      if provider == nil || provider == .vip { vipContent }
      if provider == nil { Divider() }
      if provider == nil || provider == .deepSeek { deepSeekContent }
      if provider == .antigravity { antigravityContent }
      Divider()
      Button("Manage AI services", action: onAddProvider)
        .buttonStyle(PulseActionButtonStyle())
        .accessibilityIdentifier("addProviderButton")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.system(size: 13))
  }

  private var codexContent: some View {
    quotaContent(
      usage: usage, provider: .codex, refreshTitle: "Refresh Codex usage",
      refreshingTitle: "Refreshing Codex usage", identifier: "refreshCodexUsageButton"
    ) { CodexProviderIcon(size: 16) }
  }

  private var antigravityContent: some View {
    quotaContent(
      usage: antigravityUsage, provider: .antigravity, refreshTitle: "Refresh Gemini quotas",
      refreshingTitle: "Refreshing Gemini quotas", identifier: "refreshAntigravityUsageButton"
    ) { GeminiProviderIcon(size: 16) }
  }

  private func quotaContent<Icon: View>(
    usage: UsageController, provider: ProviderID, refreshTitle: String, refreshingTitle: String,
    identifier: String, @ViewBuilder icon: () -> Icon
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        icon()
        Text(provider.name)
          .font(.subheadline.weight(.semibold))
        Spacer()
        UsageRefreshButton(
          refreshStartedAt: usage.refreshStartedAt, refreshTitle: refreshTitle,
          refreshingTitle: refreshingTitle, identifier: identifier
        ) { usage.requestRefresh() }
      }

      switch usage.state {
      case .loading:
        Text("Checking usage…")
          .foregroundStyle(.secondary)
      case .unavailable(let message):
        Label(message, systemImage: "minus.circle")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      case .success(let snapshot):
        ForEach(Array(snapshot.quotaWindows.enumerated()), id: \.offset) { index, window in
          if index > 0 { Divider() }
          quotaRow(window)
        }
        updated(at: snapshot.fetchedAt)
      }
    }
  }

  private var vipContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        VIPProviderIcon(size: 16)
        Text("88VIP")
          .font(.subheadline.weight(.semibold))
        Spacer()
        UsageRefreshButton(
          refreshStartedAt: vipUsage.refreshStartedAt, refreshTitle: "Refresh 88VIP balance",
          refreshingTitle: "Refreshing 88VIP balance", identifier: "refreshVIPUsageButton"
        ) { vipUsage.requestRefresh() }
      }

      switch vipUsage.state {
      case .loading:
        Text("Checking balance…")
          .foregroundStyle(.secondary)
      case .unavailable(let message):
        Label(message, systemImage: "minus.circle")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      case .success(let snapshot):
        if snapshot.metrics.contains(.unlimited) {
          detailRow("Balance", value: PulseLocalization.string("Unlimited"))
        } else {
          if let allowance = amount(for: .allowance, in: snapshot) {
            detailRow(
              "Limit", value: MoneyFormatter.string(allowance.amount, currency: allowance.currency))
          }
          if let used = amount(for: .usage, in: snapshot) {
            detailRow("Used", value: MoneyFormatter.string(used.amount, currency: used.currency))
          }
          if let remaining = amount(for: .balance, in: snapshot) {
            detailRow(
              "Remaining",
              value: MoneyFormatter.string(remaining.amount, currency: remaining.currency))
          } else {
            detailRow("Remaining", value: "--")
          }
        }
        if let expiry = expiry(in: snapshot) {
          detailRow("Access until", value: expiry.formatted(date: .abbreviated, time: .shortened))
        }
        ForEach(Array(unavailableMessages(in: snapshot).enumerated()), id: \.offset) { _, message in
          Label(message, systemImage: "minus.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        updated(at: snapshot.fetchedAt)
      }
    }
  }

  private var deepSeekContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        DeepSeekProviderIcon(size: 16)
        Text("DeepSeek").font(.subheadline.weight(.semibold))
        Spacer()
        UsageRefreshButton(
          refreshStartedAt: deepSeekUsage.refreshStartedAt,
          refreshTitle: "Refresh DeepSeek balance",
          refreshingTitle: "Refreshing DeepSeek balance", identifier: "refreshDeepSeekUsageButton"
        ) { deepSeekUsage.requestRefresh() }
      }
      switch deepSeekUsage.state {
      case .loading:
        Text("Checking balance…").foregroundStyle(.secondary)
      case .unavailable(let message):
        Label(message, systemImage: "minus.circle")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Providers settings", action: onAddProvider)
          .buttonStyle(.borderless)
          .font(.caption.weight(.medium))
          .accessibilityIdentifier("configureDeepSeekButton")
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      case .success(let snapshot):
        ForEach(snapshot.balances, id: \.currency) { balance in
          detailRow(
            PulseLocalization.format("Total balance (%@)", balance.currency),
            value: MoneyFormatter.string(balance.amount, currency: balance.currency))
        }
        updated(at: snapshot.fetchedAt)
      }
    }
  }

  private func quotaRow(_ window: QuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(window.displayName)
          .font(.system(size: PulseDesignTokens.caption))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Text(window.remainingPercent.map { "\($0)%" } ?? "--")
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .layoutPriority(1)
      }
      Text(
        window.resetsAt.map {
          PulseLocalization.format("Resets %@", $0.formatted(date: .abbreviated, time: .shortened))
        }
          ?? PulseLocalization.string("Reset time unavailable")
      )
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Label left, value right. The value is the number that matters, so it is
  /// semibold monospaced while the label stays a quiet caption; both are free
  /// to wrap instead of clipping digits when a balance runs long.
  private func detailRow(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(PulseLocalization.string(title))
        .font(.system(size: PulseDesignTokens.caption))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: PulseDesignTokens.footnote, weight: .semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
  }

  private func updated(at date: Date) -> some View {
    Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
      .font(.system(size: 12))
      .foregroundStyle(.tertiary)
  }

  private enum VIPAmountKind {
    case allowance
    case usage
    case balance
  }

  private func amount(
    for kind: VIPAmountKind,
    in snapshot: UsageSnapshot
  ) -> (amount: Decimal, currency: String)? {
    for metric in snapshot.metrics {
      switch (kind, metric) {
      case (.allowance, .allowance(let amount, let currency)),
        (.usage, .usage(let amount, let currency)),
        (.balance, .balance(let amount, let currency)):
        return (amount, currency)
      default:
        continue
      }
    }
    return nil
  }

  private func expiry(in snapshot: UsageSnapshot) -> Date? {
    for metric in snapshot.metrics {
      if case .expiresAt(let date) = metric { return date }
    }
    return nil
  }

  private func unavailableMessages(in snapshot: UsageSnapshot) -> [String] {
    snapshot.metrics.compactMap {
      guard case .unavailable(let reason) = $0 else { return nil }
      return reason
    }
  }
}

/// The label keeps its geometry while refreshing. The busy glyph owns its
/// delay, so completing or leaving this detail page cancels that delay.
private struct UsageRefreshButton: View {
  let refreshStartedAt: ContinuousClock.Instant?
  let refreshTitle: String
  let refreshingTitle: String
  let identifier: String
  let action: () -> Void

  var body: some View {
    let isRefreshing = refreshStartedAt != nil
    let title = PulseLocalization.string(isRefreshing ? refreshingTitle : refreshTitle)
    Button(action: action) {
      HStack(spacing: 6) {
        Group {
          if let refreshStartedAt {
            BusyGlyph(startedAt: refreshStartedAt).id(refreshStartedAt)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        Text("Refresh")
      }
      .font(.system(size: 12, weight: .medium))
    }
    .buttonStyle(.borderless)
    .disabled(isRefreshing)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityIdentifier(identifier)
  }

  private struct BusyGlyph: View {
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var showsBusyIndicator: Bool
    private let deadline: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant) {
      let deadline = startedAt.advanced(by: .milliseconds(150))
      self.deadline = deadline
      _showsBusyIndicator = State(initialValue: deadline <= .now)
    }

    var body: some View {
      Group {
        if !showsBusyIndicator {
          Image(systemName: "arrow.clockwise")
        } else if reduceMotion {
          Image(systemName: "clock")
        } else {
          ProgressView().controlSize(.mini)
        }
      }
      .task {
        guard !showsBusyIndicator else { return }
        do {
          try await Task.sleep(until: deadline, clock: .continuous)
          try Task.checkCancellation()
          showsBusyIndicator = true
        } catch { return }
      }
    }
  }
}
