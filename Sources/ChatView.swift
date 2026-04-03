import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.chatMessages.isEmpty && session.status != .idle {
                        WelcomeCard(session: session)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .padding(.top, 20)
                    }

                    ForEach(session.chatMessages) { message in
                        if message.role == .user {
                            UserMessageRow(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        } else {
                            AssistantMessageRow(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }

                    // Thinking indicator
                    if case .thinking(let text) = session.assistantState {
                        ThinkingIndicator(text: text)
                            .id("thinking")
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.chatMessages.count)
                .animation(.easeInOut(duration: 0.25), value: session.assistantState)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: session.chatMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let last = session.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.assistantState) { _, newState in
                if case .thinking = newState {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    @ObservedObject var session: Session
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0.0)

            Text("Claude Code")
                .font(.title3.bold())
                .opacity(appeared ? 1.0 : 0.0)

            Text(session.workingDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
                .opacity(appeared ? 1.0 : 0.0)

            Group {
                if session.status == .running || session.status == .waitingForInput {
                    Text("Ready. Type a message below.")
                } else {
                    Text("Starting Claude...")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .opacity(appeared ? 1.0 : 0.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }
}

// MARK: - User Message

struct UserMessageRow: View {
    let message: ChatMessage
    @State private var appeared = false

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
                .scaleEffect(appeared ? 1.0 : 0.92)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

// MARK: - Assistant Message (Structured Blocks)

struct AssistantMessageRow: View {
    let message: ChatMessage
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 6, height: 6)
                Text("Claude")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                if let secs = message.durationSeconds {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formatDuration(secs))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Content blocks
            VStack(alignment: .leading, spacing: 6) {
                if message.blocks.isEmpty {
                    TextBlockView(text: message.content)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(Array(message.blocks.enumerated()), id: \.element.id) { index, block in
                        Group {
                            switch block {
                            case .text(let text):
                                TextBlockView(text: text)
                            case .toolUse(let name, let args, let output):
                                ToolUseBlockView(name: name, args: args, output: output)
                            case .timing:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 12)
                        .opacity(appeared ? 1.0 : 0.0)
                        .offset(y: appeared ? 0 : 6)
                        .animation(
                            .easeOut(duration: 0.3).delay(Double(index) * 0.06),
                            value: appeared
                        )
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.trailing, 24)
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Text Block

struct TextBlockView: View {
    let text: String

    private var isCodeLike: Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return false }
        let codeIndicators = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("diff ") || t.hasPrefix("---") || t.hasPrefix("+++")
                || t.hasPrefix("@@") || t.hasPrefix("index ")
                || t.hasPrefix("$ ") || t.hasPrefix("> ")
                || t.contains(" | ") && (t.contains("+") || t.contains("-"))
                || t.hasSuffix(".swift") || t.hasSuffix(".json") || t.hasSuffix(".py")
        }
        return codeIndicators.count >= 2
    }

    var body: some View {
        if isCodeLike {
            let parts = splitTextAndCode(text)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.isCode {
                        Text(part.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(part.text)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            Text(text)
                .font(.system(.body, design: .default))
                .textSelection(.enabled)
        }
    }

    private func splitTextAndCode(_ text: String) -> [(text: String, isCode: Bool)] {
        let lines = text.components(separatedBy: "\n")
        var parts: [(text: String, isCode: Bool)] = []
        var current: [String] = []
        var currentIsCode = false

        func flush() {
            let joined = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                parts.append((text: joined, isCode: currentIsCode))
            }
            current = []
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            let lineIsCode = t.hasPrefix("diff ") || t.hasPrefix("---") || t.hasPrefix("+++")
                || t.hasPrefix("@@") || t.hasPrefix("index ")
                || t.hasPrefix("$ ") || t.hasPrefix("> ")
                || t.contains(" | ") && (t.contains("+") || t.contains("-"))

            if lineIsCode != currentIsCode && !current.isEmpty {
                flush()
            }
            currentIsCode = lineIsCode
            current.append(line)
        }
        flush()
        return parts
    }
}

// MARK: - Tool Use Block

struct ToolUseBlockView: View {
    let name: String
    let args: String
    let output: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: toolIcon)
                        .font(.caption)
                        .foregroundStyle(toolColor)
                        .frame(width: 16)

                    Text(name)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(toolColor)

                    Text("(\(args))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if !output.isEmpty {
                        HStack(spacing: 3) {
                            Text(expanded ? "Hide" : "\(output.count) line\(output.count == 1 ? "" : "s")")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Tool output
            if expanded && !output.isEmpty {
                Divider()
                    .padding(.horizontal, 8)
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(output.prefix(20).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if output.count > 20 {
                        Text("... +\(output.count - 20) more lines")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(toolColor.opacity(0.15), lineWidth: 1)
        )
    }

    var toolIcon: String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Glob": return "magnifyingglass"
        case "Grep": return "text.magnifyingglass"
        case "Agent": return "person.2"
        case "WebFetch", "WebSearch": return "globe"
        default: return "wrench"
        }
    }

    var toolColor: Color {
        switch name {
        case "Read": return .blue
        case "Write": return .green
        case "Edit": return .orange
        case "Bash": return .purple
        case "Glob", "Grep": return .cyan
        case "Agent": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Timing

struct TimingView: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .padding(.leading, 4)
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let text: String
    @State private var dotCount = 0

    var body: some View {
        HStack(spacing: 8) {
            // Animated dots
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotCount % 3 == i ? 1.3 : 0.7)
                        .opacity(dotCount % 3 == i ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.4),
                            value: dotCount
                        )
                }
            }

            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount += 1
            }
        }
    }
}

// MARK: - Make AssistantState equatable for onChange
extension AssistantState: Equatable {
    static func == (lhs: AssistantState, rhs: AssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.thinking(let a), .thinking(let b)): return a == b
        case (.responding, .responding): return true
        case (.done, .done): return true
        default: return false
        }
    }
}
