// Screenshots of SketchyBar for the README: only its windows, so that neither the desktop nor the
// windows under a popup end up in them, on a background of their own
//   capture <png> [--popup] <x,y,w,h>...
//                       capture the items in the rects on one display, in the points of
//                       sketchybar --query (bounding_rects), side by side, e.g. the left and the
//                       right items of a wide bar. The display is the main one or, with --popup, the
//                       one where the popup is open, which SketchyBar opens where the mouse is: the
//                       rects on the others are left out, and the first one grows to take in the
//                       popup. In the pixels of the display: 2 per point on a Retina one
// SketchyBar draws each item, bracket and popup row in a window of its own: only those in the rects
// and those of the popup are captured, not the items next to them that a wide popup would take in
// ScreenCaptureKit needs the Screen Recording permission of the app that runs this, e.g. Terminal
// take.sh compiles it with: swiftc -O capture.swift -o capture

import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let margin: CGFloat = 16  // around the captures
let gap: CGFloat = 32     // between them
let radius: CGFloat = 12  // of the corners of the background
// The background, from the top left: Catppuccin Mocha mauve and blue, darkened like a wallpaper
// under the bar, so that the pills stand out as they do on the desktop
let colors = [CGColor(srgbRed: 0x5a / 255, green: 0x4a / 255, blue: 0x7a / 255, alpha: 1),
              CGColor(srgbRed: 0x2c / 255, green: 0x46 / 255, blue: 0x6c / 255, alpha: 1)]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("capture: \(message)\n".data(using: .utf8)!)
  exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("usage: capture <png> [--popup] <x,y,w,h>...") }
let output = URL(fileURLWithPath: arguments.removeFirst())
let popup = arguments.first == "--popup"
if popup { arguments.removeFirst() }
var rects = arguments.map { argument -> CGRect in
  let values = argument.split(separator: ",").compactMap { Double($0) }
  guard values.count == 4 else { fail("not a rect: \(argument)") }
  return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}
guard !rects.isEmpty else { fail("usage: capture <png> [--popup] <x,y,w,h>...") }

// The bar is below the windows, at the level of the desktop windows
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
let windows = content.windows.filter { $0.owningApplication?.applicationName == "sketchybar" }
// The popup is the windows above the bar, its background and its rows; SketchyBar keeps the hidden
// ones off screen
let popupWindows = windows.filter { $0.windowLayer > 0 }
let main = CGDisplayBounds(CGMainDisplayID())
guard let display = content.displays.first(where: { display in
  popup ? popupWindows.contains { display.frame.intersects($0.frame) } : display.frame == main
}) else { fail(popup ? "no popup open" : "no main display") }

rects = rects.filter { display.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) }
guard !rects.isEmpty else { fail("no rect on the display at \(display.frame)") }
let shown = popupWindows.filter { display.frame.intersects($0.frame) }
var included = windows.filter { window in
  window.windowLayer <= 0 && rects.contains { $0.insetBy(dx: -1, dy: -1).contains(window.frame) }
}
if popup {
  included += shown
  for window in shown {
    rects[0] = rects[0].union(window.frame)
  }
}

let filter = SCContentFilter(display: display, including: included)
let scale = CGFloat(filter.pointPixelScale)
var images: [CGImage] = []
for rect in rects {
  let configuration = SCStreamConfiguration()
  configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
  configuration.width = Int(rect.width * scale)
  configuration.height = Int(rect.height * scale)
  configuration.showsCursor = false
  configuration.backgroundColor = .clear
  configuration.pixelFormat = kCVPixelFormatType_32BGRA
  configuration.colorSpaceName = CGColorSpace.sRGB
  images.append(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration))
}

let width = rects.reduce(0) { $0 + $1.width } + gap * CGFloat(rects.count - 1) + 2 * margin
let height = rects.map(\.height).max()! + 2 * margin
guard let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("can't draw \(width)×\(height)") }
context.scaleBy(x: scale, y: scale)
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
// Core Graphics counts from the bottom: the captures are at the top, as the bar on the screen
var x = margin
for (rect, image) in zip(rects, images) {
  context.draw(image, in: CGRect(x: x, y: height - margin - rect.height, width: rect.width, height: rect.height))
  x += rect.width + gap
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail("can't write \(output.path)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("can't write \(output.path)") }
