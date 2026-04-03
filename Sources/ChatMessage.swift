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
enum ContentBlock: Identifiable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: String)

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.prefix(40).hashValue)"
        case .toolUse(let id, _, _): return "tool-\(id)"
        case .toolResult(let id, _): return "result-\(id)"
        }
    }
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
