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
    @State private var showImagePreview = false
    @StateObject private var minigameBridge = MinigameBridge()
    @StateObject private var pasteboardWatcher = PasteboardWatcher()
    @FocusState private var inputFocused: Bool
    @State private var taskStartTime: Date?
    
    var body: some View {
        VStack(spacing: 0) {
            if activeTab == .minigame {
                MinigameView(bridge: minigameBridge)
            } else {
            ChatView(session: session)
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
                            hasAttachment: !pasteboardWatcher.pendingImagePaths.isEmpty,
                            onRemoveAttachment: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    pasteboardWatcher.clear()
                                }
                            },
                            onSend: {
                                let hasPendingImages = !pasteboardWatcher.pendingImagePaths.isEmpty
                                guard !inputText.isEmpty || hasPendingImages else { return }
                                var message = inputText
                                // Append all pending image paths
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
                            },
                            onForceQueue: {
                                guard !inputText.isEmpty else { return }
                                sessionManager.queueMessage(inputText, for: session)
                                inputText = ""
                            },
                            onAttach: {
                                showFilePicker = true
                            },
                            showImagePreview: $showImagePreview
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
                                    try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: tempPath))
                                    if let image = NSImage(contentsOf: url) {
                                        pasteboardWatcher.pendingImage = image
                                        pasteboardWatcher.pendingImagePath = tempPath
                                    } else {
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
                    provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url = url else { return }
                        if let image = NSImage(contentsOf: url), image.size.width > 10 {
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
                            DispatchQueue.main.async {
                                let sep = self.inputText.isEmpty ? "" : "\n"
                                self.inputText += "\(sep)[File: \(url.path)]"
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
            if showImagePreview, let img = pasteboardWatcher.pendingImage {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { showImagePreview = false }
                    .overlay {
                        VStack(spacing: 8) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 700, maxHeight: 500)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 20)
                                .onTapGesture {}
                            Text("\(Int(img.size.width)) x \(Int(img.size.height))")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showImagePreview)
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
            }
            if oldStatus == .running && newStatus == .waitingForInput {
                let duration = taskStartTime.map { Date().timeIntervalSince($0) } ?? 30
                minigameBridge.taskCompleted(durationSeconds: Int(duration))
                taskStartTime = nil
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
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
}

// MARK: - Session Header

struct SessionHeaderBar: View {
    @ObservedObject var session: Session
    @Binding var activeTab: DetailTab
    @Environment(\.theme) var theme
    @State private var showFolderPicker = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.status == .running ? theme.accent : theme.successDot)
                .frame(width: 6, height: 6)

            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = URL(fileURLWithPath: (session.workingDirectory as NSString).expandingTildeInPath)
                panel.prompt = "Choose"
                panel.message = "Select working directory"
                if panel.runModal() == .OK, let url = panel.url {
                    session.workingDirectory = url.path
                    session.claudeSessionId = nil // Reset conversation for new directory
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(session.workingDirectory)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.chromeText)
            }
            .buttonStyle(.plain)
            .help("Change working directory")

            Spacer()

            Text(session.status.rawValue)
                .font(.caption2)
                .foregroundStyle(theme.chromeText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .modifier(LiquidGlassChrome())
        .animation(.easeInOut(duration: 0.3), value: session.status)
    }
}

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
                    .cursor(.pointingHand)

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
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct InputBar: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    @ObservedObject var session: Session
    var attachedImage: NSImage? = nil
    var hasAttachment: Bool = false
    var onRemoveAttachment: () -> Void = {}
    var onSend: () -> Void
    var onForceQueue: () -> Void
    var onAttach: () -> Void = {}
    @Environment(\.theme) var theme
    @Binding var showImagePreview: Bool

    private var isReady: Bool {
        session.status == .waitingForInput || session.status == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Input field in rounded container
            VStack(alignment: .leading, spacing: 8) {
                // Attached images inside the pill
                if let img = attachedImage {
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
                                .onTapGesture { showImagePreview = true }
                                .cursor(.pointingHand)

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
                // Pixel pet mascot
                PetView(session: session)

                // Plus button for attachments
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 28, height: 28)
                        .background(theme.inputBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.inputBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Attach file")

                // Text field — grows up to 8 lines, scrolls internally beyond that
                TextField("Message to Claude...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.assistantText)
                    .focused(inputFocused)
                    .lineLimit(1...8)
                    .onSubmit { onSend() }

                // Right side buttons
                HStack(spacing: 6) {
                    // Plan mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { session.planMode.toggle() }
                    } label: {
                        Text("Plan")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(session.planMode ? theme.userBubbleText : theme.mutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(session.planMode ? theme.accent : theme.inputBg)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(session.planMode ? theme.accent : theme.inputBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle plan mode")

                    // Send button
                    Button(action: onSend) {
                        Image(systemName: isReady ? "arrow.up" : "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(inputText.isEmpty && !hasAttachment ? theme.mutedText : theme.assistantBubble)
                            .frame(width: 28, height: 28)
                            .background(inputText.isEmpty && !hasAttachment ? theme.inputBg : theme.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty && !hasAttachment)
                    .help(isReady ? "Send (Enter)" : "Queue (Enter)")
                }
            }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.inputBg.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(theme.inputBorder, lineWidth: 1)
            )
            .modifier(LiquidGlassChrome(cornerRadius: 20))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
