import AppKit
import UserNotifications

final class AppDelegate: NSObject,
                         NSApplicationDelegate,
                         UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        _ = DriveSyncNotificationController.shared
        registerLoginItemIfNeeded()

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
    
    private func registerLoginItemIfNeeded() {
        let key = "loginItemConfigured"

        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        do {
            let controller = DriveSyncLoginItemController()
            try controller.setEnabled(true)

            if controller.isEnabled {
                UserDefaults.standard.set(true, forKey: key)
            }
        } catch {
            print("Could not register login item: \(error.localizedDescription)")
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
