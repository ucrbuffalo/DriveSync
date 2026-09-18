import Foundation

struct DriveSyncIssue: Codable, Identifiable, Hashable {
    let timestamp: Date
    let type: String
    let location: String?
    let path: String?
    let rsyncExitCode: Int?
    let technicalDetail: String?
    let logFile: String

    var id: String {
        [
            timestamp.ISO8601Format(),
            type,
            location ?? "",
            path ?? "",
            String(rsyncExitCode ?? -1),
            logFile
        ]
        .joined(separator: "|")
    }
}

final class DriveSyncIssueStore {
    private let fileManager = FileManager.default

    private var applicationSupportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
    }

    private var stateDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("state")
    }

    private var issuesURL: URL {
        stateDirectory
            .appendingPathComponent("issues.jsonl")
    }

    private var lastSuccessURL: URL {
        stateDirectory
            .appendingPathComponent("last-success")
    }

    func loadIssues() throws -> [DriveSyncIssue] {
        guard fileManager.fileExists(atPath: issuesURL.path) else {
            return []
        }

        let contents = try String(
            contentsOf: issuesURL,
            encoding: .utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var issues: [DriveSyncIssue] = []

        for line in contents.split(whereSeparator: \.isNewline) {
            let data = Data(line.utf8)

            do {
                let issue = try decoder.decode(
                    DriveSyncIssue.self,
                    from: data
                )

                issues.append(issue)
            } catch {
                // Ignore an individual malformed record rather than
                // preventing the rest of the issue history from loading.
                continue
            }
        }

        return issues.sorted {
            $0.timestamp > $1.timestamp
        }
    }

    func currentIssues() throws -> [DriveSyncIssue] {
        let issues = try loadIssues()

        guard let lastSuccess = lastSuccessfulSyncDate() else {
            return issues
        }

        return issues.filter {
            $0.timestamp > lastSuccess
        }
    }

    func pruneIssues(retentionDays: Int) throws {
        guard retentionDays > 0 else {
            return
        }

        guard fileManager.fileExists(atPath: issuesURL.path) else {
            return
        }

        let cutoffDate =
            Calendar.current.date(
                byAdding: .day,
                value: -retentionDays,
                to: Date()
            ) ?? Date()

        let retainedIssues =
            try loadIssues()
                .filter {
                    $0.timestamp >= cutoffDate
                }

        try writeIssues(retainedIssues)
    }

    private func lastSuccessfulSyncDate() -> Date? {
        guard
            fileManager.fileExists(
                atPath: lastSuccessURL.path
            )
        else {
            return nil
        }

        guard
            let attributes =
                try? fileManager.attributesOfItem(
                    atPath: lastSuccessURL.path
                ),
            let modificationDate =
                attributes[.modificationDate] as? Date
        else {
            return nil
        }

        return modificationDate
    }

    private func writeIssues(
        _ issues: [DriveSyncIssue]
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let chronologicalIssues =
            issues.sorted {
                $0.timestamp < $1.timestamp
            }

        let lines = try chronologicalIssues.map { issue in
            let data = try encoder.encode(issue)

            guard
                let line = String(
                    data: data,
                    encoding: .utf8
                )
            else {
                throw DriveSyncIssueStoreError.encodingFailed
            }

            return line
        }

        let contents =
            lines.isEmpty
                ? ""
                : lines.joined(separator: "\n") + "\n"

        try contents.write(
            to: issuesURL,
            atomically: true,
            encoding: .utf8
        )
    }
}

enum DriveSyncIssueStoreError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "DriveSync could not encode its issue history."
        }
    }
}
