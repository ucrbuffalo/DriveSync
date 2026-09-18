import Foundation
import AppKit

final class DriveSyncUninstallController {
    private let fileManager = FileManager.default
    
    private var driveSyncAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("DriveSync.app")
    }
    
    private var runningPIDURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
            .appendingPathComponent("state")
            .appendingPathComponent("running.lock")
            .appendingPathComponent("pid")
    }

    private var driveSyncScriptURL: URL {
        driveSyncAppURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("DriveSync.sh")
    }
    
    private var appSupportURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
    }

    private var stateDirectoryURL: URL {
        appSupportURL
            .appendingPathComponent("state")
    }

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    private var syncAgentURL: URL {
        launchAgentsDirectory
            .appendingPathComponent("com.drivesync.sync.plist")
    }

    private var healthAgentURL: URL {
        launchAgentsDirectory
            .appendingPathComponent("com.drivesync.health.plist")
    }

    private var userDomain: String {
        "gui/\(getuid())"
    }
    
    func activeSyncState() -> DriveSyncActiveSyncState {
        do {
            return try detectActiveSync()
                ? .running
                : .notRunning
        } catch {
            return .unableToVerify
        }
    }

    func verifyNoActiveSync() throws {
        switch activeSyncState() {
        case .notRunning:
            return

        case .running:
            throw DriveSyncUninstallError.syncRunning

        case .unableToVerify:
            throw DriveSyncUninstallError.syncVerificationFailed
        }
    }

    private func detectActiveSync() throws -> Bool {
        guard fileManager.fileExists(atPath: runningPIDURL.path) else {
            return false
        }

        let pidText: String

        do {
            pidText = try String(
                contentsOf: runningPIDURL,
                encoding: .utf8
            )
        } catch {
            throw DriveSyncUninstallError.syncVerificationFailed
        }

        guard let pid = Int32(
            pidText.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw DriveSyncUninstallError.syncVerificationFailed
        }

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "-ww",
            "-p",
            String(pid),
            "-o",
            "command="
        ]

        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DriveSyncUninstallError.syncVerificationFailed
        }

        if process.terminationStatus != 0 {
            return false
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard
            let command = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !command.isEmpty
        else {
            throw DriveSyncUninstallError.syncVerificationFailed
        }

        return command.contains(driveSyncScriptURL.path)
    }
    
    func validateDriveSyncApp() throws -> URL {
        guard fileManager.fileExists(atPath: driveSyncAppURL.path) else {
            throw DriveSyncUninstallError.driveSyncAppNotFound(
                driveSyncAppURL.path
            )
        }

        guard
            let bundle = Bundle(url: driveSyncAppURL),
            bundle.bundleIdentifier == "com.drivesync.app"
        else {
            throw DriveSyncUninstallError.invalidDriveSyncApp(
                driveSyncAppURL.path
            )
        }

        return driveSyncAppURL
    }

    func removeLaunchAgents() throws {
        let services = [
            ("com.drivesync.sync", syncAgentURL),
            ("com.drivesync.health", healthAgentURL)
        ]

        for (label, plistURL) in services {
            if serviceIsLoaded(label: label) {
                let status = runLaunchctl([
                    "bootout",
                    "\(userDomain)/\(label)"
                ])

                guard status == 0 else {
                    throw DriveSyncUninstallError.unloadFailed(label)
                }
            }

            if fileManager.fileExists(atPath: plistURL.path) {
                do {
                    try fileManager.removeItem(at: plistURL)
                } catch {
                    throw DriveSyncUninstallError.removeFailed(
                        plistURL.path
                    )
                }
            }
        }
    }
    
    func closeDriveSyncApp() throws {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.drivesync.app"
        )

        guard !runningApps.isEmpty else {
            return
        }

        for app in runningApps {
            app.terminate()
        }

        let timeout = Date().addingTimeInterval(5)

        while Date() < timeout {
            let stillRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.drivesync.app"
            )

            if stillRunning.isEmpty {
                return
            }

            RunLoop.current.run(
                until: Date().addingTimeInterval(0.1)
            )
        }

        throw DriveSyncUninstallError.appQuitFailed
    }
    
    func removeTransientState() throws {
        let transientItems = [
            stateDirectoryURL.appendingPathComponent("running.lock"),
            stateDirectoryURL.appendingPathComponent("current-log"),
            stateDirectoryURL.appendingPathComponent("cancelled")
        ]

        for itemURL in transientItems {
            guard fileManager.fileExists(atPath: itemURL.path) else {
                continue
            }

            do {
                try fileManager.removeItem(at: itemURL)
            } catch {
                throw DriveSyncUninstallError.removeTransientStateFailed(
                    itemURL.path
                )
            }
        }
    }

    func removeUserData() throws {
        guard fileManager.fileExists(atPath: appSupportURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: appSupportURL)
        } catch {
            throw DriveSyncUninstallError.removeUserDataFailed(
                appSupportURL.path
            )
        }
    }

    private func serviceIsLoaded(label: String) -> Bool {
        runLaunchctl([
            "print",
            "\(userDomain)/\(label)"
        ]) == 0
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

enum DriveSyncActiveSyncState {
    case notRunning
    case running
    case unableToVerify
}

enum DriveSyncUninstallError: LocalizedError {
    case driveSyncAppNotFound(String)
    case syncRunning
    case syncVerificationFailed
    case unloadFailed(String)
    case removeFailed(String)
    case invalidDriveSyncApp(String)
    case appQuitFailed
    case removeTransientStateFailed(String)
    case removeUserDataFailed(String)

    var errorDescription: String? {
        switch self {
        case .driveSyncAppNotFound(let path):
            return "DriveSync could not be found at \(path)."
        
        case .unloadFailed(let label):
            return "\(label) could not be unloaded."

        case .removeFailed(let path):
            return "DriveSync could not remove the LaunchAgent at \(path)."
            
        case .syncRunning:
            return "DriveSync cannot be uninstalled while a backup is running. Stop the current backup and try again."
            
        case .syncVerificationFailed:
            return "DriveSync could not determine whether a backup is currently running. Uninstallation has been stopped for safety."
            
        case .invalidDriveSyncApp(let path):
            return "The application at \(path) is not a valid DriveSync installation."
            
        case .appQuitFailed:
            return "DriveSync could not be closed. Quit DriveSync and try again."
            
        case .removeTransientStateFailed(let path):
            return "DriveSync could not remove transient state at \(path)."

        case .removeUserDataFailed(let path):
            return "DriveSync could not remove its user data at \(path)."
        }
    }
}
