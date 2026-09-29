import SwiftUI
import AppKit
import Combine

struct DriveSyncMenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    let statusMonitor: DriveSyncStatusMonitor

    private let commandController = DriveSyncCommandController()

    var body: some View {
        Group {
            Text(
                statusMonitor.runtimeStatus.isRunning
                    ? "Status: Syncing"
                    : "Status: Idle"
            )

            Divider()

            Button(
                statusMonitor.runtimeStatus.isRunning
                    ? "Stop Sync"
                    : "Run Sync Now"
            ) {
                runOrStopSync()
            }
            
            if !statusMonitor.currentIssues.isEmpty {
                Button {
                    AppDelegate.activateDriveSync()

                    openWindow(id: "issues")

                    DispatchQueue.main.async {
                        AppDelegate.activateDriveSync()

                        NSApplication.shared.windows
                            .first { $0.title == "DriveSync Issues" }?
                            .makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Label(
                        "Issues (\(statusMonitor.currentIssues.count))",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            
            if let availableUpdate = statusMonitor.availableUpdate {
                Button {
                    NSWorkspace.shared.open(availableUpdate.releaseURL)
                } label: {
                    Label(
                        "Version \(availableUpdate.version) is available",
                        systemImage: "arrow.down.circle"
                    )
                }
            }

            Divider()

            Button {
                AppDelegate.activateDriveSync()

                openWindow(id: "main")

                DispatchQueue.main.async {
                    AppDelegate.activateDriveSync()

                    NSApplication.shared.windows
                        .first { $0.title == "DriveSync" }?
                        .makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open DriveSync", systemImage: "macwindow")
            }

            Button {
                AppDelegate.activateDriveSync()

                openSettings()

                DispatchQueue.main.async {
                    AppDelegate.activateDriveSync()

                    NSApplication.shared.windows
                        .first { $0.title.contains("Settings") }?
                        .makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            
            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit DriveSync", systemImage: "power")
            }
        }
    }

    private func runOrStopSync() {
        do {
            if statusMonitor.runtimeStatus.isRunning {
                try commandController.stopSync()
            } else {
                try commandController.runManualSync()
            }
            
            statusMonitor.refresh()
            
        } catch {
            
            DriveSyncNotificationController.shared.send(
                title: "DriveSync couldn't complete the command",
                message: error.localizedDescription
            )
            
            statusMonitor.refresh()
        }
    }
}
