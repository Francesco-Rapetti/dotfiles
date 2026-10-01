// The Wi-Fi networks around the Mac for the network popup of SketchyBar, and joining one
//   wifi_networks watch <sketchybar path>   trigger wifi_networks_change with NETWORKS, the networks
//                                           around the Mac, whenever they change, or with
//                                           PERMISSION=denied; also when the Wi-Fi turns on or off
//                                           or joins another network, for the bar
//   wifi_networks scan                      have the watch look for networks now: it takes a few
//                                           seconds, while NETWORKS has those macOS saw last
//   wifi_networks join <name>               have the watch join the network: it triggers
//                                           wifi_networks_change with JOINED=<name> and RESULT,
//                                           ok, cancelled, missing (out of range), enterprise (a
//                                           network that also wants a user name), failed or denied
// NETWORKS has a line for each name, strongest first and then by name: <name>\t<level>\t<open|
// personal|enterprise>\t<known>, with the level of the signal from 1 to 3 as in the macOS menu.
// Since macOS 14.4 CoreWLAN gives the names of the networks only to an app that may use Location
// Services, since they tell where the Mac is, and networksetup can no longer join one. A process
// started by sketchybar would ask on behalf of AeroSpace: sketchybarrc builds this into
// wifi_networks.app, with wifi_networks.plist as its Info.plist, and starts it with `open`. The
// permission comes a few seconds after the app asks for it, every time it starts, so it keeps
// running; scan and join, run by network.sh, ask it with a distributed notification

import AppKit
import CoreLocation
import CoreWLAN

let arguments = Array(CommandLine.arguments.dropFirst())
let scanRequest = Notification.Name("com.github.francesco-rapetti.sketchybar-wifi.scan")
let joinRequest = Notification.Name("com.github.francesco-rapetti.sketchybar-wifi.join")

switch (arguments.first, arguments.count) {
case ("scan", 1):
  DistributedNotificationCenter.default().postNotificationName(scanRequest, object: nil, deliverImmediately: true)
  exit(0)
case ("join", 2):
  DistributedNotificationCenter.default().postNotificationName(joinRequest, object: arguments[1], deliverImmediately: true)
  exit(0)
case ("watch", 2):
  break
default:
  FileHandle.standardError.write("usage: wifi_networks watch <sketchybar path> | scan | join <name>\n".data(using: .utf8)!)
  exit(1)
}
let sketchybar = arguments[1]

// The app shows a window only to ask for a password or, the first time, for the permission: it
// has no Dock icon and comes to the front just for that
func front() {
  NSApplication.shared.setActivationPolicy(.accessory)
  NSApp.activate(ignoringOtherApps: true)
}

func isOpen(_ network: CWNetwork) -> Bool {
  [.none, .OWE, .oweTransition].contains { network.supportsSecurity($0) }
}

func isEnterprise(_ network: CWNetwork) -> Bool {
  [.dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise]
    .contains { network.supportsSecurity($0) }
}

// The bars of the Wi-Fi symbol in the macOS menu
func level(_ rssi: Int) -> Int {
  rssi >= -60 ? 3 : rssi >= -72 ? 2 : 1
}

// The name of a network, on one line and without the tabs that separate the fields
func clean(_ name: String) -> String {
  name.components(separatedBy: .controlCharacters).joined(separator: " ")
}

// The passwords of the networks joined from the popup are in the login keychain, which security
// reads without asking since it saved them there, as the token of Home Assistant; another program
// would need the user's permission, again whenever it is built again
let keychainService = "sketchybar-wifi"

// security <arguments> [input]: what it prints, or nil if it fails
func security(_ arguments: [String], input: String? = nil) -> String? {
  let security = Process()
  security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  security.arguments = arguments
  let output = Pipe(), stdin = Pipe()
  security.standardOutput = output
  security.standardError = FileHandle.nullDevice
  security.standardInput = stdin
  guard (try? security.run()) != nil else { return nil }
  stdin.fileHandleForWriting.write((input ?? "").data(using: .utf8)!)
  try? stdin.fileHandleForWriting.close()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  security.waitUntilExit()
  guard security.terminationStatus == 0 else { return nil }
  return String(data: data, encoding: .utf8)
}

func savedPassword(_ name: String) -> String? {
  security(["find-generic-password", "-s", keychainService, "-a", name, "-w"])?
    .trimmingCharacters(in: .newlines)
}

// The password goes to the interactive mode of security on its input, not among its arguments,
// which any process can read
func save(_ password: String, for name: String) {
  func quoted(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
  _ = security(["-i"], input: "add-generic-password -U -s \(keychainService) -a \(quoted(name)) -w \(quoted(password))\n")
}

final class Watcher: NSObject, CLLocationManagerDelegate, CWEventDelegate {
  let location = CLLocationManager()
  let client = CWWiFiClient.shared()
  var interface: CWInterface? { client.interface() }
  var allowed: Bool { location.authorizationStatus == .authorizedAlways }
  var sent: [String]?
  var scanning = false

  func start() {
    location.delegate = self
    // The permission is .notDetermined until the app asks for it, every time: once given, the
    // answer comes in a few seconds. The first time macOS asks whether the app can use the
    // location: if there is no answer by then, the app comes to the front and asks again, in case
    // the prompt is only for an app in the front
    location.requestWhenInUseAuthorization()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
      guard location.authorizationStatus == .notDetermined else { return }
      front()
      location.requestWhenInUseAuthorization()
    }

    client.delegate = self
    for event: CWEventType in [.powerDidChange, .ssidDidChange, .scanCacheUpdated] {
      try? client.startMonitoringEvent(with: event)
    }
    let center = DistributedNotificationCenter.default()
    center.addObserver(forName: scanRequest, object: nil, queue: .main) { [self] _ in scan() }
    center.addObserver(forName: joinRequest, object: nil, queue: .main) { [self] notification in
      if let name = notification.object as? String { join(name) }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                      queue: .main) { [self] _ in send(force: true) }
  }

  // The networks macOS saw last, as in NETWORKS: a network has an access point for each band, and
  // more in a mesh, so the strongest one of each name
  func networks() -> [String] {
    guard allowed, let interface, interface.powerOn() else { return [] }
    let known = Set((interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []).compactMap(\.ssid))
    var strongest: [String: CWNetwork] = [:]
    for network in interface.cachedScanResults() ?? [] {
      guard let name = network.ssid, !name.isEmpty else { continue }
      if network.rssiValue > strongest[name]?.rssiValue ?? Int.min { strongest[name] = network }
    }
    return strongest.map { name, network in
      let security = isOpen(network) ? "open" : isEnterprise(network) ? "enterprise" : "personal"
      return (name: clean(name), level: level(network.rssiValue), security: security, known: known.contains(name))
    }
    .sorted { ($1.level, $0.name) < ($0.level, $1.name) }
    .map { [$0.name, String($0.level), $0.security, $0.known ? "1" : "0"].joined(separator: "\t") }
  }

  // send [force] [variables]: wifi_networks_change when the networks changed, or always when forced,
  // e.g. for the bar. The signal of each network changes at every scan, but rarely its level
  func send(force: Bool = false, _ variables: [String] = []) {
    let networks = networks()
    guard force || networks != sent else { return }
    sent = networks
    let permission = location.authorizationStatus == .denied || location.authorizationStatus == .restricted ? "denied" : ""
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sketchybar)
    process.arguments = ["--trigger", "wifi_networks_change", "NETWORKS=" + networks.joined(separator: "\n"),
                         "PERMISSION=" + permission] + variables
    try? process.run()
  }

  // A new scan takes a few seconds, so it runs on its own queue; the networks it finds also come
  // with scanCacheUpdated
  func scan() {
    guard allowed, !scanning, let interface, interface.powerOn() else { return }
    scanning = true
    DispatchQueue.global().async { [self] in
      _ = try? interface.scanForNetworks(withSSID: nil)
      DispatchQueue.main.async { [self] in
        scanning = false
        send()
      }
    }
  }

  // join <name>: the strongest access point of the network, among those macOS saw last or else in a
  // scan for it. CoreWLAN wants the password also for a network saved on the Mac (without it:
  // tmpErr, -3900). The one saved by the popup first; then, for a network saved on the Mac, the one
  // macOS keeps in the System keychain, which gives it to the app only with the name and the
  // password of an administrator, every time; then the user's, again while it is wrong. The one that
  // works is saved for the next time. macOS remembers a network once joined. A failed attempt leaves
  // the Wi-Fi without a network, and macOS joins one of its own. Joining takes a few seconds, and the
  // password as long as it takes to type it: it blocks the main queue, so the other requests wait
  func join(_ name: String) {
    var result = "failed"
    defer { send(force: true, ["JOINED=" + name, "RESULT=" + result]) }
    guard allowed else { result = "denied"; return }
    guard let interface, interface.powerOn() else { return }
    let seen = (interface.cachedScanResults() ?? []).filter { $0.ssid == name }
    guard let network = (seen.isEmpty ? try? interface.scanForNetworks(withName: name) : seen)?
      .max(by: { $0.rssiValue < $1.rssiValue }) else { result = "missing"; return }
    let known = (interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []).contains { $0.ssid == name }

    if isOpen(network) {
      if (try? interface.associate(to: network, password: nil)) != nil { result = "ok" }
      return
    }
    // A network of a company or a university also wants a user name: System Settings asks for both
    if isEnterprise(network) {
      result = "enterprise"
      return
    }
    func joined(_ password: String) -> Bool {
      guard (try? interface.associate(to: network, password: password)) != nil else { return false }
      save(password, for: name)
      return true
    }
    var system: NSString?
    if let saved = savedPassword(name), joined(saved) {
      result = "ok"
      return
    }
    if known, CWKeychainFindWiFiPassword(.system, Data(name.utf8), &system) == errSecSuccess, let system,
       joined(system as String) {
      result = "ok"
      return
    }
    var wrong = false
    while let password = password(for: name, wrong: wrong) {
      if joined(password) {
        result = "ok"
        return
      }
      wrong = true
    }
    result = "cancelled"
  }

  // password <name> <wrong>: the password of the network, asked the way macOS does, or nil when
  // cancelled
  func password(for name: String, wrong: Bool) -> String? {
    front()
    let alert = NSAlert()
    alert.messageText = "La rete Wi-Fi “\(name)” richiede una password."
    alert.informativeText = wrong ? "La password non è corretta: riprova." : ""
    alert.icon = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
    alert.addButton(withTitle: "Connetti")
    alert.addButton(withTitle: "Annulla")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "Password"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
  }

  // Also when the permission is given or taken away in System Settings
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined else { return }
    send(force: true)
    scan()
  }

  // The events of CoreWLAN come on a queue of their own
  func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
    DispatchQueue.main.async { [self] in send() }
  }

  func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
    DispatchQueue.main.async { [self] in
      send(force: true)
      scan()
    }
  }

  func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    DispatchQueue.main.async { [self] in send(force: true) }
  }
}

// Location Services answers only an app: a manager made before it is a process without the
// permission, which stays .notDetermined
NSApplication.shared.setActivationPolicy(.accessory)
let watcher = Watcher()
watcher.start()
NSApplication.shared.run()
