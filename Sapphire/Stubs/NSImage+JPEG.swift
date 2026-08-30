#if !SAPPHIRE_FULL_BUILD
import AppKit

extension NSImage {
    /// Compresses the image to JPEG data, optionally downscaling the longest edge.
    func jpegData(maxPixel: CGFloat, quality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let width = CGFloat(rep.pixelsWide)
        let height = CGFloat(rep.pixelsHigh)
        let longest = max(width, height)
        let scale = longest > maxPixel && longest > 0 ? maxPixel / longest : 1

        let targetSize = NSSize(width: max(1, width * scale), height: max(1, height * scale))
        let scaled = NSImage(size: targetSize)
        scaled.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        scaled.unlockFocus()

        guard let scaledTiff = scaled.tiffRepresentation,
              let scaledRep = NSBitmapImageRep(data: scaledTiff) else {
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
        return scaledRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
#endif
