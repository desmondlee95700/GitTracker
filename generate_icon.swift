import AppKit

let iconSize = NSSize(width: 1024, height: 1024)
let icon = NSImage(size: iconSize, flipped: false) { rect in
    let path = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
    NSColor.systemBlue.set()
    path.fill()
    
    if #available(macOS 11.0, *), let glyph = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
        let glyphConfig = NSImage.SymbolConfiguration(pointSize: 512, weight: .black)
        let whiteGlyph = glyph.withSymbolConfiguration(glyphConfig)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let glyphRect = NSRect(x: 256, y: 256, width: 512, height: 512)
        whiteGlyph?.draw(in: glyphRect)
    }
    return true
}

if let tiff = icon.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
    let png = bitmap.representation(using: .png, properties: [:])
    try? png?.write(to: URL(fileURLWithPath: "AppIcon.png"))
}
