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
        var winSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&primary, &secondary, nil, nil, &winSize) == 0 else {
            DispatchQueue.main.async {
                session.status = .error
                session.outputBuffer += "\n[Error: Failed to create pseudo-terminal]\n"
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

        // Read OAuth token from keychain in the shell (which has access), pass as env var
        let readToken = "export ANTHROPIC_API_KEY=$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null | python3 -c \"import sys,json; print(json.load(sys.stdin).get('claudeAiOauth',{}).get('accessToken',''))\" 2>/dev/null)"
        process.arguments = ["-l", "-c", "\(readToken); cd '\(workDir)' && exec \(claudeCmd)"]
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "120"
        env["ROWS"] = "40"
        env["NO_COLOR"] = "1"
        process.environment = env

        session.process = process
        session.ptyPrimary = primaryHandle

        // Raw buffer for trust detection (accessed on I/O thread)
        var rawBuffer = ""

        // Read output from the primary side of the PTY
        primaryHandle.readabilityHandler = { [weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? ""
            guard !text.isEmpty else { return }

            // Auto-accept prompts on I/O thread using synchronous sleep
            rawBuffer += text

            // Auto-accept trust prompt (words split by ANSI cursor codes)
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

                let stripped = Self.stripAnsi(text)
                session.outputBuffer += stripped
                self.detectStatus(from: text, session: session)

                // Trim buffer if too long
                if session.outputBuffer.count > settings.maxOutputBufferLines * 80 {
                    let lines = session.outputBuffer.components(separatedBy: "\n")
                    let trimmed = lines.suffix(settings.maxOutputBufferLines)
                    session.outputBuffer = trimmed.joined(separator: "\n")
                }
            }
        }

        // Handle process termination — clean up PTY before it goes stale
        process.terminationHandler = { [weak session] _ in
            DispatchQueue.main.async {
                guard let session = session else { return }
                session.ptyPrimary?.readabilityHandler = nil
                if let handle = session.ptyPrimary {
                    close(handle.fileDescriptor)
                }
                session.ptyPrimary = nil
                session.status = .idle
            }
        }

        do {
            try process.run()
            // Close the secondary side in the parent — child has its own copy
            close(secondary)
            DispatchQueue.main.async {
                session.status = .running
            }
        } catch {
            close(primary)
            close(secondary)
            DispatchQueue.main.async {
                session.status = .error
                session.outputBuffer += "\n[Error launching Claude Code: \(error.localizedDescription)]\n"
            }
        }
    }

    // MARK: - Send Input

    func send(text: String, to session: Session) {
        guard let handle = session.ptyPrimary else { return }
        // PTY uses carriage return for Enter
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
        session.status = .idle
    }

    // MARK: - Status Detection

    /// Heuristic detection of Claude Code's state from output
    private func detectStatus(from text: String, session: Session?) {
        guard let session = session else { return }

        // Strip ANSI escape codes for pattern matching
        let clean = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]]",
            with: "",
            options: .regularExpression
        )

        // Don't detect prompt if we're still on the trust/setup screen
        let fullClean = session.outputBuffer.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]]",
            with: "",
            options: .regularExpression
        )
        let isTrustScreen = fullClean.contains("trust") && fullClean.contains("cancel")

        // The real Claude prompt is ❯ at the start of a line, not inside a menu
        if !isTrustScreen && clean.contains("❯") {
            session.status = .waitingForInput

            // Auto-process queue when ready
            if !session.messageQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processQueueIfNeeded(session: session)
                }
            }
        } else if text.contains("⠋") || text.contains("⠙")
                    || text.contains("⠹") || text.contains("⠸")
                    || text.contains("⠼") || text.contains("⠴") {
            session.status = .running
        }
    }

    /// Strip ANSI escape codes from terminal output for display
    static func stripAnsi(_ text: String) -> String {
        var result = text
        // Replace cursor-forward sequences [1C, [2C etc. with a space
        result = result.replacingOccurrences(
            of: "\u{1B}\\[(\\d+)C",
            with: " ",
            options: .regularExpression
        )
        // Strip all other CSI sequences (colors, cursor movement, modes, etc.)
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        // Strip OSC sequences (title bar, etc.)
        result = result.replacingOccurrences(
            of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
        // Strip other escape sequences
        result = result.replacingOccurrences(
            of: "\u{1B}[><=][^\u{1B}]{0,20}",
            with: "",
            options: .regularExpression
        )
        // Clean up excessive blank lines
        result = result.replacingOccurrences(
            of: "\r\n",
            with: "\n"
        )
        result = result.replacingOccurrences(
            of: "\r",
            with: "\n"
        )
        // Collapse runs of 3+ newlines to 2
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return result
    }

    private func processQueueIfNeeded(session: Session) {
        guard session.status == .waitingForInput,
              !session.messageQueue.isEmpty else { return }

        let message = session.messageQueue.removeFirst()
        send(text: message.text, to: session)
        session.status = .running
    }
}
