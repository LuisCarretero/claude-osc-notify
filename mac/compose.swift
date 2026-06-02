import AppKit

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write("usage: compose <topLeft.png> <bottomRight.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let topLeftPath = CommandLine.arguments[1]
let bottomRightPath = CommandLine.arguments[2]
let outPath = CommandLine.arguments[3]

guard let topLeft = NSImage(byReferencingFile: topLeftPath), topLeft.isValid else {
    FileHandle.standardError.write("cant read \(topLeftPath)\n".data(using: .utf8)!); exit(1)
}
guard let bottomRight = NSImage(byReferencingFile: bottomRightPath), bottomRight.isValid else {
    FileHandle.standardError.write("cant read \(bottomRightPath)\n".data(using: .utf8)!); exit(1)
}

let size: CGFloat = 512
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// transparent background
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

// Upper-left triangle (y >= x): topLeft image
NSGraphicsContext.current?.saveGraphicsState()
let p1 = NSBezierPath()
p1.move(to: NSPoint(x: 0, y: 0))
p1.line(to: NSPoint(x: size, y: size))
p1.line(to: NSPoint(x: 0, y: size))
p1.close()
p1.addClip()
let inset: CGFloat = size * 0.092  // match macOS app-icon safe-area
topLeft.draw(in: NSRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset),
             from: .zero, operation: .sourceOver, fraction: 1.0,
             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.current?.restoreGraphicsState()

// Lower-right triangle (y <= x): bottomRight image
NSGraphicsContext.current?.saveGraphicsState()
let p2 = NSBezierPath()
p2.move(to: NSPoint(x: 0, y: 0))
p2.line(to: NSPoint(x: size, y: 0))
p2.line(to: NSPoint(x: size, y: size))
p2.close()
p2.addClip()
bottomRight.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                 from: .zero, operation: .sourceOver, fraction: 1.0,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.current?.restoreGraphicsState()

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode png\n".data(using: .utf8)!); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
