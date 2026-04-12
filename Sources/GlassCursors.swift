import AppKit
import SwiftUI

/// Cursor pack definitions and hotspot configs
struct CursorPack: Identifiable, Equatable {
    let id: String
    let name: String
    let size: CGFloat
    let arrowHotspot: NSPoint
    let pointerHotspot: NSPoint
    let textHotspot: NSPoint

    static let system = CursorPack(
        id: "system", name: "System",
        size: 32, arrowHotspot: .zero, pointerHotspot: .zero, textHotspot: .zero
    )
    static let mickey = CursorPack(
        id: "Mickey", name: "Mickey Glove",
        size: 32, arrowHotspot: NSPoint(x: 5, y: 2), pointerHotspot: NSPoint(x: 16, y: 16), textHotspot: NSPoint(x: 5, y: 2)
    )
    static let bibataClassic = CursorPack(
        id: "Bibata-Classic", name: "Bibata Classic",
        size: 32, arrowHotspot: NSPoint(x: 7, y: 2), pointerHotspot: NSPoint(x: 14, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )
    static let bibataIce = CursorPack(
        id: "Bibata-Ice", name: "Bibata Ice",
        size: 32, arrowHotspot: NSPoint(x: 7, y: 2), pointerHotspot: NSPoint(x: 14, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )
    static let bibataAmber = CursorPack(
        id: "Bibata-Amber", name: "Bibata Amber",
        size: 32, arrowHotspot: NSPoint(x: 7, y: 2), pointerHotspot: NSPoint(x: 14, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )
    static let kenney = CursorPack(
        id: "Kenney", name: "Kenney Pixel",
        size: 32, arrowHotspot: NSPoint(x: 2, y: 2), pointerHotspot: NSPoint(x: 10, y: 4), textHotspot: NSPoint(x: 8, y: 2)
    )
    static let win11Light = CursorPack(
        id: "Win11-Light", name: "Win11 Light",
        size: 32, arrowHotspot: NSPoint(x: 4, y: 2), pointerHotspot: NSPoint(x: 10, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )
    static let win11Dark = CursorPack(
        id: "Win11-Dark", name: "Win11 Dark",
        size: 32, arrowHotspot: NSPoint(x: 4, y: 2), pointerHotspot: NSPoint(x: 10, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )

    static let wii = CursorPack(
        id: "Wii", name: "Wii",
        size: 32, arrowHotspot: NSPoint(x: 10, y: 2), pointerHotspot: NSPoint(x: 10, y: 2), textHotspot: NSPoint(x: 10, y: 2)
    )

    static let blueGlass = CursorPack(
        id: "BlueGlass", name: "Blue Glass",
        size: 32, arrowHotspot: NSPoint(x: 4, y: 2), pointerHotspot: NSPoint(x: 8, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )

    static let aeroNoTail = CursorPack(
        id: "Aero-NoTail", name: "Aero No Tail",
        size: 32, arrowHotspot: NSPoint(x: 4, y: 2), pointerHotspot: NSPoint(x: 8, y: 2), textHotspot: NSPoint(x: 16, y: 16)
    )

    static let all: [CursorPack] = [system, mickey, wii, blueGlass, aeroNoTail, bibataClassic, bibataIce, bibataAmber, kenney, win11Light, win11Dark]
}

/// Custom cursor management
enum CursorManager {

    private static var currentPackId: String = "system"
    private static var isSwizzled = false

    // Cached cursors for the active pack
    private static var customArrow: NSCursor?
    private static var customPointer: NSCursor?
    private static var customIBeam: NSCursor?

    // Original cursors (saved before first swizzle)
    private static var originalArrow: NSCursor?
    private static var originalPointer: NSCursor?
    private static var originalIBeam: NSCursor?

    private static func loadCursor(pack: CursorPack, name: String, hotSpot: NSPoint) -> NSCursor? {
        let resourcePath = Bundle.main.resourcePath ?? ""
        let path = "\(resourcePath)/Cursors/\(pack.id)/\(name).png"
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        image.size = NSSize(width: pack.size, height: pack.size)
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    static func applyPack(_ packId: String) {
        currentPackId = packId

        guard let pack = CursorPack.all.first(where: { $0.id == packId }), packId != "system" else {
            // Restore system cursors
            customArrow = nil
            customPointer = nil
            customIBeam = nil
            if isSwizzled { swizzle() ; isSwizzled = false }
            return
        }

        customArrow = loadCursor(pack: pack, name: "arrow", hotSpot: pack.arrowHotspot)
        customPointer = loadCursor(pack: pack, name: "pointer", hotSpot: pack.pointerHotspot)
        customIBeam = loadCursor(pack: pack, name: "text", hotSpot: pack.textHotspot)

        if !isSwizzled { swizzle(); isSwizzled = true }

        // Force cursor update
        NSCursor.arrow.set()
    }

    private static func swizzle() {
        let pairs: [(Selector, Selector)] = [
            (#selector(getter: NSCursor.arrow), #selector(getter: CursorOverrides.overrideArrow)),
            (#selector(getter: NSCursor.pointingHand), #selector(getter: CursorOverrides.overridePointer)),
            (#selector(getter: NSCursor.iBeam), #selector(getter: CursorOverrides.overrideIBeam)),
        ]
        for (orig, repl) in pairs {
            if let m1 = class_getClassMethod(NSCursor.self, orig),
               let m2 = class_getClassMethod(CursorOverrides.self, repl) {
                method_exchangeImplementations(m1, m2)
            }
        }
    }

    // Accessors for the override class
    static var arrow: NSCursor { customArrow ?? NSCursor.arrow }
    static var pointer: NSCursor { customPointer ?? NSCursor.pointingHand }
    static var iBeam: NSCursor { customIBeam ?? NSCursor.iBeam }
}

class CursorOverrides: NSObject {
    @objc class var overrideArrow: NSCursor { CursorManager.arrow }
    @objc class var overridePointer: NSCursor { CursorManager.pointer }
    @objc class var overrideIBeam: NSCursor { CursorManager.iBeam }
}
