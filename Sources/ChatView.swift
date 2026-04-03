import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session
    @Environment(\.theme) var theme

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

                    if case .thinking(let text) = session.assistantState {
                        ThinkingIndicator(text: text)
                            .id("thinking")
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    }

                    // Invisible scroll anchor at the very bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.chatMessages.count)
                .animation(.easeInOut(duration: 0.25), value: session.assistantState)
            }
            .background(theme.chatBg)
            .onChange(of: session.chatMessages.count) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom")
                    }
                }
            }
            .onChange(of: session.assistantState) { _, newState in
                if case .thinking = newState {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom")
                    }
                }
            }
        }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    @ObservedObject var session: Session
    @Environment(\.theme) var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(theme.mutedText)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0.0)
            Text("Claude Code")
                .font(.title3.bold())
                .foregroundStyle(theme.assistantText)
                .opacity(appeared ? 1.0 : 0.0)
            Text(session.workingDirectory)
                .font(.caption)
                .foregroundStyle(theme.mutedText)
                .fontDesign(.monospaced)
                .opacity(appeared ? 1.0 : 0.0)
            Text(session.status == .waitingForInput ? "Ready. Type a message below." : "Starting Claude...")
                .font(.caption)
                .foregroundStyle(theme.mutedText)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }
}

// MARK: - User Message

struct UserMessageRow: View {
    let message: ChatMessage
    @Environment(\.theme) var theme
    @State private var appeared = false

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(theme.monoFont)
                .foregroundStyle(theme.userBubbleText)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
                .scaleEffect(appeared ? 1.0 : 0.92)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageRow: View {
    let message: ChatMessage
    @Environment(\.theme) var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Circle().fill(theme.accent).frame(width: 6, height: 6)
                Text("Claude").font(.caption2.bold()).foregroundStyle(theme.chromeText)
                if let secs = message.durationSeconds {
                    Text("·").foregroundStyle(theme.mutedText)
                    Image(systemName: "clock").font(.caption2).foregroundStyle(theme.timestampText)
                    Text(formatDuration(secs)).font(.caption2).foregroundStyle(theme.timestampText)
                }
                if let cost = message.costUsd, cost > 0 {
                    Text("·").foregroundStyle(theme.mutedText)
                    Text(String(format: "$%.3f", cost)).font(.caption2).foregroundStyle(theme.costText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Content blocks
            VStack(alignment: .leading, spacing: 6) {
                if message.blocks.isEmpty {
                    Text(message.content)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.assistantText)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(Array(message.blocks.enumerated()), id: \.element.id) { index, block in
                        Group {
                            switch block.kind {
                            case .text(let text):
                                MarkdownText(text: text)
                            case .toolUse(let name, _):
                                ToolUseCard(name: name, input: block.toolInput)
                            case .toolResult(let content):
                                ToolResultCard(content: content)
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
        .background(theme.assistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius)
                .stroke(theme.assistantBubbleBorder, lineWidth: 1)
        )
        .padding(.trailing, 24)
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Markdown Text

struct MarkdownText: View {
    let text: String
    @Environment(\.theme) var theme

    var body: some View {
        Text(rendered)
            .font(theme.monoFont)
            .foregroundStyle(theme.assistantText)
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Tool Use Card

struct ToolUseCard: View {
    let name: String
    let input: [String: Any]
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon)
                .font(.caption)
                .foregroundStyle(toolColor)
                .frame(width: 16)
            Text(name)
                .font(theme.monoCaptionFont.bold())
                .foregroundStyle(toolColor)
            Text(toolSummary)
                .font(theme.monoCaptionFont)
                .foregroundStyle(theme.toolCardText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.toolCardBg)
        .clipShape(RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 0)))
        .overlay(
            RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 0))
                .stroke(theme.toolCardBorder, lineWidth: 1)
        )
    }

    private var toolSummary: String {
        if let path = input["file_path"] as? String { return (path as NSString).lastPathComponent }
        if let cmd = input["command"] as? String { return String(cmd.prefix(60)) }
        if let pattern = input["pattern"] as? String { return pattern }
        if let desc = input["description"] as? String { return String(desc.prefix(50)) }
        return ""
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

    var toolColor: Color { theme.accent }
}

// MARK: - Tool Result Card

struct ToolResultCard: View {
    let content: String
    @Environment(\.theme) var theme
    @State private var expanded = false

    var body: some View {
        if !content.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.caption2)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("\(content.components(separatedBy: "\n").count) lines output").font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(theme.mutedText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(content.prefix(2000)))
                            .font(theme.monoCaption2Font)
                            .foregroundStyle(theme.toolCardText)
                            .textSelection(.enabled)
                        if content.count > 2000 {
                            Text("... truncated (\(content.count - 2000) more characters)")
                                .font(theme.monoCaption2Font)
                                .foregroundStyle(theme.mutedText)
                                .italic()
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(theme.toolCardBg)
            .clipShape(RoundedRectangle(cornerRadius: max(theme.borderRadius - 6, 0)))
            .overlay(
                RoundedRectangle(cornerRadius: max(theme.borderRadius - 6, 0))
                    .stroke(theme.toolCardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let text: String
    @Environment(\.theme) var theme
    @State private var dotCount = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotCount % 3 == i ? 1.3 : 0.7)
                        .opacity(dotCount % 3 == i ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.4), value: dotCount)
                }
            }
            Text(text)
                .font(theme.monoCaptionFont)
                .foregroundStyle(theme.mutedText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in dotCount += 1 }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
