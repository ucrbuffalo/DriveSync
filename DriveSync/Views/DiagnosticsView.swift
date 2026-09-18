import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.openWindow) private var openWindow
    
    let config: DriveSyncConfig
    let statusMonitor: DriveSyncStatusMonitor
    
    private let serviceController = DriveSyncServiceController()
    private let commandController = DriveSyncCommandController()
    private let logController = DriveSyncLogController()
    
    @AppStorage("skipDisableAutomaticSyncingWarning")
    private var skipDisableAutomaticSyncingWarning = false

    @State private var healthCheckMessage: String?
    @State private var showingHealthCheckResult = false
    @State private var logError: String?
    @State private var repairMessage: String?
    @State private var showingRepairResult = false
    @State private var repairTitle = "DriveSync Services"

    private var serviceActionTitle: String {
        if !statusMonitor.serviceStatus.syncLoaded &&
           !statusMonitor.serviceStatus.healthLoaded {
            return "Enable Automatic Syncing"
        }

        return "Repair Services"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // MARK: - Status
                
                Text("Status")
                    .font(.headline)
                
                HStack {
                    Text("Last Successful Sync")

                    Spacer()

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

                    Button("Check for Stale") {
                        runHealthCheck()
                    }
                    .padding(.leading, 12)
                    .help(
                        "Checks whether the last successful sync is older than your Stale Sync Threshold. You can change this threshold in Settings."
                    )
                }
                
                HStack {
                    Text("Current Status")

                    Spacer()

                    if statusMonitor.runtimeStatus.isRunning {
                        Button("Open Log") {
                            do {
                                try logController.openCurrentLog()
                                logError = nil
                            } catch {
                                logError = error.localizedDescription
                            }
                        }
                    }
                    
                    Text(statusMonitor.runtimeStatus.isRunning ? "Syncing" : "Idle")
                }
                
                Divider()

                // MARK: - Logs
                
                HStack {
                    Text("Logs")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Open Logs Folder") {
                        do {
                            try logController.openLogsFolder()
                            logError = nil
                        } catch {
                            logError = error.localizedDescription
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Log")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text(statusMonitor.latestLogName ?? "No logs found.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Spacer()

                        Button("Open Latest Log") {
                            do {
                                try logController.openLatestLog()
                                logError = nil
                            } catch {
                                logError = error.localizedDescription
                            }
                        }
                        .disabled(statusMonitor.latestLogName == nil)
                    }
                }
                
                Divider()

                // MARK: - Warnings

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset Dismissed Warnings")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(
                            skipDisableAutomaticSyncingWarning
                                ? "One or more confirmation messages have been dismissed."
                                : "No confirmation messages are currently dismissed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset Warnings") {
                        resetDismissedWarnings()
                    }
                    .disabled(!skipDisableAutomaticSyncingWarning)
                    .help(
                        skipDisableAutomaticSyncingWarning
                            ? "Restores confirmation messages that were previously dismissed."
                            : "No confirmation messages are currently dismissed."
                    )
                }

                Divider()

                // MARK: - Repair

                Text("Repair")
                    .font(.headline)
                
                HStack {
                    Text("Sync Service")
                    Spacer()
                    Text(statusMonitor.serviceStatus.syncLoaded ? "Active" : "Not Loaded")
                }

                HStack {
                    Text("Health Service")
                    Spacer()
                    Text(statusMonitor.serviceStatus.healthLoaded ? "Active" : "Not Loaded")
                }
                
                HStack {
                    Spacer()
                    
                    Button("Refresh Status") {
                        statusMonitor.refreshAll()
                    }
                    
                    Button("Disable Automatic Syncing") {
                        disableServices()
                    }
                    .disabled(
                        statusMonitor.runtimeStatus.isRunning ||
                        (!statusMonitor.serviceStatus.syncLoaded &&
                         !statusMonitor.serviceStatus.healthLoaded)
                    )
                    
                    Button(serviceActionTitle) {
                        repairServices()
                    }
                    .disabled(statusMonitor.runtimeStatus.isRunning)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .task {
            statusMonitor.refreshAll()
        }
        .alert(
            "DriveSync Health Check",
            isPresented: $showingHealthCheckResult
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(healthCheckMessage ?? "Health check completed.")
        }
        .alert(
            "DriveSync Logs",
            isPresented: Binding(
                get: { logError != nil },
                set: { isPresented in
                    if !isPresented {
                        logError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logError ?? "DriveSync could not access the logs.")
        }
        .alert(
            repairTitle,
            isPresented: $showingRepairResult
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(repairMessage ?? "Service operation completed.")
        }
        
    }
    
    private func resetDismissedWarnings() {
        skipDisableAutomaticSyncingWarning = false
    }
    
    private func repairServices() {
        let wasDisabled =
            !statusMonitor.serviceStatus.syncLoaded &&
            !statusMonitor.serviceStatus.healthLoaded

        repairTitle = wasDisabled
            ? "Automatic Syncing Enabled"
            : "DriveSync Service Repair"

        do {
            try serviceController.configureAndActivateServices(config: config)

            statusMonitor.refreshAll()

            if statusMonitor.serviceStatus.allServicesLoaded {
                repairMessage = wasDisabled
                    ? "DriveSync automatic syncing has been enabled."
                    : "DriveSync services were repaired successfully."
            } else {
                repairMessage =
                    "DriveSync completed the service update, but one or more services are still not loaded."
            }

            showingRepairResult = true

        } catch {
            statusMonitor.refreshAll()

            repairMessage = wasDisabled
                ? """
                DriveSync could not enable automatic syncing.

                \(error.localizedDescription)
                """
                : """
                DriveSync could not repair its services.

                \(error.localizedDescription)
                """

            showingRepairResult = true
        }
    }
    
    private func disableServices() {
        repairTitle = "Automatic Syncing Disabled"
        
        do {
            try serviceController.deactivateServices()

            statusMonitor.refreshAll()

            if !statusMonitor.serviceStatus.syncLoaded &&
               !statusMonitor.serviceStatus.healthLoaded {
                repairMessage = """
                DriveSync automatic syncing has been disabled.

                Use Enable Automatic Syncing to turn automatic syncing back on.
                """
            } else {
                repairMessage = """
                DriveSync attempted to disable automatic syncing, but one or more services are still loaded.
                """
            }

            showingRepairResult = true

        } catch {
            statusMonitor.refreshAll()

            repairMessage = """
            DriveSync could not disable automatic syncing.

            \(error.localizedDescription)
            """

            showingRepairResult = true
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

            showingHealthCheckResult = true

        } catch {
            healthCheckMessage = error.localizedDescription
            showingHealthCheckResult = true
        }
    }
}
