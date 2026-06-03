// Generates the Snipper app icon (a region-selection mark on a slate squircle)
// as a 1024×1024 PNG. Reproducible source for icon/AppIcon.png — re-run after
// editing to regenerate the art:
//
//   swift icon/make-icon.swift icon/AppIcon.png
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let px = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

let size = CGFloat(px)

// Slate squircle background (flat — no gradient).
let bg = CGRect(x: 0, y: 0, width: size, height: size)
ctx.addPath(CGPath(roundedRect: bg, cornerWidth: size * 0.2237, cornerHeight: size * 0.2237, transform: nil))
ctx.setFillColor(CGColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1))
ctx.fillPath()

// Faintly-filled selection region in the middle.
let sel = CGRect(x: size * 0.28, y: size * 0.28, width: size * 0.44, height: size * 0.44)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.09))
ctx.fill(sel)

// Four white corner brackets — the "select an area" mark.
let arm = size * 0.135
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(size * 0.035)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
func bracket(_ corner: CGPoint, _ dx: CGFloat, _ dy: CGFloat) {
    ctx.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    ctx.addLine(to: corner)
    ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
}
bracket(CGPoint(x: sel.minX, y: sel.minY),  1,  1) // bottom-left
bracket(CGPoint(x: sel.maxX, y: sel.minY), -1,  1) // bottom-right
bracket(CGPoint(x: sel.minX, y: sel.maxY),  1, -1) // top-left
bracket(CGPoint(x: sel.maxX, y: sel.maxY), -1, -1) // top-right
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("no destination") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
