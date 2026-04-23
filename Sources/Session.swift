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
    let id: UUID

    @Published var name: String
    @Published var workingDirectory: String
    @Published var status: SessionStatus = .idle
    @Published var messageQueue: [QueuedMessage] = []
    @Published var isProcessingQueue: Bool = false
    @Published var chatMessages: [ChatMessage] = []
    @Published var assistantState: AssistantState = .idle
    @Published var effortLevel: String = "xhigh"  // low, medium, high, xhigh, max
    @Published var planMode: Bool = false
    @Published var planResponseReceived: Bool = false
    @Published var lastToolName: String?
    @Published var lastToolCommand: String?
    @Published var sleepEndTime: Date?
    @Published var suggestedActions: [(icon: String, label: String, prompt: String)] = []
    @Published var contextSummary: String = ""
    @Published var totalCostUsd: Double = 0
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var lastContextSize: Int = 0  // input + cache tokens from last message = current context window usage
    @Published var rateLimitResetsAt: Date?
    @Published var rateLimitType: String?  // "five_hour", "weekly", etc.
    @Published var celebrating: Bool = false
    var celebrationStart: Date = .distantPast

    /// Claude Code session ID for --resume multi-turn
    var claudeSessionId: String?

    /// Currently running claude process (one per message)
    var activeProcess: Process?

    /// Callback for feeding raw PTY data to the terminal view (kept for SwiftTerm)
    var terminalFeed: ((Data) -> Void)?
    var terminalDataBuffer = Data()
    var terminalCols: Int = 80
    var terminalRows: Int = 24

    // Legacy PTY fields (kept for SwiftTerm background view)
    var process: Process?
    var ptyPrimary: FileHandle?

    var displayName: String {
        if !name.isEmpty { return name }
        let dir = (workingDirectory as NSString).lastPathComponent
        return dir.isEmpty ? "Session" : dir
    }

    init(id: UUID = UUID(), name: String = "", workingDirectory: String = "~") {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
    }
}
