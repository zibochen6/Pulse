import AppKit
import SwiftUI

struct HomeView: View {
  static let popoverSize = NSSize(width: 360, height: 510)

  @ObservedObject var config: AppConfig
  @ObservedObject var usage: UsageController
  @ObservedObject var pages: PopoverPageController
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
          destination: destination,
          onBack: { pages.showHome() },
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
      HStack(spacing: 8) {
        Image(systemName: "waveform.path")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.tint)
          .frame(width: 28, height: 28)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        Text("Pulse")
          .font(.system(size: 16, weight: .semibold))
        Spacer(minLength: 4)
        ScrollView(.horizontal, showsIndicators: false) {
          AIStatusSummary(state: usage.state, onOpenUsage: { pages.showUsage() })
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 174, alignment: .trailing)
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
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      TasksView(onConnect: { pages.showSettings(.tasks) })
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
        UsageView(usage: usage, onAddProvider: { pages.showSettings(.providers) })
          .padding(16)
      }
      .accessibilityIdentifier("usageDetailRegion")
    }
  }
}
