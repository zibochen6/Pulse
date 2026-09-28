import ServiceManagement

enum LoginItemStatus: Equatable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
}

@MainActor
protocol LoginItemManaging {
  var status: LoginItemStatus { get }
  func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemService: LoginItemManaging {
  var status: LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .notRegistered: .notRegistered
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    @unknown default: .notFound
    }
  }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
