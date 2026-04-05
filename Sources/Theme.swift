import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String

    // Chat
    let chatBg: Color
    let chatBgGradientEnd: Color?  // If set, chatBg → chatBgGradientEnd vertical gradient
    let userBubble: Color
    let userBubbleText: Color
    let assistantBubble: Color
    let assistantBubbleBorder: Color
    let assistantText: Color

    // Tool cards
    let toolCardBg: Color
    let toolCardBorder: Color
    let toolCardText: Color

    // Accent
    let accent: Color

    // Chrome (header, input bar, queue)
    let chromeBar: Color
    let chromeBorder: Color
    let chromeText: Color

    // Input
    let inputBg: Color
    let inputBorder: Color

    // Semantic
    let mutedText: Color
    let successDot: Color
    let costText: Color
    let timestampText: Color
    let promptChar: String
    let promptColor: Color

    // Typography
    let fontMono: String
    let fontUI: String
    let borderRadius: CGFloat

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }

    /// Background view — animated gradient if configured, solid color otherwise
    @ViewBuilder func chatBackground(toolName: String? = nil, isRunning: Bool = false) -> some View {
        if chatBgGradientEnd != nil {
            AnimatedGradientBackground(theme: self, toolName: toolName, isRunning: isRunning)
        } else {
            chatBg
        }
    }

    /// Static background for places that don't have session context
    @ViewBuilder var chatBackground: some View {
        if chatBgGradientEnd != nil {
            AnimatedGradientBackground(theme: self, toolName: nil, isRunning: false)
        } else {
            chatBg
        }
    }
}

// MARK: - Animated Gradient Background with Particles

struct AnimatedGradientBackground: View {
    let theme: Theme
    var toolName: String?
    var isRunning: Bool
    @State private var particles: [Particle] = []
    @State private var initialized = false

    struct Particle {
        var x: Double
        var y: Double
        var size: Double
        var opacity: Double
        var speedX: Double
        var speedY: Double
        var phase: Double
        var phaseSpeed: Double
        var life: Double
    }

    /// Accent color shifts based on what Claude is doing
    private var activityColor: NSColor {
        guard isRunning, let tool = toolName else {
            return NSColor(theme.accent)
        }
        switch tool {
        case "Read":                return NSColor(Color(hex: "#60A5FA")) // blue — reading
        case "Write", "Edit":      return NSColor(Color(hex: "#34D399")) // green — writing
        case "Bash":               return NSColor(Color(hex: "#FBBF24")) // amber — executing
        case "Grep", "Glob":       return NSColor(Color(hex: "#A78BFA")) // purple — searching
        case "Agent":              return NSColor(Color(hex: "#F472B6")) // pink — thinking
        case "WebSearch","WebFetch":return NSColor(Color(hex: "#38BDF8")) // cyan — web
        default:                   return NSColor(theme.accent)
        }
    }

    /// Particle speed multiplier based on activity
    private var speedMult: Double {
        isRunning ? 1.8 : 1.0
    }

    /// Blob opacity changes with activity
    private var blobOpacity: Double {
        isRunning ? 0.10 : 0.06
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let base = theme.chatBg
                let end = theme.chatBgGradientEnd ?? theme.chatBg

                // Base gradient
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [base, end]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Moving gradient blobs
                let blobRadius = min(size.width, size.height) * 0.5
                let blobColor = Color(nsColor: activityColor.withAlphaComponent(blobOpacity))
                let blobs: [(Double, Double, Double, Double)] = [
                    (0.25, 0.2, 0.7, 0.5),
                    (0.75, 0.7, 0.6, 0.8),
                    (0.5,  0.5, 0.4, 0.3),
                    (0.3,  0.8, 0.5, 0.6),
                ]
                for (bx, by, fx, fy) in blobs {
                    let cx = size.width * (bx + 0.2 * sin(t * 0.05 * fx * speedMult))
                    let cy = size.height * (by + 0.15 * cos(t * 0.05 * fy * speedMult))
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: cx - blobRadius, y: cy - blobRadius,
                            width: blobRadius * 2, height: blobRadius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [blobColor, .clear]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: blobRadius
                        )
                    )
                }

                // Particles
                let accentColor = activityColor
                for i in particles.indices {
                    var p = particles[i]
                    let elapsed = t * p.phaseSpeed
                    let px = (p.x + p.speedX * t * speedMult + sin(elapsed + p.phase) * 0.02)
                        .truncatingRemainder(dividingBy: 1.1)
                    let py = (p.y - p.speedY * t * speedMult + cos(elapsed + p.phase) * 0.015)
                        .truncatingRemainder(dividingBy: 1.1)
                    // Wrap around
                    let wx = px < -0.05 ? px + 1.15 : px
                    let wy = py < -0.05 ? py + 1.15 : py

                    // Fade near edges
                    let edgeFade = min(
                        min(wx, 1.0 - wx) * 8,
                        min(wy, 1.0 - wy) * 8
                    ).clamped(to: 0...1)
                    // Twinkle
                    let twinkle = 0.5 + 0.5 * sin(t * p.phaseSpeed * 2 + p.phase)
                    let alpha = p.opacity * edgeFade * twinkle

                    let screenX = wx * size.width
                    let screenY = wy * size.height
                    let r = p.size

                    // Glow
                    context.fill(
                        Path(ellipseIn: CGRect(x: screenX - r * 2, y: screenY - r * 2, width: r * 4, height: r * 4)),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(nsColor: accentColor.withAlphaComponent(alpha * 0.3)),
                                .clear
                            ]),
                            center: CGPoint(x: screenX, y: screenY),
                            startRadius: 0,
                            endRadius: r * 2
                        )
                    )

                    // Core dot
                    context.fill(
                        Path(ellipseIn: CGRect(x: screenX - r/2, y: screenY - r/2, width: r, height: r)),
                        with: .color(Color(nsColor: accentColor.withAlphaComponent(alpha * 0.8)))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            particles = (0..<25).map { _ in
                Particle(
                    x: Double.random(in: 0...1),
                    y: Double.random(in: 0...1),
                    size: Double.random(in: 1.5...3.5),
                    opacity: Double.random(in: 0.3...0.8),
                    speedX: Double.random(in: -0.003...0.003),
                    speedY: Double.random(in: 0.002...0.008),
                    phase: Double.random(in: 0...(.pi * 2)),
                    phaseSpeed: Double.random(in: 0.3...1.2),
                    life: 1.0
                )
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Predefined Themes

extension Theme {
    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        chatBg: Color(hex: "#1a1535"), chatBgGradientEnd: Color(hex: "#0e1025"),
        userBubble: Color(hex: "#7B6FDE"), userBubbleText: .white,
        assistantBubble: Color(hex: "#1C1C2E"), assistantBubbleBorder: Color(hex: "#2D2D44"), assistantText: Color(hex: "#E0E0F0"),
        toolCardBg: Color(hex: "#161625"), toolCardBorder: Color(hex: "#2D2D44"), toolCardText: Color(hex: "#A0A0C0"),
        accent: Color(hex: "#7B6FDE"),
        chromeBar: Color(hex: "#1C1C2E"), chromeBorder: Color(hex: "#2D2D44"), chromeText: Color(hex: "#8888AA"),
        inputBg: Color(hex: "#1C1C2E"), inputBorder: Color(hex: "#2D2D44"),
        mutedText: Color(hex: "#5A5A7A"), successDot: Color(hex: "#4ADE80"),
        costText: Color(hex: "#5A5A7A"), timestampText: Color(hex: "#5A5A7A"),
        promptChar: "❯", promptColor: Color(hex: "#7B6FDE"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12
    )

    static let aurora = Theme(
        id: "aurora", name: "Aurora",
        chatBg: Color(hex: "#303848"), chatBgGradientEnd: Color(hex: "#181E28"),
        userBubble: Color(hex: "#88C0D0"), userBubbleText: Color(hex: "#2E3440"),
        assistantBubble: Color(hex: "#2E3440"), assistantBubbleBorder: Color(hex: "#3B4252"), assistantText: Color(hex: "#D8DEE9"),
        toolCardBg: Color(hex: "#272D38"), toolCardBorder: Color(hex: "#3B4252"), toolCardText: Color(hex: "#81A1C1"),
        accent: Color(hex: "#88C0D0"),
        chromeBar: Color(hex: "#2E3440"), chromeBorder: Color(hex: "#3B4252"), chromeText: Color(hex: "#7B88A1"),
        inputBg: Color(hex: "#2E3440"), inputBorder: Color(hex: "#3B4252"),
        mutedText: Color(hex: "#616E88"), successDot: Color(hex: "#A3BE8C"),
        costText: Color(hex: "#616E88"), timestampText: Color(hex: "#616E88"),
        promptChar: "❯", promptColor: Color(hex: "#88C0D0"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12
    )

    static let rose = Theme(
        id: "rose", name: "Rosé",
        chatBg: Color(hex: "#262040"), chatBgGradientEnd: Color(hex: "#12101A"),
        userBubble: Color(hex: "#EB6F92"), userBubbleText: .white,
        assistantBubble: Color(hex: "#1F1D2E"), assistantBubbleBorder: Color(hex: "#2A2740"), assistantText: Color(hex: "#E0DEF4"),
        toolCardBg: Color(hex: "#1A1826"), toolCardBorder: Color(hex: "#2A2740"), toolCardText: Color(hex: "#908CAA"),
        accent: Color(hex: "#EB6F92"),
        chromeBar: Color(hex: "#1F1D2E"), chromeBorder: Color(hex: "#2A2740"), chromeText: Color(hex: "#6E6A86"),
        inputBg: Color(hex: "#1F1D2E"), inputBorder: Color(hex: "#2A2740"),
        mutedText: Color(hex: "#524F67"), successDot: Color(hex: "#9CCFD8"),
        costText: Color(hex: "#524F67"), timestampText: Color(hex: "#524F67"),
        promptChar: "❯", promptColor: Color(hex: "#EB6F92"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12
    )

    static let paper = Theme(
        id: "paper", name: "Paper",
        chatBg: Color(hex: "#FAF8F4"), chatBgGradientEnd: nil,
        userBubble: Color(hex: "#C0593A"), userBubbleText: .white,
        assistantBubble: Color(hex: "#F0ECE4"), assistantBubbleBorder: Color(hex: "#E0DAD0"), assistantText: Color(hex: "#3D3830"),
        toolCardBg: Color(hex: "#F5F1EB"), toolCardBorder: Color(hex: "#E0DAD0"), toolCardText: Color(hex: "#6B6258"),
        accent: Color(hex: "#C0593A"),
        chromeBar: Color(hex: "#F5F1EB"), chromeBorder: Color(hex: "#E0DAD0"), chromeText: Color(hex: "#8A8078"),
        inputBg: Color(hex: "#F5F1EB"), inputBorder: Color(hex: "#E0DAD0"),
        mutedText: Color(hex: "#A09888"), successDot: Color(hex: "#5A8A5A"),
        costText: Color(hex: "#A09888"), timestampText: Color(hex: "#A09888"),
        promptChar: "❯", promptColor: Color(hex: "#C0593A"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12
    )

    static let phosphor = Theme(
        id: "phosphor", name: "Phosphor",
        chatBg: Color(hex: "#061806"), chatBgGradientEnd: Color(hex: "#020402"),
        userBubble: Color(hex: "#1A6B1A"), userBubbleText: Color(hex: "#33FF33"),
        assistantBubble: Color(hex: "#0A120A"), assistantBubbleBorder: Color(hex: "#1A2E1A"), assistantText: Color(hex: "#33FF33"),
        toolCardBg: Color(hex: "#0E140E"), toolCardBorder: Color(hex: "#1A2E1A"), toolCardText: Color(hex: "#33FF33"),
        accent: Color(hex: "#33FF33"),
        chromeBar: Color(hex: "#0A120A"), chromeBorder: Color(hex: "#1A2E1A"), chromeText: Color(hex: "#1A8A1A"),
        inputBg: Color(hex: "#0A120A"), inputBorder: Color(hex: "#1A2E1A"),
        mutedText: Color(hex: "#1A6B1A"), successDot: Color(hex: "#33FF33"),
        costText: Color(hex: "#1A6B1A"), timestampText: Color(hex: "#1A6B1A"),
        promptChar: ">", promptColor: Color(hex: "#33FF33"),
        fontMono: "Menlo", fontUI: "Menlo", borderRadius: 0
    )

    static let deepSea = Theme(
        id: "deepsea", name: "Deep Sea",
        chatBg: Color(hex: "#102238"), chatBgGradientEnd: Color(hex: "#060C14"),
        userBubble: Color(hex: "#0D4A3A"), userBubbleText: Color(hex: "#00D4AA"),
        assistantBubble: Color(hex: "#0D1B2A"), assistantBubbleBorder: Color(hex: "#1B2D45"), assistantText: Color(hex: "#C0D8E8"),
        toolCardBg: Color(hex: "#0B1724"), toolCardBorder: Color(hex: "#1B2D45"), toolCardText: Color(hex: "#00D4AA"),
        accent: Color(hex: "#00D4AA"),
        chromeBar: Color(hex: "#0D1B2A"), chromeBorder: Color(hex: "#1B2D45"), chromeText: Color(hex: "#4A6A8A"),
        inputBg: Color(hex: "#0D1B2A"), inputBorder: Color(hex: "#1B2D45"),
        mutedText: Color(hex: "#3A5A7A"), successDot: Color(hex: "#00D4AA"),
        costText: Color(hex: "#3A5A7A"), timestampText: Color(hex: "#3A5A7A"),
        promptChar: "❯", promptColor: Color(hex: "#00D4AA"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12
    )

    static let amber = Theme(
        id: "amber", name: "Amber",
        chatBg: Color(hex: "#201810"), chatBgGradientEnd: Color(hex: "#0A0804"),
        userBubble: Color(hex: "#3D2A0A"), userBubbleText: Color(hex: "#FFB347"),
        assistantBubble: Color(hex: "#1A1410"), assistantBubbleBorder: Color(hex: "#2E2418"), assistantText: Color(hex: "#FFB347"),
        toolCardBg: Color(hex: "#161110"), toolCardBorder: Color(hex: "#2E2418"), toolCardText: Color(hex: "#FFB347"),
        accent: Color(hex: "#FFB347"),
        chromeBar: Color(hex: "#1A1410"), chromeBorder: Color(hex: "#2E2418"), chromeText: Color(hex: "#8A6A3A"),
        inputBg: Color(hex: "#1A1410"), inputBorder: Color(hex: "#2E2418"),
        mutedText: Color(hex: "#6A5030"), successDot: Color(hex: "#FFB347"),
        costText: Color(hex: "#6A5030"), timestampText: Color(hex: "#6A5030"),
        promptChar: ">", promptColor: Color(hex: "#FFB347"),
        fontMono: "Menlo", fontUI: "Menlo", borderRadius: 4
    )

    static let sakura = Theme(
        id: "sakura", name: "Sakura",
        chatBg: Color(hex: "#FDF6F6"), chatBgGradientEnd: nil,
        userBubble: Color(hex: "#D4728C"), userBubbleText: .white,
        assistantBubble: Color(hex: "#F5ECEC"), assistantBubbleBorder: Color(hex: "#E8D8D8"), assistantText: Color(hex: "#4A3535"),
        toolCardBg: Color(hex: "#F8F0F0"), toolCardBorder: Color(hex: "#E8D8D8"), toolCardText: Color(hex: "#8A6070"),
        accent: Color(hex: "#D4728C"),
        chromeBar: Color(hex: "#F8F0F0"), chromeBorder: Color(hex: "#E8D8D8"), chromeText: Color(hex: "#9A7A7A"),
        inputBg: Color(hex: "#F8F0F0"), inputBorder: Color(hex: "#E8D8D8"),
        mutedText: Color(hex: "#B0A0A0"), successDot: Color(hex: "#7AB87A"),
        costText: Color(hex: "#B0A0A0"), timestampText: Color(hex: "#B0A0A0"),
        promptChar: "❯", promptColor: Color(hex: "#D4728C"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 14
    )

    static let violet = Theme(
        id: "violet", name: "Violet",
        chatBg: Color(hex: "#1E1230"), chatBgGradientEnd: Color(hex: "#0F0A1A"),
        userBubble: Color(hex: "#A855F7"), userBubbleText: .white,
        assistantBubble: Color(hex: "#1A1228"), assistantBubbleBorder: Color(hex: "#2E1F4A"), assistantText: Color(hex: "#E8E0F8"),
        toolCardBg: Color(hex: "#150E22"), toolCardBorder: Color(hex: "#2E1F4A"), toolCardText: Color(hex: "#B89EDB"),
        accent: Color(hex: "#A855F7"),
        chromeBar: Color(hex: "#1A1228"), chromeBorder: Color(hex: "#2E1F4A"), chromeText: Color(hex: "#8A70AA"),
        inputBg: Color(hex: "#1A1228"), inputBorder: Color(hex: "#2E1F4A"),
        mutedText: Color(hex: "#5E4880"), successDot: Color(hex: "#86EFAC"),
        costText: Color(hex: "#5E4880"), timestampText: Color(hex: "#5E4880"),
        promptChar: "❯", promptColor: Color(hex: "#A855F7"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 14
    )

    static let neon = Theme(
        id: "neon", name: "Neon",
        chatBg: Color(hex: "#0A0A0F"), chatBgGradientEnd: Color(hex: "#050510"),
        userBubble: Color(hex: "#FF3CAC"), userBubbleText: .white,
        assistantBubble: Color(hex: "#0E0E1A"), assistantBubbleBorder: Color(hex: "#1A1A30"), assistantText: Color(hex: "#F0F0FF"),
        toolCardBg: Color(hex: "#0A0A14"), toolCardBorder: Color(hex: "#1A1A30"), toolCardText: Color(hex: "#B0B0D0"),
        accent: Color(hex: "#FF3CAC"),
        chromeBar: Color(hex: "#0E0E1A"), chromeBorder: Color(hex: "#1A1A30"), chromeText: Color(hex: "#7070A0"),
        inputBg: Color(hex: "#0E0E1A"), inputBorder: Color(hex: "#1A1A30"),
        mutedText: Color(hex: "#4A4A70"), successDot: Color(hex: "#00FF88"),
        costText: Color(hex: "#4A4A70"), timestampText: Color(hex: "#4A4A70"),
        promptChar: "▸", promptColor: Color(hex: "#FF3CAC"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 10
    )

    static let all: [Theme] = [midnight, aurora, rose, paper, phosphor, deepSea, amber, sakura, violet, neon]

    static func byId(_ id: String) -> Theme {
        all.first { $0.id == id } ?? midnight
    }

    /// Create a copy with custom fonts
    func withFonts(mono: String?, ui: String?) -> Theme {
        Theme(
            id: id, name: name, chatBg: chatBg, chatBgGradientEnd: chatBgGradientEnd,
            userBubble: userBubble, userBubbleText: userBubbleText,
            assistantBubble: assistantBubble, assistantBubbleBorder: assistantBubbleBorder, assistantText: assistantText,
            toolCardBg: toolCardBg, toolCardBorder: toolCardBorder, toolCardText: toolCardText,
            accent: accent,
            chromeBar: chromeBar, chromeBorder: chromeBorder, chromeText: chromeText,
            inputBg: inputBg, inputBorder: inputBorder,
            mutedText: mutedText, successDot: successDot,
            costText: costText, timestampText: timestampText,
            promptChar: promptChar, promptColor: promptColor,
            fontMono: mono ?? fontMono, fontUI: ui ?? fontUI, borderRadius: borderRadius
        )
    }

    /// Available monospaced fonts for the picker
    static let availableMonoFonts = [
        "System Mono", "Menlo", "Monaco", "Courier New",
        "JetBrains Mono", "Fira Code", "Source Code Pro",
        "IBM Plex Mono", "Hack", "Inconsolata"
    ]

    /// Resolve NSFont — "System Mono" maps to the system monospaced font
    func resolvedNSFont(size: CGFloat) -> NSFont {
        if fontMono == "System Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: fontMono, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Font helpers — use the same NSFont resolution as SelectableText
    var monoFont: Font { Font(resolvedNSFont(size: 13)) }
    var monoCaptionFont: Font { Font(resolvedNSFont(size: 11)) }
    var monoCaption2Font: Font { Font(resolvedNSFont(size: 10)) }
    var uiFont: Font { fontUI == ".AppleSystemUIFont" ? .body : .custom(fontUI, size: 13) }
    var uiCaptionFont: Font { fontUI == ".AppleSystemUIFont" ? .caption : .custom(fontUI, size: 11) }
    var uiCaption2Font: Font { fontUI == ".AppleSystemUIFont" ? .caption2 : .custom(fontUI, size: 10) }
}

// MARK: - Theme Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.midnight
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
