import Foundation
import SwiftUI

// MARK: - Launch Profile

struct LaunchProfile: Identifiable, Codable {
    var id = UUID()
    var name: String
    var workingDirectory: String
    var flags: [String] = []
    var planMode: Bool = false
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var claudeCodePath: String {
        didSet { UserDefaults.standard.set(claudeCodePath, forKey: "claudeCodePath") }
    }
    @Published var defaultWorkingDirectory: String {
        didSet { UserDefaults.standard.set(defaultWorkingDirectory, forKey: "defaultWorkingDirectory") }
    }
    @Published var alwaysBypassPermissions: Bool {
        didSet { UserDefaults.standard.set(alwaysBypassPermissions, forKey: "alwaysBypassPermissions") }
    }
    @Published var autoProcessQueue: Bool {
        didSet { UserDefaults.standard.set(autoProcessQueue, forKey: "autoProcessQueue") }
    }
    @Published var maxOutputBufferLines: Int {
        didSet { UserDefaults.standard.set(maxOutputBufferLines, forKey: "maxOutputBufferLines") }
    }

    @Published var launchProfiles: [LaunchProfile] = []

    private init() {
        let defaults = UserDefaults.standard
        self.claudeCodePath = defaults.string(forKey: "claudeCodePath") ?? "claude"
        self.defaultWorkingDirectory = defaults.string(forKey: "defaultWorkingDirectory") ?? "~/Documents/ClaudeStation"
        // Use object(forKey:) so we can distinguish "never set" from "set to false"
        self.alwaysBypassPermissions = defaults.object(forKey: "alwaysBypassPermissions") as? Bool ?? true
        self.autoProcessQueue = defaults.object(forKey: "autoProcessQueue") as? Bool ?? true
        self.maxOutputBufferLines = defaults.object(forKey: "maxOutputBufferLines") as? Int ?? 10000
        loadProfiles()
    }

    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: "launchProfiles"),
           let profiles = try? JSONDecoder().decode([LaunchProfile].self, from: data) {
            launchProfiles = profiles
        }
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(launchProfiles) {
            UserDefaults.standard.set(data, forKey: "launchProfiles")
        }
    }
}
