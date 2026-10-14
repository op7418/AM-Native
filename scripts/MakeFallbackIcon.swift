import AppKit
import Foundation

// Source-build fallback. Release builds can supply Resources/AppIcon-v1.png.
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
NSColor(white: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 295, y: 180, width: 434, height: 664), xRadius: 205, yRadius: 205).fill()
NSColor(white: 0.65, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 488, y: 620, width: 48, height: 125), xRadius: 24, yRadius: 24).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
