import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

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
  @ObservedObject var pages: PopoverPageController
  let onDeepSeekCredentialsChanged: () -> Void
  let onVIPCredentialsChanged: () -> Void
  let onQuit: () -> Void
  var onTaskEditingChanged: (Bool) -> Void = { _ in }

  var body: some View {
    Group {
      switch pages.page {
      case .home:
        homeContent
      case .usage:
        usageContent
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
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // Cover the entire hosting surface with an adaptive opaque color.
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .topTrailing) {
      // The gear is pinned over the header rather than laid out inside it, so
      // the composer can replace the tag row without taking Settings with it.
      // Usage and Settings do not repeat it: those pages already sit behind it.
      if case .home = pages.page {
        settingsButton
          .padding(.top, 4)
          .padding(.trailing, 14)
      }
    }
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 7) {
          brand.fixedSize()
          statusSummaries.fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: 6) {
          brand
          statusSummaries
        }
      }
      .padding(.leading, 14)
      .padding(.trailing, 48)
      .padding(.vertical, 7)

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
          .font(.system(size: 16, weight: .semibold))
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 10)

      Divider()

      ScrollView {
        UsageView(
          usage: usage,
          vipUsage: vipUsage,
          deepSeekUsage: deepSeekUsage,
          onAddProvider: { pages.showSettings(.providers) }
        )
        .padding(16)
      }
      .accessibilityIdentifier("usageDetailRegion")
    }
  }

  private var brand: some View {
    HStack(spacing: 7) {
      Image(systemName: "waveform.path")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 26, height: 26)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
      Text("Pulse")
        .font(.system(size: 19, weight: .semibold))
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
