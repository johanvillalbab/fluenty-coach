// Render AppIcon.svg into a macOS .icns iconset and a menu-bar PDF template.
// Usage: swift make-icon.swift
import AppKit

let projectRoot = FileManager.default.currentDirectoryPath
let svgURL = URL(fileURLWithPath: "\(projectRoot)/FluentyCoach/Resources/AppIcon.svg")
let iconsetDir = URL(fileURLWithPath: "\(projectRoot)/build/AppIcon.iconset")
let icnsOutput = URL(fileURLWithPath: "\(projectRoot)/FluentyCoach/Resources/AppIcon.icns")
let menuBarOutput = URL(fileURLWithPath: "\(projectRoot)/FluentyCoach/Resources/MenuBarIcon.pdf")

// Load SVG as NSImage (macOS 13+ supports SVG natively)
guard let svgImage = NSImage(contentsOf: svgURL) else {
    print("ERROR: cannot load \(svgURL.path)")
    exit(1)
}

func render(_ image: NSImage, size: CGFloat, padding: CGFloat = 0) -> Data? {
    let pixelSize = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let drawSize = size - (padding * 2)
    image.draw(
        in: NSRect(x: padding, y: padding, width: drawSize, height: drawSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// Build .iconset directory
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// macOS iconset format: padded icon so it fits the rounded-rect mask
let iconSpecs: [(size: CGFloat, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for spec in iconSpecs {
    let paddingRatio: CGFloat = 0.12   // ~12% inset so glyph isn't edge-to-edge
    let padding = (spec.size * paddingRatio).rounded()
    guard let data = render(svgImage, size: spec.size, padding: padding) else {
        print("Failed to render \(spec.name)"); exit(1)
    }
    try data.write(to: iconsetDir.appendingPathComponent(spec.name))
}

// Run iconutil to build .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", icnsOutput.path, iconsetDir.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    print("iconutil failed with status \(task.terminationStatus)"); exit(1)
}

// Build menu-bar PDF template (vector — scales for retina and tints automatically)
let menuSize = NSSize(width: 18, height: 18)
let pdfData = NSMutableData()
var box = NSRect(origin: .zero, size: menuSize)
guard let consumer = CGDataConsumer(data: pdfData),
      let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
    print("PDF context failed"); exit(1)
}
ctx.beginPDFPage(nil)
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
svgImage.draw(
    in: NSRect(x: 1, y: 1, width: menuSize.width - 2, height: menuSize.height - 2),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()
ctx.endPDFPage()
ctx.closePDF()
try pdfData.write(to: menuBarOutput, options: .atomic)

print("==> \(icnsOutput.path)")
print("==> \(menuBarOutput.path)")
