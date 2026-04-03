import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ProfilesSettingsTab(settings: settings, sessionManager: sessionManager)
                .tabItem {
                    Label("Profiles", systemImage: "person.crop.rectangle.stack")
                }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Claude Code") {
                TextField("Binary Path", text: $settings.claudeCodePath)
                    .textFieldStyle(.roundedBorder)

                TextField("Default Working Directory", text: $settings.defaultWorkingDirectory)
                    .textFieldStyle(.roundedBorder)

                Toggle("Always bypass permissions (--dangerously-skip-permissions)",
                       isOn: $settings.alwaysBypassPermissions)
            }

            Section("Queue Behavior") {
                Toggle("Auto-process queue when Claude is ready",
                       isOn: $settings.autoProcessQueue)
            }

            Section("Display") {
                Stepper("Max output buffer: \(settings.maxOutputBufferLines) lines",
                        value: $settings.maxOutputBufferLines,
                        in: 1000...50000,
                        step: 1000)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Profiles Settings

struct ProfilesSettingsTab: View {
    @ObservedObject var settings: AppSettings
    var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($settings.launchProfiles) { $profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Name", text: $profile.name)
                                .textFieldStyle(.plain)
                                .font(.headline)
                            TextField("Working Directory", text: $profile.workingDirectory)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Launch") {
                            sessionManager.createSessionFromProfile(profile)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            settings.launchProfiles.removeAll { $0.id == profile.id }
                            settings.saveProfiles()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                Button {
                    settings.launchProfiles.append(
                        LaunchProfile(name: "New Profile", workingDirectory: "~")
                    )
                    settings.saveProfiles()
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }

                Spacer()
            }
            .padding(12)
        }
    }
}
