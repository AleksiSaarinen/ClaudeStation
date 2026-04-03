import Foundation

/// Persists session metadata and chat history to disk
struct SessionPersistence {
    private static let dirPath = NSHomeDirectory() + "/.claudestation"
    private static let filePath = dirPath + "/sessions.json"

    struct SavedSession: Codable {
        let id: String
        let name: String
        let workingDirectory: String
        let claudeSessionId: String?
        let chatMessages: [ChatMessage]
    }

    static func save(sessions: [Session]) {
        let saved = sessions.map { session in
            SavedSession(
                id: session.id.uuidString,
                name: session.name,
                workingDirectory: session.workingDirectory,
                claudeSessionId: session.claudeSessionId,
                chatMessages: Array(session.chatMessages.suffix(100)) // Keep last 100 messages
            )
        }

        do {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: URL(fileURLWithPath: filePath))
        } catch {
            // Silent fail — persistence is best-effort
        }
    }

    static func load() -> [Session] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let saved = try? JSONDecoder().decode([SavedSession].self, from: data)
        else { return [] }

        return saved.map { s in
            let session = Session(name: s.name, workingDirectory: s.workingDirectory)
            session.claudeSessionId = s.claudeSessionId
            session.chatMessages = s.chatMessages
            session.status = .waitingForInput
            return session
        }
    }
}
