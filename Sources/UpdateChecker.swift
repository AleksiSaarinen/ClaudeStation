import Foundation
import Combine
import AppKit

/// Checks if a newer local build exists by comparing modification times
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var updateAvailable = false

    private var timer: Timer?

    /// Path to the locally built app (build output)
    private let buildBinaryPath: String = {
        // The build output lives next to the project
        // Find the project directory from the running binary
        let runningPath = Bundle.main.executablePath ?? ""
        // Running from /Applications/ClaudeStation.app/Contents/MacOS/ClaudeStation
        // Build is at <project>/build/ClaudeStation.app/Contents/MacOS/ClaudeStation
        // We need to find the project dir — check common locations
        let home = NSHomeDirectory()
        let candidates = [
            home + "/Documents/ClaudeStation/build/ClaudeStation.app/Contents/MacOS/ClaudeStation",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }()

    /// Snapshot of the running binary's mod time, captured at launch
    private let launchBinaryModTime: Date? = {
        guard let path = Bundle.main.executablePath else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }()

    init() {
        startChecking()
    }

    func startChecking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        guard let launchTime = launchBinaryModTime,
              let installedTime = modTime(of: "/Applications/ClaudeStation.app/Contents/MacOS/ClaudeStation") else {
            return
        }
        let available = installedTime > launchTime
        if available != updateAvailable {
            DispatchQueue.main.async {
                self.updateAvailable = available
            }
        }
    }

    private func modTime(of path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    func restart() {
        let buildAppPath = buildBinaryPath.replacingOccurrences(of: "/Contents/MacOS/ClaudeStation", with: "")
        // Use nohup so the script survives app termination
        let script = """
            sleep 0.3
            killall -9 ClaudeStation 2>/dev/null
            sleep 0.5
            rm -rf /Applications/ClaudeStation.app
            cp -R "\(buildAppPath)" /Applications/ClaudeStation.app
            open /Applications/ClaudeStation.app
        """
        // Write script to temp file and execute detached
        let scriptPath = NSTemporaryDirectory() + "claudestation_restart.sh"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]
        task.qualityOfService = .background
        // Detach from parent process group so it survives our exit
        task.arguments = ["-c", "nohup bash \(scriptPath) &"]
        try? task.run()
        // Give the script a moment to start, then exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.terminate(nil)
        }
    }
}
