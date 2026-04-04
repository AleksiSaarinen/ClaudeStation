import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session
    @Environment(\.theme) var theme
    @State private var isAtBottom = true
    @State private var lastScrollTime: Date = .distantPast

    /// Track content length of last message to detect streaming updates
    private var lastMessageContent: Int {
        session.chatMessages.last?.content.count ?? 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BottomVisibleKey.self,
                            value: geo.frame(in: .named("chatScroll")).maxY
                        )
                    }
                    .frame(height: 1)
                    .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.chatMessages.count)
                .animation(.easeInOut(duration: 0.25), value: session.assistantState)
            }
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: "chatScroll")
            .onPreferenceChange(BottomVisibleKey.self) { maxY in
                // Generous threshold — during streaming, content grows fast and pushes
                // the bottom anchor down before scroll catches up. A tight threshold
                // causes isAtBottom to flip false permanently, killing auto-scroll.
                isAtBottom = maxY < 2000 && maxY > 0
            }
            .onAppear {
                // Single delayed scroll for initial layout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.chatMessages.count) { _, _ in
                // New message added — always scroll
                throttledScroll(proxy: proxy, force: true)
            }
            .onChange(of: lastMessageContent) { _, _ in
                // Streaming content — always scroll (throttled prevents flicker)
                throttledScroll(proxy: proxy, force: true)
            }
            .onChange(of: session.assistantState) { _, _ in
                throttledScroll(proxy: proxy, force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("ScrollToBottom"))) { _ in
                proxy.scrollTo("bottom")
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("ScrollToBottomIfNeeded"))) { _ in
                if isAtBottom {
                    proxy.scrollTo("bottom")
                }
            }
        } // ScrollViewReader

            // Floating scroll-to-bottom button (outside ScrollViewReader, inside ZStack)
            if !isAtBottom {
                VStack {
                    Spacer()
                    Button {
                        // Can't access proxy here, use notification
                        NotificationCenter.default.post(name: .init("ScrollToBottom"), object: nil)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.chromeText)
                            .frame(width: 32, height: 32)
                            .background(theme.assistantBubble)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.chromeBorder, lineWidth: 1))
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .allowsHitTesting(true)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        } // ZStack
        .background(theme.chatBackground)
        .animation(.easeInOut(duration: 0.2), value: isAtBottom)
    }

    /// Scroll to bottom, throttled to ~100ms to avoid layout thrashing during streaming.
    /// `force: true` skips the isAtBottom check (used for new messages from the user).
    private func throttledScroll(proxy: ScrollViewProxy, force: Bool) {
        guard force || isAtBottom else { return }
        let now = Date()
        guard now.timeIntervalSince(lastScrollTime) > 0.1 else { return }
        lastScrollTime = now
        proxy.scrollTo("bottom")
    }
}

// MARK: - Preference Keys

struct BottomVisibleKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

    private var textContent: String {
        // Strip [Image: path] from display text
        message.content.replacingOccurrences(
            of: "\\[Image: [^\\]]+\\]", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var imagePath: String? {
        guard let range = message.content.range(of: "\\[Image: ([^\\]]+)\\]", options: .regularExpression),
              let innerRange = message.content.range(of: "(?<=\\[Image: )[^\\]]+", options: .regularExpression)
        else { return nil }
        return String(message.content[innerRange])
    }

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 6) {
                // Image preview if attached
                if let path = imagePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Text content (without [Image: ...])
                if !textContent.isEmpty {
                    Text(textContent)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.userBubbleText)
                        .textSelection(.enabled)
                }
            }
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
    @State private var showThinking = false

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
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                } else {
                    let textBlocks = message.blocks.filter { if case .text = $0.kind { return true }; return false }
                    let hasThinking = textBlocks.count > 1 || message.blocks.contains { if case .toolUse = $0.kind { return true }; return false }

                    // "Show thinking" toggle when there's intermediate content
                    if hasThinking && !showThinking {
                        // Show only the last text block (the final answer)
                        if let lastText = textBlocks.last, case .text(let text) = lastText.kind {
                            MarkdownText(text: text)
                                .padding(.horizontal, 12)
                        }

                        // Expandable thinking toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showThinking = true }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                Text("Show reasoning (\(message.blocks.count - (textBlocks.isEmpty ? 0 : 1)) steps)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(theme.mutedText)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Show all blocks (expanded or simple response)
                        if showThinking {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showThinking = false }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                    Text("Hide reasoning")
                                        .font(.caption2)
                                }
                                .foregroundStyle(theme.mutedText)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }

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
                        }
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
        .padding(.trailing, 8)
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
        let parts = splitCodeBlocks(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isCode {
                    // Code block with syntax highlighting
                    VStack(alignment: .leading, spacing: 0) {
                        if !part.language.isEmpty {
                            Text(part.language)
                                .font(theme.monoCaption2Font)
                                .foregroundStyle(theme.mutedText)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                        }
                        Text(highlightSyntax(part.text))
                            .font(theme.monoCaption2Font)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(theme.toolCardBg)
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 4))
                            .stroke(theme.toolCardBorder, lineWidth: 1)
                    )
                } else {
                    Text(renderInline(part.text))
                        .foregroundStyle(theme.assistantText)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func renderInline(_ text: String) -> AttributedString {
        let baseFont = theme.resolvedNSFont(size: 13)

        // Insert a zero-width space after `<` when followed by a letter or `/`
        // so the markdown parser doesn't interpret <Config>, </Tag>, <T> etc. as
        // HTML tags and silently strip them from the output.
        let escaped = text.replacingOccurrences(
            of: "<([A-Za-z/])",
            with: "<\u{200B}$1",
            options: .regularExpression
        )

        if var result = try? AttributedString(markdown: escaped, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // Verify the parser didn't silently drop content
            let renderedCount = result.characters.count
            let expectedMin = text.count * 2 / 3  // allow some shrinkage from syntax removal
            if renderedCount >= expectedMin {
                for run in result.runs {
                    let isBold = result[run.range].inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
                    let isItalic = result[run.range].inlinePresentationIntent?.contains(.emphasized) ?? false
                    if isBold {
                        result[run.range].font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                    } else if isItalic {
                        result[run.range].font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                    } else {
                        result[run.range].font = baseFont
                    }
                }
                return result
            }
        }

        // Fallback: plain attributed string — no content loss
        var plain = AttributedString(text)
        plain.font = baseFont
        return plain
    }

    private struct TextPart {
        let text: String
        let isCode: Bool
        let language: String
    }

    private func splitCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let lines = text.components(separatedBy: "\n")
        var current: [String] = []
        var inCode = false
        var lang = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") && !inCode {
                // Start code block — flush accumulated prose
                let prose = current.joined(separator: "\n")
                // Only trim leading/trailing blank lines, preserve internal structure
                let trimmedProse = prose
                    .drop(while: { $0.isNewline })
                    .reversed().drop(while: { $0.isNewline }).reversed()
                let final = String(trimmedProse)
                if !final.isEmpty { parts.append(TextPart(text: final, isCode: false, language: "")) }
                current = []
                inCode = true
                lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("```") && inCode {
                // End code block
                let code = current.joined(separator: "\n")
                parts.append(TextPart(text: code, isCode: true, language: lang))
                current = []
                inCode = false
                lang = ""
            } else {
                current.append(line)
            }
        }

        let remaining = current.joined(separator: "\n")
        let trimmedRemaining = remaining
            .drop(while: { $0.isNewline })
            .reversed().drop(while: { $0.isNewline }).reversed()
        let final = String(trimmedRemaining)
        if !final.isEmpty {
            parts.append(TextPart(text: final, isCode: inCode, language: inCode ? lang : ""))
        }
        return parts
    }

    private func highlightSyntax(_ code: String) -> AttributedString {
        var result = AttributedString(code)

        let keywords = ["func", "var", "let", "if", "else", "for", "while", "return", "import",
                        "struct", "class", "enum", "case", "switch", "guard", "self", "true", "false",
                        "nil", "static", "private", "public", "async", "await", "try", "catch",
                        "def", "from", "in", "const", "function", "export", "default"]

        for keyword in keywords {
            var search = result.startIndex
            while let range = result[search...].range(of: keyword) {
                // Check word boundaries
                let before = range.lowerBound == result.startIndex ||
                    !result.characters[result.index(beforeCharacter: range.lowerBound)].isLetter
                let after = range.upperBound == result.endIndex ||
                    !result.characters[range.upperBound].isLetter
                if before && after {
                    result[range].foregroundColor = NSColor(theme.accent)
                }
                search = range.upperBound
            }
        }

        // Strings (simple quotes)
        colorPattern(&result, pattern: "\"[^\"]*\"", color: NSColor(.green.opacity(0.8)))
        // Comments
        colorPattern(&result, pattern: "//.*$", color: NSColor(theme.mutedText))

        return result
    }

    private func colorPattern(_ string: inout AttributedString, pattern: String, color: NSColor) {
        let plain = String(string.characters)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let matches = regex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for match in matches {
            guard let swiftRange = Range(match.range, in: plain) else { continue }
            let lower = AttributedString.Index(swiftRange.lowerBound, within: string)
            let upper = AttributedString.Index(swiftRange.upperBound, within: string)
            if let lower, let upper {
                string[lower..<upper].foregroundColor = color
            }
        }
    }
}

// MARK: - Selectable Text (NSTextField for easy click-anywhere text selection)

struct SelectableText: NSViewRepresentable {
    let text: String
    let theme: Theme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isEditable = false
        field.isSelectable = true
        field.drawsBackground = false
        field.isBezeled = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        field.font = theme.resolvedNSFont(size: 13)
        field.textColor = NSColor(theme.assistantText)
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
