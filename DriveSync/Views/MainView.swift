import SwiftUI
import Combine
import AppKit

struct MainView: View {
    @Environment(\.openWindow) private var openWindow
    
    let config: DriveSyncConfig
    let statusMonitor: DriveSyncStatusMonitor

    private let serviceController = DriveSyncServiceController()
    private let commandController = DriveSyncCommandController()
    private let logController = DriveSyncLogController()

    @State private var commandError: String?
    @State private var healthCheckMessage: String?
    @State private var showingHealthCheckResult = false
    @State private var showingDisableConfirmation = false
    @State private var dontShowDisableWarningAgain = false
    
    @AppStorage("skipDisableAutomaticSyncingWarning")
    private var skipDisableAutomaticSyncingWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                Text("DriveSync")
                    .font(.title)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            if let availableUpdate = statusMonitor.availableUpdate {
                Button {
                    NSWorkspace.shared.open(availableUpdate.releaseURL)
                } label: {
                    Label(
                        "Version \(availableUpdate.version) is available",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.callout)
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last Successful Sync")
                    .font(.headline)

                HStack {
                    if let lastSuccessfulSync = statusMonitor.runtimeStatus.lastSuccessfulSync {
                        Text(formattedLastSuccessfulSync(lastSuccessfulSync))
                    } else {
                        Text("No successful sync recorded.")
                            .foregroundStyle(.secondary)
                    }

                    if !statusMonitor.currentIssues.isEmpty {
                        Button {
                            openWindow(id: "issues")
                        } label: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Open DriveSync Issues")
                        .accessibilityLabel("Open DriveSync Issues")
                    }

                    Spacer()
                    
                    Button("Check for Stale") {
                        runHealthCheck()
                    }
                    .help(
                        "Checks whether the last successful sync is older than your Stale Sync Threshold. You can change this threshold in Settings."
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Status")
                    .font(.headline)

                HStack {
                    Text(statusMonitor.runtimeStatus.isRunning ? "Syncing" : "Idle")

                    if statusMonitor.runtimeStatus.isRunning {
                        Button("Open Log") {
                            do {
                                try logController.openCurrentLog()
                                commandError = nil
                            } catch {
                                commandError = error.localizedDescription
                            }
                        }
                    }

                    Spacer()

                    Button(statusMonitor.runtimeStatus.isRunning ? "Stop Sync" : "Run Sync Now") {
                        do {
                            if statusMonitor.runtimeStatus.isRunning {
                                try commandController.stopSync()
                            } else {
                                try commandController.runManualSync()
                            }

                            commandError = nil
                        } catch {
                            commandError = error.localizedDescription
                        }
                    }
                }
            }

            if let commandError {
                Text(commandError)
                    .foregroundStyle(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Automatic Syncing")
                        .font(.headline)
                        .foregroundStyle(
                            statusMonitor.runtimeStatus.isRunning
                                ? .secondary
                                : .primary
                        )
                        .accessibilityHidden(true)

                    Spacer()

                    Text("Off")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Toggle(
                        "",
                        isOn: Binding(
                            get: {
                                statusMonitor.serviceStatus.allServicesLoaded
                            },
                            set: { newValue in
                                if newValue {
                                    setAutomaticSyncing(true)
                                } else if skipDisableAutomaticSyncingWarning {
                                    setAutomaticSyncing(false)
                                } else {
                                    dontShowDisableWarningAgain = false
                                    showingDisableConfirmation = true
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Automatic Syncing")
                    .accessibilityValue(
                        statusMonitor.serviceStatus.allServicesLoaded
                            ? "On"
                            : "Off"
                    )
                    .tint(.gray)
                    .controlSize(.mini)
                    .disabled(statusMonitor.runtimeStatus.isRunning)
                    .help(
                        statusMonitor.runtimeStatus.isRunning
                            ? "Automatic Syncing cannot be changed while a sync is running."
                            : "Controls whether DriveSync runs scheduled syncs automatically."
                    )

                    Text("On")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                if statusMonitor.runtimeStatus.isRunning {
                    Text("Automatic Syncing cannot be changed while a sync is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.headline)

                Text(config.sourcePath)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination")
                    .font(.headline)

                Text(config.destinationPath)
                    .textSelection(.enabled)
            }
        }
        .frame(
            minWidth: 300,
            idealWidth: 300,
            minHeight: 450,
            idealHeight: 450
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .task {
            statusMonitor.refreshAll()
            await statusMonitor.refreshUpdateStatus()
        }
        .alert("DriveSync Health Check", isPresented: $showingHealthCheckResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(healthCheckMessage ?? "Health check completed.")
        }
        .sheet(isPresented: $showingDisableConfirmation) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Disable Automatic Syncing?")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Scheduled syncs and health checks will not run while Automatic Syncing is disabled."
                    )

                    Text(
                        "You can turn Automatic Syncing back on at any time."
                    )
                }

                Toggle(
                    "Don't show this warning again",
                    isOn: $dontShowDisableWarningAgain
                )
                .toggleStyle(.checkbox)

                VStack(spacing: 8) {
                    Button {
                        if dontShowDisableWarningAgain {
                            skipDisableAutomaticSyncingWarning = true
                        }

                        showingDisableConfirmation = false
                        setAutomaticSyncing(false)
                    } label: {
                        Text("Disable")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)

                    Button {
                        showingDisableConfirmation = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(width: 300)
        }
    }
    
    private func setAutomaticSyncing(_ enabled: Bool) {
        do {
            if enabled {
                try serviceController.configureAndActivateServices(
                    config: config
                )
            } else {
                try serviceController.deactivateServices()
            }

            statusMonitor.refreshAll()
            commandError = nil

        } catch {
            statusMonitor.refreshAll()
            commandError = error.localizedDescription
        }
    }

    private func formattedLastSuccessfulSync(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(
            date: .omitted,
            time: .shortened
        )

        if calendar.isDateInToday(date) {
            return "Today at \(time)"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday at \(time)"
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private func timeUntilStale(
        lastSuccessfulSync: Date
    ) -> String? {
        let staleSeconds =
            TimeInterval(config.staleSyncDays * 86_400)

        let ageSeconds =
            Date().timeIntervalSince(lastSuccessfulSync)

        let remainingSeconds =
            staleSeconds - ageSeconds

        guard remainingSeconds > 0 else {
            return nil
        }

        if remainingSeconds >= 86_400 {
            let days = Int(
                ceil(remainingSeconds / 86_400)
            )

            return "Time until Stale: \(days) \(days == 1 ? "Day" : "Days")"
        }

        if remainingSeconds >= 3_600 {
            let hours = Int(
                ceil(remainingSeconds / 3_600)
            )

            return "Time until Stale: \(hours) \(hours == 1 ? "Hour" : "Hours")"
        }

        return "Time until Stale: Less than 1 Hour"
    }
    
    private func runHealthCheck() {
        do {
            let result = try commandController.checkHealth()

            switch result {
            case .healthy:
                if let lastSuccessfulSync = statusMonitor.runtimeStatus.lastSuccessfulSync {
                    let staleCountdown =
                        timeUntilStale(
                            lastSuccessfulSync: lastSuccessfulSync
                        )

                    if let staleCountdown {
                        healthCheckMessage = """
                        DriveSync is healthy.
                        \(staleCountdown)

                        Last successful sync was \(formattedLastSuccessfulSync(lastSuccessfulSync)).
                        """
                    } else {
                        healthCheckMessage = """
                        DriveSync is healthy.

                        Last successful sync was \(formattedLastSuccessfulSync(lastSuccessfulSync)).
                        """
                    }
                } else {
                    healthCheckMessage = "DriveSync is healthy."
                }
            case .unhealthy:
                if let lastSuccessfulSync = statusMonitor.runtimeStatus.lastSuccessfulSync {
                    healthCheckMessage = """
                    DriveSync is stale.

                    Last successful sync was \(formattedLastSuccessfulSync(lastSuccessfulSync)).
                    """
                } else {
                    healthCheckMessage = """
                    DriveSync is stale.

                    No successful sync has been recorded.
                    """
                }
            }

            commandError = nil
            showingHealthCheckResult = true
        } catch {
            commandError = error.localizedDescription
        }
    }
}
