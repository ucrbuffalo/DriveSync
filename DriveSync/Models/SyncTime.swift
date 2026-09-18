import Foundation

struct SyncTime: Codable, Equatable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    static func < (lhs: SyncTime, rhs: SyncTime) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }

        return lhs.minute < rhs.minute
    }
}
