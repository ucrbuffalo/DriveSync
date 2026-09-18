import Foundation
import Darwin

final class DriveSyncUninstallHelper:
    NSObject,
    DriveSyncUninstallHelperProtocol
{
    private let clientPID: pid_t
    private let fileManager = FileManager.default

    private let driveSyncAppURL = URL(
        fileURLWithPath: "/Applications/DriveSync/DriveSync.app"
    )

    private let uninstallerURL = URL(
        fileURLWithPath: "/Applications/DriveSync/DriveSync Uninstaller.app"
    )

    private let installDirectoryURL = URL(
        fileURLWithPath: "/Applications/DriveSync"
    )

    private let launchDaemonURL = URL(
        fileURLWithPath:
            "/Library/LaunchDaemons/com.drivesync.uninstall-helper.plist"
    )

    private let helperExecutableURL = URL(
        fileURLWithPath:
            "/Library/PrivilegedHelperTools/com.drivesync.uninstall-helper"
    )

    init(clientPID: pid_t) {
        self.clientPID = clientPID
    }
    
    func verifyAvailability(
        reply: @escaping (Bool) -> Void
    ) {
        reply(true)
    }
    
    func removeDriveSyncApplication(
        reply: @escaping (Bool, String?) -> Void
    ) {
        guard fileManager.fileExists(atPath: driveSyncAppURL.path) else {
            reply(
                false,
                "DriveSync.app was not found at the expected installation location."
            )
            return
        }

        do {
            try fileManager.removeItem(at: driveSyncAppURL)
            reply(true, nil)
        } catch {
            reply(
                false,
                "DriveSync.app could not be removed: \(error.localizedDescription)"
            )
        }
    }

    func finishUninstall(
        reply: @escaping (Bool, String?) -> Void
    ) {
        // Tell the Uninstaller that the final cleanup request
        // has been accepted before it terminates itself.
        reply(true, nil)

        let pid = clientPID

        DispatchQueue.global(qos: .utility).async { [self] in
            waitForClientToExit(pid)

            removeIfPresent(uninstallerURL)
            removeIfPresent(launchDaemonURL)
            removeIfPresent(helperExecutableURL)

            removeInstallDirectoryIfEmpty()

            unloadSelf()
        }
    }

    private func waitForClientToExit(_ pid: pid_t) {
        let timeout = Date().addingTimeInterval(10)

        while Date() < timeout {
            if kill(pid, 0) != 0 && errno == ESRCH {
                return
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func removeIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    private func removeInstallDirectoryIfEmpty() {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: installDirectoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        // Finder may leave this behind after browsing the folder.
        for item in contents where item.lastPathComponent == ".DS_Store" {
            try? fileManager.removeItem(at: item)
        }

        guard
            let remainingContents = try? fileManager.contentsOfDirectory(
                at: installDirectoryURL,
                includingPropertiesForKeys: nil
            ),
            remainingContents.isEmpty
        else {
            return
        }

        try? fileManager.removeItem(at: installDirectoryURL)
    }

    private func unloadSelf() {
        let process = Process()

        process.executableURL = URL(
            fileURLWithPath: "/bin/launchctl"
        )

        process.arguments = [
            "bootout",
            "system/com.drivesync.uninstall-helper"
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
    }
}

final class ListenerDelegate:
    NSObject,
    NSXPCListenerDelegate
{
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.setCodeSigningRequirement(
            """
            identifier "com.drivesync.app.uninstaller" and \
            anchor apple generic and \
            certificate leaf[subject.OU] = "JBZ7JH4SX5"
            """
        )

        let helper = DriveSyncUninstallHelper(
            clientPID: newConnection.processIdentifier
        )

        newConnection.exportedInterface = NSXPCInterface(
            with: DriveSyncUninstallHelperProtocol.self
        )

        newConnection.exportedObject = helper
        newConnection.resume()

        return true
    }
}

let delegate = ListenerDelegate()

let listener = NSXPCListener(
    machServiceName: "com.drivesync.uninstall-helper"
)

listener.delegate = delegate
listener.resume()

RunLoop.current.run()
