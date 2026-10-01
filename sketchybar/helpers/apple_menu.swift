// What the Apple menu of SketchyBar needs and macOS has no command line tool for
//   apple_menu recent <dir> <width>  print "<kind>\t<name>\t<target>\t<icon>" of each item of Recent Items:
//                                    <kind> is application, document or server, in this order and each by
//                                    name as in the real menu; <target> is what open opens and <icon> a PNG
//                                    drawn in <dir>, 4 px per point. Names wider than <width> points in the
//                                    font of the rows lose their middle
//   apple_menu clear                 empty Recent Items, like its Clear Menu
//   apple_menu lock                  lock the screen, like Lock Screen
// sketchybarrc compiles it with: swiftc -O apple_menu.swift -o apple_menu

import AppKit
import CoreServices

// Recent Items is in ~/Library/Application Support/com.apple.sharedfilelist, which macOS keeps from
// other apps; the old LSSharedFileList API still reads it through the system
let lists = [("application", kLSSharedFileListRecentApplicationItems.takeUnretainedValue()),
             ("document", kLSSharedFileListRecentDocumentItems.takeUnretainedValue()),
             ("server", kLSSharedFileListRecentServerItems.takeUnretainedValue())]

let font = NSFont(name: "HelveticaNeue-Bold", size: 13)!  // the default label font of the bar
let iconSize = 16

func items(of list: LSSharedFileList) -> [LSSharedFileListItem] {
  var seed: UInt32 = 0
  return LSSharedFileListCopySnapshot(list, &seed)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
}

func width(_ text: String) -> CGFloat {
  (text as NSString).size(withAttributes: [.font: font]).width
}

// Takes characters out of the middle until the name fits, as the menus of macOS do
func truncated(_ name: String, to maxWidth: CGFloat) -> String {
  guard width(name) > maxWidth else { return name }
  var characters = Array(name)
  while characters.count > 1 {
    characters.remove(at: characters.count / 2)
    let half = characters.count / 2
    let candidate = String(characters[..<half]) + "…" + String(characters[half...])
    if width(candidate) <= maxWidth { return candidate }
  }
  return "…"
}

// The icon file is named after the target, so each item keeps its own
func iconFile(for target: String, in directory: URL) -> URL {
  var hash: UInt64 = 0xcbf29ce484222325  // FNV-1a
  for byte in target.utf8 {
    hash = (hash ^ UInt64(byte)) &* 0x100000001b3
  }
  return directory.appendingPathComponent(String(format: "%016llx.png", hash))
}

func writeIcon(_ image: NSImage, to file: URL) {
  let pixels = iconSize * 4
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
  NSGraphicsContext.restoreGraphicsState()
  try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
}

func recent(directory: URL, maxWidth: CGFloat) {
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var icons = Set<String>()
  // Without asking and without mounting anything: an item that can't be found that way is left out
  let flags = UInt32(kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes)
  for (kind, name) in lists {
    guard let list = LSSharedFileListCreate(nil, name, nil)?.takeRetainedValue() else { continue }
    var rows: [(name: String, target: String, icon: String)] = []
    for item in items(of: list) {
      guard let url = LSSharedFileListItemCopyResolvedURL(item, flags, nil)?.takeRetainedValue() as URL? else { continue }
      let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String
      let target = url.isFileURL ? url.path : url.absoluteString
      // A list can have the same item twice, e.g. a volume mounted by two updates of macOS
      guard !rows.contains(where: { $0.target == target }) else { continue }
      let file = iconFile(for: target, in: directory)
      if !icons.contains(file.lastPathComponent) {
        writeIcon(url.isFileURL ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(named: NSImage.networkName)!, to: file)
        icons.insert(file.lastPathComponent)
      }
      rows.append((name, target, file.path))
    }
    for row in rows.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
      let name = truncated(row.name, to: maxWidth).replacingOccurrences(of: "\t", with: " ")
      print("\(kind)\t\(name)\t\(row.target)\t\(row.icon)")
    }
  }
  // The icons of the items that are gone
  for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where !icons.contains(file) {
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
  }
}

func clear() {
  for (_, name) in lists {
    if let list = LSSharedFileListCreate(nil, name, nil)?.takeRetainedValue() {
      LSSharedFileListRemoveAllItems(list)
    }
  }
}

// The function the Apple menu calls, from a private framework
func lock() {
  guard let login = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
        let lockScreen = dlsym(login, "SACLockScreenImmediate") else { exit(1) }
  _ = unsafeBitCast(lockScreen, to: (@convention(c) () -> Int32).self)()
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "recent" where arguments.count == 4:
  recent(directory: URL(fileURLWithPath: arguments[2]), maxWidth: CGFloat(Double(arguments[3]) ?? 280))
case "clear":
  clear()
case "lock":
  lock()
default:
  FileHandle.standardError.write("usage: apple_menu recent <dir> <width> | clear | lock\n".data(using: .utf8)!)
  exit(1)
}
