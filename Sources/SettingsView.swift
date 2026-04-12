import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            ThemeSettingsTab()
                .tabItem {
                    Label("Themes", systemImage: "paintbrush")
                }

            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ProfilesSettingsTab(settings: settings, sessionManager: sessionManager)
                .tabItem {
                    Label("Profiles", systemImage: "person.crop.rectangle.stack")
                }
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - Theme Settings

struct ThemeSettingsTab: View {
    @AppStorage("selectedTheme") private var selectedThemeId = "midnight"
    @AppStorage("customMonoFont") private var customMonoFont = ""
    @AppStorage("selectedCursorPack") private var selectedCursorPack = "system"
    @Environment(\.theme) var theme

    let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Font picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font")
                        .font(.headline)
                    let fontCols = [GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 8)]
                    LazyVGrid(columns: fontCols, spacing: 8) {
                        ForEach(Theme.availableMonoFonts, id: \.self) { font in
                            let active = (customMonoFont.isEmpty ? theme.fontMono : customMonoFont) == font
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    customMonoFont = font
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    Text("Aa 01")
                                        .font(.custom(font, size: 13))
                                        .frame(height: 18)
                                    Text(font)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(active ? theme.accent.opacity(0.15) : Color.primary.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? theme.accent : Color.primary.opacity(0.1), lineWidth: active ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // Cursor picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cursor")
                        .font(.headline)
                    let cursorCols = [GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 8)]
                    LazyVGrid(columns: cursorCols, spacing: 8) {
                        ForEach(CursorPack.all) { pack in
                            let active = selectedCursorPack == pack.id
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedCursorPack = pack.id
                                    CursorManager.applyPack(pack.id)
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    if pack.id == "system" {
                                        Image(systemName: "cursorarrow")
                                            .font(.system(size: 16))
                                            .frame(height: 22)
                                    } else {
                                        CursorPreview(packId: pack.id)
                                            .frame(height: 22)
                                    }
                                    Text(pack.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(active ? theme.accent.opacity(0.15) : Color.primary.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? theme.accent : Color.primary.opacity(0.1), lineWidth: active ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // Theme picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Theme.all) { t in
                            ThemeSwatch(theme: t, isSelected: t.id == selectedThemeId)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedThemeId = t.id
                                    }
                                }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Mini preview
            VStack(spacing: 3) {
                // User bubble
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.userBubble)
                        .frame(width: 40, height: 10)
                }

                // Assistant bubble
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.accent.opacity(0.4))
                            .frame(width: 30, height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.assistantText.opacity(0.3))
                            .frame(width: 55, height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.assistantText.opacity(0.2))
                            .frame(width: 45, height: 6)
                    }
                    .padding(5)
                    .background(theme.assistantBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.assistantBubbleBorder, lineWidth: 1)
                    )
                    Spacer()
                }

                // Tool card mini
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.toolCardBg)
                        .frame(width: 50, height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(theme.toolCardBorder, lineWidth: 0.5)
                        )
                    Spacer()
                }

                Spacer()

                // Input bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.inputBg)
                    .frame(height: 8)
                    .overlay(
                        HStack(spacing: 2) {
                            Circle().fill(theme.promptColor).frame(width: 3, height: 3)
                            Spacer()
                        }.padding(.horizontal, 3)
                    )
            }
            .padding(8)
            .frame(height: 90)
            .background(theme.chatBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Label
            Text(theme.name)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? theme.accent : .secondary)
                .padding(.top, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 2)
                .padding(-2)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
                                .textFieldStyle(.plain).font(.headline)
                            TextField("Working Directory", text: $profile.workingDirectory)
                                .textFieldStyle(.plain).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Launch") {
                            sessionManager.createSessionFromProfile(profile)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Button(role: .destructive) {
                            settings.launchProfiles.removeAll { $0.id == profile.id }
                            settings.saveProfiles()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Button {
                    settings.launchProfiles.append(LaunchProfile(name: "New Profile", workingDirectory: "~"))
                    settings.saveProfiles()
                } label: { Label("Add Profile", systemImage: "plus") }
                Spacer()
            }
            .padding(12)
        }
    }
}

struct CursorPreview: View {
    let packId: String

    var body: some View {
        let resourcePath = Bundle.main.resourcePath ?? ""
        let path = "\(resourcePath)/Cursors/\(packId)/arrow.png"
        if let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "cursorarrow")
                .font(.system(size: 16))
        }
    }
}
