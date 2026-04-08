import SwiftUI

/// Applies Liquid Glass effect on macOS 26+, no-op on older versions.
struct LiquidGlassChrome: ViewModifier {
    var cornerRadius: CGFloat? = nil

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let r = cornerRadius {
                content.glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: r))
            } else {
                content.glassEffect(.clear.interactive())
            }
        } else {
            content
        }
    }
}
