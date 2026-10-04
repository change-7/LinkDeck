import AppKit
import Foundation

enum SmartphoneIconData {
    private static let maximumPixelDimension = 256
    private static let maximumSourceDataLength = 20 * 1024 * 1024
    private static let maximumDataLength = 512 * 1024

    static func normalizedPNGData(from data: Data) -> Data? {
        guard data.count <= maximumSourceDataLength,
              let image = NSImage(data: data),
              let sourceRepresentation = image.representations.first else {
            return nil
        }

        let sourceSize = sourceRepresentation.size
        let sourceWidth = max(sourceRepresentation.pixelsWide, Int(sourceSize.width.rounded()))
        let sourceHeight = max(sourceRepresentation.pixelsHigh, Int(sourceSize.height.rounded()))
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let scale = min(
            1,
            CGFloat(maximumPixelDimension) / CGFloat(max(sourceWidth, sourceHeight))
        )
        let width = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let height = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]),
              pngData.count <= maximumDataLength else {
            return nil
        }
        return pngData
    }

    static func dataFromPasteboard() -> Data? {
        let pasteboard = NSPasteboard.general
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString),
           let fileData = try? Data(contentsOf: fileURL) {
            return fileData
        }

        return nil
    }
}
