import SwiftUI
import AppKit

struct ContentView: View {
    let config: DriveSyncConfig
    let statusMonitor: DriveSyncStatusMonitor

    @State private var loadError: String?
    @State private var window: NSWindow?

    @State private var initialLoadComplete = false
    @State private var setupWasShown = false
    @State private var setupSucceeded = false

    private let mainWindowFrameName = "DriveSyncMainWindow"

    var body: some View {
        Group {
            if !initialLoadComplete {
                ProgressView("Loading DriveSync…")
                    .frame(
                        minWidth: 300,
                        minHeight: 450
                    )

            } else if let loadError {
                VStack(spacing: 12) {
                    Text("DriveSync could not load its configuration.")
                        .font(.headline)
                    
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
            } else if config.isConfigured && (!setupWasShown || setupSucceeded) {
                MainView(
                    config: config,
                    statusMonitor: statusMonitor
                )

            } else {
                SetupView(config: config) {
                    setupSucceeded = true
                }
            }
        }
        .task {
            do {
                try config.load()

                let issueStore = DriveSyncIssueStore()

                do {
                    try issueStore.pruneIssues(
                        retentionDays: config.logRetentionDays
                    )
                } catch {
                    print(
                        "DriveSync could not prune issue history: \(error.localizedDescription)"
                    )
                }

                setupWasShown = !config.isConfigured
                initialLoadComplete = true

                restoreMainWindowFrameIfNeeded()

            } catch {
                loadError = error.localizedDescription
                initialLoadComplete = true
            }
        }
        .background {
            ContentWindowReader { window in
                self.window = window
                restoreMainWindowFrameIfNeeded()
            }
        }
        .onChange(of: setupSucceeded) { oldValue, newValue in
            guard
                initialLoadComplete,
                setupWasShown,
                oldValue == false,
                newValue == true
            else {
                return
            }

            // Setup has just completed.
            setupWasShown = false

            guard let window else {
                return
            }

            // Give MainView a sensible size after the larger SetupView.
            window.setContentSize(
                NSSize(
                    width: 300,
                    height: 450
                )
            )

            // From this point forward, remember whatever size
            // this user chooses for the Main window.
            window.setFrameAutosaveName(mainWindowFrameName)
        }
    }

    private func restoreMainWindowFrameIfNeeded() {
        guard
            initialLoadComplete,
            config.isConfigured,
            !setupWasShown,
            let window
        else {
            return
        }

        window.setFrameAutosaveName(mainWindowFrameName)
    }
}

private struct ContentWindowReader: NSViewRepresentable {
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
