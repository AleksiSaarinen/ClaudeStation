import Foundation
import Combine
import AppKit

/// Checks if a newer local build exists by comparing modification times
class UpdateChecker: ObservableObject {
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

    private var runningBinaryModTime: Date? {
        guard let path = Bundle.main.executablePath else { return nil }
        return modTime(of: path)
    }

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
        guard let runningTime = runningBinaryModTime,
              let buildTime = modTime(of: buildBinaryPath) else {
            return
        }
        let available = buildTime > runningTime
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
        // Re-run build.sh --force which kills and relaunches
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", """
            sleep 0.5
            killall -9 ClaudeStation 2>/dev/null
            sleep 0.5
            cp -R "\(buildBinaryPath.replacingOccurrences(of: "/Contents/MacOS/ClaudeStation", with: ""))" /Applications/ClaudeStation.app
            open /Applications/ClaudeStation.app
        """]
        try? task.run()
        NSApp.terminate(nil)
    }
}
