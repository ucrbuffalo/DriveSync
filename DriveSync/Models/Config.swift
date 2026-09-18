import Foundation
import Observation

@Observable
final class DriveSyncConfig {
    var sourcePath: String = ""
    var destinationPath: String = ""
    var scheduleTimes: [SyncTime] = [
        SyncTime(hour: 0, minute: 0)
    ]
    var scheduleWindowMinutes: Int = 30
    var logRetentionDays: Int = 90
    var staleSyncDays: Int = 14
    var setupComplete: Bool = false

    var isConfigured: Bool {
        setupComplete &&
        !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DriveSync")
            .appendingPathComponent("config")
            .appendingPathComponent("config.plist")
    }

    func load() throws {
        let data = try Data(contentsOf: configURL)

        guard
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            throw DriveSyncConfigError.invalidPlist
        }

        sourcePath = plist["SourcePath"] as? String ?? ""
        destinationPath = plist["DestinationPath"] as? String ?? ""
        setupComplete = plist["SetupComplete"] as? Bool ?? (
            !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        if let scheduleTimesArray = plist["ScheduleTimes"] as? [[String: Any]] {
            scheduleTimes = scheduleTimesArray.compactMap { entry in
                guard
                    let hour = entry["Hour"] as? Int,
                    let minute = entry["Minute"] as? Int
                else {
                    return nil
                }

                return SyncTime(
                    hour: hour,
                    minute: minute
                )
            }
            .sorted()

        } else if let legacyHours = plist["ScheduleHours"] as? [Int] {
            // Backward compatibility with older DriveSync configurations.
            scheduleTimes = legacyHours
                .map {
                    SyncTime(
                        hour: $0,
                        minute: 0
                    )
                }
                .sorted()

        } else {
            scheduleTimes = [
                SyncTime(hour: 0, minute: 0)
            ]
        }
        scheduleWindowMinutes = plist["ScheduleWindowMinutes"] as? Int ?? 30
        logRetentionDays = plist["LogRetentionDays"] as? Int ?? 90
        staleSyncDays = plist["StaleSyncDays"] as? Int ?? 14
    }

    func save(
        source: String,
        destination: String,
        scheduleTimes: [SyncTime],
        scheduleWindowMinutes: Int,
        logRetentionDays: Int,
        staleSyncDays: Int
    ) throws {
        let data = try Data(contentsOf: configURL)

        guard
            var plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            throw DriveSyncConfigError.invalidPlist
        }

        plist["SourcePath"] = source
        plist["DestinationPath"] = destination
        plist["SetupComplete"] = setupComplete
        plist["ScheduleTimes"] = scheduleTimes
            .sorted()
            .map { time in
                [
                    "Hour": time.hour,
                    "Minute": time.minute
                ]
            }

        plist.removeValue(forKey: "ScheduleHours")
        plist["ScheduleWindowMinutes"] = scheduleWindowMinutes
        plist["LogRetentionDays"] = logRetentionDays
        plist["StaleSyncDays"] = staleSyncDays

        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        try updatedData.write(to: configURL, options: .atomic)

        sourcePath = source
        destinationPath = destination
        self.scheduleTimes = scheduleTimes.sorted()
        self.scheduleWindowMinutes = scheduleWindowMinutes
        self.logRetentionDays = logRetentionDays
        self.staleSyncDays = staleSyncDays
    }
    
    func setSetupComplete(_ complete: Bool) throws {
        let data = try Data(contentsOf: configURL)

        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw DriveSyncConfigError.invalidPlist
        }

        plist["SetupComplete"] = complete

        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        try updatedData.write(to: configURL, options: .atomic)

        setupComplete = complete
    }
}

enum DriveSyncConfigError: Error {
    case invalidPlist
}
