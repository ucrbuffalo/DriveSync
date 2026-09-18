import SwiftUI
import AppKit

struct ConfigurationView: View {
    @Binding var draft: SettingsDraft

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Files")
                        .font(.headline)

                    folderRow(
                        title: "Source",
                        path: draft.sourcePath,
                        buttonTitle: "Choose Source…"
                    ) {
                        if let url = chooseFolder() {
                            draft.sourcePath = url.path
                        }
                    }

                    folderRow(
                        title: "Destination",
                        path: draft.destinationPath,
                        buttonTitle: "Choose Destination…"
                    ) {
                        if let url = chooseFolder() {
                            draft.destinationPath = url.path
                        }
                    }

                    Divider()

                    Text("Schedule")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sync Times")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(draft.scheduleTimes.indices, id: \.self) { index in
                            HStack(spacing: 12) {
                                DatePicker(
                                    "",
                                    selection: syncTimeBinding(for: index),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                Button {
                                    draft.scheduleTimes.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(draft.scheduleTimes.count <= 1)
                                .help("Remove sync time")
                            }
                        }

                        Button {
                            addSyncTime()
                        } label: {
                            Label("Add Sync Time", systemImage: "plus")
                        }

                        if draft.scheduleTimes.isEmpty {
                            Text("Add at least one sync time.")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule Window")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Stepper(
                            "\(draft.scheduleWindowMinutes) minutes",
                            value: $draft.scheduleWindowMinutes,
                            in: 1...59
                        )
                    }

                    Divider()

                    Text("Maintenance")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Log Retention")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Stepper(
                            "\(draft.logRetentionDays) days",
                            value: $draft.logRetentionDays,
                            in: 1...365
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stale Sync Threshold")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Stepper(
                            "\(draft.staleSyncDays) days",
                            value: $draft.staleSyncDays,
                            in: 1...365
                        )
                    }
                }
                .padding(24)
            }
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
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Text(path.isEmpty ? "No folder selected" : path)
                    .foregroundStyle(
                        path.isEmpty ? .secondary : .primary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                Button(buttonTitle, action: action)
            }
        }
    }

    private func syncTimeBinding(
        for index: Int
    ) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = draft.scheduleTimes[index].hour
                components.minute = draft.scheduleTimes[index].minute

                return Calendar.current.date(
                    from: components
                ) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: newDate
                )

                guard
                    let hour = components.hour,
                    let minute = components.minute
                else {
                    return
                }

                draft.scheduleTimes[index] = SyncTime(
                    hour: hour,
                    minute: minute
                )
            }
        )
    }

    private func addSyncTime() {
        let existingTimes = Set(draft.scheduleTimes)

        for hour in 0...23 {
            let candidate = SyncTime(
                hour: hour,
                minute: 0
            )

            if !existingTimes.contains(candidate) {
                draft.scheduleTimes.append(candidate)
                draft.scheduleTimes.sort()
                return
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

        return panel.runModal() == .OK
            ? panel.url
            : nil
    }
}
