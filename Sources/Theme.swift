import SwiftUI

struct PetPalette: Equatable {
    let body: NSColor       // replaces #D27850
    let highlight: NSColor  // replaces #E18C64
    let shadow: NSColor     // replaces #B96441
    let eyes: NSColor       // replaces #1E1E1E
}

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

    // Pet palette (nil = use original colors)
    var petPalette: PetPalette? = nil

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id && lhs.fontMono == rhs.fontMono && lhs.fontUI == rhs.fontUI
    }

    /// Background view — animated gradient if configured, solid color otherwise
    @ViewBuilder func chatBackground(toolName: String? = nil, isRunning: Bool = false, session: Session? = nil) -> some View {
        if chatBgGradientEnd != nil {
            AnimatedGradientBackground(theme: self, toolName: toolName, isRunning: isRunning, session: session)
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
    var session: Session?
    @State private var particles: [Particle] = Self.makeParticles(count: 60)
    @State private var startTime: Date = .now
    /// Smoothed running intensity (0 = idle, 1 = fully running). Eases transitions.
    @State private var runIntensity: Double = 0
    @State private var lastRunningState: Bool = false

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

    /// Accent color shifts based on what Claude is doing.
    /// During celebration, blends from last tool color back to accent.
    private var activityColor: NSColor {
        let toolColor: NSColor? = {
            guard let tool = toolName else { return nil }
            switch tool {
            case "Read":                return NSColor(Color(hex: "#60A5FA"))
            case "Write", "Edit":      return NSColor(Color(hex: "#34D399"))
            case "Bash":               return NSColor(Color(hex: "#FBBF24"))
            case "Grep", "Glob":       return NSColor(Color(hex: "#A78BFA"))
            case "Agent":              return NSColor(Color(hex: "#F472B6"))
            case "WebSearch","WebFetch":return NSColor(Color(hex: "#38BDF8"))
            default:                   return nil
            }
        }()
        let accent = NSColor(theme.accent)

        if isRunning {
            return toolColor ?? accent
        }

        // During celebration, use accent (blobs shouldn't flash with tool colors)
        if celIntensity > 0 {
            return accent
        }

        return accent
    }

    static func makeParticles(count: Int) -> [Particle] {
        (0..<count).map { _ in
            Particle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 0.8...3.0),
                opacity: Double.random(in: 0.3...1.0),
                speedX: Double.random(in: -0.005...0.005),
                speedY: Double.random(in: 0.003...0.015),
                phase: Double.random(in: 0...(.pi * 2)),
                phaseSpeed: Double.random(in: 0.5...2.0),
                life: 1.0
            )
        }
    }

    /// How far into the celebration we are (0 = just started, 1+ = winding down)
    private var celProgress: Double {
        guard session?.celebrating == true,
              let start = session?.celebrationStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Celebration intensity: gentle ramp up, long slow fade
    private var celIntensity: Double {
        guard celProgress > 0 else { return 0 }
        let rampUp = min(celProgress / 0.8, 1.0) // 0.8s gentle ramp up
        let rampDown = max(0, 1.0 - (celProgress - 2.0) / 3.0) // fade from 2s to 5s
        return rampUp * rampDown
    }

    /// Effective activity level — blends runIntensity with celIntensity for smooth transitions
    private var activity: Double {
        max(runIntensity, celIntensity)
    }

    /// Particle speed multiplier — smoothly transitions between states
    private var speedMult: Double {
        0.8 + 29.2 * runIntensity + 9.2 * celIntensity
    }

    /// Particle vertical direction: smoothly transitions between rise (-1) and drift (+1)
    private var particleDirection: Double {
        activity > 0.01 ? -1.0 : 1.0
    }

    /// Blob opacity — only responds to running state, not celebration
    private var blobOpacity: Double {
        0.12 + 0.06 * runIntensity
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSince(startTime)
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

                // Moving gradient blobs — alternate between accent and userBubble colors
                let blobRadius = min(size.width, size.height) * 0.5
                let blobColor = Color(nsColor: activityColor.withAlphaComponent(blobOpacity))
                let blobColor2 = Color(nsColor: NSColor(theme.userBubble).withAlphaComponent(blobOpacity))
                let blobs: [(Double, Double, Double, Double, Bool)] = [
                    (0.25, 0.2, 0.7, 0.5, false),
                    (0.75, 0.7, 0.6, 0.8, true),
                    (0.5,  0.5, 0.4, 0.3, false),
                    (0.3,  0.8, 0.5, 0.6, true),
                ]
                // Blobs drift slowly — speed based on smooth activity
                let blobSpeed = 0.5 + 0.5 * runIntensity
                for (bx, by, fx, fy, useAlt) in blobs {
                    let cx = size.width * (bx + 0.2 * sin(t * 0.05 * fx * blobSpeed))
                    let cy = size.height * (by + 0.15 * cos(t * 0.05 * fy * blobSpeed))
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: cx - blobRadius, y: cy - blobRadius,
                            width: blobRadius * 2, height: blobRadius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [useAlt ? blobColor2 : blobColor, .clear]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: blobRadius
                        )
                    )
                }

                // Particles — render multiple passes when celebrating for burst effect
                let bgBrightness = NSColor(base).brightnessComponent
                let isBubbleMode = bgBrightness > 0.35
                let accentColor = isBubbleMode ? NSColor(Color(hex: "#B3E5FC")) : activityColor
                let celI = celIntensity
                let passes = celI > 0.1 ? 2 : 1
                let active = activity > 0.01
                let speed = speedMult

                for pass in 0..<passes {
                    let phaseOffset = Double(pass) * 1.7
                    let posOffset = Double(pass) * 0.23

                    for i in particles.indices {
                        let p = particles[i]
                        let elapsed = t * p.phaseSpeed
                        let wobbleX = active ? sin(elapsed * 2 + p.phase + phaseOffset) * 0.008 : sin(elapsed + p.phase) * 0.02
                        var wx = (p.x + posOffset + p.speedX * t * (active ? 0.3 : speed) + wobbleX)
                            .truncatingRemainder(dividingBy: 1.0)
                        var wy = (p.y + posOffset * 0.7 + p.speedY * t * speed * particleDirection)
                            .truncatingRemainder(dividingBy: 1.0)
                        if wx < 0 { wx += 1.0 }
                        if wy < 0 { wy += 1.0 }

                        let edgeFade = min(
                            min(wx, 1.0 - wx) * 8,
                            min(wy, 1.0 - wy) * 8
                        ).clamped(to: 0...1)
                        let twinkleSpeed = active ? p.phaseSpeed * 6 : p.phaseSpeed * 2
                        let twinkle = active ? 0.6 + 0.4 * sin(t * twinkleSpeed + p.phase + phaseOffset) : 0.4 + 0.6 * sin(t * twinkleSpeed + p.phase)
                        let sizeScale = active ? 1.0 + 0.3 * sin(t * p.phaseSpeed * 3 + p.phase + phaseOffset) : 1.0
                        let alpha = p.opacity * edgeFade * twinkle * (pass > 0 ? celI : 1.0)

                        let screenX = wx * size.width
                        let screenY = wy * size.height

                        if isBubbleMode {
                            let r = (p.size * sizeScale) * 2.5
                            let rect = CGRect(x: screenX - r, y: screenY - r, width: r * 2, height: r * 2)
                            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha * 0.08)))
                            context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha * 0.35)), lineWidth: 0.6)
                            let hlSize = r * 0.35
                            let hlX = screenX - r * 0.35
                            let hlY = screenY - r * 0.35
                            context.fill(
                                Path(ellipseIn: CGRect(x: hlX - hlSize/2, y: hlY - hlSize/2, width: hlSize, height: hlSize)),
                                with: .color(Color.white.opacity(alpha * 0.5))
                            )
                        } else {
                            let r = p.size * sizeScale
                            let glowMult = active ? 3.0 : 2.0
                            let glowAlpha = active ? alpha * 0.7 : alpha * 0.5
                            context.fill(
                                Path(ellipseIn: CGRect(x: screenX - r * glowMult, y: screenY - r * glowMult, width: r * glowMult * 2, height: r * glowMult * 2)),
                                with: .radialGradient(
                                    Gradient(colors: [
                                        Color(nsColor: accentColor.withAlphaComponent(glowAlpha)),
                                        .clear
                                    ]),
                                    center: CGPoint(x: screenX, y: screenY),
                                    startRadius: 0,
                                    endRadius: r * glowMult
                                )
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(x: screenX - r/2, y: screenY - r/2, width: r, height: r)),
                                with: .color(Color(nsColor: accentColor.withAlphaComponent(alpha * 0.8)))
                            )
                        }
                    }
                }

            }
        }
        .ignoresSafeArea()
        .onAppear {
            startTime = .now
            runIntensity = isRunning ? 1.0 : 0.0
            lastRunningState = isRunning
        }
        .onChange(of: isRunning) { _, newValue in
            guard newValue != lastRunningState else { return }
            lastRunningState = newValue
            withAnimation(.easeInOut(duration: newValue ? 1.5 : 2.5)) {
                runIntensity = newValue ? 1.0 : 0.0
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
        // Midnight: keep original orange pet — warm contrast on dark
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#88C0D0")),
            highlight: NSColor(Color(hex: "#A3D4E0")),
            shadow: NSColor(Color(hex: "#6BA8B8")),
            eyes: NSColor(Color(hex: "#2E3440"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#E0DEF4")),
            highlight: NSColor(Color(hex: "#F0EEF8")),
            shadow: NSColor(Color(hex: "#C0BDD4")),
            eyes: NSColor(Color(hex: "#EB6F92"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#C8B8A0")),
            highlight: NSColor(Color(hex: "#D8CDB8")),
            shadow: NSColor(Color(hex: "#A89880")),
            eyes: NSColor(Color(hex: "#5C4A3A"))
        )
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
        fontMono: "Menlo", fontUI: "Menlo", borderRadius: 0,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#33FF33")),
            highlight: NSColor(Color(hex: "#66FF66")),
            shadow: NSColor(Color(hex: "#1ABF1A")),
            eyes: NSColor(Color(hex: "#0A0A0A"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#4A90B8")),
            highlight: NSColor(Color(hex: "#60A8D0")),
            shadow: NSColor(Color(hex: "#3A7098")),
            eyes: NSColor(Color(hex: "#C0D8E8"))
        )
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
        fontMono: "Menlo", fontUI: "Menlo", borderRadius: 4,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#FFB347")),
            highlight: NSColor(Color(hex: "#FFCC77")),
            shadow: NSColor(Color(hex: "#CC8A30")),
            eyes: NSColor(Color(hex: "#1A1410"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 14,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#F8C8D0")),
            highlight: NSColor(Color(hex: "#FFE0E8")),
            shadow: NSColor(Color(hex: "#D8A0B0")),
            eyes: NSColor(Color(hex: "#8B3A50"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 14,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#B088E0")),
            highlight: NSColor(Color(hex: "#C8A8F0")),
            shadow: NSColor(Color(hex: "#8860C0")),
            eyes: NSColor(Color(hex: "#F0F0FF"))
        )
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
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 10,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#FF00FF")),
            highlight: NSColor(Color(hex: "#FF66FF")),
            shadow: NSColor(Color(hex: "#CC00CC")),
            eyes: NSColor(Color(hex: "#00FFFF"))
        )
    )

    static let melon = Theme(
        id: "melon", name: "Melon",
        chatBg: Color(hex: "#20905A"), chatBgGradientEnd: Color(hex: "#E8509A"),
        userBubble: Color(hex: "#FF69B4"), userBubbleText: .white,
        assistantBubble: Color(hex: "#152420"), assistantBubbleBorder: Color(hex: "#30E080"), assistantText: Color(hex: "#E8FFF0"),
        toolCardBg: Color(hex: "#12201A"), toolCardBorder: Color(hex: "#30E080"), toolCardText: Color(hex: "#50FF90"),
        accent: Color(hex: "#50FF90"),
        chromeBar: Color(hex: "#152420"), chromeBorder: Color(hex: "#30E080"), chromeText: Color(hex: "#50FF90"),
        inputBg: Color(hex: "#2A5040"), inputBorder: Color(hex: "#30E080"),
        mutedText: Color(hex: "#40C070"), successDot: Color(hex: "#50FF90"),
        costText: Color(hex: "#40C070"), timestampText: Color(hex: "#40C070"),
        promptChar: "❯", promptColor: Color(hex: "#FF6EB4"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 6,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#30E080")),
            highlight: NSColor(Color(hex: "#50F0A0")),
            shadow: NSColor(Color(hex: "#20B060")),
            eyes: NSColor(Color(hex: "#E8FFF0"))
        )
    )

    static let sorbet = Theme(
        id: "sorbet", name: "Sorbet",
        chatBg: Color(hex: "#E8F5EE"), chatBgGradientEnd: Color(hex: "#F5E8E0"),
        userBubble: Color(hex: "#FF4500"), userBubbleText: .white,
        assistantBubble: Color(hex: "#F0EBF5"), assistantBubbleBorder: Color(hex: "#D0C0E8"), assistantText: Color(hex: "#2A2035"),
        toolCardBg: Color(hex: "#F5F0FA"), toolCardBorder: Color(hex: "#D0C0E8"), toolCardText: Color(hex: "#5A4070"),
        accent: Color(hex: "#FF6030"),
        chromeBar: Color(hex: "#F0EBF5"), chromeBorder: Color(hex: "#D0C0E8"), chromeText: Color(hex: "#6A5090"),
        inputBg: Color(hex: "#F0EBF5"), inputBorder: Color(hex: "#D0C0E8"),
        mutedText: Color(hex: "#9A88B8"), successDot: Color(hex: "#30C070"),
        costText: Color(hex: "#9A88B8"), timestampText: Color(hex: "#9A88B8"),
        promptChar: "❯", promptColor: Color(hex: "#FF4500"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 8,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#D0B8E8")),
            highlight: NSColor(Color(hex: "#E0D0F0")),
            shadow: NSColor(Color(hex: "#B098D0")),
            eyes: NSColor(Color(hex: "#5A3A70"))
        )
    )

    static let aero = Theme(
        id: "aero", name: "Frutiger Aero",
        chatBg: Color(hex: "#3BA8E0"), chatBgGradientEnd: Color(hex: "#5EC45E"),
        userBubble: Color(hex: "#E8F4FD"), userBubbleText: Color(hex: "#1A3A5C"),
        assistantBubble: Color.white.opacity(0.15), assistantBubbleBorder: Color(hex: "#90CAF9"), assistantText: .white,
        toolCardBg: Color.white.opacity(0.15), toolCardBorder: Color.white.opacity(0.3), toolCardText: .white,
        accent: Color(hex: "#1565C0"),
        chromeBar: Color(hex: "#1976D2"), chromeBorder: Color(hex: "#42A5F5"), chromeText: .white,
        inputBg: Color.white.opacity(0.15), inputBorder: Color.white.opacity(0.3),
        mutedText: Color(hex: "#B3D9F2"), successDot: Color(hex: "#66BB6A"),
        costText: Color(hex: "#80DEEA"), timestampText: Color(hex: "#90CAF9"),
        promptChar: ">", promptColor: Color(hex: "#4CAF50"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 14,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#E8F4FC")),
            highlight: NSColor(Color(hex: "#FFFFFF")),
            shadow: NSColor(Color(hex: "#C0DAE8")),
            eyes: NSColor(Color(hex: "#1565C0"))
        )
    )

    static let rgb = Theme(
        id: "rgb", name: "RGB",
        chatBg: Color(hex: "#0A0410"), chatBgGradientEnd: Color(hex: "#400010"),
        userBubble: Color(hex: "#FF1A2E"), userBubbleText: .white,
        assistantBubble: Color(hex: "#1A0A14"), assistantBubbleBorder: Color(hex: "#FF1A2E"), assistantText: Color(hex: "#F0F0F8"),
        toolCardBg: Color(hex: "#14081A"), toolCardBorder: Color(hex: "#FF1A2E"), toolCardText: Color(hex: "#C0C0D0"),
        accent: Color(hex: "#FF1A2E"),
        chromeBar: Color(hex: "#14081A"), chromeBorder: Color(hex: "#80101A"), chromeText: Color(hex: "#C0C0D0"),
        inputBg: Color(hex: "#14081A"), inputBorder: Color(hex: "#FF1A2E"),
        mutedText: Color(hex: "#707080"), successDot: Color(hex: "#1AFF8A"),
        costText: Color(hex: "#707080"), timestampText: Color(hex: "#707080"),
        promptChar: "❯", promptColor: Color(hex: "#FF1A2E"),
        fontMono: "Menlo", fontUI: ".AppleSystemUIFont", borderRadius: 12,
        petPalette: PetPalette(
            body: NSColor(Color(hex: "#FF1A2E")),
            highlight: NSColor(Color(hex: "#FF5A5E")),
            shadow: NSColor(Color(hex: "#C00010")),
            eyes: NSColor(Color(hex: "#1A0A14"))
        )
    )

    static let all: [Theme] = [midnight, aurora, rose, paper, phosphor, deepSea, amber, sakura, violet, neon, melon, sorbet, aero, rgb]

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
            fontMono: mono ?? fontMono, fontUI: ui ?? fontUI, borderRadius: borderRadius,
            petPalette: petPalette
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

// MARK: - RGB Hue Rotation
// Continuously rotates the hue of saturated colors when the RGB theme is active.
// Whites/grays have zero saturation, so text stays readable while accents cycle.
//
// Phase is integrated as ∫ω·dt, so changing `period` adjusts angular velocity
// without snapping the hue — needed for smooth idle↔working speed transitions.

final class RGBHueState: ObservableObject {
    @Published var degrees: Double = 0
    var periodProvider: () -> Double = { 12 }
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            let dt = now - self.lastTick
            self.lastTick = now
            let period = max(0.1, self.periodProvider())
            let speed = 360.0 / period
            self.degrees = (self.degrees + dt * speed).truncatingRemainder(dividingBy: 360)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}

struct RGBHueRotationModifier: ViewModifier {
    @StateObject private var state = RGBHueState()
    let active: Bool
    let periodProvider: () -> Double

    func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(active ? state.degrees : 0))
            .onAppear {
                state.periodProvider = periodProvider
                if active { state.start() }
            }
            .onChange(of: active) { _, isActive in
                if isActive { state.start() } else { state.stop() }
            }
            .onDisappear { state.stop() }
    }
}

extension View {
    func rgbHueRotation(active: Bool, period: @escaping () -> Double = { 12 }) -> some View {
        modifier(RGBHueRotationModifier(active: active, periodProvider: period))
    }
}
