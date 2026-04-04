import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

enum AssistantState: Equatable {
    case idle
    case thinking(String)
    case responding
    case done

    static func == (lhs: AssistantState, rhs: AssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.responding, .responding), (.done, .done): return true
        case (.thinking(let a), .thinking(let b)): return a == b
        default: return false
        }
    }
}

/// A structured block within an assistant response
struct ContentBlock: Identifiable, Codable {
    let id: String
    let kind: ContentBlockKind

    static func text(_ text: String) -> ContentBlock {
        ContentBlock(id: "text-\(UUID().uuidString)", kind: .text(text))
    }
    static func toolUse(id: String, name: String, input: [String: Any]) -> ContentBlock {
        let inputJson = (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ContentBlock(id: "tool-\(id)", kind: .toolUse(name: name, inputJson: inputJson))
    }
    static func toolResult(toolUseId: String, content: String) -> ContentBlock {
        ContentBlock(id: "result-\(toolUseId)", kind: .toolResult(content: content))
    }

    /// Convenience to get tool input as dictionary
    var toolInput: [String: Any] {
        if case .toolUse(_, let json) = kind,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }
}

enum ContentBlockKind: Codable {
    case text(String)
    case toolUse(name: String, inputJson: String)
    case toolResult(content: String)
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var content: String
    var blocks: [ContentBlock]
    let timestamp: Date
    var durationSeconds: Double?
    var durationApiMs: Int?
    var costUsd: Double?
    var attachedImagePath: String?

    init(role: ChatRole, content: String, blocks: [ContentBlock] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.blocks = blocks
        self.timestamp = Date()
    }
}
