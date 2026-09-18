import AppKit

// Draws the app icon: a dark rounded square with the notch silhouette
// hanging from the top edge and a terracotta status dot beside it.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22).fill()

    // Notch silhouette, hanging from the top of the inner rect.
    let notchW = rect.width * 0.52
    let notchH = rect.height * 0.20
    let notch = NSRect(x: rect.midX - notchW / 2,
                       y: rect.maxY - notchH,
                       width: notchW, height: notchH)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: notch.minX, y: notch.maxY))
    path.line(to: NSPoint(x: notch.minX, y: notch.minY + notchH * 0.45))
    path.curve(to: NSPoint(x: notch.minX + notchH * 0.45, y: notch.minY),
               controlPoint1: NSPoint(x: notch.minX, y: notch.minY),
               controlPoint2: NSPoint(x: notch.minX, y: notch.minY))
    path.line(to: NSPoint(x: notch.maxX - notchH * 0.45, y: notch.minY))
    path.curve(to: NSPoint(x: notch.maxX, y: notch.minY + notchH * 0.45),
               controlPoint1: NSPoint(x: notch.maxX, y: notch.minY),
               controlPoint2: NSPoint(x: notch.maxX, y: notch.minY))
    path.line(to: NSPoint(x: notch.maxX, y: notch.maxY))
    path.close()
    NSColor.black.setFill()
    path.fill()

    // Status bar under the notch.
    let bar = NSRect(x: notch.minX + notchW * 0.1,
                     y: notch.minY - s * 0.075,
                     width: notchW * 0.8, height: s * 0.042)
    NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1).setFill()
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()

    image.unlockFocus()
    return image
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(px).png"))
}
print("icons written to \(outDir)")
