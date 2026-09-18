import Foundation
import AppKit

final class DriveSyncLogController {
    private let fileManager = FileManager.default

    private var logsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
            .appendingPathComponent("logs")
    }

    private var currentLogStateURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
            .appendingPathComponent("state")
            .appendingPathComponent("current-log")
    }

    func currentLogURL() -> URL? {
        guard
            let path = try? String(
                contentsOf: currentLogStateURL,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }

        let url = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }
    
    func latestLogURL() -> URL? {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        let currentLog = currentLogURL()

        let logFiles = files.filter { url in
            guard
                url.pathExtension == "log",
                url.lastPathComponent.hasPrefix("DriveSync-")
            else {
                return false
            }

            if let currentLog {
                return url.standardizedFileURL != currentLog.standardizedFileURL
            }

            return true
        }

        return logFiles.max { first, second in
            let firstDate =
                (try? first.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast

            let secondDate =
                (try? second.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast

            return firstDate < secondDate
        }
    }

    func latestLogName() -> String? {
        latestLogURL()?.lastPathComponent
    }

    func openCurrentLog() throws {
        guard let currentLog = currentLogURL() else {
            throw DriveSyncLogError.noCurrentLog
        }

        NSWorkspace.shared.open(currentLog)
    }
    
    func openLatestLog() throws {
        guard let latestLog = latestLogURL() else {
            throw DriveSyncLogError.noLogsFound
        }

        NSWorkspace.shared.open(latestLog)
    }

    func openLogsFolder() throws {
        guard fileManager.fileExists(atPath: logsDirectory.path) else {
            throw DriveSyncLogError.logsDirectoryMissing
        }

        NSWorkspace.shared.open(logsDirectory)
    }
}

enum DriveSyncLogError: LocalizedError {
    case noLogsFound
    case noCurrentLog
    case logsDirectoryMissing

    var errorDescription: String? {
        switch self {
        case .noLogsFound:
            return "No DriveSync logs could be found."
            
        case .noCurrentLog:
            return "There is no active DriveSync log."

        case .logsDirectoryMissing:
            return "The DriveSync logs folder could not be found."
        }
    }
}
