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
  case general, providers, tasks, updates, about
  var id: String { rawValue }
  var title: String {
    switch self {
    case .general: PulseLocalization.string("General")
    case .providers: PulseLocalization.string("AI services")
    case .tasks: PulseLocalization.string("Lists & tags")
    case .updates: PulseLocalization.string("Updates")
    case .about: PulseLocalization.string("About")
    }
  }
  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .providers: "square.stack.3d.up"
    case .tasks: "tag"
    case .updates: "arrow.down.circle"
    case .about: "info.circle"
    }
  }
}

enum PopoverPage: Equatable {
  case home
  case usage(ProviderID)
  case tagManagement
}

/// Only the quick panel navigates here. Settings has its own window/session.
@MainActor
final class PopoverPageController: ObservableObject {
  @Published private(set) var page: PopoverPage = .home
  func showUsage(_ provider: ProviderID = .codex) { page = .usage(provider) }
  func showTagManagement() { page = .tagManagement }
  func showHome() { page = .home }
  func reset() { page = .home }
}
