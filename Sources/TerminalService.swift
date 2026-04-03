import Foundation
import Combine
import Darwin

/// Handles spawning and communicating with Claude Code processes via PTY
class TerminalService {
    static let shared = TerminalService()

    // MARK: - Launch Claude Code

    func launch(session: Session, settings: AppSettings) {
        // Create a pseudo-terminal so Claude Code sees a real TTY
        var primary: Int32 = 0
        var secondary: Int32 = 0
        // Use SwiftTerm's reported size if available, otherwise default
        var winSize = winsize(
            ws_row: UInt16(session.terminalRows),
            ws_col: UInt16(session.terminalCols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&primary, &secondary, nil, nil, &winSize) == 0 else {
            DispatchQueue.main.async {
                session.status = .error
            }
            return
        }

        let process = Process()
        let primaryHandle = FileHandle(fileDescriptor: primary, closeOnDealloc: false)
        let secondaryHandle = FileHandle(fileDescriptor: secondary, closeOnDealloc: false)

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        // Build the claude command
        var claudeCmd = settings.claudeCodePath
        if settings.alwaysBypassPermissions {
            claudeCmd += " --dangerously-skip-permissions"
        }

        // Expand ~ in working directory
        let workDir = (session.workingDirectory as NSString).expandingTildeInPath

        process.arguments = ["-l", "-c", "cd '\(workDir)' && exec \(claudeCmd)"]
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        // Don't set COLUMNS/ROWS — SwiftTerm reports its actual size via TIOCSWINSZ
        env.removeValue(forKey: "COLUMNS")
        env.removeValue(forKey: "ROWS")
        process.environment = env

        session.process = process
        session.ptyPrimary = primaryHandle

        // Raw buffer for auto-accept detection (accessed on I/O thread)
        var rawBuffer = ""
        // Buffer for incomplete UTF-8 sequences split across reads
        var utf8Remainder = Data()

        // Read output from the primary side of the PTY
        primaryHandle.readabilityHandler = { [weak session] handle in
            // Use low-level read() instead of availableData to avoid abort on closed FD
            let fd = handle.fileDescriptor
            guard fd >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            guard bytesRead > 0 else {
                if bytesRead <= 0 { handle.readabilityHandler = nil }
                return
            }
            let rawData = Data(buffer[0..<bytesRead])

            // Buffer raw data for replay on session switch
            session?.terminalDataBuffer.append(rawData)
            // Feed to the SwiftTerm terminal view (raw bytes, it handles decoding)
            session?.terminalFeed?(rawData)

            // Prepend any leftover bytes from previous read, then split at UTF-8 boundary
            var data = utf8Remainder + rawData
            utf8Remainder = Data()
            // Check if data ends mid-UTF-8 sequence
            if let lastByte = data.last, lastByte & 0x80 != 0 {
                var i = data.count - 1
                while i > max(0, data.count - 4) && data[i] & 0xC0 == 0x80 { i -= 1 }
                if i >= 0 && data[i] & 0xC0 == 0xC0 {
                    let lead = data[i]
                    let expected = lead & 0xE0 == 0xC0 ? 2 : lead & 0xF0 == 0xE0 ? 3 : 4
                    if data.count - i < expected {
                        utf8Remainder = Data(data[i...])
                        data = Data(data[0..<i])
                    }
                }
            }

            if let text = String(data: data, encoding: .utf8) {
                rawBuffer += text

                // Auto-accept trust prompt
                if let session = session, !session.trustAccepted,
                   rawBuffer.contains("trust"), rawBuffer.contains("confirm") {
                    session.trustAccepted = true
                    Thread.sleep(forTimeInterval: 0.5)
                    handle.write(Data([0x0D]))
                }

                // Auto-accept "use this API key?" prompt
                if rawBuffer.contains("API") && rawBuffer.contains("key") && rawBuffer.contains("Yes")
                    && !rawBuffer.contains("__API_ACCEPTED__") {
                    rawBuffer += "__API_ACCEPTED__"
                    Thread.sleep(forTimeInterval: 0.5)
                    handle.write("\u{1B}[A".data(using: .utf8)!) // Arrow up → Yes
                    Thread.sleep(forTimeInterval: 0.3)
                    handle.write(Data([0x0D])) // Enter
                }

                DispatchQueue.main.async {
                    guard let session = session else { return }

                    // Accumulate response text
                    if session.isCollectingResponse {
                        session.responseBuffer += text
                    }

                    // Detect thinking indicators
                    if let thinking = OutputParser.thinkingIndicator(in: text) {
                        session.assistantState = .thinking(thinking)
                    }

                    // Update status detection
                    self.detectStatus(from: text, session: session)

                    // Debounce-based response finalization:
                    // When status becomes .waitingForInput, schedule finalization after 1s.
                    // If status goes back to .running, cancel it.
                    if session.isCollectingResponse {
                        if session.status == .running {
                            // Claude is working — cancel any pending finalization
                            session.pendingFinalization?.cancel()
                            session.pendingFinalization = nil
                        } else if session.status == .waitingForInput && session.pendingFinalization == nil {
                            // Prompt detected — schedule finalization (debounce 1s)
                            let work = DispatchWorkItem { [weak self, weak session] in
                                guard let session = session, session.isCollectingResponse else { return }
                                self?.finalizeResponse(session: session)
                            }
                            session.pendingFinalization = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
                        }
                    }
                }
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak session, weak primaryHandle] _ in
            // Clear readability handler immediately to prevent reads on closed FD
            primaryHandle?.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let session = session else { return }
                if let handle = session.ptyPrimary {
                    close(handle.fileDescriptor)
                }
                session.ptyPrimary = nil
                session.terminalFeed = nil
                session.status = .idle
            }
        }

        do {
            try process.run()
            close(secondary)
            DispatchQueue.main.async {
                session.status = .running
            }
        } catch {
            close(primary)
            close(secondary)
            DispatchQueue.main.async {
                session.status = .error
            }
        }
    }

    // MARK: - Send Input

    func send(text: String, to session: Session) {
        guard let handle = session.ptyPrimary else { return }

        // Record user message in chat
        if !text.isEmpty {
            let msg = ChatMessage(role: .user, content: text)
            DispatchQueue.main.async {
                session.chatMessages.append(msg)
                session.responseBuffer = ""
                session.isCollectingResponse = true
                session.collectionStartTime = Date()
                // Snapshot the terminal buffer position so we can read clean rendered text later
                session.bufferSnapshotLine = TerminalViewCache.shared.bufferLineCount(for: session.id)
                session.assistantState = .thinking("Thinking...")
            }
        }

        let data = (text + "\r").data(using: .utf8)!
        handle.write(data)
    }

    // MARK: - Terminate

    func terminate(session: Session) {
        session.ptyPrimary?.readabilityHandler = nil
        session.process?.terminate()
        if let handle = session.ptyPrimary {
            close(handle.fileDescriptor)
        }
        session.process = nil
        session.ptyPrimary = nil
        session.terminalFeed = nil
        session.status = .idle
    }

    // MARK: - Response Finalization

    private func finalizeResponse(session: Session) {
        session.isCollectingResponse = false
        session.pendingFinalization = nil
        session.debugLastRawResponse = session.responseBuffer

        let blocks = OutputParser.extractBlocks(session.responseBuffer)
        if !blocks.isEmpty {
            let plainText = blocks.compactMap { block -> String? in
                if case .text(let s) = block { return s }
                return nil
            }.joined(separator: "\n")
            let duration = session.collectionStartTime.map { Date().timeIntervalSince($0) }
            var msg = ChatMessage(role: .assistant, content: plainText, blocks: blocks)
            msg.durationSeconds = duration
            session.chatMessages.append(msg)
        }
        session.assistantState = .idle
        session.responseBuffer = ""
    }

    // MARK: - Status Detection

    private func detectStatus(from text: String, session: Session?) {
        guard let session = session else { return }

        // Check for ❯ prompt FIRST — it takes priority over running indicators
        let clean = OutputParser.stripAnsi(text)
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("❯") && !trimmed.contains("trust") && !trimmed.contains("Yes") {
            session.status = .waitingForInput
            if !session.messageQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processQueueIfNeeded(session: session)
                }
            }
            return
        }

        // Only detect .running if we're actively collecting a response (user sent a message).
        // This prevents Bristle animations and status bar output from falsely setting .running.
        guard session.isCollectingResponse else { return }

        let spinners: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "✽", "✻", "✶", "✳", "✢", "✹"]
        if text.contains(where: { spinners.contains($0) }) {
            session.status = .running
            return
        }

        if text.contains("Noodling") || text.contains("Waddling") || text.contains("Harmonizing")
            || text.contains("Pondering") || text.contains("Crunching") || text.contains("Churning")
            || text.contains("Bootstrapping") || text.contains("Sprouting") || text.contains("Evaporating")
            || text.contains("Percolating") || text.contains("Simmering") {
            session.status = .running
            return
        }
    }

    private func processQueueIfNeeded(session: Session) {
        guard session.status == .waitingForInput,
              !session.messageQueue.isEmpty else { return }
        let message = session.messageQueue.removeFirst()
        send(text: message.text, to: session)
        session.status = .running
    }
}
