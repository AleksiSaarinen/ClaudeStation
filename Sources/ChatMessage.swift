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

/// A structured block within an assistant response
enum ContentBlock: Identifiable {
    case text(String)
    case toolUse(name: String, args: String, output: [String])
    case timing(String)

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.prefix(40).hashValue)"
        case .toolUse(let n, let a, _): return "tool-\(n)-\(a.prefix(30).hashValue)"
        case .timing(let s): return "time-\(s.hashValue)"
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    var blocks: [ContentBlock] = []
    let timestamp = Date()
    var isStreaming: Bool = false
    var durationSeconds: Double?
}

// MARK: - Output Parser

/// Parses raw PTY output to extract chat messages
class OutputParser {
    private var currentResponseBuffer = ""
    private var isCollectingResponse = false

    /// Known thinking indicator words from Claude Code
    static let thinkingWords = [
        "Noodling", "Waddling", "Harmonizing", "Pondering", "Crunching",
        "Churning", "Sprouting", "Evaporating", "Percolating", "Simmering",
        "Mulling", "Embellishing", "Fluttering", "Bootstrapping",
        "Lollygagging", "Cascading", "Herding", "Thuddering"
    ]

    /// Known tool names in Claude Code
    private static let toolNames: Set<String> = [
        "Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent",
        "TodoRead", "TodoWrite", "WebFetch", "WebSearch",
        "NotebookEdit", "Skill", "ToolSearch"
    ]

    /// Characters used by Claude Code's spinner animation
    private static let chromeChars: Set<Character> = ["✻", "✶", "✳", "✢", "✽", "✹", "❯", "⏵", "⎿"]

    // MARK: - ANSI Stripping

    static func stripAnsi(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9]*C", with: " ", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9]*B", with: "\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\u{1B}[^\\[\\]][^\u{1B}]?", with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "")
        return result
    }

    // MARK: - Detection

    static func thinkingIndicator(in text: String) -> String? {
        let clean = stripAnsi(text)
        for word in thinkingWords {
            if clean.contains(word) { return "\(word)..." }
        }
        return nil
    }

    static func containsPrompt(_ text: String) -> Bool {
        let clean = stripAnsi(text)
        return clean.contains("❯")
    }

    // MARK: - Block Extraction

    /// Extract structured content blocks from accumulated terminal output
    static func extractBlocks(_ raw: String) -> [ContentBlock] {
        let clean = stripAnsi(raw)
        let lines = clean.components(separatedBy: "\n")

        var blocks: [ContentBlock] = []
        var inBlock = false
        var skipChromeContinuation = false
        var currentToolName: String?
        var currentToolArgs: String = ""
        var currentToolOutput: [String] = []
        var currentTextLines: [String] = []

        func flushText() {
            let text = currentTextLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.text(text))
            }
            currentTextLines = []
        }

        func flushTool() {
            if let name = currentToolName {
                blocks.append(.toolUse(name: name, args: currentToolArgs, output: currentToolOutput))
                currentToolName = nil
                currentToolArgs = ""
                currentToolOutput = []
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ⏺ marks start of a Claude output block
            if trimmed.hasPrefix("⏺") {
                inBlock = true
                skipChromeContinuation = false
                var content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)

                // Split at chrome characters and keep the longest real segment
                // (handles both "Hello! ✻ Thinking…" and "✻Hello!" cases)
                let segments = content.split { chromeChars.contains($0) }
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !isChromeLine($0) && !isAnimationNoise($0) }
                let hadChrome = content.contains(where: { chromeChars.contains($0) })
                skipChromeContinuation = hadChrome
                content = segments.max(by: { $0.count < $1.count }) ?? ""

                // Split space-padded content
                if !content.isEmpty {
                    let segments = content.replacingOccurrences(
                        of: " {2,}", with: "\n", options: .regularExpression
                    ).components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    content = segments.joined(separator: "\n")
                }

                guard !content.isEmpty else { continue }

                // Check if this is a tool use block: ToolName(args...)
                if let parsed = parseToolUse(content) {
                    flushText()
                    flushTool()
                    currentToolName = parsed.name
                    currentToolArgs = parsed.args
                    currentToolOutput = []
                } else {
                    // It's a text block — filter chrome/noise from ⏺ content too
                    flushTool()
                    for segment in content.components(separatedBy: "\n") {
                        if !segment.isEmpty && !isChromeLine(segment) && !isAnimationNoise(segment) {
                            currentTextLines.append(segment)
                        }
                    }
                }
                continue
            }

            // ❯ prompt = end of response, but only on short prompt-like lines.
            // Mid-line ❯ from cursor positioning artifacts shouldn't kill the block.
            if trimmed.hasPrefix("❯") && trimmed.count < 10 {
                inBlock = false
                skipChromeContinuation = false
                continue
            }

            guard inBlock else { continue }

            if skipChromeContinuation {
                if trimmed.isEmpty { skipChromeContinuation = false }
                continue
            }

            if trimmed.isEmpty { continue }
            if isChromeLine(trimmed) { continue }
            // Filter animation fragments (short letter-only lines from spinner)
            if trimmed.count <= 3 && trimmed.allSatisfy({ $0.isLetter || $0 == " " || $0 == "…" }) { continue }

            // Clean line
            var cleanLine = trimmed
            if cleanLine.hasPrefix("⎿") {
                cleanLine = String(cleanLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if cleanLine.hasPrefix("● ") {
                cleanLine = String(cleanLine.dropFirst(2))
            }
            // Re-check chrome/noise after prefix stripping (catches ⎿ Tip:... etc.)
            if cleanLine.isEmpty || isChromeLine(cleanLine) || isAnimationNoise(cleanLine) { continue }
            // Remove trailing chrome chars
            for (i, ch) in cleanLine.enumerated() {
                if chromeChars.contains(ch) {
                    cleanLine = String(cleanLine.prefix(i)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            guard !cleanLine.isEmpty else { continue }

            // Route to current tool output or text
            if currentToolName != nil {
                currentToolOutput.append(cleanLine)
            } else {
                // Skip animation noise from spinner (short fragments with animation chars or letter pairs)
                if isAnimationNoise(cleanLine) { continue }
                currentTextLines.append(cleanLine)
            }
        }

        flushTool()
        flushText()

        return blocks
    }

    /// Parse a tool use line like "Read(file.swift)" or "Bash(ls -la)"
    private static func parseToolUse(_ content: String) -> (name: String, args: String)? {
        // Match: ToolName(args) or ToolName(args...)
        let firstLine = content.components(separatedBy: "\n").first ?? content
        guard let parenIdx = firstLine.firstIndex(of: "(") else { return nil }
        let name = String(firstLine[firstLine.startIndex..<parenIdx])
        guard toolNames.contains(name) else { return nil }
        var args = String(firstLine[firstLine.index(after: parenIdx)...])
        if args.hasSuffix(")") { args = String(args.dropLast()) }
        return (name: name, args: args)
    }

    // MARK: - Legacy plain-text extraction (uses extractBlocks internally)

    static func extractResponse(_ raw: String) -> String {
        let blocks = extractBlocks(raw)
        return blocks.compactMap { block in
            switch block {
            case .text(let s): return s
            case .toolUse(let name, let args, _): return "\(name)(\(args))"
            case .timing(let s): return s
            }
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a short line is animation noise from spinner rendering
    private static func isAnimationNoise(_ line: String) -> Bool {
        let animChars: Set<Character> = ["✻", "✶", "✳", "✢", "·", "✽", "✹", "✦"]
        // Any line containing animation/decoration characters
        if line.contains(where: { animChars.contains($0) }) { return true }
        // Short lines of only symbols/punctuation (Bristle owl art, decoration)
        if line.count <= 6 && line.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return true }
        // Short fragments: all words <= 3 chars and all letters
        if line.count <= 6 {
            let words = line.split(separator: " ")
            if words.allSatisfy({ $0.count <= 3 && $0.allSatisfy({ $0.isLetter || $0 == "…" }) }) { return true }
        }
        return false
    }

    /// Check if a line is Claude Code UI chrome
    private static func isChromeLine(_ line: String) -> Bool {
        let animationChars: Set<Character> = ["✻", "✶", "✳", "✢", "·", "✽", "✹"]
        if line.allSatisfy({ animationChars.contains($0) || $0.isWhitespace }) { return true }
        if line.hasPrefix("⏵") { return true }
        if line.contains("bypass permissions") || line.contains("bypasspermissions") { return true }
        if line.contains("esc to interrupt") { return true }
        // Progress bars, context usage, branch status
        if line.contains("ctx ") && line.contains("%") { return true }
        if line.contains("[") && line.contains("]") && line.contains("  ") && line.count < 80
            && line.filter({ $0 == " " }).count > line.count / 3 { return true }
        if line.hasPrefix("main ") || line.hasPrefix("master ") { return true }
        if line.contains("In-flight") || line.contains("in-flight") { return true }
        if line == "(No output)" { return true }
        if line.contains("2>/dev/null") || line.contains("2>|") { return true }
        if line.contains("shift+tab to cycle") { return true }
        if line.contains("ctrl+o") || line.contains("ctrl+b") { return true }
        // Tool feedback lines (e.g., "Reading 1 file…")
        if line.hasPrefix("Reading ") && line.hasSuffix("…") { return true }
        if line.hasPrefix("Tip:") || line.hasPrefix("Tip: /") { return true }
        if line.hasPrefix("Added ") && line.contains("line") { return true }
        if line.hasPrefix("Changed ") && line.contains("line") { return true }
        if line.hasPrefix("Removed ") && line.contains("line") { return true }
        if line.contains("(✦)") || line.contains("(+)") { return true }
        if line.contains("(running stop hook)") || line.contains("(running start hook)") { return true }
        if line.contains("Bristle") { return true }
        // Box-drawing borders (Bristle speech box, decorations)
        if line.hasPrefix("│") || line.hasPrefix("╭") || line.hasPrefix("╰") { return true }
        if line.contains("/\\  /\\") { return true }
        if line.contains("((") && line.contains("))") && line.count < 30 { return true }
        if line.contains("><") && line.contains("(") && line.count < 30 { return true }
        if line.contains("*blinks") || line.contains("*ruffles") || line.contains("*adjusts") || line.contains("*tilts") { return true }
        if line.contains("Owl ") && line.count < 60 { return true }
        if line.allSatisfy({ "─━─-—=_╭╮╰╯│┌┐└┘├┤┬┴┼`´'\" ".contains($0) }) { return true }
        for word in thinkingWords {
            if line.contains(word) { return true }
        }
        if line.hasSuffix("…") && !line.contains(" ") && line.count < 20 { return true }
        if line.hasPrefix("(thinking)") { return true }
        // Owl art fragments
        if line.hasPrefix("/\\") || line.hasPrefix("\\/") { return true }
        if line.hasPrefix("(( )") || line.hasPrefix("( (") { return true }
        if line.hasPrefix("(") && line.hasSuffix(")") && line.count < 15
            && line.allSatisfy({ "() ".contains($0) }) { return true }
        return false
    }
}
