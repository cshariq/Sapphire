#if !SAPPHIRE_FULL_BUILD
import AppKit

extension NSImage {
    func jpegData(maxPixel: CGFloat, quality: CGFloat) -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let longestEdge = CGFloat(max(cgImage.width, cgImage.height))
        let scale = min(1, maxPixel / longestEdge)
        let width = Int(CGFloat(cgImage.width) * scale)
        let height = Int(CGFloat(cgImage.height) * scale)

        let scaled = NSImage(size: NSSize(width: width, height: height))
        scaled.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        scaled.unlockFocus()

        guard let scaledCG = scaled.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaledCG)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
#endif
