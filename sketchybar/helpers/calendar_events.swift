// Next calendar event of the day for SketchyBar
//   calendar_events <sketchybar path>   trigger calendar_change with the event to show, and again
//                                       whenever it changes: KIND (upcoming, ongoing, allday, none
//                                       or denied), TIME (HH:mm) and TITLE
// macOS grants calendar access to the app that asks for it, and a process started by sketchybar
// would ask on behalf of AeroSpace: sketchybarrc builds this into calendar_events.app, with
// calendar_events.plist as its Info.plist, and starts it with `open`

import AppKit
import EventKit

if CommandLine.arguments.count != 2 {
  FileHandle.standardError.write("usage: calendar_events <sketchybar path>\n".data(using: .utf8)!)
  exit(1)
}
let sketchybar = CommandLine.arguments[1]

let store = EKEventStore()
let clock = DateFormatter()
clock.dateFormat = "HH:mm"

func title(_ event: EKEvent) -> String {
  let title = (event.title ?? "").components(separatedBy: .newlines).joined(separator: " ")
    .trimmingCharacters(in: .whitespaces)
  if title.isEmpty { return "Senza titolo" }
  return title.count > 30 ? title.prefix(29) + "…" : title
}

func declined(_ event: EKEvent) -> Bool {
  event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
}

func current() -> [String] {
  guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return ["KIND=denied"] }
  let now = Date()
  let today = Calendar.current.dateInterval(of: .day, for: now)!
  let events = store.events(matching: store.predicateForEvents(withStart: today.start, end: today.end, calendars: nil))
    .filter { $0.status != .canceled && !declined($0) }
    .sorted { ($0.startDate, $0.title ?? "") < ($1.startDate, $1.title ?? "") }

  let timed = events.filter { !$0.isAllDay && $0.endDate > now }
  let next = timed.first { $0.startDate > now }
  // The event in progress (the one that ends first), until it ends or the next one starts
  if let ongoing = timed.filter({ $0.startDate <= now }).min(by: { $0.endDate < $1.endDate }),
     next.map({ ongoing.endDate <= $0.startDate }) ?? true {
    return ["KIND=ongoing", "TIME=\(clock.string(from: ongoing.endDate))", "TITLE=\(title(ongoing))"]
  }
  if let next {
    return ["KIND=upcoming", "TIME=\(clock.string(from: next.startDate))", "TITLE=\(title(next))"]
  }
  let allDay = events.filter(\.isAllDay)
  if !allDay.isEmpty {
    return ["KIND=allday", "TITLE=\(allDay.map(title).joined(separator: " · "))"]
  }
  return ["KIND=none"]
}

var sent: [String]?
var timer: Timer?

func update() {
  let payload = current()
  if payload != sent {
    sent = payload
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sketchybar)
    process.arguments = ["--trigger", "calendar_change"] + payload
    try? process.run()
  }
  // Events start and end on the minute: check again at the next one
  timer?.invalidate()
  let minute = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)!
  timer = Timer(fire: minute, interval: 0, repeats: false) { _ in update() }
  RunLoop.main.add(timer!, forMode: .common)
}

NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in update() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in update() }
// Shows the permission prompt the first time, then answers right away
store.requestFullAccessToEvents { _, _ in DispatchQueue.main.async { update() } }
NSApplication.shared.run()
