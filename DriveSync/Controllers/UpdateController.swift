import Foundation

struct DriveSyncUpdate {
    let version: String
    let releaseURL: URL
}

enum DriveSyncUpdateCheck {
    case available(DriveSyncUpdate)
    case upToDate
    case failed
}

final class DriveSyncUpdateController: Sendable {
    private let releasesURL = URL(
        string: "https://api.github.com/repos/ucrbuffalo/DriveSync/releases/latest"
    )!

    private let lastCheckKey = "lastUpdateCheck"
    private let checkInterval: TimeInterval = 86400

    private var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    // Return the latest release if it is newer than this build.
    func checkForUpdate(force: Bool = false) async -> DriveSyncUpdateCheck {
        if !force,
           let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < checkInterval {
            return .upToDate
        }

        var request = URLRequest(url: releasesURL)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.timeoutInterval = 15

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let urlString = json["html_url"] as? String,
            let url = URL(string: urlString)
        else {
            return .failed
        }

        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

        guard isNewer(latest, than: currentVersion) else {
            return .upToDate
        }

        return .available(
            DriveSyncUpdate(
                version: latest,
                releaseURL: url
            )
        )
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(new.count, old.count) {
            let left = index < new.count ? new[index] : 0
            let right = index < old.count ? old[index] : 0

            if left != right {
                return left > right
            }
        }

        return false
    }
}
