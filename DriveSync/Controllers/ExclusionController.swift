import Foundation

final class DriveSyncExclusionController {
    private let fileManager = FileManager.default

    private var userExclusionsURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
            .appendingPathComponent("config")
            .appendingPathComponent("exclusions-user")
    }

    func loadUserExclusions() throws -> [String] {
        guard fileManager.fileExists(atPath: userExclusionsURL.path) else {
            throw DriveSyncExclusionError.userExclusionsMissing
        }

        let contents = try String(
            contentsOf: userExclusionsURL,
            encoding: .utf8
        )

        return contents
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                !$0.isEmpty
            }
    }

    func saveUserExclusions(_ exclusions: [String]) throws {
        let contents: String

        if exclusions.isEmpty {
            contents = ""
        } else {
            contents = exclusions.joined(separator: "\n") + "\n"
        }

        do {
            try contents.write(
                to: userExclusionsURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw DriveSyncExclusionError.saveFailed
        }
    }

    func exclusionPattern(
        for selectedURL: URL,
        sourcePath: String,
        isDirectory: Bool
    ) throws -> String {
        let sourceURL = URL(fileURLWithPath: sourcePath)
            .standardizedFileURL

        let selectedURL = selectedURL.standardizedFileURL

        let sourceComponents = sourceURL.pathComponents
        let selectedComponents = selectedURL.pathComponents

        guard
            selectedComponents.count > sourceComponents.count,
            Array(selectedComponents.prefix(sourceComponents.count))
                == sourceComponents
        else {
            throw DriveSyncExclusionError.outsideSource
        }

        let relativeComponents =
            selectedComponents.dropFirst(sourceComponents.count)

        var pattern =
            "/" + relativeComponents.joined(separator: "/")

        if isDirectory {
            pattern += "/"
        }

        return pattern
    }
}

enum DriveSyncExclusionError: LocalizedError {
    case userExclusionsMissing
    case outsideSource
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .userExclusionsMissing:
            return "The DriveSync user exclusions file could not be found."

        case .outsideSource:
            return "The selected item must be inside the configured DriveSync source folder."

        case .saveFailed:
            return "DriveSync could not save the user exclusions."
        }
    }
}
