import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: canvas.size)

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let baseRect = NSRect(x: 82, y: 82, width: 860, height: 860)
let base = NSBezierPath(
    roundedRect: baseRect,
    xRadius: 205,
    yRadius: 205
)

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -16)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedRed: 0.04, green: 0.15, blue: 0.19, alpha: 1).setFill()
base.fill()
NSGraphicsContext.restoreGraphicsState()

let backgroundGradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.49, alpha: 1),
    ending: NSColor(calibratedRed: 0.035, green: 0.13, blue: 0.18, alpha: 1)
)
NSGraphicsContext.saveGraphicsState()
base.addClip()
backgroundGradient?.draw(in: base, angle: -90)

let topGlow = NSBezierPath(
    roundedRect: NSRect(x: 120, y: 530, width: 784, height: 390),
    xRadius: 170,
    yRadius: 170
)
NSColor(calibratedWhite: 1, alpha: 0.045).setFill()
topGlow.fill()
NSGraphicsContext.restoreGraphicsState()

let innerBorder = NSBezierPath(
    roundedRect: baseRect.insetBy(dx: 5, dy: 5),
    xRadius: 200,
    yRadius: 200
)
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
innerBorder.lineWidth = 3
innerBorder.stroke()

let screenRect = NSRect(x: 206, y: 236, width: 612, height: 552)
let screen = NSBezierPath(
    roundedRect: screenRect,
    xRadius: 96,
    yRadius: 96
)
NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.095, alpha: 1).setFill()
screen.fill()

let screenBorder = NSBezierPath(
    roundedRect: screenRect.insetBy(dx: 2, dy: 2),
    xRadius: 94,
    yRadius: 94
)
NSColor(calibratedWhite: 1, alpha: 0.075).setStroke()
screenBorder.lineWidth = 3
screenBorder.stroke()

let statusColors = [
    NSColor(calibratedRed: 0.34, green: 0.90, blue: 0.73, alpha: 1),
    NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.58, blue: 0.94, alpha: 1)
]

for (index, color) in statusColors.enumerated() {
    color.setFill()
    NSBezierPath(
        ovalIn: NSRect(x: 272 + CGFloat(index) * 46, y: 704, width: 22, height: 22)
    ).fill()
}

let chevron = NSBezierPath()
chevron.move(to: NSPoint(x: 320, y: 558))
chevron.line(to: NSPoint(x: 448, y: 458))
chevron.line(to: NSPoint(x: 320, y: 358))
chevron.lineWidth = 54
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
NSColor(calibratedRed: 0.34, green: 0.90, blue: 0.73, alpha: 1).setStroke()
chevron.stroke()

let promptLine = NSBezierPath()
promptLine.move(to: NSPoint(x: 506, y: 358))
promptLine.line(to: NSPoint(x: 650, y: 358))
promptLine.lineWidth = 54
promptLine.lineCapStyle = .round
NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
promptLine.stroke()

let badge = NSBezierPath(ovalIn: NSRect(x: 670, y: 302, width: 74, height: 74))
NSColor(calibratedRed: 0.34, green: 0.90, blue: 0.73, alpha: 1).setFill()
badge.fill()

let badgeMark = NSBezierPath()
badgeMark.move(to: NSPoint(x: 695, y: 323))
badgeMark.line(to: NSPoint(x: 718, y: 339))
badgeMark.line(to: NSPoint(x: 695, y: 355))
badgeMark.lineWidth = 7
badgeMark.lineCapStyle = .round
badgeMark.lineJoinStyle = .round
NSColor(calibratedRed: 0.03, green: 0.19, blue: 0.20, alpha: 1).setStroke()
badgeMark.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
