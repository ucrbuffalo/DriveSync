import SwiftUI
import AppKit

@main
struct DriveSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    
    @State private var config = DriveSyncConfig()
    @State private var statusMonitor = DriveSyncStatusMonitor()

    var body: some Scene {
        Window("DriveSync", id: "main") {
            ContentView(
                config: config,
                statusMonitor: statusMonitor
            )
        }
        .defaultSize(width: 300, height: 450)
        .restorationBehavior(.disabled)
        
        Window("DriveSync Issues", id: "issues") {
            IssuesView(
                statusMonitor: statusMonitor
            )
        }
        .defaultSize(width: 500, height: 350)
        .restorationBehavior(.disabled)
        .commands {
            IssuesCommands()
            HelpCommands(statusMonitor: statusMonitor)
        }

        MenuBarExtra(
            "DriveSync",
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            DriveSyncMenuBarView(
                statusMonitor: statusMonitor
            )
        }
        
        Settings {
            SettingsView(
                config: config,
                statusMonitor: statusMonitor
            )
        }
    }
}

struct IssuesCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Issues") {
            Button("Open Issues") {
                openWindow(id: "issues")
            }
            .keyboardShortcut(
                "i",
                modifiers: [.command]
            )
        }
    }
}

struct HelpCommands: Commands {
    let statusMonitor: DriveSyncStatusMonitor

    private var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "?"
    }

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Check for Updates…") {
                checkForUpdates()
            }

            Button("Uninstall DriveSync…") {
                launchUninstaller()
            }
        }
    }

    private func checkForUpdates() {
        Task { @MainActor in
            switch await statusMonitor.refreshUpdateStatus(force: true) {
            case .available(let update):
                let alert = NSAlert()
                alert.messageText = "Version \(update.version) is available"
                alert.informativeText = "You are running \(currentVersion)."
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Later")

                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(update.releaseURL)
                }

            case .upToDate:
                presentMessage("DriveSync is running the latest version.")

            case .failed:
                presentMessage("DriveSync could not check for updates.")
            }
        }
    }

    @MainActor
    private func presentMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func launchUninstaller() {
        let uninstallerURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("DriveSync Uninstaller.app")

        NSWorkspace.shared.openApplication(
            at: uninstallerURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                print("Could not launch DriveSync Uninstaller: \(error)")
            }
        }
    }
}
