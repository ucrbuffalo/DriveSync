import SwiftUI
import AppKit

struct ExclusionsView: View {
    @Binding var draft: SettingsDraft

    private let exclusionController = DriveSyncExclusionController()

    @State private var errorMessage: String?
    @State private var showingError = false
    
    @State private var showingSystemExclusions = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Folders and files listed here will not be copied to the destination.")
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("User Exclusions")
                        .font(.headline)

                    if draft.exclusions.isEmpty {
                        Text("No user exclusions configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(draft.exclusions.enumerated()), id: \.offset) { index, exclusion in
                                HStack {
                                    Text(exclusion)
                                        .textSelection(.enabled)

                                    Spacer()

                                    Button {
                                        draft.exclusions.remove(at: index)
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
                            addFolder()
                        }

                        Button("Add File") {
                            addFile()
                        }

                        Spacer()
                    }

                    Divider()

                    HStack {
                        Text("System Exclusions")
                            .font(.headline)

                        Spacer()

                        Button(showingSystemExclusions ? "Hide" : "Show") {
                            showingSystemExclusions.toggle()
                        }
                    }

                    Text("DriveSync automatically excludes common system and metadata files. These exclusions are managed by DriveSync and cannot be edited here.")
                        .foregroundStyle(.secondary)

                    if showingSystemExclusions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(".Spotlight-V100/")
                            Text(".Trashes/")
                            Text(".TemporaryItems/")
                            Text(".fseventsd/")
                            Text("Thumbs.db")
                            Text("._*")
                            Text(".DS_Store")
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
        }
        
        .alert(
            "DriveSync Exclusions",
            isPresented: $showingError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "DriveSync could not update exclusions.")
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Exclude Folder"

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        do {
            let pattern = try exclusionController.exclusionPattern(
                for: url,
                sourcePath: draft.sourcePath,
                isDirectory: true
            )

            addExclusionIfNeeded(pattern)

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func addFile() {
        let panel = NSOpenPanel()

        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Exclude File"

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        do {
            let pattern = try exclusionController.exclusionPattern(
                for: url,
                sourcePath: draft.sourcePath,
                isDirectory: false
            )

            addExclusionIfNeeded(pattern)

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func addExclusionIfNeeded(_ pattern: String) {
        guard !draft.exclusions.contains(pattern) else {
            return
        }

        draft.exclusions.append(pattern)
        draft.exclusions.sort()
    }
}
