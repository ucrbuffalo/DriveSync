import Foundation

struct SettingsDraft: Equatable {
    var sourcePath: String
    var destinationPath: String
    var scheduleTimes: [SyncTime]
    var scheduleWindowMinutes: Int
    var logRetentionDays: Int
    var staleSyncDays: Int

    var exclusions: [String]

    init(
        config: DriveSyncConfig,
        exclusions: [String]
    ) {
        self.sourcePath = config.sourcePath
        self.destinationPath = config.destinationPath
        self.scheduleTimes = config.scheduleTimes
        self.scheduleWindowMinutes = config.scheduleWindowMinutes
        self.logRetentionDays = config.logRetentionDays
        self.staleSyncDays = config.staleSyncDays
        self.exclusions = exclusions
    }
}
