// Home Assistant for SketchyBar, through its WebSocket and REST APIs
//   home_assistant watch <server> <cache> <entity_id>...
//                        keep in <cache> the state of the entities, as JSON:
//                          {"online": true, "states": {"light.desk": {"state": "on", "attributes": {...}}}}
//                        and trigger home_assistant_change whenever it changes. Home Assistant
//                        sends the changes as they happen (subscribe_entities). When the server
//                        can't be reached online is false, with the last states, and it tries again
//                        every 10 seconds, or at once after SIGUSR1 (home.sh sends it on wake)
//   home_assistant call <server> <domain> <service> <JSON data>
//                        call the service, e.g. light turn_on '{"entity_id": "light.desk"}', and fail
//                        unless Home Assistant accepts it
// The token is a long-lived access token (Home Assistant > Profile > Security) in the login
// keychain, which security reads without asking since it saved it there:
//   security add-generic-password -U -a "$USER" -s sketchybar-home-assistant -w "$(pbpaste)"
// (the prompt of -w without a value takes at most 128 characters, fewer than a token has)
// sketchybarrc compiles it with: swiftc -O home_assistant.swift -o home_assistant

import Foundation

let keychainService = "sketchybar-home-assistant"
let retryInterval = 10.0
// A ping without a pong by the next one means the connection is gone, e.g. after sleep
let pingInterval = 30.0

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("home_assistant: \(message)\n".data(using: .utf8)!)
  exit(1)
}

// From the keychain through security: another program would need the user's permission, again
// each time sketchybarrc rebuilds it
func token() -> String? {
  let security = Process()
  security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  security.arguments = ["find-generic-password", "-s", keychainService, "-w"]
  let output = Pipe()
  security.standardOutput = output
  security.standardError = FileHandle.nullDevice
  guard (try? security.run()) != nil else { return nil }
  let data = output.fileHandleForReading.readDataToEndOfFile()
  security.waitUntilExit()
  guard security.terminationStatus == 0,
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !token.isEmpty else { return nil }
  return token
}

func call(server: URL, domain: String, service: String, data: String) -> Never {
  guard let token = token() else { fail("no token in the keychain (\(keychainService))") }
  guard let body = data.data(using: .utf8), (try? JSONSerialization.jsonObject(with: body)) is [String: Any] else {
    fail("not a JSON object: \(data)")
  }
  var request = URLRequest(url: server.appendingPathComponent("api/services/\(domain)/\(service)"), timeoutInterval: 10)
  request.httpMethod = "POST"
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = body
  let done = DispatchSemaphore(value: 0)
  var status = 0
  URLSession.shared.dataTask(with: request) { _, response, _ in
    status = (response as? HTTPURLResponse)?.statusCode ?? 0
    done.signal()
  }.resume()
  done.wait()
  guard status == 200 else { fail("\(domain).\(service): HTTP \(status)") }
  exit(0)
}

// Everything runs on the main queue: the callbacks of the socket come back to it
final class Watcher {
  let socket: URL
  let cache: URL
  let entities: [String]
  var states: [String: [String: Any]] = [:]
  var online = false
  var written: Data?
  var task: URLSessionWebSocketTask?
  var awaitingPong = false
  // In a row: after the first the states stay online for a second, the time to connect again,
  // so that a dropped connection doesn't dim the bar
  var failures = 0
  var retry: DispatchWorkItem?

  init(server: URL, cache: URL, entities: [String]) {
    var components = URLComponents(url: server.appendingPathComponent("api/websocket"), resolvingAgainstBaseURL: false)!
    components.scheme = components.scheme == "http" ? "ws" : "wss"
    socket = components.url!
    self.cache = cache
    self.entities = entities
  }

  func connect() {
    retry?.cancel()
    retry = nil
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    guard let token = token() else { return disconnected() }
    let task = URLSession.shared.webSocketTask(with: socket)
    task.maximumMessageSize = 64 << 20
    self.task = task
    awaitingPong = false
    task.resume()
    receive(task, token: token)
  }

  // The callbacks of a connection that was replaced are ignored
  func receive(_ task: URLSessionWebSocketTask, token: String) {
    task.receive { result in
      DispatchQueue.main.async {
        guard task === self.task else { return }
        switch result {
        case .failure:
          self.disconnected()
        case .success(let message):
          self.handle(message, task: task, token: token)
          self.receive(task, token: token)
        }
      }
    }
  }

  func send(_ object: [String: Any], on task: URLSessionWebSocketTask) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    // A failed send fails the receive too
    task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
  }

  func handle(_ message: URLSessionWebSocketTask.Message, task: URLSessionWebSocketTask, token: String) {
    let data: Data
    switch message {
    case .string(let text): data = Data(text.utf8)
    case .data(let bytes): data = bytes
    @unknown default: return
    }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    switch json["type"] as? String {
    case "auth_required":
      send(["type": "auth", "access_token": token], on: task)
    case "auth_ok":
      send(["id": 1, "type": "subscribe_entities", "entity_ids": entities], on: task)
    case "auth_invalid":
      disconnected()
    case "result" where json["success"] as? Bool == false:
      disconnected()
    case "event":
      guard let event = json["event"] as? [String: Any] else { return }
      apply(event)
      online = true
      failures = 0
      write()
    default:
      break
    }
  }

  // The compressed states of subscribe_entities: a for the entities added (all of them in the
  // first event), with their state s and attributes a; c for what changed, with + the new state or
  // attributes and - the attributes removed; r for the entities removed
  func apply(_ event: [String: Any]) {
    for (id, value) in event["a"] as? [String: [String: Any]] ?? [:] {
      states[id] = ["state": value["s"] ?? "", "attributes": value["a"] ?? [String: Any]()]
    }
    for (id, change) in event["c"] as? [String: [String: Any]] ?? [:] {
      guard var entity = states[id] else { continue }
      var attributes = entity["attributes"] as? [String: Any] ?? [:]
      if let added = change["+"] as? [String: Any] {
        if let state = added["s"] { entity["state"] = state }
        attributes.merge(added["a"] as? [String: Any] ?? [:]) { $1 }
      }
      for name in (change["-"] as? [String: Any])?["a"] as? [String] ?? [] {
        attributes[name] = nil
      }
      entity["attributes"] = attributes
      states[id] = entity
    }
    for id in event["r"] as? [String] ?? [] {
      states[id] = nil
    }
  }

  // Only when it changed: the time of the last update and the context aren't kept
  func write() {
    let object: [String: Any] = ["online": online, "states": states]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys), data != written else {
      return
    }
    written = data
    try? data.write(to: cache, options: .atomic)
    let sketchybar = Process()
    sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    sketchybar.arguments = ["sketchybar", "--trigger", "home_assistant_change"]
    try? sketchybar.run()
  }

  func disconnected() {
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    failures += 1
    if failures > 1 {
      online = false
      write()
    }
    let retry = DispatchWorkItem { self.connect() }
    self.retry = retry
    DispatchQueue.main.asyncAfter(deadline: .now() + (failures > 1 ? retryInterval : 1), execute: retry)
  }

  func ping() {
    guard let task else { return }
    if awaitingPong { return disconnected() }
    awaitingPong = true
    task.sendPing { error in
      DispatchQueue.main.async {
        guard task === self.task else { return }
        if error != nil {
          self.disconnected()
        } else {
          self.awaitingPong = false
        }
      }
    }
  }
}

func watch(server: URL, cache: URL, entities: [String]) -> Never {
  let watcher = Watcher(server: server, cache: cache, entities: entities)
  watcher.connect()

  let pings = DispatchSource.makeTimerSource(queue: .main)
  pings.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
  pings.setEventHandler { watcher.ping() }
  pings.resume()

  // After sleep the connection is gone, though nothing says so until the next ping
  signal(SIGUSR1, SIG_IGN)
  let woke = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
  woke.setEventHandler {
    watcher.failures = 0
    watcher.connect()
  }
  woke.resume()

  dispatchMain()
}

func server(_ string: String) -> URL {
  guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else {
    fail("not the URL of a server: \(string)")
  }
  return url
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "watch" where arguments.count >= 4:
  watch(server: server(arguments[1]), cache: URL(fileURLWithPath: arguments[2]), entities: Array(arguments.dropFirst(3)))
case "call" where arguments.count == 5:
  call(server: server(arguments[1]), domain: arguments[2], service: arguments[3], data: arguments[4])
default:
  FileHandle.standardError.write("""
    usage: home_assistant watch <server> <cache> <entity_id>...
           home_assistant call <server> <domain> <service> <JSON data>

    """.data(using: .utf8)!)
  exit(1)
}
