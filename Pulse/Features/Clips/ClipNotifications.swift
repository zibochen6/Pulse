import AppKit
import UserNotifications

final class ClipNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private let center = UNUserNotificationCenter.current()

  func register() {
    center.delegate = self
    let folder = UNNotificationAction(
      identifier: "folder", title: PulseLocalization.string("Open work folder"),
      options: [.foreground])
    let review = UNNotificationAction(
      identifier: "review", title: PulseLocalization.string("View review page"),
      options: [.foreground])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "clip-folder", actions: [folder], intentIdentifiers: []),
      UNNotificationCategory(
        identifier: "clip-review", actions: [folder, review], intentIdentifiers: []),
    ])
  }

  func requestPermission() {
    center.requestAuthorization(options: [.alert]) { _, _ in }
  }

  func deliver(_ state: ClipSnapshot) {
    let content = UNMutableNotificationContent()
    content.title = state.phase.title
    let platforms = state.platforms.map {
      PulseLocalization.string($0.platform) + " · " + PulseLocalization.string("clip." + $0.status)
    }
    content.body =
      ([state.source]
      + (platforms.isEmpty ? [PulseLocalization.string(state.detail ?? "")] : platforms))
      .filter { !$0.isEmpty }.joined(separator: "\n")
    if let folder = state.folderURL {
      content.userInfo["folder"] = folder.path
      content.categoryIdentifier = "clip-folder"
      if let review = state.reviewURL {
        content.userInfo["review"] = review.path
        content.categoryIdentifier = "clip-review"
      }
    }
    center.add(UNNotificationRequest(identifier: state.id, content: content, trigger: nil))
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let key = response.actionIdentifier == "review" ? "review" : "folder"
    let path = info[key] as? String
    Task { @MainActor in
      if let path { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
      completionHandler()
    }
  }
}
