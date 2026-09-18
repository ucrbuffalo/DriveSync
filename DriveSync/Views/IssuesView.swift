import SwiftUI
import AppKit

struct IssuesView: View {
    let statusMonitor: DriveSyncStatusMonitor

    @State private var showTechnicalDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DriveSync Issues")
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let lastSuccessfulSync =
                            statusMonitor.runtimeStatus.lastSuccessfulSync {

                            Text(
                                "Last successful sync: \(lastSuccessfulSync.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("Technical Details", isOn: $showTechnicalDetails)
                        .toggleStyle(.checkbox)
                        .focusable(false)
                }

                if statusMonitor.currentIssues.isEmpty {
                    Text("No current issues.")
                        .foregroundStyle(.secondary)

                } else {
                    VStack(spacing: 28) {
                        ForEach(issueGroups) { group in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(group.issues) { issue in
                                        let issueDescription = description(for: issue)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "exclamationmark.triangle")
                                                
                                                Text(issueDescription.title)
                                                    .font(.headline)
                                            }
                                            
                                            Text(issueDescription.explanation)
                                            
                                            Text(issueDescription.recommendation)
                                                .foregroundStyle(.secondary)
                                            
                                            if showTechnicalDetails {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Technical Details")
                                                        .fontWeight(.semibold)
                                                        .padding(.top, 6)
                                                    
                                                    Group {
                                                        Text("Type: \(issue.type)")
                                                        
                                                        if let location = issue.location {
                                                            Text("Location: \(location)")
                                                        }
                                                        
                                                        if let path = issue.path {
                                                            Text("Path: \(path)")
                                                                .textSelection(.enabled)
                                                        }
                                                        
                                                        if let exitCode = issue.rsyncExitCode {
                                                            Text("rsync exit code: \(exitCode)")
                                                        }
                                                        
                                                        if let technicalDetail = issue.technicalDetail {
                                                            Text("Error: \(technicalDetail)")
                                                                .textSelection(.enabled)
                                                        }
                                                    }
                                                    .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        
                                        if issue.id != group.issues.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                
                            } label: {
                                HStack {
                                    Text(
                                        group.timestamp.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.headline)
                                    
                                    Spacer()
                                    
                                    Button("Open Log") {
                                        NSWorkspace.shared.open(
                                            URL(fileURLWithPath: group.logFile)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(
            minWidth: 550,
            idealWidth: 550,
            minHeight: 400,
            idealHeight: 400
        )
        .task {
            statusMonitor.refresh()
        }
    }
    
    private var issueGroups: [DriveSyncIssueGroup] {
        Dictionary(
            grouping: statusMonitor.currentIssues,
            by: \.logFile
        )
        .map { logFile, issues in
            DriveSyncIssueGroup(
                logFile: logFile,
                timestamp:
                    issues
                        .map(\.timestamp)
                        .min() ?? Date(),
                issues:
                    issues.sorted {
                        $0.timestamp < $1.timestamp
                    }
            )
        }
        .sorted {
            $0.timestamp > $1.timestamp
        }
    }
    
    private func description(for issue: DriveSyncIssue) -> DriveSyncIssueDescription {
        switch issue.type {

        case "destinationFull":
            return DriveSyncIssueDescription(
                title: "Destination is full",
                explanation:
                    "DriveSync couldn't finish because the destination ran out of free space.",
                recommendation:
                    "Free some space on the destination and run the sync again."
            )

        case "partialTransfer":
            return DriveSyncIssueDescription(
                title: "Some items couldn't be transferred",
                explanation:
                    "DriveSync finished with one or more files or file attributes that couldn't be transferred.",
                recommendation:
                    "Run the sync again. If the issue continues, check the log for details."
            )

        case "accessDenied":
            let location = issue.location == "source" ? "source" : "destination"

            return DriveSyncIssueDescription(
                title: "DriveSync can't access the \(location)",
                explanation:
                    "DriveSync doesn't have permission to access the \(location).",
                recommendation:
                    "Allow DriveSync to access the \(location), then run the sync again."
            )

        case "syncInterrupted":
            let location = issue.location == "source" ? "source" : "destination"

            return DriveSyncIssueDescription(
                title: "\(location.capitalized) became unavailable",
                explanation:
                    "DriveSync lost access to the \(location) while the sync was running.",
                recommendation:
                    "Reconnect the \(location), then run the sync again."
            )

        case "configurationProblem":
            return DriveSyncIssueDescription(
                title: "DriveSync configuration problem",
                explanation:
                    "DriveSync couldn't start the sync because part of its configuration is missing or unavailable.",
                recommendation:
                    "Review DriveSync's settings and try the sync again."
            )

        case "internalProblem":
            return DriveSyncIssueDescription(
                title: "DriveSync encountered an internal problem",
                explanation:
                    "A component DriveSync needs to perform the sync is missing or unavailable.",
                recommendation:
                    "Try restarting DriveSync. If the issue continues, check the log for details."
            )

        case "syncFailed":
            return DriveSyncIssueDescription(
                title: "Sync failed",
                explanation:
                    "DriveSync couldn't complete the sync because an unexpected error occurred.",
                recommendation:
                    "Try the sync again. If it continues to fail, check the log for details."
            )

        default:
            return DriveSyncIssueDescription(
                title: "Sync issue",
                explanation:
                    "DriveSync encountered a problem while running the sync.",
                recommendation:
                    "Check the log for more information."
            )
        }
    }
}

struct DriveSyncIssueGroup: Identifiable {
    let logFile: String
    let timestamp: Date
    let issues: [DriveSyncIssue]

    var id: String {
        logFile
    }
}

struct DriveSyncIssueDescription {
    let title: String
    let explanation: String
    let recommendation: String
}
