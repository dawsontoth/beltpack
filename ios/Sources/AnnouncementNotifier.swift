import Foundation
import OSLog
import UserNotifications

/// Delivers announcements as local notifications.
///
/// An in-app banner is invisible to the person who most needs it: a camera
/// operator with the phone in a pocket and the screen off. A notification
/// reaches the lock screen, vibrates, and stays in Notification Centre until
/// it is dismissed.
@MainActor
final class AnnouncementNotifier: NSObject, ObservableObject {
    @Published private(set) var isAuthorised = false

    private let centre = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "org.beltpack", category: "notify")

    override init() {
        super.init()
        centre.delegate = self
    }

    /// Asked for once the phone is on comms, rather than at launch: the
    /// permission makes sense to somebody who has just joined a channel, and
    /// makes none to somebody who has opened the app to type a server address.
    func requestAuthorisation() async {
        do {
            isAuthorised = try await centre.requestAuthorization(options: [.alert, .sound])
            let settings = await centre.notificationSettings()
            log.notice("notification auth=\(self.isAuthorised, privacy: .public) status=\(settings.authorizationStatus.rawValue, privacy: .public) alert=\(settings.alertSetting.rawValue, privacy: .public)")
        } catch {
            log.error("notification permission failed: \(error.localizedDescription, privacy: .public)")
            isAuthorised = false
        }
    }

    func post(_ announcement: Announcement) {
        log.notice("posting announcement, authorised=\(self.isAuthorised, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = announcement.text
        content.body = announcement.sender.isEmpty ? "Announcement" : announcement.sender
        content.sound = .default
        // Not .timeSensitive: that level needs the time-sensitive
        // entitlement, and without it the request can be rejected outright
        // rather than quietly downgraded.
        content.interruptionLevel = .active

        // Identified by the announcement, so the same cue arriving twice does
        // not stack up two copies on the lock screen.
        let request = UNNotificationRequest(
            identifier: announcement.id.uuidString,
            content: content,
            trigger: nil,
        )
        centre.add(request) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.log.error("could not post: \(error.localizedDescription, privacy: .public)")
                } else {
                    self?.log.notice("posted announcement notification")
                }
            }
        }
    }

    /// Clears what has already been delivered. Pending requests go too, though
    /// there are none: announcements fire immediately rather than on a trigger.
    func clearAll() {
        centre.removeAllDeliveredNotifications()
        centre.removeAllPendingNotificationRequests()
    }
}

extension AnnouncementNotifier: UNUserNotificationCenterDelegate {
    /// iOS suppresses notifications while the app is in front. For comms that
    /// is wrong: somebody staring at the talk button still needs to see a cue.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
