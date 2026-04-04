import Foundation
import Combine
import UserNotifications

/// Handles communication with Claude Code via stream-json API mode.
/// Each user message spawns: `claude -p --output-format stream-json --verbose --resume <session>`
/// and reads structured JSON events from stdout.
class TerminalService {
    static let shared = TerminalService()

    // MARK: - Send Message

    func send(text: String, to session: Session) {
        guard !text.isEmpty else { return }

        // Prevent concurrent processes — queue if busy
        if session.activeProcess != nil {
            session.messageQueue.append(QueuedMessage(text: text))
            return
        }

        // Record user message
        let userMsg = ChatMessage(role: .user, content: text)
        DispatchQueue.main.async {
            session.chatMessages.append(userMsg)
            session.status = .running
            session.assistantState = .thinking("Thinking...")
        }

        let startTime = Date()

        // Build claude command
        let settings = AppSettings.shared
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]

        if settings.alwaysBypassPermissions {
            args.append("--dangerously-skip-permissions")
        }

        // Plan mode
        if session.planMode {
            args += ["--permission-mode", "plan"]
        }

        // Resume existing conversation or start new
        if let sessionId = session.claudeSessionId {
            args += ["--resume", sessionId]
        }

        args.append(text)

        let workDir = (session.workingDirectory as NSString).expandingTildeInPath

        // Validate working directory
        if !FileManager.default.fileExists(atPath: workDir) {
            DispatchQueue.main.async {
                let err = ChatMessage(role: .assistant, content: "Error: Working directory not found: \(workDir)")
                session.chatMessages.append(err)
                session.status = .waitingForInput
                session.assistantState = .idle
            }
            return
        }

        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        let escapedText = text.replacingOccurrences(of: "'", with: "'\\''")
        let claudeCmd = ([settings.claudeCodePath] + args.dropLast()).joined(separator: " ")
        let fullCmd = "cd '\(workDir)' && \(claudeCmd) '\(escapedText)'"

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", fullCmd]
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Environment — TERM=dumb prevents any terminal UI
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        session.activeProcess = process

        // Collect events on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runAndCollect(process: process, pipe: pipe, errorPipe: errorPipe, session: session, startTime: startTime)
        }
    }

    // MARK: - Run Process & Collect JSON Events

    private func runAndCollect(process: Process, pipe: Pipe, errorPipe: Pipe, session: Session, startTime: Date) {
        do {
            try process.run()
        } catch {
            DispatchQueue.main.async {
                let err = ChatMessage(role: .assistant, content: "Failed to launch claude: \(error.localizedDescription)")
                session.chatMessages.append(err)
                session.status = .error
                session.assistantState = .idle
            }
            return
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        var messageIndex: Int?       // Index of the live assistant message
        var resultDuration: Int?
        var resultCost: Double?

        /// Append a block to the live streaming message (creates it if needed)
        func appendBlock(_ block: ContentBlock, textContent: String? = nil) {
            DispatchQueue.main.async {
                if let idx = messageIndex, idx < session.chatMessages.count {
                    session.chatMessages[idx].blocks.append(block)
                    if let text = textContent {
                        let existing = session.chatMessages[idx].content
                        session.chatMessages[idx].content = existing.isEmpty ? text : existing + "\n" + text
                    }
                } else {
                    var msg = ChatMessage(role: .assistant, content: textContent ?? "", blocks: [block])
                    msg.durationSeconds = 0
                    session.chatMessages.append(msg)
                    messageIndex = session.chatMessages.count - 1
                }
            }
        }

        // Read stdout line by line — stream blocks into live message
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                buffer = Data(buffer[newlineRange.upperBound...])

                guard let line = String(data: lineData, encoding: .utf8),
                      !line.isEmpty,
                      let jsonData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = json["type"] as? String
                else { continue }

                switch type {
                case "system":
                    if let sid = json["session_id"] as? String {
                        DispatchQueue.main.async { session.claudeSessionId = sid }
                    }

                case "assistant":
                    if let message = json["message"] as? [String: Any],
                       let content = message["content"] as? [[String: Any]] {
                        for block in content {
                            guard let blockType = block["type"] as? String else { continue }

                            switch blockType {
                            case "text":
                                if let text = block["text"] as? String, !text.isEmpty {
                                    // Skip if already streamed via content_block_delta
                                    if messageIndex == nil {
                                        appendBlock(.text(text), textContent: text)
                                        DispatchQueue.main.async {
                                            session.assistantState = .responding
                                        }
                                    }
                                }

                            case "tool_use":
                                let toolId = block["id"] as? String ?? UUID().uuidString
                                let name = block["name"] as? String ?? "Unknown"
                                let input = block["input"] as? [String: Any] ?? [:]
                                appendBlock(.toolUse(id: toolId, name: name, input: input))
                                let label: String = {
                                    let file = (input["file_path"] as? String ?? "").components(separatedBy: "/").last ?? ""
                                    switch name {
                                    case "Read": return "Reading \(file)..."
                                    case "Write": return "Writing \(file)..."
                                    case "Edit": return "Editing \(file)..."
                                    case "Bash":
                                        let cmd = (input["command"] as? String ?? "").prefix(50)
                                        return "Running: \(cmd)"
                                    case "Glob": return "Searching: \(input["pattern"] as? String ?? "files")..."
                                    case "Grep": return "Grep: \(input["pattern"] as? String ?? "")..."
                                    case "Agent":
                                        let desc = input["description"] as? String ?? input["prompt"] as? String ?? "task"
                                        return "Agent: \(desc.prefix(40))..."
                                    case "WebSearch": return "Searching: \(input["query"] as? String ?? "")..."
                                    case "WebFetch": return "Fetching URL..."
                                    default: return "\(name)..."
                                    }
                                }()
                                DispatchQueue.main.async { session.assistantState = .thinking(label) }

                            default: break
                            }
                        }
                    }

                case "tool_result":
                    let toolUseId = json["tool_use_id"] as? String ?? ""
                    var resultContent = ""
                    if let content = json["content"] as? String {
                        resultContent = content
                    } else if let content = json["content"] as? [[String: Any]] {
                        resultContent = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    if !resultContent.isEmpty {
                        appendBlock(.toolResult(toolUseId: toolUseId, content: resultContent))
                    }

                case "stream_event":
                    if let event = json["event"] as? [String: Any],
                       let eventType = event["type"] as? String {
                        if eventType == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String {
                            if deltaType == "text_delta", let text = delta["text"] as? String {
                                // Stream text word-by-word into the live message
                                DispatchQueue.main.async {
                                    if let idx = messageIndex, idx < session.chatMessages.count {
                                        // Update existing text block or create one
                                        let blocks = session.chatMessages[idx].blocks
                                        if let lastIdx = blocks.lastIndex(where: {
                                            if case .text = $0.kind { return true }; return false
                                        }) {
                                            if case .text(let existing) = session.chatMessages[idx].blocks[lastIdx].kind {
                                                session.chatMessages[idx].blocks[lastIdx] = ContentBlock(
                                                    id: session.chatMessages[idx].blocks[lastIdx].id,
                                                    kind: .text(existing + text)
                                                )
                                                session.chatMessages[idx].content += text
                                            }
                                        } else {
                                            session.chatMessages[idx].blocks.append(.text(text))
                                            session.chatMessages[idx].content += text
                                        }
                                        session.assistantState = .responding
                                    } else {
                                        // First content — create the message
                                        var msg = ChatMessage(role: .assistant, content: text, blocks: [.text(text)])
                                        msg.durationSeconds = 0
                                        session.chatMessages.append(msg)
                                        messageIndex = session.chatMessages.count - 1
                                        session.assistantState = .responding
                                    }
                                }
                            }
                        }
                    }

                case "result":
                    resultDuration = json["duration_ms"] as? Int
                    resultCost = json["total_cost_usd"] as? Double
                    if let sid = json["session_id"] as? String {
                        DispatchQueue.main.async { session.claudeSessionId = sid }
                    }

                default: break
                }
            }
        }

        process.waitUntilExit()

        // Read stderr
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Finalize
        let duration = Date().timeIntervalSince(startTime)
        DispatchQueue.main.async {
            session.activeProcess = nil

            // Update duration/cost on the streamed message
            if let idx = messageIndex, idx < session.chatMessages.count {
                session.chatMessages[idx].durationSeconds = duration
                session.chatMessages[idx].durationApiMs = resultDuration
                session.chatMessages[idx].costUsd = resultCost
            } else if process.terminationStatus != 0 && !stderrText.isEmpty {
                let err = ChatMessage(role: .assistant, content: "Error: \(stderrText)")
                session.chatMessages.append(err)
            }

            session.status = .waitingForInput
            session.assistantState = .idle

            // Trigger save after response completes
            NotificationCenter.default.post(name: .init("ClaudeStationSave"), object: nil)

            // System notification if app is not focused
            if !NSApp.isActive {
                let content = UNMutableNotificationContent()
                content.title = "Claude finished"
                let preview = session.chatMessages.last?.content.prefix(80) ?? ""
                content.body = String(preview)
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }

            if !session.messageQueue.isEmpty {
                self.processNextInQueue(for: session)
            }
        }
    }

    // MARK: - Queue Processing

    func processNextInQueue(for session: Session) {
        guard session.status == .waitingForInput,
              !session.messageQueue.isEmpty else { return }
        let message = session.messageQueue.removeFirst()
        send(text: message.text, to: session)
    }

    // MARK: - Terminate

    func terminate(session: Session) {
        session.activeProcess?.terminate()
        session.activeProcess = nil
        // Also terminate legacy PTY if present
        session.ptyPrimary?.readabilityHandler = nil
        session.process?.terminate()
        if let handle = session.ptyPrimary {
            close(handle.fileDescriptor)
        }
        session.process = nil
        session.ptyPrimary = nil
        session.terminalFeed = nil
        session.status = .idle
        session.assistantState = .idle
    }
}
