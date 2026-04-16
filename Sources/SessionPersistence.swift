import Foundation

/// Persists session metadata and chat history to disk
struct SessionPersistence {
    private static let dirPath = NSHomeDirectory() + "/.claudestation"
    private static let filePath = dirPath + "/sessions.json"
    private static let activeIdPath = dirPath + "/active_session_id"

    struct SavedSession: Codable {
        let id: String
        let name: String
        let workingDirectory: String
        let claudeSessionId: String?
        let chatMessages: [ChatMessage]
        let contextSummary: String?
        let totalCostUsd: Double?
    }

    static func save(sessions: [Session], activeSessionId: UUID?) {
        let saved = sessions.map { session in
            SavedSession(
                id: session.id.uuidString,
                name: session.name,
                workingDirectory: session.workingDirectory,
                claudeSessionId: session.claudeSessionId,
                chatMessages: Array(session.chatMessages.suffix(100)), // Keep last 100 messages
                contextSummary: session.contextSummary.isEmpty ? nil : session.contextSummary,
                totalCostUsd: session.totalCostUsd > 0 ? session.totalCostUsd : nil
            )
        }

        do {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: URL(fileURLWithPath: filePath))
            if let activeId = activeSessionId {
                try activeId.uuidString.write(toFile: activeIdPath, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silent fail — persistence is best-effort
        }
    }

    static func load() -> (sessions: [Session], activeSessionId: UUID?) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let saved = try? JSONDecoder().decode([SavedSession].self, from: data)
        else { return ([], nil) }

        let sessions = saved.map { s in
            let id = UUID(uuidString: s.id) ?? UUID()
            let session = Session(id: id, name: s.name, workingDirectory: s.workingDirectory)
            session.claudeSessionId = s.claudeSessionId
            session.chatMessages = s.chatMessages
            session.contextSummary = s.contextSummary ?? ""
            // Bootstrap totalCostUsd from message costs if not persisted yet
            if let saved = s.totalCostUsd, saved > 0 {
                session.totalCostUsd = saved
            } else {
                session.totalCostUsd = session.chatMessages.compactMap(\.costUsd).reduce(0, +)
            }
            session.status = .waitingForInput
            return session
        }

        let activeId: UUID?
        if let str = try? String(contentsOfFile: activeIdPath, encoding: .utf8) {
            activeId = UUID(uuidString: str.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            activeId = nil
        }

        return (sessions, activeId)
    }
}
