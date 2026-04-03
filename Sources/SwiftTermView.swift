import SwiftUI
import SwiftTerm

/// Cache of TerminalView instances per session — survives view recreation
class TerminalViewCache {
    static let shared = TerminalViewCache()
    private var views: [UUID: TerminalView] = [:]
    private var coordinators: [UUID: SwiftTermView.Coordinator] = [:]

    func terminalView(for session: Session, coordinator: SwiftTermView.Coordinator) -> TerminalView {
        if let existing = views[session.id] {
            // Update coordinator's session reference and delegate
            existing.terminalDelegate = coordinator
            coordinator.terminalView = existing
            coordinators[session.id] = coordinator
            return existing
        }

        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = coordinator
        tv.nativeBackgroundColor = .black
        tv.nativeForegroundColor = .white
        coordinator.terminalView = tv
        views[session.id] = tv
        coordinators[session.id] = coordinator

        // Set up PTY feed
        session.terminalFeed = { [weak tv] data in
            guard let tv = tv else { return }
            let bytes = Array(data)
            DispatchQueue.main.async {
                tv.feed(byteArray: bytes[...])
            }
        }

        return tv
    }

    func remove(sessionId: UUID) {
        views.removeValue(forKey: sessionId)
        coordinators.removeValue(forKey: sessionId)
    }

    /// Get current buffer line count by iterating getLine()
    func bufferLineCount(for sessionId: UUID) -> Int {
        guard let tv = views[sessionId] else { return 0 }
        let terminal = tv.getTerminal()
        var count = 0
        while terminal.getLine(row: count) != nil { count += 1 }
        return count
    }

    /// Read clean rendered text from the terminal buffer starting at a given line.
    /// Uses BufferLine.translateToString() which returns properly rendered characters
    /// (no ANSI codes, cursor artifacts, or animation overlaps).
    func getRenderedText(for sessionId: UUID, fromLine: Int) -> String {
        guard let tv = views[sessionId] else { return "" }
        let terminal = tv.getTerminal()
        var lines: [String] = []
        var row = fromLine
        while let bufLine = terminal.getLine(row: row) {
            lines.append(bufLine.translateToString(trimRight: true))
            row += 1
        }
        return lines.joined(separator: "\n")
    }
}

/// NSViewRepresentable wrapping SwiftTerm's TerminalView for proper terminal emulation
struct SwiftTermView: NSViewRepresentable {
    @ObservedObject var session: Session

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalViewCache.shared.terminalView(for: session, coordinator: context.coordinator)
        return tv
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // If the view in the cache differs from what's displayed, swap it
        let cached = TerminalViewCache.shared.terminalView(for: session, coordinator: context.coordinator)
        if cached !== nsView {
            // Can't swap NSViews in updateNSView — the .id() handles this
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        var session: Session
        weak var terminalView: TerminalView?

        init(session: Session) {
            self.session = session
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let handle = session.ptyPrimary else { return }
            handle.write(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            session.terminalCols = newCols
            session.terminalRows = newRows

            guard let handle = session.ptyPrimary else { return }
            var ws = winsize(
                ws_row: UInt16(newRows),
                ws_col: UInt16(newCols),
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            _ = ioctl(handle.fileDescriptor, TIOCSWINSZ, &ws)
            if let pid = session.process?.processIdentifier, pid > 0 {
                kill(pid, SIGWINCH)
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        func bell(source: TerminalView) {
            NSSound.beep()
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
