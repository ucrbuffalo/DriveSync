import Foundation

final class DriveSyncServiceController {
    private let fileManager = FileManager.default
    private let accessProbeName = ".drivesync-access-probe"
    
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

    func configureAndActivateServices(config: DriveSyncConfig) throws {
        try validatePrerequisites(scheduleTimes: config.scheduleTimes)
        try createLaunchAgentsDirectory()

        try writeSyncLaunchAgent(scheduleTimes: config.scheduleTimes)
        try writeHealthLaunchAgent()
        
        try validatePlist(at: syncAgentURL)
        try validatePlist(at: healthAgentURL)

        var syncActivated = false

        do {
            try activateService(
                label: "com.drivesync.sync",
                plistURL: syncAgentURL
            )

            syncActivated = true

            try activateService(
                label: "com.drivesync.health",
                plistURL: healthAgentURL
            )
        } catch {
            if syncActivated {
                _ = runLaunchctl([
                    "bootout",
                    "\(userDomain)/com.drivesync.sync"
                ])
            }

            throw error
        }
    }
    
    func updateSyncSchedule(config: DriveSyncConfig) throws {
        try validatePrerequisites(scheduleTimes: config.scheduleTimes)
        try createLaunchAgentsDirectory()

        try writeSyncLaunchAgent(scheduleTimes: config.scheduleTimes)
        try validatePlist(at: syncAgentURL)

        try activateService(
            label: "com.drivesync.sync",
            plistURL: syncAgentURL
        )
    }

    func serviceStatus() -> DriveSyncServiceStatus {
        DriveSyncServiceStatus(
            syncLoaded: serviceIsLoaded(label: "com.drivesync.sync"),
            healthLoaded: serviceIsLoaded(label: "com.drivesync.health")
        )
    }
    
    func deactivateServices() throws {
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
                    throw DriveSyncServiceError.unloadFailed(label)
                }
            }

            if fileManager.fileExists(atPath: plistURL.path) {
                do {
                    try fileManager.removeItem(at: plistURL)
                } catch {
                    throw DriveSyncServiceError.removeFailed(
                        plistURL.path
                    )
                }
            }
        }
    }
    
    func requestAccessCheck() throws {
        try kickstartSyncJob(flagName: "check-access")
    }

    func requestImmediateSync() throws {
        try kickstartSyncJob(flagName: "run-now")
    }

    // Remove the probe file the access check leaves in the destination.
    func scheduleAccessProbeCleanup(destinationPath: String) {
        let probeURL = URL(fileURLWithPath: destinationPath)
            .appendingPathComponent(accessProbeName)

        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            let deadline = Date().addingTimeInterval(120)

            while Date() < deadline {
                if fileManager.fileExists(atPath: probeURL.path) {
                    try? fileManager.removeItem(at: probeURL)
                    return
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func validatePrerequisites(scheduleTimes: [SyncTime]) throws {
        guard
            let scriptURL,
            fileManager.fileExists(atPath: scriptURL.path)
        else {
            throw DriveSyncServiceError.missingScript
        }
        
        guard
            let rsyncURL,
            fileManager.isExecutableFile(atPath: rsyncURL.path)
        else {
            throw DriveSyncServiceError.missingRsync
        }

        guard !scheduleTimes.isEmpty else {
            throw DriveSyncServiceError.invalidSchedule
        }

        for time in scheduleTimes {
            guard
                (0...23).contains(time.hour),
                (0...59).contains(time.minute)
            else {
                throw DriveSyncServiceError.invalidSchedule
            }
        }
    }

    private func createLaunchAgentsDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DriveSyncServiceError.launchAgentsDirectoryFailed
        }
    }

    private func writeSyncLaunchAgent(scheduleTimes: [SyncTime]) throws {
        guard let scriptURL else {
            throw DriveSyncServiceError.missingScript
        }
        
        let schedule = scheduleTimes
            .sorted()
            .map { time in
                [
                    "Hour": time.hour,
                    "Minute": time.minute
                ]
            }

        guard let rsyncURL else {
            throw DriveSyncServiceError.missingRsync
        }

        let plist: [String: Any] = [
            "Label": "com.drivesync.sync",
            "AssociatedBundleIdentifiers": [
                "com.drivesync.app"
            ],
            "ProgramArguments": [
                "/bin/zsh",
                scriptURL.path
            ],
            "EnvironmentVariables": [
                "DRIVESYNC_RSYNC": rsyncURL.path
            ],
            "StartCalendarInterval": schedule,
            "RunAtLoad": false
        ]

        try writePlist(plist, to: syncAgentURL)
    }

    private func writeHealthLaunchAgent() throws {
        guard let scriptURL else {
            throw DriveSyncServiceError.missingScript
        }
        
        let plist: [String: Any] = [
            "Label": "com.drivesync.health",
            "ProgramArguments": [
                "/bin/zsh",
                scriptURL.path,
                "--check"
            ],
            "StartCalendarInterval": [
                "Hour": 12,
                "Minute": 0
            ],
            "RunAtLoad": true
        ]

        try writePlist(plist, to: healthAgentURL)
    }

    private func writePlist(_ plist: [String: Any], to url: URL) throws {
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )

            try data.write(to: url, options: .atomic)
        } catch {
            throw DriveSyncServiceError.plistWriteFailed(url.path)
        }
    }

    private func validatePlist(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = [
            "-lint",
            url.path
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DriveSyncServiceError.plistValidationFailed(url.path)
        }

        guard process.terminationStatus == 0 else {
            throw DriveSyncServiceError.plistValidationFailed(url.path)
        }
    }

    private func activateService(label: String, plistURL: URL) throws {
        if serviceIsLoaded(label: label) {
            let bootoutStatus = runLaunchctl([
                "bootout",
                "\(userDomain)/\(label)"
            ])

            guard bootoutStatus == 0 else {
                throw DriveSyncServiceError.unloadFailed(label)
            }
        }

        let bootstrapStatus = runLaunchctl([
            "bootstrap",
            userDomain,
            plistURL.path
        ])

        guard bootstrapStatus == 0 else {
            throw DriveSyncServiceError.loadFailed(label)
        }

        guard serviceIsLoaded(label: label) else {
            throw DriveSyncServiceError.verificationFailed(label)
        }
    }
    
    private func kickstartSyncJob(flagName: String) throws {
        let label = "com.drivesync.sync"

        guard serviceIsLoaded(label: label) else {
            throw DriveSyncServiceError.verificationFailed(label)
        }

        let stateDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/DriveSync/state"
            )

        try fileManager.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )

        let flagURL = stateDirectory
            .appendingPathComponent(flagName)

        guard fileManager.createFile(
            atPath: flagURL.path,
            contents: nil
        ) else {
            throw DriveSyncServiceError.jobStartFailed(label)
        }

        let status = runLaunchctl([
            "kickstart",
            "-k",
            "\(userDomain)/\(label)"
        ])

        guard status == 0 else {
            try? fileManager.removeItem(at: flagURL)
            throw DriveSyncServiceError.jobStartFailed(label)
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

struct DriveSyncServiceStatus {
    let syncLoaded: Bool
    let healthLoaded: Bool

    var allServicesLoaded: Bool {
        syncLoaded && healthLoaded
    }
}

enum DriveSyncServiceError: LocalizedError {
    case missingScript
    case missingRsync
    case launchAgentsDirectoryFailed
    case invalidSchedule
    case plistWriteFailed(String)
    case plistValidationFailed(String)
    case unloadFailed(String)
    case loadFailed(String)
    case verificationFailed(String)
    case removeFailed(String)
    case jobStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "DriveSync's bundled DriveSync.sh could not be found."
            
        case .missingRsync:
            return "DriveSync's bundled rsync engine could not be found."
            
        case .launchAgentsDirectoryFailed:
            return "DriveSync could not create the LaunchAgents directory."

        case .invalidSchedule:
            return "DriveSync does not have a valid sync schedule."

        case .plistWriteFailed(let path):
            return "DriveSync could not create the LaunchAgent at \(path)."

        case .plistValidationFailed(let path):
            return "The LaunchAgent at \(path) is invalid."

        case .unloadFailed(let label):
            return "\(label) could not be unloaded."

        case .loadFailed(let label):
            return "\(label) could not be loaded."

        case .verificationFailed(let label):
            return "\(label) did not register correctly."
            
        case .removeFailed(let path):
            return "DriveSync could not remove the LaunchAgent at \(path)."
            
        case .jobStartFailed(let label):
            return "\(label) could not be started."
        }
    }
}
