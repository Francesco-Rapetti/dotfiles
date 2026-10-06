// What the Apple menu of SketchyBar needs and macOS has no command line tool for
//   apple_menu lock   lock the screen, like Lock Screen
// sketchybarrc compiles it with: swiftc -O apple_menu.swift -o apple_menu

import Foundation

// The function the Apple menu calls, from a private framework
func lock() {
  guard let login = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
        let lockScreen = dlsym(login, "SACLockScreenImmediate") else { exit(1) }
  _ = unsafeBitCast(lockScreen, to: (@convention(c) () -> Int32).self)()
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "lock":
  lock()
default:
  FileHandle.standardError.write("usage: apple_menu lock\n".data(using: .utf8)!)
  exit(1)
}
