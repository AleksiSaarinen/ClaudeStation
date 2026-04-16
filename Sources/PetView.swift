import SwiftUI
import AppKit

// MARK: - Pet State

enum PetState: String, Equatable {
    case idle, coding, thinking, reading, searching, testing, deploying, success, error, sleepy, web, running

    var frameCount: Int {
        switch self {
        case .idle, .coding, .testing, .sleepy: return 10
        case .thinking, .success, .error, .searching, .reading, .deploying, .web, .running: return 8
        }
    }

    var frameDuration: Double {
        switch self {
        case .idle: return 0.18
        case .sleepy: return 0.25
        case .coding, .testing: return 0.10
        case .thinking, .deploying: return 0.16
        case .searching: return 0.15
        case .reading: return 0.22
        case .success: return 0.12
        case .error: return 0.10
        case .web: return 0.16
        case .running: return 0.10
        }
    }

    var loops: Bool {
        switch self {
        case .success, .error: return false
        default: return true
        }
    }

    static func refineBash(command: String) -> PetState {
        let cmd = command.lowercased()
        if cmd.contains("test") || cmd.contains("jest") || cmd.contains("pytest") || cmd.contains("vitest") { return .testing }
        if cmd.contains("git push") || cmd.contains("git commit") || cmd.contains("deploy") || cmd.contains("publish") { return .deploying }
        if cmd.contains("grep") || cmd.contains("find ") || cmd.contains("search") || cmd.contains("rg ") { return .searching }
        if cmd.contains("curl") || cmd.contains("wget") || cmd.contains("http") || cmd.contains("fetch") { return .web }
        return .running
    }
}

// MARK: - Pet Frame Cache

class PetFrameCache {
    static let shared = PetFrameCache()
    private var frames: [String: [NSImage]] = [:]

    /// Original palette colors (with tolerance for anti-aliasing)
    private static let originalBody = NSColor(red: 0xD2/255, green: 0x78/255, blue: 0x50/255, alpha: 1)
    private static let originalHighlight = NSColor(red: 0xE1/255, green: 0x8C/255, blue: 0x64/255, alpha: 1)
    private static let originalShadow = NSColor(red: 0xB9/255, green: 0x64/255, blue: 0x41/255, alpha: 1)
    private static let originalEyes = NSColor(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255, alpha: 1)

    func framesFor(state: PetState, palette: PetPalette? = nil) -> [NSImage] {
        let key = "\(state.rawValue)_\(palette.map { "\($0.body.hashValue)" } ?? "default")"
        if let cached = frames[key] { return cached }

        var loaded: [NSImage] = []
        let resourcePath = Bundle.main.resourcePath ?? ""
        for i in 0..<state.frameCount {
            let path = "\(resourcePath)/PetFrames/\(state.rawValue)_\(i).png"
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 120, height: 120)
                if let palette = palette {
                    loaded.append(paletteSwap(image: image, palette: palette))
                } else {
                    loaded.append(image)
                }
            }
        }

        frames[key] = loaded
        return loaded
    }

    private func paletteSwap(image: NSImage, palette: PetPalette) -> NSImage {
        // Draw into a known RGBA bitmap
        let w = 120, h = 120
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
        ), let data = rep.bitmapData else { return image }

        // Draw the original image into our bitmap
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        // Build replacement map: (r, g, b) -> (r, g, b)
        func rgb(_ c: NSColor) -> (UInt8, UInt8, UInt8) {
            let c = c.usingColorSpace(.deviceRGB) ?? c
            return (UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255), UInt8(c.blueComponent * 255))
        }
        let map: [(from: (UInt8, UInt8, UInt8), to: (UInt8, UInt8, UInt8))] = [
            (from: (0xD2, 0x78, 0x50), to: rgb(palette.body)),
            (from: (0xE1, 0x8C, 0x64), to: rgb(palette.highlight)),
            (from: (0xB9, 0x64, 0x41), to: rgb(palette.shadow)),
            (from: (0x1E, 0x1E, 0x1E), to: rgb(palette.eyes)),
        ]

        let total = w * h * 4
        let tolerance: Int = 20
        var i = 0
        while i < total {
            let r = Int(data[i])
            let g = Int(data[i+1])
            let b = Int(data[i+2])
            // Skip transparent
            if data[i+3] > 5 {
                for entry in map {
                    if abs(r - Int(entry.from.0)) <= tolerance &&
                       abs(g - Int(entry.from.1)) <= tolerance &&
                       abs(b - Int(entry.from.2)) <= tolerance {
                        data[i]   = entry.to.0
                        data[i+1] = entry.to.1
                        data[i+2] = entry.to.2
                        break
                    }
                }
            }
            i += 4
        }

        let result = NSImage(size: NSSize(width: w, height: h))
        result.addRepresentation(rep)
        return result
    }
}

// MARK: - Pet View

struct PetView: View {
    @ObservedObject var session: Session
    var overrideState: PetState? = nil
    @Environment(\.theme) var theme

    @State private var currentState: PetState = .idle
    @State private var previousStatus: SessionStatus = .idle
    @State private var currentFrame = 0
    @State private var timer: Timer?
    @State private var idleSince = Date()
    @State private var oneShotDone = false

    private let size: CGFloat = 36

    var body: some View {
        let activeState = overrideState ?? currentState
        let frames = PetFrameCache.shared.framesFor(state: activeState, palette: theme.petPalette)

        Group {
            if !frames.isEmpty && currentFrame < frames.count {
                Image(nsImage: frames[currentFrame])
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            if let forced = overrideState {
                currentState = forced
                currentFrame = 0
                oneShotDone = false
                startAnimation()
            } else {
                updateState(); startAnimation()
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: session.status) { _, _ in if overrideState == nil { updateState() } }
        .onChange(of: session.assistantState) { _, _ in if overrideState == nil { updateState() } }
        .onChange(of: session.lastToolName) { _, _ in if overrideState == nil { updateState() } }
    }

    private func updateState() {
        let newState: PetState

        switch session.status {
        case .running:
            if let tool = session.lastToolName {
                switch tool {
                case "Read": newState = .reading
                case "Grep", "Glob": newState = .searching
                case "Bash": newState = PetState.refineBash(command: session.lastToolCommand ?? "")
                case "Write", "Edit": newState = .coding
                case "WebSearch", "WebFetch": newState = .web
                case "Agent": newState = .thinking
                default: newState = .coding
                }
            } else if case .thinking(let label) = session.assistantState {
                let l = label.lowercased()
                if l.hasPrefix("running:") { newState = .running }
                else if l.hasPrefix("reading") { newState = .reading }
                else if l.hasPrefix("editing") || l.hasPrefix("writing") { newState = .coding }
                else if l.hasPrefix("searching") { newState = .searching }
                else if l.hasPrefix("fetching") { newState = .web }
                else if l.hasPrefix("agent:") { newState = .thinking }
                else { newState = .thinking }
            } else if case .responding = session.assistantState {
                newState = .coding
            } else {
                newState = .thinking
            }
            idleSince = Date()

        case .waitingForInput:
            // Play success animation when transitioning from running to waiting
            if previousStatus == .running && currentState != .success {
                newState = .success
            } else if currentState == .success {
                // Already playing success, let it finish
                return
            } else {
                newState = .idle
            }

        case .error: newState = .error
        case .idle: newState = .idle
        }

        previousStatus = session.status

        if newState != currentState {
            currentState = newState
            currentFrame = 0
            oneShotDone = false
            startAnimation()
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        let state = currentState
        timer = Timer.scheduledTimer(withTimeInterval: state.frameDuration, repeats: true) { _ in
            let count = PetFrameCache.shared.framesFor(state: state, palette: theme.petPalette).count
            guard count > 0 else { return }

            if state.loops {
                currentFrame = (currentFrame + 1) % count
            } else if currentFrame < count - 1 {
                currentFrame += 1
            } else if !oneShotDone {
                oneShotDone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if currentState == state {
                        currentState = .idle
                        currentFrame = 0
                        startAnimation()
                    }
                }
            }

        }
    }
}
