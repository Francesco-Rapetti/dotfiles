// Audio devices for SketchyBar (CoreAudio has no command line tool for them)
//   audio_devices output|input   print "<id>\t<transport>\t<type>\t<name>\t<battery>" of the default device,
//                                where <id> is the same for the output and input of one device and
//                                <battery> the percentage of a Bluetooth device (empty when unknown)
//   audio_devices list           print each device the Sound settings list for the output and for the input,
//                                "<output|input>\t<uid>\t<default>\t<transport>\t<type>\t<name>\t<battery>" with
//                                <default> 1 for the default one, then each paired Bluetooth audio device, also
//                                when not connected, "bluetooth\t<address>\t<connected>\t<type>\t<name>"
//   audio_devices set output|input <uid>
//                                make that device the default one
//   audio_devices volume output|input [<percent>]
//                                print the volume of the default device, 0 when muted, or nothing when macOS
//                                can't change it (e.g. a headset with the volume on its base station); or set it
//   audio_devices watch          trigger audio_device_change whenever a default device changes or a device
//                                comes or goes, and audio_volume_change whenever the volume of one changes
// sketchybarrc compiles it with: swiftc -O audio_devices.swift -o audio_devices

import AudioToolbox  // kAudioHardwareServiceDeviceProperty_VirtualMainVolume
import CoreAudio
import Foundation

let system = AudioObjectID(kAudioObjectSystemObject)

func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
  var addr = address(selector, scope)
  var value = initial
  var size = UInt32(MemoryLayout<T>.size)
  let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0) }
  return status == noErr ? value : nil
}

func setProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, to value: T) -> Bool {
  var addr = address(selector, scope)
  let size = UInt32(MemoryLayout<T>.size)
  return withUnsafePointer(to: value) { AudioObjectSetPropertyData(object, &addr, 0, nil, size, $0) } == noErr
}

func isSettable(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> Bool {
  var addr = address(selector, scope)
  var settable: DarwinBoolean = false
  return AudioObjectHasProperty(object, &addr) && AudioObjectIsPropertySettable(object, &addr, &settable) == noErr
    && settable.boolValue
}

func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
  let value: Unmanaged<CFString>?? = property(device, selector, initial: nil)
  return value??.takeRetainedValue() as String?
}

// USB headsets are one device, but Bluetooth ones are two, with UIDs
// "<address>:output" and "<address>:input": drop the suffix so both get the same id
func id(_ device: AudioObjectID) -> String {
  let uid = string(device, kAudioDevicePropertyDeviceUID) ?? String(device)
  for suffix in [":output", ":input"] where uid.hasSuffix(suffix) {
    return String(uid.dropLast(suffix.count))
  }
  return uid
}

func transport(_ device: AudioObjectID) -> String {
  switch property(device, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0 {
  case kAudioDeviceTransportTypeBuiltIn: "builtin"
  case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "bluetooth"
  case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: "display"
  case kAudioDeviceTransportTypeAirPlay: "airplay"
  case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: "virtual"
  default: "external"  // USB, Thunderbolt, PCI...
  }
}

// Terminal types are CoreAudio codes or, for USB devices, the codes of the USB Audio spec
func type(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> String {
  let streams: AudioObjectID? = property(device, kAudioDevicePropertyStreams, scope, initial: 0)
  let terminal = streams.flatMap { property($0, kAudioStreamPropertyTerminalType, initial: UInt32(0)) } ?? 0
  switch terminal {
  case kAudioStreamTerminalTypeHeadphones, 0x0302: return "headphones"
  case kAudioStreamTerminalTypeHeadsetMicrophone, 0x0401...0x0402: return "headset"
  case kAudioStreamTerminalTypeSpeaker, kAudioStreamTerminalTypeLFESpeaker, kAudioStreamTerminalTypeReceiverSpeaker,
       0x0301, 0x0304...0x0307, 0x0403...0x0405: return "speaker"
  case kAudioStreamTerminalTypeMicrophone, kAudioStreamTerminalTypeReceiverMicrophone, 0x0201...0x0206: return "microphone"
  default: break
  }
  // Intel Macs switch the built-in output to the headphone jack as a data source ('hdpn')
  return property(device, kAudioDevicePropertyDataSource, scope, initial: UInt32(0)) == 0x6864706E ? "headphones" : "unknown"
}

func run(_ path: String, _ arguments: String...) -> Data {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = arguments
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  guard (try? process.run()) != nil else { return Data() }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return data
}

struct BluetoothDevice {
  let name: String
  let connected: Bool
  let info: [String: Any]
}

// What the batteries and the Bluetooth devices come from, read once and only when needed
enum Bluetooth {
  static let controllers: [[String: Any]] = {
    let data = run("/usr/sbin/system_profiler", "SPBluetoothDataType", "-json")
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return json?["SPBluetoothDataType"] as? [[String: Any]] ?? []
  }()
  static let on = controllers.contains {
    ($0["controller_properties"] as? [String: Any])?["controller_state"] as? String == "attrib_on"
  }
  // The paired devices, connected and not
  static let devices = controllers.flatMap { controller in
    [("device_connected", true), ("device_not_connected", false)].flatMap { key, connected in
      (controller[key] as? [[String: [String: Any]]] ?? []).flatMap { entry in
        entry.map { BluetoothDevice(name: $0.key, connected: connected, info: $0.value) }
      }
    }
  }
  static let accessories = String(decoding: run("/usr/bin/pmset", "-g", "accps"), as: UTF8.self).split(separator: "\n")
}

// CoreAudio doesn't know the battery of Bluetooth devices. system_profiler reports it for Apple
// earbuds, one per side (and the case): the lower of the two sides in use. The id of a Bluetooth
// device is its address ("40-70-F5-CF-79-F1")
func earbudsBattery(_ id: String) -> Int? {
  let address = id.uppercased().replacingOccurrences(of: "-", with: ":")
  guard let device = Bluetooth.devices.first(where: {
    $0.connected && ($0.info["device_address"] as? String)?.uppercased() == address
  }) else { return nil }
  let level = { (key: String) in (device.info[key] as? String).flatMap { Int($0.dropLast()) } }
  let sides = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
  return sides.min() ?? level("device_batteryLevelMain")
}

// Other headphones and headsets (e.g. over the HFP battery indicator) only show up among the
// accessories of pmset, by name: " -<name> (id=570889427)\t98%; discharging present: true"
func accessoryBattery(_ name: String) -> Int? {
  let prefix = " -\(name) (id="
  guard let line = Bluetooth.accessories.first(where: { $0.hasPrefix(prefix) }),
        let percent = line.split(separator: "\t").dropFirst().first?.split(separator: "%").first else { return nil }
  return Int(percent)
}

func battery(_ id: String, _ name: String) -> String {
  (earbudsBattery(id) ?? accessoryBattery(name)).map(String.init) ?? ""
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
  let device = property(system, selector, initial: AudioObjectID(kAudioObjectUnknown))
  return device == kAudioObjectUnknown ? nil : device
}

func printDefault(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) {
  guard let device = defaultDevice(selector) else { exit(1) }
  let id = id(device), transport = transport(device), name = string(device, kAudioObjectPropertyName) ?? ""
  let battery = transport == "bluetooth" ? battery(id, name) : ""
  print("\(id)\t\(transport)\t\(type(device, scope))\t\(name)\t\(battery)")
}

// The devices the Sound settings list for the scope: those with streams in it that can be the
// default, which leaves out hidden ones and those of apps, e.g. Microsoft Teams Audio
func devices(_ scope: AudioObjectPropertyScope) -> [AudioObjectID] {
  var addr = address(kAudioHardwarePropertyDevices)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
  var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
  guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &devices) == noErr else { return [] }
  return devices.filter { device in
    var streams = address(kAudioDevicePropertyStreams, scope)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr && size > 0
      && property(device, kAudioDevicePropertyIsHidden, initial: UInt32(0)) != 1
      && property(device, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope, initial: UInt32(0)) == 1
  }
}

// The types of type() for the minor types system_profiler gives the Bluetooth audio devices
let bluetoothTypes = ["Headphones": "headphones", "Headset": "headset", "Hands-free": "headset",
                      "Speaker": "speaker", "Loudspeaker": "speaker", "Portable Audio": "speaker",
                      "Car Audio": "speaker", "HiFi Audio": "speaker", "Microphone": "microphone"]

func printList() {
  var audio = Set<String>()  // the Bluetooth devices with their audio in CoreAudio, by id
  for (direction, (selector, scope)) in [("output", directions["output"]!), ("input", directions["input"]!)] {
    let current = defaultDevice(selector)
    for device in devices(scope) {
      guard let uid = string(device, kAudioDevicePropertyDeviceUID) else { continue }
      let transport = transport(device), name = string(device, kAudioObjectPropertyName) ?? ""
      if transport == "bluetooth" { audio.insert(id(device).uppercased()) }
      let battery = transport == "bluetooth" ? battery(id(device), name) : ""
      print("\(direction)\t\(uid)\t\(device == current ? 1 : 0)\t\(transport)\t\(type(device, scope))\t\(name)\t\(battery)")
    }
  }
  // By name, so that their rows in the popup stay where they are when one connects. Connected
  // means with its audio in CoreAudio: system_profiler still has a device among the connected ones
  // for a while after it disconnects, while CoreAudio drops its audio at once, and with it
  // audio_device_change sets the popup again
  guard Bluetooth.on else { return }
  for device in Bluetooth.devices.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
    guard let type = (device.info["device_minorType"] as? String).flatMap({ bluetoothTypes[$0] }),
          let address = device.info["device_address"] as? String else { continue }
    let connected = audio.contains(address.uppercased().replacingOccurrences(of: ":", with: "-"))
    print("bluetooth\t\(address)\t\(connected ? 1 : 0)\t\(type)\t\(device.name)")
  }
}

func setDefault(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ uid: String) {
  guard let device = devices(scope).first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) else { exit(1) }
  // The alerts and sound effects move with the output, unless the Sound settings play them on
  // another device
  let effects = selector == kAudioHardwarePropertyDefaultOutputDevice
    && defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) == defaultDevice(selector)
    && property(device, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, scope, initial: UInt32(0)) == 1
  guard setProperty(system, selector, to: device) else { exit(1) }
  if effects { _ = setProperty(system, kAudioHardwarePropertyDefaultSystemOutputDevice, to: device) }
}

// The volume of the macOS slider, whether the device has a main volume or one per channel. Some
// devices have none macOS can change: displays, or headsets with a volume knob such as the Arctis
// Nova Pro Wireless
let volume = kAudioHardwareServiceDeviceProperty_VirtualMainVolume

func printVolume(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) {
  guard let device = defaultDevice(selector) else { exit(1) }
  guard isSettable(device, volume, scope), let level = property(device, volume, scope, initial: Float32(0)) else { return }
  // Muted, the slider of macOS is empty too
  let muted = property(device, kAudioDevicePropertyMute, scope, initial: UInt32(0)) == 1
  print(muted ? 0 : Int((level * 100).rounded()))
}

func setVolume(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ percent: Int) {
  guard let device = defaultDevice(selector),
        setProperty(device, volume, scope, to: Float32(min(max(percent, 0), 100)) / 100) else { exit(1) }
  // Like the volume keys, raising the volume unmutes
  if percent > 0 && isSettable(device, kAudioDevicePropertyMute, scope) {
    _ = setProperty(device, kAudioDevicePropertyMute, scope, to: UInt32(0))
  }
}

func watch() -> Never {
  // Coalesce the bursts of notifications CoreAudio sends, e.g. while switching devices or holding
  // a volume key
  var pending: [String: DispatchWorkItem] = [:]
  func trigger(_ event: String) {
    pending[event]?.cancel()
    let trigger = DispatchWorkItem {
      let sketchybar = Process()
      sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      sketchybar.arguments = ["sketchybar", "--trigger", event]
      try? sketchybar.run()
    }
    pending[event] = trigger
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: trigger)
  }

  // The volume and mute of the default devices, on the whole device or on each channel. Listening
  // to the volume of the macOS slider itself isn't reliable, so all of them, which the default
  // devices may not have
  let volumeChanged: AudioObjectPropertyListenerBlock = { _, _ in trigger("audio_volume_change") }
  var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []
  func watchVolumes() {
    for (device, var addr) in watched {
      AudioObjectRemovePropertyListenerBlock(device, &addr, .main, volumeChanged)
    }
    watched = []
    for (selector, scope) in [(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeOutput),
                              (kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeInput)] {
      guard let device = defaultDevice(selector) else { continue }
      for (property, element) in [(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
                                  (kAudioDevicePropertyVolumeScalar, 1), (kAudioDevicePropertyVolumeScalar, 2),
                                  (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)] {
        var addr = AudioObjectPropertyAddress(mSelector: property, mScope: scope, mElement: element)
        if AudioObjectHasProperty(device, &addr),
           AudioObjectAddPropertyListenerBlock(device, &addr, .main, volumeChanged) == noErr {
          watched.append((device, addr))
        }
      }
    }
  }

  let changed: AudioObjectPropertyListenerBlock = { _, _ in
    watchVolumes()
    trigger("audio_device_change")
  }
  for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
                   kAudioHardwarePropertyDevices] {
    var addr = address(selector)
    AudioObjectAddPropertyListenerBlock(system, &addr, .main, changed)
  }
  watchVolumes()
  dispatchMain()
}

// The default device selector and the scope of each direction
let directions = [
  "output": (kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeOutput),
  "input": (kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeInput),
]

func usage() -> Never {
  FileHandle.standardError.write("usage: audio_devices output|input|list|watch, set|volume output|input\n".data(using: .utf8)!)
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.dropFirst().first.flatMap { directions[$0] }) {
case ("output", _), ("input", _):
  let (selector, scope) = directions[arguments[0]]!
  printDefault(selector, scope)
case ("watch", _): watch()
case ("list", _) where arguments.count == 1: printList()
case ("set", let (selector, scope)?) where arguments.count == 3: setDefault(selector, scope, arguments[2])
case ("volume", let (selector, scope)?) where arguments.count == 2: printVolume(selector, scope)
case ("volume", let (selector, scope)?) where arguments.count == 3:
  guard let percent = Int(arguments[2]) else { usage() }
  setVolume(selector, scope, percent)
default: usage()
}
