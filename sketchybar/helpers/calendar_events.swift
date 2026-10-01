// Next calendar event of the day for SketchyBar
//   calendar_events <sketchybar path>   trigger calendar_change with the event to show, and again
//                                       whenever it changes: KIND (upcoming, ongoing, allday, none
//                                       or denied) and LABEL, the text for the bar, with EVENTS,
//                                       all the events of the day for the popup of calendar.sh, when
//                                       they change: the countdown of LABEL changes every minute
// The texts are in the language of the Mac, with the times in the format of its region
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

// The texts in each language, in English when the Mac has none of these among its languages.
// until takes the title, the time the event ends and the time left until then, countdown the time
// left until it starts
let texts = [
  "en": (untitled: "Untitled", until: "%@ · until %@ (%@ left)", countdown: "in %@", allDay: "All day",
         denied: "No access to calendars"),
  "it": (untitled: "Senza titolo", until: "%@ · fino alle %@ (ancora %@)", countdown: "tra %@",
         allDay: "Tutto il giorno", denied: "Nessun accesso al calendario"),
]
// Read at each update, so the texts follow the language and the region set in System Settings
var text: (untitled: String, until: String, countdown: String, allDay: String, denied: String) {
  let codes = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
  return codes.lazy.compactMap { texts[$0] }.first ?? texts["en"]!
}

// e.g. 14:30, or 2:30 PM where the region uses 12 hours or when chosen in System Settings
func time(_ date: Date) -> String {
  date.formatted(date: .omitted, time: .shortened)
}

// e.g. 20 min, 1 h or 1 h 20 min, rounded up to the minute: at 9:29 an event at 9:30 is 1 min away,
// and one that ends at 9:30 has 1 min left
func timeLeft(until date: Date, from now: Date) -> String {
  let (hours, minutes) = Int((date.timeIntervalSince(now) / 60).rounded(.up)).quotientAndRemainder(dividingBy: 60)
  if hours == 0 { return "\(minutes) min" }
  return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
}

// On one line and without the separator of EVENTS, up to length characters
func title(_ event: EKEvent, length: Int = 30) -> String {
  let title = (event.title ?? "").components(separatedBy: CharacterSet.newlines.union(["\u{1f}"]))
    .joined(separator: " ").trimmingCharacters(in: .whitespaces)
  if title.isEmpty { return text.untitled }
  return title.count > length ? title.prefix(length - 1) + "…" : title
}

func declined(_ event: EKEvent) -> Bool {
  event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
}

// The Google Meet call of the event: Google Calendar writes it in the notes ("Join with Google Meet:
// https://meet.google.com/abc-defg-hij"), and an event made elsewhere may have it as its location or
// its URL. Only the address of the call, which has no characters that need quoting in calendar.sh
let meet = try! NSRegularExpression(pattern: "https://meet\\.google\\.com/[a-z0-9_/-]+", options: .caseInsensitive)

func meetLink(_ event: EKEvent) -> String? {
  for field in [event.location, event.url?.absoluteString, event.notes].compactMap({ $0 }) {
    if let match = meet.firstMatch(in: field, range: NSRange(field.startIndex..., in: field)) {
      return String(field[Range(match.range, in: field)!])
    }
  }
  return nil
}

// The URL that shows the event in Calendar. Its identifier is percent-encoded down to characters
// that need no quoting in calendar.sh
let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:@")

func calendarLink(_ event: EKEvent) -> String {
  let identifier = event.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
  return "ical://ekevent/\(identifier)?method=show&options=more"
}

// A line for each event, the all-day ones first, with its fields separated by \u{1f}: allday, past,
// ongoing or upcoming, the time, the title, the Meet call if it has one and the link to Calendar
func list(_ events: [EKEvent], _ now: Date) -> String {
  (events.filter(\.isAllDay) + events.filter { !$0.isAllDay }).map { event in
    let state = event.isAllDay ? "allday" : event.endDate <= now ? "past" : event.startDate <= now ? "ongoing" : "upcoming"
    let hours = event.isAllDay ? text.allDay : "\(time(event.startDate)) – \(time(event.endDate))"
    return [state, hours, title(event, length: 40), meetLink(event) ?? "", calendarLink(event)].joined(separator: "\u{1f}")
  }.joined(separator: "\n")
}

// KIND and LABEL, and EVENTS
func current() -> (bar: [String], events: String) {
  guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
    return (["KIND=denied", "LABEL=\(text.denied)"], "")
  }
  let now = Date()
  let today = Calendar.current.dateInterval(of: .day, for: now)!
  let events = store.events(matching: store.predicateForEvents(withStart: today.start, end: today.end, calendars: nil))
    .filter { $0.status != .canceled && !declined($0) }
    .sorted { ($0.startDate, $0.title ?? "") < ($1.startDate, $1.title ?? "") }
  return (bar(events, now), list(events, now))
}

// KIND and LABEL
func bar(_ events: [EKEvent], _ now: Date) -> [String] {
  let timed = events.filter { !$0.isAllDay && $0.endDate > now }
  let next = timed.first { $0.startDate > now }
  // The event in progress (the one that ends first), until it ends or the next one starts
  if let ongoing = timed.filter({ $0.startDate <= now }).min(by: { $0.endDate < $1.endDate }),
     next.map({ ongoing.endDate <= $0.startDate }) ?? true {
    let left = timeLeft(until: ongoing.endDate, from: now)
    return ["KIND=ongoing", "LABEL=" + String(format: text.until, title(ongoing), time(ongoing.endDate), left)]
  }
  if let next {
    let countdown = String(format: text.countdown, timeLeft(until: next.startDate, from: now))
    return ["KIND=upcoming", "LABEL=\(time(next.startDate))  \(title(next)) · \(countdown)"]
  }
  let allDay = events.filter(\.isAllDay)
  if !allDay.isEmpty {
    return ["KIND=allday", "LABEL=\(allDay.map { title($0) }.joined(separator: " · "))"]
  }
  return ["KIND=none"]
}

var sent: (bar: [String], events: String)?
var timer: Timer?

func update() {
  let (bar, events) = current()
  if bar != sent?.bar || events != sent?.events {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sketchybar)
    process.arguments = ["--trigger", "calendar_change"] + bar + (events != sent?.events ? ["EVENTS=" + events] : [])
    sent = (bar, events)
    try? process.run()
  }
  // Events start and end on the minute, and the countdown counts minutes: check again at the next one
  timer?.invalidate()
  let minute = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)!
  timer = Timer(fire: minute, interval: 0, repeats: false) { _ in update() }
  RunLoop.main.add(timer!, forMode: .common)
}

NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in update() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in update() }
NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { _ in update() }
// Shows the permission prompt the first time, then answers right away
store.requestFullAccessToEvents { _, _ in DispatchQueue.main.async { update() } }
NSApplication.shared.run()
