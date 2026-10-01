// Order of the AeroSpace windows for SketchyBar: `aerospace list-windows` sorts them by app name,
// and the order of the tiling tree isn't in its output
//   aerospace list-windows --all --format '%{workspace}|%{window-id}|...' | window_order <file>
//                                print the same lines with the windows of each workspace in the order
//                                they have on screen: by left edge, then top edge (the windows stacked
//                                in a column go from top to bottom). AeroSpace hides the windows of the
//                                workspaces that aren't on screen in a corner of it: those keep the
//                                order that <file> has from the last run, with the new ones last
// sketchybarrc compiles it with: swiftc -O window_order.swift -o window_order

import CoreGraphics
import Foundation

// The window id of AeroSpace is the one of the window server
func frames() -> [CGWindowID: CGRect] {
  let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
  var frames: [CGWindowID: CGRect] = [:]
  for window in info {
    guard let id = window[kCGWindowNumber as String] as? CGWindowID,
          let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
    frames[id] = frame
  }
  return frames
}

// Connecting to the window server takes most of the time: the first call does it while AeroSpace
// is still answering
var frame = frames()

struct Window {
  let line: String
  let workspace: String
  let id: CGWindowID
}

let file = CommandLine.arguments[1]

var windows: [Window] = []
while let line = readLine() {
  let fields = line.split(separator: "|", omittingEmptySubsequences: false)
  guard fields.count >= 2 else { continue }
  windows.append(Window(line: line, workspace: String(fields[0]), id: CGWindowID(fields[1]) ?? 0))
}
let ids = windows.map(\.id)

// AeroSpace moves the windows after it has answered: wait until they stay where they are
for _ in 0..<20 {
  usleep(20_000)
  let next = frames()
  let moved = ids.contains { next[$0] != frame[$0] }
  frame = next
  if !moved { break }
}

var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var displayIds = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &displayIds, &count)
let displays = displayIds.map(CGDisplayBounds)

// A hidden window has 1pt left on screen
func isOnScreen(_ window: Window) -> Bool {
  guard let frame = frame[window.id] else { return false }
  return displays.contains {
    let part = $0.intersection(frame)
    return part.width >= 10 && part.height >= 10
  }
}

var rank: [CGWindowID: Int] = [:]
let saved = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
for (i, id) in saved.split(separator: "\n").compactMap({ CGWindowID($0) }).enumerated() where rank[id] == nil {
  rank[id] = i
}

var workspaces: [String] = []
var members: [String: [Window]] = [:]
for window in windows {
  if members[window.workspace] == nil { workspaces.append(window.workspace) }
  members[window.workspace, default: []].append(window)
}

var ordered: [Window] = []
for workspace in workspaces {
  let group = members[workspace]!
  // A workspace coming on screen or going away has some windows still in the corner: then it keeps
  // the saved order too. Right and bottom edges only break ties: the windows of an accordion start
  // at the same edge, except the first one
  let onScreen = group.allSatisfy(isOnScreen)
  let keys = group.enumerated().map { i, window in
    let f = onScreen ? frame[window.id]! : .zero
    return (window, (f.minX, f.minY, f.maxX, f.maxY, rank[window.id] ?? Int.max, i))
  }
  ordered += keys.sorted { $0.1 < $1.1 }.map(\.0)
}

for window in ordered {
  print(window.line)
}
try? ordered.map { String($0.id) }.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
