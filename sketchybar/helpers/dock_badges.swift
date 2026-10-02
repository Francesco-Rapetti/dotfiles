// The badges on the icons in the Dock, for notification.sh: the ones the Dock shows, which
// `lsappinfo` doesn't always know. It knows those of NSDockTile, e.g. Slack, but not those that the
// apps of iOS (Catalyst, e.g. WhatsApp) set through their notifications
//   dock_badges   prints <bundle id>\t<name>\t<badge> for each app with a badge, in the order of the
//                 Dock. The Dock says them through the Accessibility API: without its permission it
//                 prints nothing and exits with 2. SketchyBar has the one of AeroSpace, which starts
//                 it
// sketchybarrc compiles it with: swiftc -O dock_badges.swift -o dock_badges

import AppKit
import ApplicationServices

guard AXIsProcessTrusted() else { exit(2) }
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
else { exit(1) }

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
  var value: AnyObject?
  return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

// The Dock has a list of items: the apps, a separator, the folders and the trash. The apps have the
// URL of their bundle, and the badge as their AXStatusLabel
let lists = attribute(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute as String)
for list in lists as? [AXUIElement] ?? [] {
  for item in attribute(list, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] {
    guard let badge = attribute(item, "AXStatusLabel") as? String, !badge.isEmpty,
          let url = attribute(item, kAXURLAttribute as String) as? URL,
          let bundle = Bundle(url: url)?.bundleIdentifier else { continue }
    let name = attribute(item, kAXTitleAttribute as String) as? String ?? bundle
    print("\(bundle)\t\(name)\t\(badge)")
  }
}
