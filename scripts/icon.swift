import AppKit
import Foundation

let destination = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(white: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 492, height: 492), xRadius: 100, yRadius: 100).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(x: 181, y: 175, width: 150, height: 255), xRadius: 75, yRadius: 75).fill()
        NSColor.darkGray.setStroke()
        let stand = NSBezierPath(); stand.lineWidth = 24
        stand.move(to: NSPoint(x: 135, y: 280)); stand.line(to: NSPoint(x: 135, y: 225))
        stand.curve(to: NSPoint(x: 377, y: 225), controlPoint1: NSPoint(x: 135, y: 70), controlPoint2: NSPoint(x: 377, y: 70))
        stand.line(to: NSPoint(x: 377, y: 280))
        stand.move(to: NSPoint(x: 256, y: 111)); stand.line(to: NSPoint(x: 256, y: 65))
        stand.move(to: NSPoint(x: 196, y: 65)); stand.line(to: NSPoint(x: 316, y: 65)); stand.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
