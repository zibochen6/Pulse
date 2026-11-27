import Combine

enum ProviderID: String, CaseIterable, Identifiable {
  case codex
  case vip = "88vip"
  case deepSeek = "deepseek"
  case antigravity

  var id: String { rawValue }
  var name: String {
    switch self {
    case .codex: "Codex"
    case .vip: "88VIP"
    case .deepSeek: "DeepSeek"
    case .antigravity: "Gemini"
    }
  }
}

enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
  case general, providers, tasks, clips, updates, about
  var id: String { rawValue }
  var title: String {
    switch self {
    case .clips: PulseLocalization.string("Recording edits")
    case .general: PulseLocalization.string("General")
    case .providers: PulseLocalization.string("AI services")
    case .tasks: PulseLocalization.string("Tasks")
    case .updates: PulseLocalization.string("Updates")
    case .about: PulseLocalization.string("About")
    }
  }
  var symbol: String {
    switch self {
    case .clips: "scissors"
    case .general: "slider.horizontal.3"
    case .providers: "square.stack.3d.up"
    case .tasks: "checklist"
    case .updates: "arrow.down.circle"
    case .about: "info.circle"
    }
  }
}

enum PopoverPage: Equatable {
  case home
  case clipTask
  case usage(ProviderID)
  case tagManagement
  case quickCopy
}

/// Only the quick panel navigates here. Settings has its own window/session.
@MainActor
final class PopoverPageController: ObservableObject {
  @Published private(set) var page: PopoverPage = .home
  func showUsage(_ provider: ProviderID = .codex) { navigate(to: .usage(provider)) }
  func showTagManagement() { navigate(to: .tagManagement) }
  func showQuickCopy() { navigate(to: .quickCopy) }
  func showClipTask() { navigate(to: .clipTask) }
  func showHome() { navigate(to: .home) }
  func reset() { showHome() }

  private func navigate(to destination: PopoverPage) {
    guard page != destination else { return }
    page = destination
  }
}
