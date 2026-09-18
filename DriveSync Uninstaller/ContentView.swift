import SwiftUI
import AppKit

struct ContentView: View {
    @State private var keepUserData = true
    @State private var uninstallError: String?
    @State private var isWorking = false
    @State private var activeSyncState: DriveSyncActiveSyncState = .notRunning
    @State private var showingUninstallComplete = false

    private let uninstallController = DriveSyncUninstallController()
    private let uninstallHelperClient = UninstallHelperClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Uninstall DriveSync?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(
                    "DriveSync will be removed from this Mac and automatic syncing will be disabled."
                )
                .foregroundStyle(.secondary)
            }

            Toggle(
                "Keep my configuration and backup history",
                isOn: $keepUserData
            )

            Text(
                keepUserData
                    ? "Your DriveSync settings, exclusions, logs, and sync history will be preserved if you reinstall DriveSync later."
                    : "Your DriveSync settings, exclusions, logs, and sync history will also be permanently removed."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if let uninstallError {
                Label(uninstallError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            
            if activeSyncState == .running {
                Label(
                    "DriveSync cannot be uninstalled while a backup is running. Stop the current backup and try again.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }

            if activeSyncState == .unableToVerify {
                Label(
                    "DriveSync cannot verify whether a backup is currently running. Uninstallation is disabled for safety.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    NSApplication.shared.terminate(nil)
                }
                .disabled(isWorking)
                
                Button("Uninstall") {
                    isWorking = true
                    uninstallError = nil

                    Task { @MainActor in
                        await Task.yield()

                        do {
                            _ = try uninstallController.validateDriveSyncApp()

                            try await uninstallHelperClient.verifyAvailability()

                            try uninstallController.verifyNoActiveSync()

                            try uninstallController.removeLaunchAgents()

                            try uninstallController.closeDriveSyncApp()

                            try uninstallController.verifyNoActiveSync()

                            try uninstallController.removeTransientState()

                            if !keepUserData {
                                try uninstallController.removeUserData()
                            }

                            try await uninstallHelperClient.removeDriveSyncApplication()

                            showingUninstallComplete = true
                        } catch {
                            uninstallError = error.localizedDescription
                        }

                        isWorking = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isWorking ||
                    activeSyncState != .notRunning
                )
            }
        }
        .padding(24)
        .frame(width: 480)
        .task {
            while !Task.isCancelled {
                activeSyncState = uninstallController.activeSyncState()

                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert(
            "DriveSync Uninstalled",
            isPresented: $showingUninstallComplete
        ) {
            Button("Close") {
                Task { @MainActor in
                    do {
                        try await uninstallHelperClient.finishUninstall()

                        NSApplication.shared.terminate(nil)
                    } catch {
                        uninstallError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("DriveSync has been successfully removed from this Mac.")
        }
    }
}
