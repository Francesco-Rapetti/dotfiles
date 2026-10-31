// The displays of macOS changing, for notch.sh, seen from outside SketchyBar
//   display_changes watch   trigger macos_display_change whenever macOS adds, removes, moves or
//                           resizes a display, a second after the last change of a burst, since
//                           each display reports its own
// SketchyBar has display_change, but it may miss a change: a monitor that went off and came back
// 6 seconds later reached every app but SketchyBar, which kept a single bar as wide as the other
// monitor at the top left of it, and no bar on the other one. Without the change SketchyBar has
// nothing to tell notch.sh, which would restart it. This helper is another process, which gets them
// sketchybarrc compiles it with: swiftc -O display_changes.swift -o display_changes

import CoreGraphics
import Foundation

let settle = 1.0

// The trigger waiting for the burst to end. Global, since the callback of CoreGraphics is a C
// function and can't capture it
var pending: DispatchWorkItem?

func trigger() {
  let sketchybar = Process()
  sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  sketchybar.arguments = ["sketchybar", "--trigger", "macos_display_change"]
  try? sketchybar.run()
}

func watch() -> Never {
  // Called on the main run loop twice for each display: before the change, with
  // beginConfigurationFlag, and after it
  CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
    guard !flags.contains(.beginConfigurationFlag) else { return }
    pending?.cancel()
    let work = DispatchWorkItem { trigger() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
  }, nil)
  CFRunLoopRun()
  exit(0)
}

if CommandLine.arguments.dropFirst() == ["watch"] {
  watch()
}
FileHandle.standardError.write("usage: display_changes watch\n".data(using: .utf8)!)
exit(1)
