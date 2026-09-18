import AppKit
import UserNotifications

final class AppDelegate: NSObject,
                         NSApplicationDelegate,
                         UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        _ = DriveSyncNotificationController.shared

        let notificationCenter =
            UNUserNotificationCenter.current()

        notificationCenter.delegate = self

        notificationCenter.requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error {
                print(
                    "Notification authorization failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        sender.setActivationPolicy(.accessory)

        return false
    }

    static func activateDriveSync() {
        let app = NSApplication.shared

        app.setActivationPolicy(.regular)

        NSRunningApplication.current.activate(
            options: [.activateAllWindows]
        )
    }
}
