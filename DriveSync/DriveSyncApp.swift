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
            HelpCommands()
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
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Uninstall DriveSync…") {
                launchUninstaller()
            }
        }
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
