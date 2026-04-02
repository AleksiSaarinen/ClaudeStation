import Foundation
import SwiftUI

// MARK: - Session Status

enum SessionStatus: String {
    case idle = "Idle"
    case running = "Running"
    case waitingForInput = "Waiting"
    case error = "Error"
}

// MARK: - Queued Message

enum QueuedMessageStatus {
    case queued
    case sending
    case sent
}

struct QueuedMessage: Identifiable {
    let id = UUID()
    var text: String
    var status: QueuedMessageStatus = .queued
    var createdAt = Date()
}

// MARK: - Session

class Session: ObservableObject, Identifiable {
    let id = UUID()

    @Published var name: String
    @Published var workingDirectory: String
    @Published var outputBuffer: String = ""
    @Published var status: SessionStatus = .idle
    @Published var messageQueue: [QueuedMessage] = []
    @Published var isProcessingQueue: Bool = false
    var trustAccepted: Bool = false

    var process: Process?
    var ptyPrimary: FileHandle?

    /// Callback for feeding raw PTY data to the terminal view
    var terminalFeed: ((Data) -> Void)?

    var displayName: String {
        if !name.isEmpty { return name }
        let dir = (workingDirectory as NSString).lastPathComponent
        return dir.isEmpty ? "Session" : dir
    }

    init(name: String = "", workingDirectory: String = "~") {
        self.name = name
        self.workingDirectory = workingDirectory
    }
}
