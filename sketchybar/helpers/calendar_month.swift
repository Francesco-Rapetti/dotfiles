// Mini calendar of the current month for the popup of the clock in SketchyBar
//   calendar_month <png path> <text color> <weekend color> <today color> <today text color>
// Colors are 0xAARRGGBB, as in sketchybarrc. The name of the month, the initials of the weekdays and
// the first day of the week follow the language and the region of the Mac.
// SketchyBar popups stack their items in a single row or column, so a grid with the current day
// highlighted can't be built out of items: the popup shows this image. It is drawn with the pixels
// of the display under the mouse, where the popup opens (2 per point on Retina displays), and the
// helper prints the background.image.scale that shows it at its size in points

import AppKit

func color(_ hex: String) -> NSColor? {
  guard hex.hasPrefix("0x"), hex.count == 10, let argb = UInt32(hex.dropFirst(2), radix: 16) else { return nil }
  func channel(_ shift: UInt32) -> CGFloat { CGFloat((argb >> shift) & 0xff) / 255 }
  return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: channel(24))
}

let arguments = CommandLine.arguments
let colors = arguments.dropFirst(2).compactMap(color)
guard arguments.count == 6, colors.count == 4 else {
  FileHandle.standardError.write("usage: calendar_month <png path> <text color> <weekend color> <today color> <today text color>\n".data(using: .utf8)!)
  exit(1)
}
let (textColor, weekendColor, todayColor, todayTextColor) = (colors[0], colors[1], colors[2], colors[3])

// Helvetica Neue Bold, like the labels of the bar
let titleFont = NSFont(name: "HelveticaNeue-Bold", size: 13)!
let weekdayFont = NSFont(name: "HelveticaNeue-Bold", size: 10)!
let dayFont = NSFont(name: "HelveticaNeue-Bold", size: 12)!

// Layout in points
let margin: CGFloat = 12
let cell = NSSize(width: 28, height: 24)
let titleHeight: CGFloat = 26
let weekdaysHeight: CGFloat = 20
let todaySize = NSSize(width: 24, height: 22)
let todayRadius: CGFloat = 6  // like the focused workspace

// Calendar.current also has the first day of the week chosen in System Settings
let calendar = Calendar.current
let now = Date()
let month = calendar.dateInterval(of: .month, for: now)!
let days = calendar.range(of: .day, in: .month, for: now)!.count
let today = calendar.component(.day, from: now)
// Columns before the 1st: weekday 1 is Sunday
let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
let rows = (offset + days + 6) / 7

let formatter = DateFormatter()
formatter.setLocalizedDateFormatFromTemplate("LLLLy")
// e.g. "settembre 2026": the month is lowercase in some languages, but it is the title here
let name = formatter.string(from: now)
let title = name.prefix(1).uppercased(with: formatter.locale) + name.dropFirst()
// Starting from Sunday, e.g. D L M M G V S
let initials = formatter.veryShortStandaloneWeekdaySymbols!

// The date in each column of the first row, which can be in the previous month, gives the weekday
// and whether it is a weekend day in this region
let columns = (0..<7).map { calendar.date(byAdding: .day, value: $0 - offset, to: month.start)! }
let weekend = columns.map(calendar.isDateInWeekend)

let size = NSSize(width: 2 * margin + 7 * cell.width,
                  height: 2 * margin + titleHeight + weekdaysHeight + CGFloat(rows) * cell.height)
let scale = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.backingScaleFactor ?? 2
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                              pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
// y grows downwards, from the title to the last week
let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

// On whole pixels, like the text SketchyBar draws: in between, the edges of the glyphs get blurred
func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

// Centers the text in the rect by the height of its capitals, which is where digits and initials
// have their ink, instead of by the line with the room for accents and descenders
func draw(_ text: String, _ font: NSFont, _ color: NSColor, centeredIn rect: NSRect) {
  let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
  let width = (text as NSString).size(withAttributes: attributes).width
  let baseline = pixel(rect.midY + font.capHeight / 2)
  (text as NSString).draw(at: NSPoint(x: pixel(rect.midX - width / 2), y: baseline - font.ascender), withAttributes: attributes)
}

func column(_ index: Int) -> CGFloat { margin + CGFloat(index) * cell.width }

draw(title, titleFont, textColor,
     centeredIn: NSRect(x: margin, y: margin, width: 7 * cell.width, height: titleHeight))

for index in 0..<7 {
  let weekday = calendar.component(.weekday, from: columns[index])
  draw(initials[weekday - 1], weekdayFont, weekend[index] ? weekendColor : textColor,
       centeredIn: NSRect(x: column(index), y: margin + titleHeight, width: cell.width, height: weekdaysHeight))
}

for day in 1...days {
  let index = (offset + day - 1) % 7
  let rect = NSRect(x: column(index), y: margin + titleHeight + weekdaysHeight + CGFloat((offset + day - 1) / 7) * cell.height,
                    width: cell.width, height: cell.height)
  var color = weekend[index] ? weekendColor : textColor
  if day == today {
    todayColor.setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: (cell.width - todaySize.width) / 2, dy: (cell.height - todaySize.height) / 2),
                 xRadius: todayRadius, yRadius: todayRadius).fill()
    color = todayTextColor
  }
  draw(String(day), dayFont, color, centeredIn: rect)
}

NSGraphicsContext.current?.flushGraphics()
do {
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[1]))
} catch {
  FileHandle.standardError.write("calendar_month: \(error.localizedDescription)\n".data(using: .utf8)!)
  exit(1)
}
print(1 / scale)
