import Foundation
import UserNotifications

final class DriveSyncNotificationController {
    static let shared = DriveSyncNotificationController()

    private let workingDirectoriesUnavailableNotificationName =
        "com.drivesync.app.notification.workingDirectoriesUnavailable"

    private let workingDirectoriesNotWritableNotificationName =
        "com.drivesync.app.notification.workingDirectoriesNotWritable"

    private let configurationProblemNotificationName =
        "com.drivesync.app.notification.configurationProblem"

    private let processLockFailedNotificationName =
        "com.drivesync.app.notification.processLockFailed"

    private let staleSyncNotificationName =
        "com.drivesync.app.notification.staleSync"

    private let systemExclusionsMissingNotificationName =
        "com.drivesync.app.notification.systemExclusionsMissing"

    private let userExclusionsMissingNotificationName =
        "com.drivesync.app.notification.userExclusionsMissing"

    private let accessDeniedNotificationName =
        "com.drivesync.app.notification.accessDenied"

    private let destinationFullNotificationName =
        "com.drivesync.app.notification.destinationFull"

    private let partialTransferNotificationName =
        "com.drivesync.app.notification.partialTransfer"

    private let syncFailedNotificationName =
        "com.drivesync.app.notification.syncFailed"

    private init() {

        registerDarwinNotification(
            named: workingDirectoriesUnavailableNotificationName
        ) { controller in
            controller.sendWorkingDirectoriesUnavailableNotification()
        }

        registerDarwinNotification(
            named: workingDirectoriesNotWritableNotificationName
        ) { controller in
            controller.sendWorkingDirectoriesNotWritableNotification()
        }

        registerDarwinNotification(
            named: configurationProblemNotificationName
        ) { controller in
            controller.sendConfigurationProblemNotification()
        }

        registerDarwinNotification(
            named: processLockFailedNotificationName
        ) { controller in
            controller.sendProcessLockFailedNotification()
        }

        registerDarwinNotification(
            named: staleSyncNotificationName
        ) { controller in
            controller.sendStaleSyncNotification()
        }

        registerDarwinNotification(
            named: systemExclusionsMissingNotificationName
        ) { controller in
            controller.sendSystemExclusionsMissingNotification()
        }

        registerDarwinNotification(
            named: userExclusionsMissingNotificationName
        ) { controller in
            controller.sendUserExclusionsMissingNotification()
        }

        registerDarwinNotification(
            named: accessDeniedNotificationName
        ) { controller in
            controller.sendAccessDeniedNotification()
        }

        registerDarwinNotification(
            named: destinationFullNotificationName
        ) { controller in
            controller.sendDestinationFullNotification()
        }

        registerDarwinNotification(
            named: partialTransferNotificationName
        ) { controller in
            controller.sendPartialTransferNotification()
        }

        registerDarwinNotification(
            named: syncFailedNotificationName
        ) { controller in
            controller.sendSyncFailedNotification()
        }
    }

    private func registerDarwinNotification(
        named name: String,
        handler: @escaping (DriveSyncNotificationController) -> Void
    ) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        let handlerBox = DarwinNotificationHandlerBox(
            controller: self,
            handler: handler
        )

        let observer = Unmanaged.passRetained(handlerBox).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else {
                    return
                }

                let handlerBox =
                    Unmanaged<DarwinNotificationHandlerBox>
                        .fromOpaque(observer)
                        .takeUnretainedValue()

                handlerBox.handler(handlerBox.controller)
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    func send(
        title: String,
        message: String,
        sound: Bool = true,
        completion: ((Error?) -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()

        content.title = title
        content.body = message

        if sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            completion?(error)
        }
    }

    func sendWorkingDirectoriesUnavailableNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync couldn't start",
            message: "DriveSync couldn't create the files it needs to run. Check that DriveSync has access to your user Library folder, then try again.",
            sound: true,
            completion: completion
        )
    }

    func sendWorkingDirectoriesNotWritableNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync couldn't start",
            message: "DriveSync can't write to the files it needs to run. Check that DriveSync has write access to your user Library folder, then try again.",
            sound: true,
            completion: completion
        )
    }

    func sendConfigurationProblemNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync configuration problem",
            message: "DriveSync couldn't start because part of its configuration is missing or unavailable. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }

    func sendProcessLockFailedNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync encountered a problem",
            message: "DriveSync couldn't establish its process lock. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }

    func sendStaleSyncNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        let stateDirectory =
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("DriveSync")
                .appendingPathComponent("state")

        let lastSuccessURL =
            stateDirectory.appendingPathComponent("last-success")

        var message =
            "A successful sync hasn't completed recently. Open DriveSync to check the status."

        if let attributes = try? FileManager.default.attributesOfItem(
            atPath: lastSuccessURL.path
        ),
           let modificationDate = attributes[.modificationDate] as? Date {

            let elapsedSeconds =
                Date().timeIntervalSince(modificationDate)

            let elapsedDays =
                max(0, Int(elapsedSeconds / 86_400))

            if elapsedDays == 1 {
                message = "Last successful sync was 1 day ago."
            } else {
                message = "Last successful sync was \(elapsedDays) days ago."
            }
        }

        send(
            title: "DriveSync backup is stale",
            message: message,
            sound: true,
            completion: completion
        )
    }

    func sendSystemExclusionsMissingNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync installation problem",
            message: "DriveSync's built-in exclusions file is missing. Reinstall DriveSync to repair the installation.",
            sound: true,
            completion: completion
        )
    }

    func sendUserExclusionsMissingNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync configuration problem",
            message: "Your user exclusions file is missing. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }

    func sendAccessDeniedNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync can't access a backup location",
            message: "DriveSync was denied access while syncing. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }

    func sendDestinationFullNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync couldn't finish",
            message: "The destination is full. Free up space and try again.",
            sound: true,
            completion: completion
        )
    }

    func sendPartialTransferNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync completed with issues",
            message: "Some items couldn't be transferred. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }

    func sendSyncFailedNotification(
        completion: ((Error?) -> Void)? = nil
    ) {
        send(
            title: "DriveSync couldn't finish",
            message: "The backup failed unexpectedly. Check the Issues window for details.",
            sound: true,
            completion: completion
        )
    }
}

private final class DarwinNotificationHandlerBox {
    let controller: DriveSyncNotificationController
    let handler: (DriveSyncNotificationController) -> Void

    init(
        controller: DriveSyncNotificationController,
        handler: @escaping (DriveSyncNotificationController) -> Void
    ) {
        self.controller = controller
        self.handler = handler
    }
}
