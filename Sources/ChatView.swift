import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session
    var onSuggestionTap: ((String) -> Void)? = nil
    @Environment(\.theme) var theme
    @State private var lastScrollTime: Date = .distantPast
    @State private var chatScrollView: NSScrollView?
    @State private var userScrolledUp = false
    @State private var scrollObservers: [NSObjectProtocol] = []
    @State private var isProgrammaticScroll = false
    @State private var chatPreviewImages: [String] = []
    @State private var chatPreviewIndex: Int? = nil
    @State private var visibleMessageCount: Int = 20

    /// Dynamic bottom offset accounting for input bar + queue strip
    private var bottomInsetOffset: CGFloat {
        let inputBar: CGFloat = 56
        if session.messageQueue.isEmpty { return inputBar }
        // Queue header (~30) + per-pill (~34) + padding (~16)
        let queueHeight: CGFloat = 30 + CGFloat(min(session.messageQueue.count, 3)) * 34 + 16
        return inputBar + queueHeight
    }

    /// Track content length of last message to detect streaming updates
    private var lastMessageContent: Int {
        session.chatMessages.last?.content.count ?? 0
    }

    /// Track block count of last message to detect tool use updates
    private var lastMessageBlockCount: Int {
        session.chatMessages.last?.blocks.count ?? 0
    }

    /// Check if the last assistant message looks like a completed plan (not a permission request)
    private var lastMessageLooksLikePlan: Bool {
        guard let last = session.chatMessages.last else { return false }
        let hasExitPlanMode = last.blocks.contains { block in
            if case .toolUse(let name, _) = block.kind { return name == "ExitPlanMode" }
            return false
        }
        let hasPlanWrite = last.blocks.contains { block in
            if case .toolUse(let name, _) = block.kind { return name == "Write" }
            return false
        }
        return hasExitPlanMode || hasPlanWrite
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Capture reference to the parent NSScrollView
                ScrollViewFinder { sv in
                    chatScrollView = sv
                    observeUserScroll(sv)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom()
                    }
                }
                .frame(height: 0)
                if session.chatMessages.isEmpty && session.status != .idle {
                    WelcomeCard(session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .padding(.top, 20)
                }

                // Show "Load older" button when there are hidden messages
                let totalCount = session.chatMessages.count
                let visibleMessages = Array(session.chatMessages.suffix(visibleMessageCount))
                if totalCount > visibleMessageCount {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            visibleMessageCount = min(visibleMessageCount + 20, totalCount)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle").font(.caption)
                            Text("Load \(min(20, totalCount - visibleMessageCount)) older messages (\(totalCount - visibleMessageCount) hidden)")
                                .font(.caption)
                        }
                        .foregroundStyle(theme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(theme.assistantBubble.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                ForEach(visibleMessages) { message in
                    if message.role == .user {
                        UserMessageRow(message: message, onImageTap: { paths, idx in
                            chatPreviewImages = paths
                            chatPreviewIndex = idx
                        })
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        let isLast = message.id == session.chatMessages.last?.id
                        let isStreaming = isLast
                            && session.assistantState == .responding
                        let isActive = isLast && session.status == .running
                        AssistantMessageRow(message: message, isStreaming: isStreaming, isLatestMessage: isLast, isActive: isActive)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }

                if case .thinking(let text) = session.assistantState {
                    ThinkingPetIndicator(session: session, text: text)
                        .id("thinking")
                        .transition(.opacity.combined(with: .scale(scale: 0.3, anchor: .leading)))
                }

                // Suggested actions after Claude finishes
                if session.status == .waitingForInput
                    && session.chatMessages.last?.role == .assistant
                    && !session.planMode {
                    SuggestedActions(session: session, onTap: { text in
                        onSuggestionTap?(text)
                    })
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Execute Plan button — only shows when Claude finished a plan
                // (contains ExitPlanMode or a plan file write, not permission requests)
                if session.planMode
                    && session.status == .waitingForInput
                    && session.chatMessages.last?.role == .assistant
                    && lastMessageLooksLikePlan
                    && session.planResponseReceived {
                    ExecutePlanButton(session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.chatMessages.count)
            .animation(.easeInOut(duration: 0.25), value: session.assistantState)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: session.suggestedActions.count)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onChange(of: session.chatMessages.count) { old, new in
            // User sent a message → reset and scroll
            if new > old, let last = session.chatMessages.last, last.role == .user {
                userScrolledUp = false
            }
            if !userScrolledUp { bouncyScrollToBottom() }
        }
        .onChange(of: lastMessageContent) { _, _ in
            if !userScrolledUp { scrollToBottom() }
        }
        .onChange(of: session.suggestedActions.count) { _, _ in
            if !userScrolledUp { smoothScrollToBottom() }
        }
        .onChange(of: lastMessageBlockCount) { _, _ in
            if !userScrolledUp { scrollToBottom() }
        }
        .onChange(of: session.assistantState) { _, _ in
            if !userScrolledUp { scrollToBottom() }
        }
        .onChange(of: session.messageQueue.count) { _, _ in
            // Queue strip appearing/growing changes bottom inset — re-scroll after layout settles
            if !userScrolledUp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    smoothScrollToBottom()
                }
            }
        }
        .onAppear {
            userScrolledUp = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollToBottom()
            }
        }
        .onDisappear {
            // Clean up notification observers
            for observer in scrollObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            scrollObservers = []
        }
        .overlay(alignment: .bottom) {
            if userScrolledUp && !session.chatMessages.isEmpty {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.chromeText)
                    .frame(width: 32, height: 32)
                    .modifier(LiquidGlassChrome())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .contentShape(Circle())
                    .onTapGesture {
                        userScrolledUp = false
                        bouncyScrollToBottom()
                    }
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.7)),
                        removal: .scale(scale: 0.8).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: userScrolledUp)
        .overlay {
            if let idx = chatPreviewIndex, idx < chatPreviewImages.count,
               let img = NSImage(contentsOfFile: chatPreviewImages[idx]) {
                let paths = chatPreviewImages
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { chatPreviewIndex = nil }
                    .overlay {
                        HStack(spacing: 0) {
                            if idx > 0 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { chatPreviewIndex = idx - 1 }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 12)
                            } else {
                                Spacer().frame(width: 56)
                            }

                            Spacer()

                            VStack(spacing: 8) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 700, maxHeight: 500)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 20)
                                    .onTapGesture {}
                                    .id(idx)
                                    .transition(.opacity)
                                if paths.count > 1 {
                                    Text("\(idx + 1) / \(paths.count)  ·  \(Int(img.size.width)) × \(Int(img.size.height))")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                } else {
                                    Text("\(Int(img.size.width)) × \(Int(img.size.height))")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                            }

                            Spacer()

                            if idx < paths.count - 1 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { chatPreviewIndex = idx + 1 }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 12)
                            } else {
                                Spacer().frame(width: 56)
                            }
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: chatPreviewIndex)
    }

    /// Subscribe to NSScrollView clip view bounds changes to detect user scrolls.
    /// Uses isProgrammaticScroll flag to distinguish user vs code scrolls.
    private func observeUserScroll(_ scrollView: NSScrollView) {
        for observer in scrollObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollObservers = []

        // Enable bounds change notifications on the clip view
        scrollView.contentView.postsBoundsChangedNotifications = true

        let boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [self] _ in
            // Skip if this was triggered by our own scrollToBottom()
            guard !isProgrammaticScroll else { return }

            if isScrollViewAtBottom(scrollView) {
                userScrolledUp = false
            } else {
                userScrolledUp = true
            }
        }
        scrollObservers.append(boundsObserver)
    }

    private func isScrollViewAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let docView = scrollView.documentView else { return true }
        let contentHeight = docView.bounds.height
        let viewportHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.origin.y
        let inputBarOffset: CGFloat = 56
        return offsetY + viewportHeight >= contentHeight - 80 + inputBarOffset
    }

    /// Scroll the underlying NSScrollView to the bottom.
    private func scrollToBottom() {
        let now = Date()
        guard now.timeIntervalSince(lastScrollTime) > 0.05 else { return }
        lastScrollTime = now

        DispatchQueue.main.async {
            guard let scrollView = chatScrollView,
                  let docView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = docView.bounds.height
            guard docHeight > visibleHeight else { return }
            // Add offset for the input bar safeAreaInset which overlaps the scroll view
            let target = NSPoint(x: 0, y: docHeight - visibleHeight + bottomInsetOffset)
            let currentY = scrollView.contentView.bounds.origin.y
            guard currentY < target.y - 1 else { return }
            isProgrammaticScroll = true
            scrollView.contentView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isProgrammaticScroll = false
            }
        }
    }

    private func smoothScrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let scrollView = chatScrollView,
                  let docView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = docView.bounds.height
            guard docHeight > visibleHeight else { return }
            let target = NSPoint(x: 0, y: docHeight - visibleHeight + bottomInsetOffset)
            isProgrammaticScroll = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.contentView.animator().setBoundsOrigin(target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }, completionHandler: {
                isProgrammaticScroll = false
            })
        }
    }

    private func bouncyScrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let scrollView = chatScrollView,
                  let docView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = docView.bounds.height
            guard docHeight > visibleHeight else { return }
            let target = NSPoint(x: 0, y: docHeight - visibleHeight + bottomInsetOffset)
            let overshoot = NSPoint(x: 0, y: target.y + 35)
            isProgrammaticScroll = true

            // Phase 1: Quick scroll past the bottom
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(overshoot)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }, completionHandler: {
                // Phase 2: Spring back to target
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.contentView.animator().setBoundsOrigin(target)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }, completionHandler: {
                    isProgrammaticScroll = false
                })
            })
        }
    }
}


// MARK: - NSView helpers

/// Invisible view that captures a reference to its parent NSScrollView
struct ScrollViewFinder: NSViewRepresentable {
    var onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = Self.findParentScrollView(of: view) {
                onFound(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func findParentScrollView(of view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let sv = v as? NSScrollView { return sv }
            current = v.superview
        }
        return nil
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
    var onImageTap: (([String], Int) -> Void)? = nil
    @Environment(\.theme) var theme
    @State private var appeared = false

    private var textContent: String {
        // Strip [Image: path] from display text
        message.content.replacingOccurrences(
            of: "\\[Image: [^\\]]+\\]", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var imagePaths: [String] {
        var paths: [String] = []
        var text = message.content
        while let range = text.range(of: "(?<=\\[Image: )[^\\]]+", options: .regularExpression) {
            paths.append(String(text[range]))
            // Move past this match
            if let fullRange = text.range(of: "\\[Image: [^\\]]+\\]", options: .regularExpression) {
                text = String(text[fullRange.upperBound...])
            } else {
                break
            }
        }
        return paths
    }

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 6) {
                // Image previews
                if !imagePaths.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(imagePaths.enumerated()), id: \.element) { index, path in
                            if let image = NSImage(contentsOfFile: path) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .cursor(.pointingHand)
                                    .onTapGesture {
                                        onImageTap?(imagePaths, index)
                                    }
                            }
                        }
                    }
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
            .background(theme.userBubble.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(appeared ? 1.0 : 0.85, anchor: .trailing)
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageRow: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var isLatestMessage: Bool = false
    var isActive: Bool = false
    @Environment(\.theme) var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Circle().fill(theme.accent).frame(width: 6, height: 6)
                Text("Claude").font(.caption2.bold()).foregroundStyle(theme.chromeText)
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
                    // Group blocks into: text (always visible) + tool chains (collapsible)
                    let groups = groupBlocks(message.blocks)
                    let lastToolIdx = groups.lastIndex(where: { if case .tools = $0 { return true }; return false })
                    ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                        switch group {
                        case .text(let text, _):
                            MarkdownText(text: text, isStreaming: isStreaming)
                                .padding(.horizontal, 12)
                        case .tools(let blocks):
                            CollapsibleToolGroup(blocks: blocks, message: message, isLatestMessage: isLatestMessage, isLastToolGroup: idx == lastToolIdx, totalGroups: groups.count)
                                .padding(.horizontal, 12)
                        }
                    }
                }

                // Streaming cursor
                if isStreaming {
                    StreamingCursor()
                        .padding(.horizontal, 12)
                }
            }

            // Footer: live timer while Claude is working, duration + cost after completion
            if isActive {
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.caption2)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formatDuration(context.date.timeIntervalSince(message.timestamp)))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            } else if let secs = message.durationSeconds, secs > 0 {
                HStack(spacing: 5) {
                    let verb = message.completionVerb ?? "Baked"
                    Text("\(verb) for \(formatDuration(secs))").font(.caption2)
                    if let cost = message.costUsd, cost > 0 {
                        Text("·")
                        Text(formatCost(cost)).font(.caption2)
                    }
                }
                .foregroundStyle(theme.mutedText)
                .padding(.horizontal, 12)
                .padding(.top, 2)
            }

            Spacer().frame(height: 10)
        }
        .background(theme.assistantBubble.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.assistantBubbleBorder.opacity(0.25), lineWidth: 0.5)
        )
        .padding(.trailing, 8)
        .scaleEffect(appeared ? 1.0 : 0.9, anchor: .leading)
        .offset(y: appeared ? 0 : 6)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { appeared = true }
        }
    }

    // MARK: - Block Grouping

    private enum BlockGroup {
        case text(String, id: String)
        case tools([ContentBlock])
    }

    /// Group consecutive blocks: text blocks stay individual, consecutive tool use/result blocks merge.
    private func groupBlocks(_ blocks: [ContentBlock]) -> [BlockGroup] {
        var groups: [BlockGroup] = []
        var currentTools: [ContentBlock] = []

        func flushTools() {
            if !currentTools.isEmpty {
                groups.append(.tools(currentTools))
                currentTools = []
            }
        }

        for block in blocks {
            switch block.kind {
            case .text(let text):
                flushTools()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    groups.append(.text(text, id: block.id))
                }
            case .toolUse, .toolResult:
                currentTools.append(block)
            }
        }
        flushTools()
        return groups
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        if cost < 0.10 { return String(format: "$%.3f", cost) }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Collapsible Tool Group

/// Groups consecutive tool use + result blocks. Shows individual cards when few, collapses into a summary when many.
struct CollapsibleToolGroup: View {
    let blocks: [ContentBlock]
    let message: ChatMessage
    let isLatestMessage: Bool
    let isLastToolGroup: Bool
    let totalGroups: Int
    @Environment(\.theme) var theme
    @State private var expanded: Bool

    init(blocks: [ContentBlock], message: ChatMessage, isLatestMessage: Bool = false, isLastToolGroup: Bool = true, totalGroups: Int = 1) {
        self.blocks = blocks
        self.message = message
        self.isLatestMessage = isLatestMessage
        self.isLastToolGroup = isLastToolGroup
        self.totalGroups = totalGroups
        let toolCount = blocks.filter { if case .toolUse = $0.kind { return true }; return false }.count
        // Auto-collapse: only expand the last tool group in the latest message
        _expanded = State(initialValue: isLatestMessage && isLastToolGroup && toolCount <= 4)
    }

    private var toolSummaryLabel: String {
        var counts: [(String, Int)] = []
        for block in blocks {
            if case .toolUse(let name, _) = block.kind {
                let display: String
                switch name {
                case "Grep", "Glob": display = "Search"
                case "Bash": display = "Run"
                case "WebFetch": display = "Fetch"
                case "WebSearch": display = "Web"
                case "Agent": display = "Agent"
                default: display = name
                }
                if let idx = counts.firstIndex(where: { $0.0 == display }) {
                    counts[idx].1 += 1
                } else {
                    counts.append((display, 1))
                }
            }
        }
        let parts = counts.map { $0.1 > 1 ? "\($0.0) \u{00d7}\($0.1)" : $0.0 }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Group {
        if expanded {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { _, block in
                    switch block.kind {
                    case .toolUse(let name, _):
                        if name == "Write",
                           let path = block.toolInput["file_path"] as? String,
                           path.contains(".claude/plans/") {
                            PlanCard(input: block.toolInput)
                        } else if name == "ExitPlanMode" {
                            let hasPlanFile = message.blocks.contains { b in
                                if case .toolUse(let n, _) = b.kind,
                                   n == "Write",
                                   (b.toolInput["file_path"] as? String ?? "").contains(".claude/plans/") { return true }
                                return false
                            }
                            if !hasPlanFile {
                                PlanSummaryCard(blocks: message.blocks)
                            }
                        } else {
                            ToolUseCard(name: name, input: block.toolInput)
                        }
                    case .toolResult(let content):
                        ToolResultCard(content: content)
                    default:
                        EmptyView()
                    }
                }

                // Collapse button when there are many tools
                let toolCount = blocks.filter { if case .toolUse = $0.kind { return true }; return false }.count
                if toolCount > 4 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up").font(.caption2)
                            Text("Collapse tools").font(.caption2)
                        }
                        .foregroundStyle(theme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            // Collapsed: single-line summary
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.caption2)
                    Text(toolSummaryLabel).font(.caption2)
                }
                .foregroundStyle(theme.mutedText)
            }
            .buttonStyle(.plain)
        }
        }
        .onChange(of: totalGroups) { _, _ in
            if !isLastToolGroup && expanded {
                withAnimation(.easeInOut(duration: 0.2)) { expanded = false }
            }
        }
    }
}

// MARK: - Markdown Text

struct MarkdownText: View {
    let text: String
    var isStreaming: Bool = false
    @Environment(\.theme) var theme

    var body: some View {
        let parts = splitCodeBlocks(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
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
                    let blocks = splitMarkdownBlocks(part.text)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .heading(let level, let content):
                            Text(renderInline(content))
                                .font(.system(size: level == 1 ? 17 : level == 2 ? 15 : 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.assistantText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        case .divider:
                            Rectangle()
                                .fill(theme.mutedText.opacity(0.2))
                                .frame(height: 1)
                                .padding(.vertical, 4)
                        case .paragraph(let content):
                            Text(renderInline(content))
                                .foregroundStyle(theme.assistantText)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
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
            let expectedMin = text.count / 3  // allow shrinkage from markdown syntax removal
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

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case divider
        case paragraph(String)
    }

    private func splitMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentLines: [String] = []

        func flushParagraph() {
            let para = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !para.isEmpty { blocks.append(.paragraph(para)) }
            currentLines = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Heading: # through ###
            if let match = trimmed.range(of: "^#{1,3}\\s+", options: .regularExpression) {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level: level, text: String(trimmed[match.upperBound...])))
            }
            // Divider: --- or *** or ___ (3+ of same char)
            else if trimmed.count >= 3 &&
                    (trimmed.allSatisfy({ $0 == "-" }) || trimmed.allSatisfy({ $0 == "*" }) || trimmed.allSatisfy({ $0 == "_" })) {
                flushParagraph()
                blocks.append(.divider)
            }
            else {
                currentLines.append(line)
            }
        }
        flushParagraph()
        return blocks
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
    @State private var showFullImage = false

    private var imagePath: String? {
        guard name == "Read", let path = input["file_path"] as? String else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff"].contains(ext) else { return nil }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .font(.caption)
                    .foregroundStyle(toolColor)
                    .frame(width: 16)
                Text(displayName)
                    .font(theme.monoCaptionFont.bold())
                    .foregroundStyle(toolColor)
                Text(toolSummary)
                    .font(theme.monoCaptionFont)
                    .foregroundStyle(theme.toolCardText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Show image preview for Read on image files
            if let path = imagePath, let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: showFullImage ? 400 : 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showFullImage.toggle() } }
            }
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

    var displayName: String {
        switch name {
        case "Grep", "Glob": return "Search"
        case "Bash": return "Run"
        case "WebFetch": return "Fetch"
        case "WebSearch": return "Web Search"
        case "Agent": return "Subagent"
        case "ToolSearch": return "Tools"
        case "ExitPlanMode": return "Plan Ready"
        default: return name
        }
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
        case "ToolSearch": return "wrench.and.screwdriver"
        case "ExitPlanMode": return "checkmark.circle"
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { expanded.toggle() }
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

// MARK: - Plan Summary Card (shown for ExitPlanMode)

struct PlanSummaryCard: View {
    let blocks: [ContentBlock]
    @Environment(\.theme) var theme
    @State private var expanded = false

    /// Extract headers and bullet points from all text blocks as a plan summary
    private var summary: [String] {
        let allText = blocks.compactMap { block -> String? in
            if case .text(let text) = block.kind { return text }
            return nil
        }.joined(separator: "\n")

        return allText.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ") ||
                line.hasPrefix("1.") || line.hasPrefix("2.") || line.hasPrefix("3.") ||
                line.hasPrefix("4.") || line.hasPrefix("5.") || line.hasPrefix("6.") ||
                line.hasPrefix("7.") || line.hasPrefix("8.") || line.hasPrefix("9.")
            }
            .prefix(15)
            .map { String($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(theme.successDot)
                Text("Plan Summary")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(theme.successDot)
                Spacer()
                if !summary.isEmpty {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(theme.mutedText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }

            if summary.isEmpty {
                Text("Plan ready to execute")
                    .font(theme.monoCaptionFont)
                    .foregroundStyle(theme.mutedText)
            } else {
                // Always show first few lines
                let visible = expanded ? summary : Array(summary.prefix(5))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("#") {
                            Text(trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression))
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(theme.assistantText)
                        } else {
                            Text(trimmed)
                                .font(theme.monoCaptionFont)
                                .foregroundStyle(theme.assistantText.opacity(0.85))
                        }
                    }
                    if !expanded && summary.count > 5 {
                        Text("+ \(summary.count - 5) more steps...")
                            .font(theme.monoCaptionFont)
                            .foregroundStyle(theme.mutedText)
                    }
                }
            }
        }
        .padding(10)
        .background(theme.toolCardBg)
        .clipShape(RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 4)))
        .overlay(
            RoundedRectangle(cornerRadius: max(theme.borderRadius - 4, 4))
                .stroke(theme.successDot.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    let input: [String: Any]
    @Environment(\.theme) var theme
    @State private var expanded = false

    private var filePath: String {
        input["file_path"] as? String ?? "plan.md"
    }

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// Read plan content from the file on disk (it was written by Claude)
    private var planContent: String {
        if let content = input["content"] as? String, !content.isEmpty {
            return content
        }
        // Fallback: try reading from disk
        return (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
    }

    /// Non-empty content lines for summary
    private var contentLines: [String] {
        planContent.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                Text("Plan: \(fileName)")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(theme.accent)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(theme.mutedText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }

            // Plan content rendered as markdown
            let visibleLines = expanded ? contentLines : Array(contentLines.prefix(12))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") {
                        Text(trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression))
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(theme.assistantText)
                            .padding(.top, 4)
                    } else {
                        Text(renderPlanLine(trimmed))
                            .font(theme.monoCaptionFont)
                            .foregroundStyle(theme.assistantText.opacity(0.85))
                    }
                }
            }

            if !expanded && contentLines.count > 12 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded = true }
                } label: {
                    Text("Show \(contentLines.count - 12) more lines...")
                        .font(theme.monoCaptionFont)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func renderPlanLine(_ text: String) -> AttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        if let result = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            var styled = result
            for run in styled.runs {
                let isBold = styled[run.range].inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
                styled[run.range].font = isBold ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask) : baseFont
            }
            return styled
        }
        var plain = AttributedString(text)
        plain.font = baseFont
        return plain
    }
}

// MARK: - Execute Plan Button

struct ExecutePlanButton: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 12) {
            Button {
                // Disable plan mode so execution runs with full permissions
                session.planMode = false
                sessionManager.sendImmediately("Go ahead and execute the plan.", to: session)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    Text("Execute Plan")
                        .font(.system(.caption, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                sessionManager.sendImmediately("Reject the plan. Explain what you would do differently.", to: session)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.caption)
                    Text("Reject")
                        .font(.system(.caption, weight: .medium))
                }
                .foregroundStyle(theme.chromeText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.chromeBar.opacity(0.6))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.chromeBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @Environment(\.theme) var theme
    @State private var visible = true

    var body: some View {
        Text("▊")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(theme.accent)
            .opacity(visible ? 0.8 : 0.15)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible.toggle() }
    }
}

// MARK: - Thinking Indicator

struct ThinkingPetIndicator: View {
    @ObservedObject var session: Session
    let text: String
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 8) {
            PetView(session: session)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .transition(.scale(scale: 0.3).combined(with: .opacity))

            if let endTime = session.sleepEndTime, endTime > Date() {
                // Live countdown for sleep commands
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(endTime.timeIntervalSince(context.date)))
                    Text("Sleeping... \(remaining)s")
                        .font(theme.monoCaptionFont)
                        .foregroundStyle(theme.accent)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
            } else {
                Text(text)
                    .font(theme.monoCaptionFont)
                    .foregroundStyle(theme.assistantText)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.25), value: text)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .modifier(LiquidGlassChrome(cornerRadius: 12))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: text)
    }
}

// MARK: - Suggested Actions

struct SuggestedActions: View {
    @ObservedObject var session: Session
    var onTap: (String) -> Void
    @Environment(\.theme) var theme
    @State private var visibleCount = 0

    var body: some View {
        if !session.suggestedActions.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(session.suggestedActions.enumerated()), id: \.element.label) { index, suggestion in
                    Button {
                        onTap(suggestion.prompt)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(suggestion.label)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(theme.chromeText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .modifier(LiquidGlassChrome(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .opacity(index < visibleCount ? 1 : 0)
                    .scaleEffect(index < visibleCount ? 1.0 : 0.8)
                    .offset(y: index < visibleCount ? 0 : 12)
                    .animation(.spring(response: 0.35, dampingFraction: 0.55).delay(Double(index) * 0.1), value: visibleCount)
                }
                Spacer()
            }
            .onAppear { visibleCount = session.suggestedActions.count }
            .onChange(of: session.suggestedActions.count) { _, new in
                visibleCount = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    visibleCount = new
                }
            }
        }
    }
}
