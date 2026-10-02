import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var vipUsage: UsageController
  @ObservedObject var vipConfiguration: VIPConfiguration
  @ObservedObject var tasks: DashboardTaskController
  @ObservedObject var localTasks: LocalTaskController
  @ObservedObject var taskSource: TaskSourceConfiguration
  @ObservedObject var dashboardPicker: DashboardFilePicker
  @StateObject private var localPresentation = LocalTaskPresentation()
  @StateObject private var dashboardPresentation = DashboardTaskPresentation()
  @ObservedObject var pages: PopoverPageController
  let onVIPCredentialsChanged: () -> Void
  let onSelectDashboardFile: () -> Void
  let onOpenDashboardFile: (DashboardTask) -> Bool
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
          vipConfiguration: vipConfiguration,
          tasks: tasks,
          localTasks: localTasks,
          taskSource: taskSource,
          dashboardPicker: dashboardPicker,
          destination: destination,
          onBack: { pages.showHome() },
          onVIPCredentialsChanged: onVIPCredentialsChanged,
          onSelectDashboardFile: onSelectDashboardFile,
          onQuit: onQuit,
          onTaskEditingChanged: onTaskEditingChanged
        )
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    // Cover the entire hosting surface with an adaptive opaque color.
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { dashboardPresentation.reconcileSelection(tasks.selectionGeneration) }
    .onChange(of: tasks.selectionGeneration) { generation in
      // Settings and the native picker can reselect a file while TasksView is
      // absent. Clear its old draft even if the new file cannot be read/parsed.
      dashboardPresentation.reconcileSelection(generation)
    }
    .onChange(of: taskSource.source) { source in
      if source == .apex { tasks.requestRefresh() }
    }
  }

  private var homeContent: some View {
    VStack(spacing: 0) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 7) {
          brand
          Spacer(minLength: 4)
          statusSummaries
          settingsButton
        }
        VStack(spacing: 6) {
          HStack(spacing: 7) {
            brand
            Spacer()
            settingsButton
          }
          HStack(spacing: 7) {
            Spacer()
            statusSummaries
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 7)

      Divider()

      Group {
        switch taskSource.source {
        case .local:
          LocalTasksView(
            controller: localTasks, presentation: localPresentation,
            onEditingChanged: onTaskEditingChanged)
        case .apex:
          TasksView(
            tasks: tasks,
            presentation: dashboardPresentation,
            onConfigure: { pages.showSettings(.tasks) },
            onOpenTask: onOpenDashboardFile,
            onUseBuiltInTasks: { taskSource.setSource(.local) },
            onEditingChanged: onTaskEditingChanged
          )
        }
      }
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
    HStack(spacing: 5) {
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
