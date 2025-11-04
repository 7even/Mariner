#!/usr/bin/env swift

import AppKit
import Foundation

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Background - nautical blue with slight gradient
    let context = NSGraphicsContext.current!.cgContext

    // Draw rounded rectangle background with proper macOS icon proportions
    // macOS icons need about 10% margin on each side
    let margin = CGFloat(size) * 0.1
    let rect = CGRect(x: margin, y: margin, width: CGFloat(size) - margin * 2, height: CGFloat(size) - margin * 2)
    let cornerRadius = CGFloat(size) * 0.18 // Adjusted for smaller visible area
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background - dark navy to slightly lighter blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1.0),
        CGColor(red: 0.15, green: 0.3, blue: 0.5, alpha: 1.0)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

    context.saveGState()
    path.addClip()
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: CGFloat(size)),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
    context.restoreGState()

    // Draw ship's wheel with handles
    let centerX = CGFloat(size) / 2
    let centerY = CGFloat(size) / 2

    // Icon should occupy about 50-60% of the canvas for proper macOS appearance
    let wheelRadius = CGFloat(size) * 0.32  // Main wheel radius

    NSColor.white.setStroke()
    NSColor.white.setFill()

    // Inner rim only
    let rimWidth = CGFloat(size) * 0.04
    let innerRim = NSBezierPath()
    innerRim.appendArc(withCenter: CGPoint(x: centerX, y: centerY),
                       radius: wheelRadius * 0.65,
                       startAngle: 0,
                       endAngle: 360)
    innerRim.lineWidth = rimWidth
    innerRim.stroke()

    // Center hub
    let hubRadius = wheelRadius * 0.12
    let hub = NSBezierPath()
    hub.appendArc(withCenter: CGPoint(x: centerX, y: centerY),
                  radius: hubRadius,
                  startAngle: 0,
                  endAngle: 360)
    hub.fill()

    // 8 spokes with handles
    let spokeWidth = rimWidth * 0.7
    let handleLength = wheelRadius * 0.18
    let handleWidth = rimWidth * 1.2

    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4

        // Spoke from hub to rim
        let spokePath = NSBezierPath()
        let innerX = centerX + cos(angle) * hubRadius
        let innerY = centerY + sin(angle) * hubRadius
        let rimX = centerX + cos(angle) * (wheelRadius * 0.65)
        let rimY = centerY + sin(angle) * (wheelRadius * 0.65)

        spokePath.move(to: CGPoint(x: innerX, y: innerY))
        spokePath.line(to: CGPoint(x: rimX, y: rimY))
        spokePath.lineWidth = spokeWidth
        spokePath.lineCapStyle = .round
        spokePath.stroke()

        // Handle extending outward from rim
        let handleStart = wheelRadius * 0.68
        let handleEnd = wheelRadius * 0.92

        let handlePath = NSBezierPath()
        let handleStartX = centerX + cos(angle) * handleStart
        let handleStartY = centerY + sin(angle) * handleStart
        let handleEndX = centerX + cos(angle) * handleEnd
        let handleEndY = centerY + sin(angle) * handleEnd

        handlePath.move(to: CGPoint(x: handleStartX, y: handleStartY))
        handlePath.line(to: CGPoint(x: handleEndX, y: handleEndY))
        handlePath.lineWidth = handleWidth
        handlePath.lineCapStyle = .round
        handlePath.stroke()
    }

    image.unlockFocus()

    return image
}

func saveIconSet() {
    let sizes = [16, 32, 128, 256, 512, 1024]
    let iconsetPath = "Mariner.iconset"

    // Create iconset directory
    try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for size in sizes {
        let image = createIcon(size: size)

        // Save standard resolution
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            let filename = "\(iconsetPath)/icon_\(size)x\(size).png"
            try? pngData.write(to: URL(fileURLWithPath: filename))
            print("Generated: \(filename)")
        }

        // Save @2x resolution for applicable sizes
        if size <= 512 {
            let image2x = createIcon(size: size * 2)
            if let tiffData = image2x.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                let filename = "\(iconsetPath)/icon_\(size)x\(size)@2x.png"
                try? pngData.write(to: URL(fileURLWithPath: filename))
                print("Generated: \(filename)")
            }
        }
    }

    print("\nIconset created at: \(iconsetPath)")
    print("Now run: iconutil -c icns Mariner.iconset")
}

saveIconSet()
