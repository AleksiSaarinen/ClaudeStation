import SwiftUI

/// Applies Liquid Glass effect on macOS 26+, no-op on older versions.
/// Use on small UI chrome elements (tab bars, input bars, buttons) — NOT on large content areas.
struct LiquidGlassChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content
        }
    }
}
