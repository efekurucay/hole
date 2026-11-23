import AppKit
import Foundation

let size = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Unable to create icon canvas") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let plate = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 196, yRadius: 196)
NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.19, blue: 0.23, alpha: 1),
                    NSColor(srgbRed: 0.08, green: 0.37, blue: 0.39, alpha: 1)])!.draw(in: plate, angle: 70)

func ring(_ rect: NSRect, color: NSColor, width: CGFloat) {
    let ellipse = NSBezierPath(ovalIn: rect)
    ellipse.lineWidth = width
    color.setStroke()
    ellipse.stroke()
}

let mint = NSColor(srgbRed: 0.62, green: 0.95, blue: 0.80, alpha: 1)
let peach = NSColor(srgbRed: 1, green: 0.77, blue: 0.46, alpha: 1)
let teal = NSColor(srgbRed: 0.21, green: 0.60, blue: 0.56, alpha: 1)
ring(NSRect(x: 241, y: 284, width: 542, height: 433), color: teal, width: 27)
ring(NSRect(x: 296, y: 342, width: 432, height: 320), color: mint, width: 48)
ring(NSRect(x: 377, y: 416, width: 270, height: 172), color: mint.withAlphaComponent(0.44), width: 27)
peach.setFill()
NSBezierPath(ovalIn: NSRect(x: 715, y: 660, width: 99, height: 99)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Unable to encode icon") }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
