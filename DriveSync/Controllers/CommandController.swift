import Foundation

enum DriveSyncHealthResult {
    case healthy
    case unhealthy
}

final class DriveSyncCommandController {
    private let fileManager = FileManager.default

    private var scriptURL: URL? {
        Bundle.main.url(
            forResource: "DriveSync",
            withExtension: "sh"
        )
    }
    
    private var rsyncURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("rsync")
    }

    func runManualSync() throws {
        guard
            let scriptURL,
            fileManager.fileExists(atPath: scriptURL.path)
        else {
            throw DriveSyncCommandError.missingScript
        }
        
        guard
            let rsyncURL,
            fileManager.isExecutableFile(atPath: rsyncURL.path)
        else {
            throw DriveSyncCommandError.missingRsync
        }

        let config = DriveSyncConfig()

        do {
            try config.load()
        } catch {
            throw DriveSyncCommandError.configurationUnavailable
        }

        var isDirectory: ObjCBool = false

        guard
            fileManager.fileExists(
                atPath: config.sourcePath,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw DriveSyncCommandError.sourceUnavailable(
                config.sourcePath
            )
        }

        isDirectory = false

        guard
            fileManager.fileExists(
                atPath: config.destinationPath,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw DriveSyncCommandError.destinationUnavailable(
                config.destinationPath
            )
        }

        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "--manual"
        ]
        
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "DRIVESYNC_RSYNC": rsyncURL.path
            ]
        ) { _, newValue in
            newValue
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw DriveSyncCommandError.launchFailed
        }
    }
    func stopSync() throws {
        guard
            let scriptURL,
            fileManager.fileExists(atPath: scriptURL.path)
        else {
            throw DriveSyncCommandError.missingScript
        }

        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "--stop"
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw DriveSyncCommandError.stopFailed
        }
    }
    
    func checkHealth() throws -> DriveSyncHealthResult {
        guard
            let scriptURL,
            fileManager.fileExists(atPath: scriptURL.path)
        else {
            throw DriveSyncCommandError.missingScript
        }

        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "--check"
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DriveSyncCommandError.checkFailed
        }

        switch process.terminationStatus {
        case 0:
            return .healthy

        case 1:
            return .unhealthy

        default:
            throw DriveSyncCommandError.checkFailed
        }
    }
}

enum DriveSyncCommandError: LocalizedError {
    case missingScript
    case missingRsync
    case configurationUnavailable
    case sourceUnavailable(String)
    case destinationUnavailable(String)
    case launchFailed
    case stopFailed
    case checkFailed

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "DriveSync's bundled DriveSync.sh could not be found."
            
        case .missingRsync:
            return "DriveSync's bundled rsync engine could not be found."

        case .launchFailed:
            return "DriveSync could not start a manual sync."
            
        case .stopFailed:
            return "DriveSync could not stop the current sync."
            
        case .checkFailed:
            return "DriveSync could not complete the health check."
            
        case .sourceUnavailable:
            return """
            The source folder is unavailable. Check that the Source is available, then try again.
            """

        case .destinationUnavailable:
            return """
            The destination is unavailable. Check that the Destination is available, then try again.
            """
            
        case .configurationUnavailable:
            return "DriveSync could not read its configuration. Open Settings and verify your Source and Destination."
        }
    }
}
