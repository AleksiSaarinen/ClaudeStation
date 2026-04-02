import SwiftUI
import SwiftTerm

/// NSViewRepresentable wrapping SwiftTerm's TerminalView for proper terminal emulation
struct SwiftTermView: NSViewRepresentable {
    @ObservedObject var session: Session

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.nativeBackgroundColor = .black
        tv.nativeForegroundColor = .white

        // Register this terminal view with the session for PTY output feeding
        context.coordinator.terminalView = tv
        session.terminalFeed = { data in
            let bytes = Array(data)
            DispatchQueue.main.async {
                tv.feed(byteArray: bytes[...])
            }
        }

        return tv
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Re-register feed callback if session changed
        if context.coordinator.session !== session {
            context.coordinator.session = session
            context.coordinator.terminalView = nsView
            session.terminalFeed = { data in
                let bytes = Array(data)
                DispatchQueue.main.async {
                    nsView.feed(byteArray: bytes[...])
                }
            }
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

        /// User typed in the terminal — forward to PTY
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let handle = session.ptyPrimary else { return }
            handle.write(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // Resize the PTY window
            guard let handle = session.ptyPrimary else { return }
            var ws = winsize(
                ws_row: UInt16(newRows),
                ws_col: UInt16(newCols),
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            ioctl(handle.fileDescriptor, TIOCSWINSZ, &ws)
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            // Could update session name here
        }

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
