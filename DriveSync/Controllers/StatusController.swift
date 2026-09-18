import Foundation

struct DriveSyncRuntimeStatus {
    let lastSuccessfulSync: Date?
    let isRunning: Bool
}

final class DriveSyncStatusController {
    private let fileManager = FileManager.default

    private var driveSyncDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
    }

    private var stateDirectory: URL {
        driveSyncDirectory
            .appendingPathComponent("state")
    }

    private var lastSuccessURL: URL {
        stateDirectory
            .appendingPathComponent("last-success")
    }

    private var lockPIDURL: URL {
        stateDirectory
            .appendingPathComponent("running.lock")
            .appendingPathComponent("pid")
    }

    private var scriptURL: URL? {
        Bundle.main.url(
            forResource: "DriveSync",
            withExtension: "sh"
        )
    }

    func runtimeStatus() -> DriveSyncRuntimeStatus {
        DriveSyncRuntimeStatus(
            lastSuccessfulSync: lastSuccessfulSync(),
            isRunning: driveSyncIsRunning()
        )
    }

    private func lastSuccessfulSync() -> Date? {
        guard fileManager.fileExists(atPath: lastSuccessURL.path) else {
            return nil
        }

        do {
            let attributes = try fileManager.attributesOfItem(
                atPath: lastSuccessURL.path
            )

            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    private func driveSyncIsRunning() -> Bool {
        guard fileManager.fileExists(atPath: lockPIDURL.path) else {
            return false
        }

        guard
            let pidText = try? String(contentsOf: lockPIDURL, encoding: .utf8),
            let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return false
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
            return false
        }

        guard process.terminationStatus == 0 else {
            return false
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard
            let command = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !command.isEmpty
        else {
            return false
        }

        guard let scriptURL else {
            return false
        }

        return command.contains(scriptURL.path)
    }
}
