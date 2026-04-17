import SwiftUI

enum DetailTab: String, CaseIterable {
    case terminal = "Terminal"
    case minigame = "Kick the Claude"
}

struct SessionDetailView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText: String = ""
    @State private var activeTab: DetailTab = .terminal
    @State private var showFilePicker = false
    @State private var isDragOver = false
    @State private var previewImageIndex: Int? = nil
    @StateObject private var minigameBridge = MinigameBridge()
    @StateObject private var pasteboardWatcher = PasteboardWatcher()
    @FocusState private var inputFocused: Bool
    @State private var taskStartTime: Date?
    @ObservedObject private var updateChecker = UpdateChecker.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if activeTab == .minigame {
                MinigameView(bridge: minigameBridge)
            } else {
            ChatView(session: session, onSuggestionTap: { text in
                    inputText = text
                })
                .contentShape(Rectangle())
                .onTapGesture { inputFocused = true }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // Inline queue strip (only visible when messages are queued)
                        if !session.messageQueue.isEmpty {
                            InlineQueueStrip(session: session)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Input bar
                        InputBar(
                            inputText: $inputText,
                            inputFocused: $inputFocused,
                            session: session,
                            attachedImage: pasteboardWatcher.pendingImage,
                            attachedImagePaths: pasteboardWatcher.pendingImagePaths,
                            hasAttachment: !pasteboardWatcher.pendingImagePaths.isEmpty,
                            onRemoveAttachment: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    pasteboardWatcher.clear()
                                }
                            },
                            onRemoveImage: { index in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    pasteboardWatcher.removeImage(at: index)
                                }
                            },
                            onSend: { handleSend() },
                            onForceQueue: {
                                guard !inputText.isEmpty else { return }
                                sessionManager.queueMessage(inputText, for: session)
                                inputText = ""
                            },
                            onAttach: {
                                showFilePicker = true
                            },
                            previewImageIndex: $previewImageIndex
                        )
                        .fileImporter(
                            isPresented: $showFilePicker,
                            allowedContentTypes: [.image, .plainText, .sourceCode, .json, .data],
                            allowsMultipleSelection: false
                        ) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                if url.startAccessingSecurityScopedResource() {
                                    defer { url.stopAccessingSecurityScopedResource() }
                                    let tempPath = NSTemporaryDirectory() + "claudestation_\(url.lastPathComponent)"
                                    let destURL = URL(fileURLWithPath: tempPath)
                                    // Remove existing file at dest to avoid copy failure
                                    try? FileManager.default.removeItem(at: destURL)
                                    try? FileManager.default.copyItem(at: url, to: destURL)
                                    if let image = NSImage(contentsOf: destURL) ?? NSImage(contentsOf: url) {
                                        if pasteboardWatcher.pendingImage == nil {
                                            pasteboardWatcher.pendingImage = image
                                        }
                                        pasteboardWatcher.pendingImagePath = tempPath
                                        pasteboardWatcher.pendingImagePaths.append(tempPath)
                                    } else {
                                        // Not an image NSImage can read — still attach as file for Claude to read
                                        inputText += (inputText.isEmpty ? "" : "\n") + "[File: \(tempPath)]"
                                    }
                                }
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: session.messageQueue.count)
                    .animation(.easeInOut(duration: 0.2), value: pasteboardWatcher.pendingImage != nil)
                }
            .overlay {
                if isDragOver {
                    DropOverlay()
                        .transition(.opacity)
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $isDragOver) { providers in
                for (i, provider) in providers.enumerated() {
                    // Try image first
                    if provider.hasItemConformingToTypeIdentifier("public.image") {
                        provider.loadObject(ofClass: NSImage.self) { image, _ in
                            guard let image = image as? NSImage else { return }
                            let path = NSTemporaryDirectory() + "claudestation_drop_\(Int(Date().timeIntervalSince1970))_\(i).png"
                            if let tiff = image.tiffRepresentation,
                               let bmp = NSBitmapImageRep(data: tiff),
                               let png = bmp.representation(using: .png, properties: [:]) {
                                try? png.write(to: URL(fileURLWithPath: path))
                                DispatchQueue.main.async {
                                    // First image shows as thumbnail preview
                                    if self.pasteboardWatcher.pendingImage == nil {
                                        self.pasteboardWatcher.pendingImage = image
                                    }
                                    self.pasteboardWatcher.pendingImagePath = path
                                    self.pasteboardWatcher.pendingImagePaths.append(path)
                                }
                            }
                        }
                    }
                    // Handle file URLs — any file or folder
                    let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url = url else { return }
                        let loadedImage: NSImage? = NSImage(contentsOf: url)
                        let isImage = loadedImage != nil && (loadedImage?.size.width ?? 0) > 10
                        if isImage, let image = loadedImage {
                            let destPath = NSTemporaryDirectory() + "claudestation_drop_\(url.lastPathComponent)"
                            if !FileManager.default.fileExists(atPath: destPath) {
                                try? FileManager.default.copyItem(atPath: url.path, toPath: destPath)
                            }
                            DispatchQueue.main.async {
                                if self.pasteboardWatcher.pendingImage == nil {
                                    self.pasteboardWatcher.pendingImage = image
                                }
                                self.pasteboardWatcher.pendingImagePaths.append(destPath)
                            }
                        } else {
                            let filePath = url.path
                            DispatchQueue.main.async {
                                let sep = self.inputText.isEmpty ? "" : "\n"
                                self.inputText += "\(sep)[File: \(filePath)]"
                            }
                        }
                    }
                }
                return true
            }
            .animation(.easeInOut(duration: 0.2), value: isDragOver)
        }
            } // end else (terminal tab)
        .overlay {
            if let idx = previewImageIndex {
                let paths = pasteboardWatcher.pendingImagePaths
                let safeIdx = min(idx, paths.count - 1)
                if safeIdx >= 0, let img = NSImage(contentsOfFile: paths[safeIdx]) {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { previewImageIndex = nil }
                        .overlay {
                            HStack(spacing: 0) {
                                // Left arrow
                                if safeIdx > 0 {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { previewImageIndex = safeIdx - 1 }
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
                                        .id(safeIdx)
                                        .transition(.opacity)
                                    Text("\(safeIdx + 1) / \(paths.count)  ·  \(Int(img.size.width)) × \(Int(img.size.height))")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }

                                Spacer()

                                // Right arrow
                                if safeIdx < paths.count - 1 {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { previewImageIndex = safeIdx + 1 }
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
        }
        .animation(.easeInOut(duration: 0.15), value: previewImageIndex)
        .onAppear {
            inputFocused = true
            pasteboardWatcher.startWatching()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputFocused = true
        }
        .onDisappear { pasteboardWatcher.stopWatching() }
        // Bridge session status changes to the minigame
        .onChange(of: session.status) { oldStatus, newStatus in
            minigameBridge.sessionStatusChanged(newStatus.rawValue)
            
            if oldStatus == .waitingForInput && newStatus == .running {
                taskStartTime = Date()
                minigameBridge.taskStarted()
                if UserDefaults.standard.bool(forKey: "cursorAnimations") {
                    CursorManager.startAnimating()
                }
            }
            if oldStatus == .running && newStatus == .waitingForInput {
                let duration = taskStartTime.map { Date().timeIntervalSince($0) } ?? 30
                minigameBridge.taskCompleted(durationSeconds: Int(duration))
                taskStartTime = nil
                CursorManager.stopAnimating()
                session.celebrationStart = .now
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    session.celebrating = true
                }
                // Longer celebration with gradual wind-down (bg handles its own fade)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    withAnimation(.easeOut(duration: 1.0)) {
                        session.celebrating = false
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            if updateChecker.updateAvailable {
                ToolbarItem(placement: .automatic) {
                    Button {
                        updateChecker.restart()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: -2)
                            }
                    }
                    .help("New build available — click to restart")
                }
            }

            ToolbarItem(placement: .automatic) {
                UsageToolbarView()
            }

            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (Cmd+,)")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    activeTab = activeTab == .terminal ? .minigame : .terminal
                } label: {
                    Label(
                        activeTab == .terminal ? "Play" : "Terminal",
                        systemImage: activeTab == .terminal ? "gamecontroller" : "terminal"
                    )
                }
                .help("Toggle minigame (Cmd+G)")
                .keyboardShortcut("g", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                if session.status == .running {
                    Button {
                        TerminalService.shared.terminate(session: session)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func handleSend() {
        let hasPendingImages = !pasteboardWatcher.pendingImagePaths.isEmpty
        guard !inputText.isEmpty || hasPendingImages else { return }
        var message = inputText
        for path in pasteboardWatcher.pendingImagePaths {
            let sep = message.isEmpty ? "" : "\n"
            message += "\(sep)[Image: \(path)]"
        }
        pasteboardWatcher.clearForSend()
        if session.status == .waitingForInput || session.status == .idle {
            sessionManager.sendImmediately(message, to: session)
        } else {
            sessionManager.queueMessage(message, for: session)
        }
        inputText = ""
    }
}

// MARK: - Usage Toolbar View

struct UsageToolbarView: View {
    @ObservedObject var usageMonitor: UsageMonitor = .shared
    @Environment(\.theme) var theme

    private var isStale: Bool {
        guard let last = usageMonitor.lastUpdated else { return true }
        return Date().timeIntervalSince(last) > 300
    }

    var body: some View {
        if usageMonitor.isLoggedIn {
            HStack(spacing: 2) {
                UsagePill(
                    label: usageMonitor.sessionResetText.isEmpty ? "" : usageMonitor.sessionResetText,
                    utilization: usageMonitor.sessionUtilization,
                    resetText: usageMonitor.sessionResetText,
                    theme: theme
                )
                if isStale {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
            }
            .opacity(isStale ? 0.5 : 1.0)
            .padding(.leading, 8)
            .onTapGesture {
                if isStale {
                    usageMonitor.openUsageInBrowser()
                } else {
                    usageMonitor.refresh()
                }
            }
            .help(isStale ? "Stale — click to reopen Chrome tab" : "Click to refresh — Resets in \(usageMonitor.sessionResetText)")
        } else {
            Button {
                usageMonitor.openUsageInBrowser()
            } label: {
                Label("Usage", systemImage: "chart.bar")
            }
            .help("Opens claude.ai usage in Chrome")
        }
    }
}

// MARK: - Usage Pill (compact progress bar)

struct UsagePill: View {
    let label: String
    let utilization: Double
    let resetText: String
    let theme: Theme

    private var barColor: Color {
        if utilization > 0.8 { return .red }
        if utilization > 0.6 { return .orange }
        return theme.accent
    }

    private var pct: Int { Int(utilization * 100) }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(pct)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(utilization > 0.8 ? .red : theme.chromeText)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.mutedText.opacity(0.2))
                    .frame(width: 32, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: max(1, 32 * utilization), height: 4)
            }

            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.mutedText)
            }
        }
        .help(resetText.isEmpty ? "\(pct)% used" : "\(pct)% used — Resets in \(resetText)")
    }
}

// MARK: - Login WebView Sheet


// MARK: - Terminal Output

// MARK: - Input Bar

// MARK: - Attachment Preview

// MARK: - Drop Overlay

struct DropOverlay: View {
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            theme.chatBg.opacity(0.85)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.accent)

                Text("Drop your files here")
                    .font(.headline)
                    .foregroundStyle(theme.assistantText)

                Text("Drop files to add them to your conversation")
                    .font(.caption)
                    .foregroundStyle(theme.mutedText)
            }
            .padding(40)
            .background(theme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
        }
    }
}

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let image: NSImage
    var onRemove: () -> Void
    @Environment(\.theme) var theme
    @State private var showFullPreview = false

    var body: some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.chromeBorder, lineWidth: 1)
                    )
                    .onTapGesture { showFullPreview = true }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.6)).frame(width: 14, height: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .overlay {
            if showFullPreview {
                // Full-screen dimmed overlay — click anywhere to dismiss
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { showFullPreview = false }
                    .overlay {
                        VStack(spacing: 8) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 700, maxHeight: 500)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 20)
                                .onTapGesture {} // prevent dismiss on image click

                            Text("\(Int(image.size.width)) x \(Int(image.size.height))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showFullPreview)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            // Re-resolve dynamically so cursor pack changes take effect
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct InputBar: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    @ObservedObject var session: Session
    var attachedImage: NSImage? = nil
    var attachedImagePaths: [String] = []
    var hasAttachment: Bool = false
    var onRemoveAttachment: () -> Void = {}
    var onRemoveImage: (Int) -> Void = { _ in }
    var onSend: () -> Void
    var onForceQueue: () -> Void
    var onAttach: () -> Void = {}
    @Environment(\.theme) var theme
    @Binding var previewImageIndex: Int?

    private var isReady: Bool {
        session.status == .waitingForInput || session.status == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Input field in rounded container
            VStack(alignment: .leading, spacing: 8) {
                // Attached images inside the pill
                if !attachedImagePaths.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(attachedImagePaths.enumerated()), id: \.element) { index, path in
                            if let img = NSImage(contentsOfFile: path) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(theme.toolCardBorder, lineWidth: 1)
                                        )
                                        .onTapGesture { previewImageIndex = index }
                                                        Button { onRemoveImage(index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white)
                                            .background(Circle().fill(.black.opacity(0.6)).frame(width: 10, height: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        Spacer()
                    }
                } else if let img = attachedImage {
                    HStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.toolCardBorder, lineWidth: 1)
                                )
                                .onTapGesture { previewImageIndex = 0 }
                                        Button(action: onRemoveAttachment) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(.black.opacity(0.6)).frame(width: 12, height: 12))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                        Spacer()
                    }
                }

            HStack(alignment: .center, spacing: 8) {
                // Pixel pet mascot — scale up during celebration, fade out when thinking
                PetView(session: session, overrideState: session.celebrating ? .success : nil)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .scaleEffect(session.celebrating ? 1.3 : 1.0)
                    .opacity({ if case .thinking = session.assistantState { return 0.0 } else { return 1.0 } }())
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: session.celebrating)

                // Plus button for attachments
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.chromeText)
                        .frame(width: 28, height: 28)
                        .background(theme.chromeText.opacity(0.25))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Attach file")

                // Text field — grows up to 8 lines, scrolls beyond that
                let ghostLabel = session.suggestedActions.first?.label ?? "Message to Claude..."
                TextField(ghostLabel, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.id == "aero" ? Color(hex: "#2E7DA8") : theme.assistantText)
                    .focused(inputFocused)
                    .lineLimit(1...8)
                    .layoutPriority(1)
                    .onSubmit {
                        // If input is empty and we have a suggestion, send it directly
                        if inputText.isEmpty, let first = session.suggestedActions.first {
                            inputText = first.prompt
                        }
                        onSend()
                    }
                    .onKeyPress(.tab) {
                        // Tab autofills the suggestion prompt for editing
                        if inputText.isEmpty, let first = session.suggestedActions.first {
                            inputText = first.prompt
                            return .handled
                        }
                        return .ignored
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !inputText.isEmpty {
                            Button {
                                inputText = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(theme.chromeText.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 2, y: 2)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }

                // Right side buttons
                HStack(spacing: 6) {
                    // Effort level cycle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            let levels = ["low", "medium", "high", "max"]
                            let idx = levels.firstIndex(of: session.effortLevel) ?? 3
                            session.effortLevel = levels[(idx + 1) % levels.count]
                        }
                    } label: {
                        let short: String = {
                            switch session.effortLevel {
                            case "low": return "Lo"
                            case "medium": return "Med"
                            case "high": return "Hi"
                            default: return "Max"
                            }
                        }()
                        Text(short)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(session.effortLevel == "max" ? .white : theme.chromeText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(session.effortLevel == "max" ? theme.accent : theme.chromeText.opacity(0.25))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Effort: \(session.effortLevel) — click to cycle")

                    // Plan mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            session.planMode.toggle()
                            session.planResponseReceived = false
                        }
                    } label: {
                        Text("Plan")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(session.planMode ? .white : theme.chromeText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(session.planMode ? theme.accent : theme.chromeText.opacity(0.25))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle plan mode")

                    // Send button
                    Button(action: onSend) {
                        Image(systemName: isReady ? "arrow.up" : "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(inputText.isEmpty && !hasAttachment ? theme.chromeText : .white)
                            .frame(width: 28, height: 28)
                            .background(inputText.isEmpty && !hasAttachment ? theme.chromeText.opacity(0.25) : theme.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty && !hasAttachment)
                    .help(isReady ? "Send (Enter)" : "Queue (Enter)")
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .modifier(LiquidGlassChrome(cornerRadius: 20))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: inputText.count)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - Pointer Hand Cursor

extension View {
    func pointerHand() -> some View {
        self.onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
