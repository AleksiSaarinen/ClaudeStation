import Foundation

enum ChatRole {
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
struct ContentBlock: Identifiable {
    let id: String
    let kind: ContentBlockKind

    static func text(_ text: String) -> ContentBlock {
        ContentBlock(id: "text-\(UUID().uuidString)", kind: .text(text))
    }
    static func toolUse(id: String, name: String, input: [String: Any]) -> ContentBlock {
        ContentBlock(id: "tool-\(id)", kind: .toolUse(name: name, input: input))
    }
    static func toolResult(toolUseId: String, content: String) -> ContentBlock {
        ContentBlock(id: "result-\(toolUseId)", kind: .toolResult(content: content))
    }
}

enum ContentBlockKind {
    case text(String)
    case toolUse(name: String, input: [String: Any])
    case toolResult(content: String)
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    var blocks: [ContentBlock] = []
    let timestamp = Date()
    var durationSeconds: Double?
    var durationApiMs: Int?
    var costUsd: Double?
}
