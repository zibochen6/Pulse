import Combine

enum SettingsDestination: Hashable {
  case general
  case providers
  case tasks
  case about
}

enum PopoverPage: Equatable {
  case home
  case usage
  case settings(SettingsDestination)
}

/// One page selection for the single popover; closing it always returns to Home.
@MainActor
final class PopoverPageController: ObservableObject {
  @Published private(set) var page: PopoverPage = .home

  func showUsage() { page = .usage }

  func showSettings(_ destination: SettingsDestination = .general) {
    page = .settings(destination)
  }

  func showHome() { page = .home }

  func reset() { page = .home }
}
