import SwiftUI
import AppKit

struct SettingsView: View {
    let config: DriveSyncConfig
    let statusMonitor: DriveSyncStatusMonitor

    private let exclusionController = DriveSyncExclusionController()
    private let serviceController = DriveSyncServiceController()

    @State private var selectedTab = 0

    @State private var draft: SettingsDraft?
    @State private var savedDraft: SettingsDraft?

    @State private var loadError: String?
    @State private var showingLoadError = false

    @State private var saveError: String?
    @State private var showingSaveError = false

    @State private var saveSuccessMessage = ""
    @State private var showingSaveSuccess = false

    @State private var showingUnsavedChangesWarning = false
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let draftBinding = Binding($draft) {
                    TabView(selection: $selectedTab) {
                        ConfigurationView(
                            draft: draftBinding
                        )
                        .tabItem {
                            Label(
                                "Configuration",
                                systemImage: "gearshape"
                            )
                        }
                        .tag(0)

                        ExclusionsView(
                            draft: draftBinding
                        )
                        .tabItem {
                            Label(
                                "Exclusions",
                                systemImage: "nosign"
                            )
                        }
                        .tag(1)

                        DiagnosticsView(
                            config: config,
                            statusMonitor: statusMonitor
                        )
                            .tabItem {
                                Label(
                                    "Diagnostics",
                                    systemImage: "stethoscope"
                                )
                            }
                            .tag(2)
                    }
                } else {
                    ProgressView("Loading Settings…")
                }
            }
            .frame(
                minWidth: 700,
                minHeight: 500
            )
            .padding()

            Divider()

            HStack {
                Spacer()

                Button("Apply Changes") {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApplyChanges)

                Button("Close") {
                    if hasChanges {
                        showingUnsavedChangesWarning = true
                    } else {
                        closeSettingsWindow()
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            selectedTab = 0
            loadDraft()
        }
        .alert(
            "DriveSync Settings",
            isPresented: $showingLoadError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                loadError ??
                "DriveSync could not load the settings."
            )
        }
        .alert(
            "Settings Updated",
            isPresented: $showingSaveSuccess
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveSuccessMessage)
        }
        .alert(
            "DriveSync Settings",
            isPresented: $showingSaveError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                saveError ??
                "DriveSync could not apply the settings."
            )
        }
        .alert(
            "Unapplied Changes",
            isPresented: $showingUnsavedChangesWarning
        ) {
            Button("Cancel", role: .cancel) { }

            Button(
                "Discard Changes",
                role: .destructive
            ) {
                discardChangesAndClose()
            }
        } message: {
            Text(
                "You have settings changes that have not been applied."
            )
        }
        .background {
            WindowReader { window in
                settingsWindow = window

                if let window {
                    NSApplication.shared.setActivationPolicy(.regular)

                    DispatchQueue.main.async {
                        NSApplication.shared.activate()
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
    }

    private var hasChanges: Bool {
        guard
            let draft,
            let savedDraft
        else {
            return false
        }

        return draft != savedDraft
    }

    private var canApplyChanges: Bool {
        guard let draft else {
            return false
        }

        let sourceValid =
            !draft.sourcePath
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty

        let destinationValid =
            !draft.destinationPath
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty

        return
            sourceValid &&
            destinationValid &&
        !draft.scheduleTimes.isEmpty &&
        hasChanges
    }

    private func loadDraft() {
        do {
            let exclusions =
                try exclusionController.loadUserExclusions()

            let loadedDraft = SettingsDraft(
                config: config,
                exclusions: exclusions
            )

            draft = loadedDraft
            savedDraft = loadedDraft

            loadError = nil

        } catch {
            loadError = error.localizedDescription
            showingLoadError = true
        }
    }

    private func applyChanges() {
        guard
            let draft,
            let savedDraft
        else {
            return
        }

        let newScheduleTimes =
            draft.scheduleTimes.sorted()

        let previousScheduleTimes =
            savedDraft.scheduleTimes.sorted()

        let scheduleChanged =
            newScheduleTimes != previousScheduleTimes
        
        let automaticSyncingEnabled =
            serviceController.serviceStatus().allServicesLoaded

        do {
            try config.save(
                source: draft.sourcePath,
                destination: draft.destinationPath,
                scheduleTimes: newScheduleTimes,
                scheduleWindowMinutes:
                    draft.scheduleWindowMinutes,
                logRetentionDays:
                    draft.logRetentionDays,
                staleSyncDays:
                    draft.staleSyncDays
            )

            try exclusionController
                .saveUserExclusions(
                    draft.exclusions
                )

            if scheduleChanged && automaticSyncingEnabled {
                try serviceController
                    .updateSyncSchedule(
                        config: config
                    )
            }

            self.savedDraft = draft

            saveError = nil
            saveSuccessMessage =
                "DriveSync settings were updated successfully."
            showingSaveSuccess = true

        } catch {
            let originalError = error

            do {
                try config.save(
                    source: savedDraft.sourcePath,
                    destination:
                        savedDraft.destinationPath,
                    scheduleTimes:
                        previousScheduleTimes,
                    scheduleWindowMinutes:
                        savedDraft
                            .scheduleWindowMinutes,
                    logRetentionDays:
                        savedDraft.logRetentionDays,
                    staleSyncDays:
                        savedDraft.staleSyncDays
                )

                try exclusionController
                    .saveUserExclusions(
                        savedDraft.exclusions
                    )

                if scheduleChanged && automaticSyncingEnabled {
                    try serviceController
                        .updateSyncSchedule(
                            config: config
                        )
                }

                saveError = """
                DriveSync could not apply the changes.

                The previous settings were restored.

                \(originalError.localizedDescription)
                """

                showingSaveError = true

            } catch {
                saveError = """
                DriveSync could not apply the changes, and the previous settings could not be fully restored.

                Original error:
                \(originalError.localizedDescription)

                Recovery error:
                \(error.localizedDescription)
                """

                showingSaveError = true
            }
        }
    }

    private func closeSettingsWindow() {
        settingsWindow?.close()
    }

    private func discardChangesAndClose() {
        if let savedDraft {
            draft = savedDraft
        }

        showingUnsavedChangesWarning = false

        DispatchQueue.main.async {
            closeSettingsWindow()
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    let onWindowAvailable: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            onWindowAvailable(view.window)
        }

        return view
    }

    func updateNSView(
        _ nsView: NSView,
        context: Context
    ) {
        DispatchQueue.main.async {
            onWindowAvailable(nsView.window)
        }
    }
}
