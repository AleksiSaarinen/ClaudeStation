import SwiftUI

/// Applies Liquid Glass effect on macOS 26+, no-op on older versions.
/// Use on small UI chrome elements (tab bars, input bars, buttons) — NOT on large content areas.
struct LiquidGlassChrome: ViewModifier {
    var cornerRadius: CGFloat? = nil

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let r = cornerRadius {
                content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: r))
            } else {
                content.glassEffect(.regular.interactive())
            }
        } else {
            content
        }
    }
}
