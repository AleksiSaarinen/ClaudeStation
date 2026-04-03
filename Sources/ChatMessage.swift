import Foundation

enum ChatRole {
    case user
    case assistant
    case system
}

enum AssistantState {
    case idle
    case thinking(String) // "Noodling...", "Waddling...", etc.
    case responding
    case done
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    let timestamp = Date()
    var isStreaming: Bool = false
}

/// Parses raw PTY output to extract chat messages
class OutputParser {
    private var currentResponseBuffer = ""
    private var isCollectingResponse = false

    /// Known thinking indicator words from Claude Code
    private static let thinkingWords = [
        "Noodling", "Waddling", "Harmonizing", "Pondering", "Crunching",
        "Churning", "Sprouting", "Evaporating", "Percolating", "Simmering"
    ]

    /// Strip all ANSI escape codes and terminal control sequences
    static func stripAnsi(_ text: String) -> String {
        var result = text
        // CSI sequences (colors, cursor, modes)
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        // OSC sequences (title, etc.)
        result = result.replacingOccurrences(
            of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
        // Other escape sequences
        result = result.replacingOccurrences(
            of: "\u{1B}[^\\[\\]][^\u{1B}]{0,10}",
            with: "",
            options: .regularExpression
        )
        // Carriage returns
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "")
        return result
    }

    /// Check if text contains a thinking indicator
    static func thinkingIndicator(in text: String) -> String? {
        let clean = stripAnsi(text)
        for word in thinkingWords {
            if clean.contains(word) {
                return "\(word)..."
            }
        }
        return nil
    }

    /// Check if text contains the Claude prompt (ready for input)
    static func containsPrompt(_ text: String) -> Bool {
        let clean = stripAnsi(text)
        return clean.contains("❯")
    }

    /// Extract clean response text from accumulated terminal output
    /// Removes prompt lines, status bars, Bristle messages, empty lines
    static func extractResponse(_ raw: String) -> String {
        let clean = stripAnsi(raw)
        let lines = clean.components(separatedBy: "\n")

        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines, prompt lines, status bars, Bristle
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("❯") { continue }
            if trimmed.hasPrefix("▸") || trimmed.hasPrefix("▹") { continue }
            if trimmed.contains("bypass permissions") { continue }
            if trimmed.contains("Bristle") { continue }
            if trimmed.contains("esc to interrupt") { continue }
            if trimmed.contains("shift+tab to cycle") { continue }
            if trimmed.contains("(+)(+)") || trimmed.contains("(+)") { continue }
            if trimmed.hasPrefix("●") || trimmed.hasPrefix("✦") { continue }
            if trimmed.hasPrefix("/\\") || trimmed.hasPrefix("\\/") { continue }
            if trimmed.hasPrefix("( )") || trimmed.hasPrefix("< )") { continue }
            if trimmed.contains("ruffles feather") || trimmed.contains("tilts h") { continue }
            if trimmed.contains("shifts on branch") { continue }
            // Skip spinner characters
            if trimmed.count <= 2 { continue }
            // Skip lines that are just dashes/decoration
            if trimmed.allSatisfy({ "─━─-—=_".contains($0) }) { continue }

            // Keep thinking indicators but mark them
            var isThinking = false
            for word in thinkingWords {
                if trimmed.contains(word) {
                    isThinking = true
                    break
                }
            }
            if isThinking { continue }

            // Clean bullet point prefix
            var cleanLine = trimmed
            if cleanLine.hasPrefix("● ") {
                cleanLine = String(cleanLine.dropFirst(2))
            }

            result.append(cleanLine)
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
