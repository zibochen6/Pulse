import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 380)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var deepSeekUsage: UsageController
  @ObservedObject var deepSeekConfiguration: DeepSeekConfiguration
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var updates: UpdateController
  @StateObject private var localPresentation = LocalTaskPresentation()
  /// "Later" hides the ready banner for this run only; the update stays staged
  /// and is still installed when Pulse quits.
  @State private var hidesUpdateBanner = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var pages: PopoverPageController
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }

  var body: some View {
    // Pages swap inside a fixed frame: only the incoming page animates, and it
    // arrives from the direction of travel (subpages from the right, Home from
    // the left). The outgoing page leaves with `.identity` on purpose — a page
    // that lingers through a removal transition keeps its AppKit field editor
    // alive, which is exactly how a saved draft gets typed back into a field
    // that should already be gone.
    ZStack {
      switch pages.page {
      case .home:
        homeContent.transition(pageTransition(fromRight: false))
      case .usage:
        usageContent.transition(pageTransition(fromRight: true))
      case .settings(let destination):
        SettingsView(
          config: config,
          deepSeekConfiguration: deepSeekConfiguration,
          vipConfiguration: vipConfiguration,
          localTasks: localTasks,
          updates: updates,
          destination: destination,
          onBack: { pages.showHome() },
          onDeepSeekCredentialsChanged: onDeepSeekCredentialsChanged,
          onVIPCredentialsChanged: onVIPCredentialsChanged,
          onQuit: onQuit,
          onTaskEditingChanged: onTaskEditingChanged
        )
        .transition(pageTransition(fromRight: true))
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // Cover the entire hosting surface with an adaptive opaque color, and keep
    // a mid-transition page from painting past the popover's fixed bounds.
    .background(Color(nsColor: .windowBackgroundColor))
    .clipped()
    // Scoped to the page value, never to the root view: typing a task while a
    // page is settled cannot start a transition.
    .animation(
      reduceMotion ? nil : PulseDesignTokens.pageTransitionAnimation, value: pages.page)
  }

  /// Reduce Motion keeps the state change and drops only the movement: the
  /// incoming page fades, nothing slides, nothing scales.
  private func pageTransition(fromRight: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .asymmetric(
      insertion: .opacity.combined(with: .offset(x: fromRight ? 18 : -18)),
      removal: .identity)
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      toolbar
      statusStrip
      Divider()

      if let release = updates.stagedRelease, !hidesUpdateBanner {
        PulseUpdateBanner(
          version: release.version.description,
          onRestart: { updates.restartToUpdate() },
          onDismiss: { hidesUpdateBanner = true }
        )
        Divider()
      }

      LocalTasksView(
        controller: localTasks, presentation: localPresentation,
        onEditingChanged: onTaskEditingChanged
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("tasksRegion")
    }
    .animation(
      reduceMotion ? nil : PulseDesignTokens.insertionAnimation,
      value: updates.stagedRelease != nil && !hidesUpdateBanner)
  }

  /// Brand on the left, Settings on the right. The gear now lives in this row
  /// instead of a pinned overlay: the row is stable across every Home state
  /// (composer open, tag entry, empty list), so it cannot be displaced while
  /// still keeping Settings reachable during editing.
  private var toolbar: some View {
    HStack(spacing: PulseDesignTokens.gap) {
      brand
      Spacer(minLength: 0)
      settingsButton
    }
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.top, 6)
    .padding(.bottom, 4)
  }

  /// Full-width usage strip on its own row. Separating it from the brand keeps
  /// the header's height predictable: it no longer re-flows between "one row"
  /// and "brand above statuses" when a balance grows.
  private var statusStrip: some View {
    statusSummaries
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.bottom, 6)
  }

  private var usageContent: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          pages.showHome()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PulseIconButtonStyle())
        .help("Back to Home")
        .accessibilityLabel("Back to Home")
        .accessibilityIdentifier("backToHomeButton")
        Text("Usage")
          .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
        Spacer()
      }
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.top, 6)
      .padding(.bottom, 4)

      Divider()

      ScrollView {
        UsageView(
          usage: usage,
          vipUsage: vipUsage,
          deepSeekUsage: deepSeekUsage,
          onAddProvider: { pages.showSettings(.providers) }
        )
        .padding(PulseDesignTokens.contentInset)
      }
      .accessibilityIdentifier("usageDetailRegion")
    }
  }

  private var brand: some View {
    HStack(spacing: 6) {
      Image(systemName: "waveform.path")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: PulseDesignTokens.brandMarkSize, height: PulseDesignTokens.brandMarkSize)
        .background(
          Color.accentColor.opacity(0.12),
          in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
      Text("Pulse")
        .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
    }
  }

  private var statusSummaries: some View {
    ProviderStatusLayout {
      AIStatusSummary(
        state: usage.state,
        onOpenUsage: {
          usage.requestRefresh()
          pages.showUsage()
        })
      VIPStatusSummary(
        state: vipUsage.state,
        onOpenUsage: {
          vipUsage.requestRefresh()
          pages.showUsage()
        })
      DeepSeekStatusSummary(
        state: deepSeekUsage.state,
        onOpenUsage: {
          deepSeekUsage.requestRefresh()
          pages.showUsage()
        })
    }
  }

  /// Settings stays reachable while a composer is open: pointer departure is
  /// already suspended during editing, so the gear must not disappear when the
  /// tags area is replaced by the inline composer.
  private var settingsButton: some View {
    Button {
      pages.showSettings()
    } label: {
      Image(systemName: "gearshape")
        .font(.system(size: 15, weight: .medium))
        .frame(width: 28, height: 28)
    }
    .buttonStyle(PulseIconButtonStyle())
    .help("Settings")
    .accessibilityLabel("Open Settings")
    .accessibilityIdentifier("openSettingsButton")
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["openSettingsButton": $0]
    }
  }

}
