import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var tasks: DashboardTaskController
  @ObservedObject var pages: PopoverPageController
  let onVIPCredentialsChanged: () -> Void
  let onSelectDashboardFile: () -> Void
  let onOpenDashboardFile: (DashboardTask) -> Bool
  let onQuit: () -> Void

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
          vipConfiguration: vipConfiguration,
          tasks: tasks,
          destination: destination,
          onBack: { pages.showHome() },
          onVIPCredentialsChanged: onVIPCredentialsChanged,
          onSelectDashboardFile: onSelectDashboardFile,
          onQuit: onQuit
        )
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // Cover the entire hosting surface with an adaptive opaque color.
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          brand
          Spacer(minLength: 4)
          statusSummaries
          settingsButton
        }
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            brand
            Spacer()
            settingsButton
          }
          HStack(spacing: 8) {
            Spacer()
            statusSummaries
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      TasksView(
        tasks: tasks,
        onConfigure: { pages.showSettings(.tasks) },
        onOpenTask: onOpenDashboardFile
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
        .buttonStyle(.borderless)
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
          onAddProvider: { pages.showSettings(.providers) }
        )
          .padding(16)
      }
      .accessibilityIdentifier("usageDetailRegion")
    }
  }

  private var brand: some View {
    HStack(spacing: 8) {
      Image(systemName: "waveform.path")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      Text("Pulse")
        .font(.system(size: 16, weight: .semibold))
    }
  }

  private var statusSummaries: some View {
    HStack(spacing: 6) {
      AIStatusSummary(state: usage.state, onOpenUsage: { pages.showUsage() })
      VIPStatusSummary(state: vipUsage.state, onOpenUsage: { pages.showUsage() })
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var settingsButton: some View {
    Button {
      pages.showSettings()
    } label: {
      Image(systemName: "gearshape")
        .font(.system(size: 15, weight: .medium))
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.borderless)
    .help("Settings")
    .accessibilityLabel("Open Settings")
    .accessibilityIdentifier("openSettingsButton")
  }

}
