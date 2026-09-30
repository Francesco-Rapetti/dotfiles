// Default audio devices for SketchyBar (CoreAudio has no command line tool for them)
//   audio_devices output|input   print "<id>\t<transport>\t<type>\t<name>\t<battery>" of the default device,
//                                where <id> is the same for the output and input of one device and
//                                <battery> the percentage of a Bluetooth device (empty when unknown)
//   audio_devices watch          trigger audio_device_change whenever a default device changes
// sketchybarrc compiles it with: swiftc -O audio_devices.swift -o audio_devices

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

// CoreAudio doesn't know the battery of Bluetooth devices. system_profiler reports it for Apple
// earbuds, one per side (and the case): the lower of the two sides in use. The id of a Bluetooth
// device is its address ("40-70-F5-CF-79-F1")
func earbudsBattery(_ id: String) -> Int? {
  let address = id.uppercased().replacingOccurrences(of: "-", with: ":")
  guard let json = try? JSONSerialization.jsonObject(with: run("/usr/sbin/system_profiler", "SPBluetoothDataType", "-json")) as? [String: Any],
        let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
  for controller in controllers {
    for entry in controller["device_connected"] as? [[String: [String: Any]]] ?? [] {
      for device in entry.values where (device["device_address"] as? String)?.uppercased() == address {
        let level = { (key: String) in (device[key] as? String).flatMap { Int($0.dropLast()) } }
        let sides = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
        return sides.min() ?? level("device_batteryLevelMain")
      }
    }
  }
  return nil
}

// Other headphones and headsets (e.g. over the HFP battery indicator) only show up among the
// accessories of pmset, by name: " -<name> (id=570889427)\t98%; discharging present: true"
func accessoryBattery(_ name: String) -> Int? {
  let prefix = " -\(name) (id="
  let lines = String(decoding: run("/usr/bin/pmset", "-g", "accps"), as: UTF8.self).split(separator: "\n")
  guard let line = lines.first(where: { $0.hasPrefix(prefix) }),
        let percent = line.split(separator: "\t").dropFirst().first?.split(separator: "%").first else { return nil }
  return Int(percent)
}

func battery(_ id: String, _ name: String) -> String {
  (earbudsBattery(id) ?? accessoryBattery(name)).map(String.init) ?? ""
}

func printDefault(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) {
  guard let device = property(system, selector, initial: AudioObjectID(kAudioObjectUnknown)),
        device != kAudioObjectUnknown else { exit(1) }
  let id = id(device), transport = transport(device), name = string(device, kAudioObjectPropertyName) ?? ""
  let battery = transport == "bluetooth" ? battery(id, name) : ""
  print("\(id)\t\(transport)\t\(type(device, scope))\t\(name)\t\(battery)")
}

func watch() -> Never {
  // Coalesce the burst of notifications CoreAudio sends while switching devices
  var pending: DispatchWorkItem?
  let changed: AudioObjectPropertyListenerBlock = { _, _ in
    pending?.cancel()
    let trigger = DispatchWorkItem {
      let sketchybar = Process()
      sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      sketchybar.arguments = ["sketchybar", "--trigger", "audio_device_change"]
      try? sketchybar.run()
    }
    pending = trigger
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: trigger)
  }
  for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
    var addr = address(selector)
    AudioObjectAddPropertyListenerBlock(system, &addr, .main, changed)
  }
  dispatchMain()
}

switch CommandLine.arguments.dropFirst().first {
case "output": printDefault(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeOutput)
case "input": printDefault(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeInput)
case "watch": watch()
default:
  FileHandle.standardError.write("usage: audio_devices output|input|watch\n".data(using: .utf8)!)
  exit(1)
}
