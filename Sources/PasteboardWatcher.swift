import AppKit
import SwiftUI

/// Monitors the system pasteboard for new images (screenshots) and surfaces them for attachment.
class PasteboardWatcher: ObservableObject {
    @Published var pendingImage: NSImage?
    @Published var pendingImagePath: String?

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startWatching() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        let oldCount = lastChangeCount
        lastChangeCount = pb.changeCount

        // Only trigger if pasteboard has image data (not just text)
        guard pb.types?.contains(.png) == true
           || pb.types?.contains(.tiff) == true
           || pb.types?.contains(NSPasteboard.PasteboardType("public.image")) == true
        else { return }

        // Don't trigger if we just cleared our own image
        guard oldCount != lastChangeCount else { return }

        guard let image = NSImage(pasteboard: pb), image.size.width > 10 else { return }

        // Save to temp file
        let filename = "claudestation_\(Int(Date().timeIntervalSince1970)).png"
        let path = NSTemporaryDirectory() + filename

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.85]) {
            try? pngData.write(to: URL(fileURLWithPath: path))
            DispatchQueue.main.async {
                self.pendingImage = image
                self.pendingImagePath = path
            }
        }
    }

    func clear() {
        pendingImage = nil
        if let path = pendingImagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        pendingImagePath = nil
    }
}
