import AppKit
import Foundation

/// In-memory ring buffer of recent log lines, mirrored to NSLog.
/// Use `DebugLog.log(...)` instead of NSLog directly so the user can
/// copy the buffer to clipboard from Settings to share back when
/// diagnosing UI issues like the chat-scroll-on-tab-switch race.
final class DebugLog {
    static let shared = DebugLog()

    private let queue = DispatchQueue(label: "com.claudestation.debuglog")
    private var buffer: [String] = []
    private let maxLines = 2000
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)"
        NSLog("%@", line)
        queue.async {
            self.buffer.append(line)
            if self.buffer.count > self.maxLines {
                self.buffer.removeFirst(self.buffer.count - self.maxLines)
            }
        }
    }

    func snapshot() -> String {
        queue.sync { buffer.joined(separator: "\n") }
    }

    func clear() {
        queue.async { self.buffer.removeAll() }
    }

    func copyToPasteboard() -> Int {
        let text = snapshot()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return text.count
    }
}
