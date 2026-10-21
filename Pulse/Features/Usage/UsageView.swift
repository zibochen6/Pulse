import SwiftUI

struct UsageView: View {
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  let onAddProvider: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      codexContent

      Divider()

      vipContent

      Divider()
      deepSeekContent

      Divider()
      HStack(spacing: 8) {
        Text("More AI providers are coming soon")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Button("Add Provider", action: onAddProvider)
          .buttonStyle(.borderless)
          .font(.caption.weight(.medium))
          .accessibilityIdentifier("addProviderButton")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var codexContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        codexIcon
        Text("Codex")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button {
          usage.requestRefresh()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .disabled(usage.isRefreshing)
        .help(usage.isRefreshing ? "Refreshing Codex usage" : "Refresh Codex usage")
        .accessibilityLabel("Refresh Codex usage")
        .accessibilityIdentifier("refreshCodexUsageButton")
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
        Button {
          vipUsage.requestRefresh()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .disabled(vipUsage.isRefreshing)
        .help(vipUsage.isRefreshing ? "Refreshing 88VIP balance" : "Refresh 88VIP balance")
        .accessibilityLabel("Refresh 88VIP balance")
        .accessibilityIdentifier("refreshVIPUsageButton")
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
          detailRow("Balance", value: "Unlimited")
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
        Button {
          deepSeekUsage.requestRefresh()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .disabled(deepSeekUsage.isRefreshing)
        .help(
          deepSeekUsage.isRefreshing ? "Refreshing DeepSeek balance" : "Refresh DeepSeek balance"
        )
        .accessibilityLabel("Refresh DeepSeek balance")
        .accessibilityIdentifier("refreshDeepSeekUsageButton")
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
            "Total balance (\(balance.currency))",
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
        window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
          ?? "Reset time unavailable"
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
      Text(title)
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
      .font(.caption2)
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

  private var codexIcon: some View { CodexProviderIcon(size: 16) }
}
