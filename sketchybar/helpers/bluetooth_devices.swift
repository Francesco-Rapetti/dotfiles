// Connects or disconnects a paired Bluetooth device for the audio popup of SketchyBar
//   bluetooth_devices connect|disconnect <address>   print ok, denied (no access to Bluetooth) or failed
// macOS grants Bluetooth access to the app that asks for it, and a process started by sketchybar
// would ask on behalf of AeroSpace: sketchybarrc builds this into bluetooth_devices.app, with
// bluetooth_devices.plist as its Info.plist, and audio.sh starts it with `open`, which writes what
// it prints to a file

import CoreBluetooth
import IOBluetooth

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, ["connect", "disconnect"].contains(arguments[0]) else {
  FileHandle.standardError.write("usage: bluetooth_devices connect|disconnect <address>\n".data(using: .utf8)!)
  exit(1)
}

// The first time, macOS asks whether the app can use Bluetooth once a manager wants it: wait for
// the answer, for up to a minute
var manager: CBCentralManager?
if CBManager.authorization == .notDetermined {
  manager = CBCentralManager(delegate: nil, queue: nil)
  let deadline = Date().addingTimeInterval(60)
  while CBManager.authorization == .notDetermined && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
  }
}
guard CBManager.authorization == .allowedAlways else {
  print("denied")
  exit(0)
}

// openConnection waits until the device answers, or gives up after a few seconds when it is off
// or out of range; its audio then connects by itself
guard let device = IOBluetoothDevice(addressString: arguments[1]) else {
  print("failed")
  exit(0)
}
let connect = arguments[0] == "connect"
let status = connect ? device.openConnection() : device.closeConnection()
// Both return as soon as bluetoothd has the request, which it carries out after: the app waits
// until the device is connected or not, for up to 10 seconds, with the run loop that brings the news
let deadline = Date().addingTimeInterval(10)
while status == kIOReturnSuccess && device.isConnected() != connect && Date() < deadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.2))
}
print(status == kIOReturnSuccess && device.isConnected() == connect ? "ok" : "failed")
