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
        // Clean up orphaned temp files older than 5 minutes
        let tmp = NSTemporaryDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tmp) {
            for file in files where file.hasPrefix("claudestation_drop_") || (file.hasPrefix("claudestation_") && file.hasSuffix(".png")) {
                let path = tmp + file
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let modified = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(modified) > 300 {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }

    func startWatching() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
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
        lastChangeCount = pb.changeCount

        // Check for image data directly
        let hasImage = pb.types?.contains(.png) == true
            || pb.types?.contains(.tiff) == true
            || pb.types?.contains(NSPasteboard.PasteboardType("public.image")) == true

        // Check for file URLs that are images (macOS screenshots)
        let hasImageFile: Bool = {
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: ["public.image"]
            ]) as? [URL], !urls.isEmpty else { return false }
            return true
        }()

        guard hasImage || hasImageFile else { return }

        // Try loading image from pasteboard data or file URL
        var image: NSImage?
        if hasImage {
            image = NSImage(pasteboard: pb)
        }
        if image == nil, let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["public.image"]
        ]) as? [URL], let url = urls.first {
            image = NSImage(contentsOf: url)
        }

        guard let image, image.size.width > 10 else { return }

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
