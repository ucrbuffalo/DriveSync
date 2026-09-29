import SwiftUI
import AppKit

struct SetupView: View {
    let config: DriveSyncConfig
    let onSetupCompleted: () -> Void
    private let serviceController = DriveSyncServiceController()
    private let exclusionController = DriveSyncExclusionController()
    
    @State private var sourcePath: String
    @State private var destinationPath: String
    @State private var exclusions: [String] = []
    
    @State private var saveError: String?
    @State private var exclusionError: String?
    @State private var setupInProgress = false

    init(
        config: DriveSyncConfig,
        onSetupCompleted: @escaping () -> Void
    ) {
        self.config = config
        self.onSetupCompleted = onSetupCompleted
        _sourcePath = State(initialValue: config.sourcePath)
        _destinationPath = State(initialValue: config.destinationPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                Text("Welcome to DriveSync")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Choose the source folder you want to back up and the destination where DriveSync should copy it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            Divider()

            folderRow(
                title: "Source",
                path: sourcePath,
                buttonTitle: "Choose Source…"
            ) {
                if let url = chooseFolder() {
                    sourcePath = url.path
                }
            }

            folderRow(
                title: "Destination",
                path: destinationPath,
                buttonTitle: "Choose Destination…"
            ) {
                if let url = chooseFolder() {
                    destinationPath = url.path
                }
            }
            
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Exclusions (Optional)")
                    .font(.headline)

                Text("Choose any folders or files inside the Source that DriveSync should skip.")
                    .foregroundStyle(.secondary)

                if exclusions.isEmpty {
                    Text("No exclusions configured.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(exclusions.enumerated()), id: \.offset) { index, exclusion in
                            HStack {
                                Text(exclusion)
                                    .textSelection(.enabled)

                                Spacer()

                                Button {
                                    exclusions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Remove exclusion")
                            }
                        }
                    }
                }

                HStack {
                    Button("Add Folder") {
                        addExclusionFolder()
                    }
                    .disabled(
                        sourcePath.isEmpty ||
                        destinationPath.isEmpty
                    )

                    Button("Add File") {
                        addExclusionFile()
                    }
                    .disabled(
                        sourcePath.isEmpty ||
                        destinationPath.isEmpty
                    )
                }

                if let exclusionError {
                    Text(exclusionError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sync Schedule")
                    .font(.headline)

                Text("By default, DriveSync will run automatically at:")

                Text(formattedScheduleTimes)
                    .fontWeight(.semibold)
                    .padding(.vertical, 6)

                Text("The sync schedule and additional options can be adjusted at any time in DriveSync Settings.")
                    .foregroundStyle(.secondary)
            }
            
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
            }
            
            Spacer()

            HStack {
                Spacer()

                Button("Finish Setup") {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    sourcePath.isEmpty ||
                    destinationPath.isEmpty ||
                    setupInProgress
                )
            }
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 720)
        .task {
            loadExclusions()
        }
    }

    private func finishSetup() {
        guard !setupInProgress else {
            return
        }

        setupInProgress = true
        saveError = nil

        defer {
            setupInProgress = false
        }

        let previousSource = config.sourcePath
        let previousDestination = config.destinationPath
        let previousSetupComplete = config.setupComplete

        let previousExclusions: [String]

        do {
            previousExclusions =
                try exclusionController.loadUserExclusions()
        } catch {
            saveError = """
            DriveSync could not read the existing exclusions.

            \(error.localizedDescription)
            """
            return
        }

        // Track whether we attempted to activate scheduled services.
        // A failure after that point requires service cleanup.
        var activationAttempted = false

        do {
            // Setup is incomplete until every step succeeds.
            try config.setSetupComplete(false)

            try config.save(
                source: sourcePath,
                destination: destinationPath,
                scheduleTimes: config.scheduleTimes,
                scheduleWindowMinutes: config.scheduleWindowMinutes,
                logRetentionDays: config.logRetentionDays,
                staleSyncDays: config.staleSyncDays
            )

            try exclusionController.saveUserExclusions(
                exclusions
            )

            activationAttempted = true

            try serviceController.configureAndActivateServices(
                config: config
            )

            // Commit completion only after both services are active.
            try config.setSetupComplete(true)

            // Setup already succeeded; a failed check must not roll it back.
            try? serviceController.requestAccessCheck()

            saveError = nil
            onSetupCompleted()

        } catch {
            let originalError = error
            var recoveryErrors: [String] = []

            // Never leave a partially activated schedule running
            // after Setup has failed.
            if activationAttempted {
                do {
                    try serviceController.deactivateServices()
                } catch {
                    recoveryErrors.append(
                        "Service cleanup: \(error.localizedDescription)"
                    )
                }
            }

            // Restore the previous configuration and exclusions.
            do {
                try config.save(
                    source: previousSource,
                    destination: previousDestination,
                    scheduleTimes: config.scheduleTimes,
                    scheduleWindowMinutes: config.scheduleWindowMinutes,
                    logRetentionDays: config.logRetentionDays,
                    staleSyncDays: config.staleSyncDays
                )
            } catch {
                recoveryErrors.append(
                    "Configuration recovery: \(error.localizedDescription)"
                )
            }

            do {
                try exclusionController.saveUserExclusions(
                    previousExclusions
                )
            } catch {
                recoveryErrors.append(
                    "Exclusions recovery: \(error.localizedDescription)"
                )
            }

            // Do not restore a completed state if service cleanup failed.
            // That could conceal a partially configured installation.
            if recoveryErrors.isEmpty {
                do {
                    try config.setSetupComplete(
                        previousSetupComplete
                    )
                } catch {
                    recoveryErrors.append(
                        "Setup state recovery: \(error.localizedDescription)"
                    )
                }
            }

            if recoveryErrors.isEmpty {
                saveError = originalError.localizedDescription
            } else {
                saveError = """
                Setup failed:
                \(originalError.localizedDescription)

                Recovery also encountered problems:
                \(recoveryErrors.joined(separator: "\n"))

                DriveSync may require manual recovery before Setup can be retried.
                """
            }
        }
    }
    
    private func loadExclusions() {
        do {
            exclusions = try exclusionController.loadUserExclusions()
            exclusionError = nil
        } catch {
            exclusionError = error.localizedDescription
        }
    }
    
    @ViewBuilder
    private func folderRow(
        title: String,
        path: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack {
                Text(path.isEmpty ? "No folder selected" : path)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(buttonTitle, action: action)
            }
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        return panel.runModal() == .OK ? panel.url : nil
    }
    
    private var formattedScheduleTimes: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let formattedTimes = config.scheduleTimes
            .sorted()
            .compactMap { time -> String? in
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute

                guard let date = Calendar.current.date(from: components) else {
                    return nil
                }

                return formatter.string(from: date)
            }

        if formattedTimes.isEmpty {
            return "No schedule configured"
        }

        if formattedTimes.count == 1 {
            return formattedTimes[0]
        }

        if formattedTimes.count == 2 {
            return "\(formattedTimes[0]) and \(formattedTimes[1])"
        }

        return formattedTimes.dropLast().joined(separator: ", ")
            + ", and "
            + formattedTimes.last!
    }
    
    private func addExclusionFolder() {
        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Exclude Folder"

        panel.directoryURL = URL(fileURLWithPath: sourcePath)

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        addExclusion(
            url: url,
            isDirectory: true
        )
    }

    private func addExclusionFile() {
        let panel = NSOpenPanel()

        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Exclude File"

        panel.directoryURL = URL(fileURLWithPath: sourcePath)

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        addExclusion(
            url: url,
            isDirectory: false
        )
    }

    private func addExclusion(
        url: URL,
        isDirectory: Bool
    ) {
        do {
            let pattern = try exclusionController.exclusionPattern(
                for: url,
                sourcePath: sourcePath,
                isDirectory: isDirectory
            )

            guard !exclusions.contains(pattern) else {
                return
            }

            exclusions.append(pattern)
            exclusions.sort()

            exclusionError = nil

        } catch {
            exclusionError = error.localizedDescription
        }
    }
}
