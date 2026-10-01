// Battery of the Mac for SketchyBar: the charge, and the Charge Limit of System Settings → Battery
// (macOS 26.4+), which has no command line tool (pmset -g battlimit only shows it)
//   battery_charge status       print "<percent>\t<power>\t<charging>\t<charged>\t<minutes>\t<limit>\t<limit state>\t<held>\t
//                               <desktop>\t<low power>\t<watts>", or nothing without a battery: <power> ac or battery,
//                               <minutes> to empty on battery or to full while charging (-1 while macOS works it out),
//                               <limit> 80-100, 100 for none, <limit state> on, off, paused (after Charge to Full Now) or
//                               none (a Mac without the Charge Limit), <held> 1 when macOS holds the charge (the limit,
//                               Optimized Battery Charging or the desktop mode), <desktop> 1 in the desktop mode of a Mac
//                               rarely used on battery, <watts> of the power adapter, <charging>, <charged> and
//                               <low power> 1 or 0
//   battery_charge limit <percent>
//                               set the Charge Limit to 80, 85, 90, 95 or 100 (none)
//   battery_charge full         charge to 100% now, as Charge to Full Now in the battery menu of macOS
//   battery_charge watch        trigger battery_change whenever the battery or the Charge Limit changes
// The Charge Limit is PowerUIAgent's, which System Settings asks through the private framework
// PowerUI. PowerUIAgent logs that this helper lacks the entitlement of System Settings, but serves it
// all the same; macOS kills a helper signed with that entitlement
// sketchybarrc compiles it with: swiftc -O battery_charge.swift -o battery_charge

import Foundation
import IOKit.ps
import notify

// The methods of PowerUISmartChargeClient used here. MCL is the Manual Charge Limit, OBC Optimized
// Battery Charging
@objc protocol SmartChargeClient {
  @objc(isMCLSupported) func isMCLSupported() -> Bool
  @objc(getMCLLimitWithError:) func mclLimit(_ error: NSErrorPointer) -> UInt8
  // 1 while on, something else after Charge to Full Now; the limit is off when it is 100
  @objc(isMCLCurrentlyEnabled:) func mclState(_ error: NSErrorPointer) -> UInt
  @objc(isOBCEngaged:asDesktopDevice:chargingOverrideAllowed:withError:)
  func isHeld(_ held: UnsafeMutablePointer<ObjCBool>, desktop: UnsafeMutablePointer<ObjCBool>,
              overrideAllowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Bool
  @objc(setMCLLimit:error:) func setMCLLimit(_ limit: UInt8, error: NSErrorPointer) -> Bool
  @objc(temporarilyDisableMCL:) func temporarilyDisableMCL(_ error: NSErrorPointer) -> Bool
}

let limits: [UInt8] = [80, 85, 90, 95, 100]

func client() -> SmartChargeClient? {
  guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
        let type = NSClassFromString("PowerUISmartChargeClient"),
        let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
        let object = allocated.perform(NSSelectorFromString("initWithClientName:"), with: "sketchybar")?
          .takeUnretainedValue()
  else { return nil }
  return unsafeBitCast(object, to: SmartChargeClient.self)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("battery_charge: \(message)\n".data(using: .utf8)!)
  exit(1)
}

// The internal battery as IOKit describes it, e.g. in pmset -g ps -xml
func battery() -> [String: Any]? {
  guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
  return sources.lazy
    .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
}

func printStatus() {
  guard let battery = battery(), let current = battery[kIOPSCurrentCapacityKey] as? Int,
        let max = battery[kIOPSMaxCapacityKey] as? Int, max > 0 else { exit(1) }
  let ac = battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
  let charging = battery[kIOPSIsChargingKey] as? Bool ?? false
  let minutes = battery[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1

  var limit: UInt8 = 100, state = "none", held: ObjCBool = false, desktop: ObjCBool = false
  if let client = client(), client.isMCLSupported() {
    var error: NSError?
    limit = client.mclLimit(&error)
    if error != nil || !limits.contains(limit) { limit = 100 }
    state = limit == 100 ? "off" : client.mclState(nil) == 1 ? "on" : "paused"
    var overrideAllowed: ObjCBool = false
    if !client.isHeld(&held, desktop: &desktop, overrideAllowed: &overrideAllowed, error: nil) {
      held = false
      desktop = false
    }
  }

  let adapter = ac ? IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] : nil
  let fields: [Any] = [
    current * 100 / max, ac ? "ac" : "battery", charging ? 1 : 0, battery[kIOPSIsChargedKey] as? Bool ?? false ? 1 : 0,
    minutes, limit, state, held.boolValue ? 1 : 0, desktop.boolValue ? 1 : 0,
    ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0,
    adapter?[kIOPSPowerAdapterWattsKey] as? Int ?? "",
  ]
  print(fields.map { "\($0)" }.joined(separator: "\t"))
}

func setLimit(_ argument: String) {
  guard let limit = UInt8(argument), limits.contains(limit) else { fail("the limit is one of \(limits)") }
  guard let client = client(), client.isMCLSupported() else { fail("this Mac has no Charge Limit") }
  var error: NSError?
  guard client.setMCLLimit(limit, error: &error) else { fail(error?.localizedDescription ?? "can't set the limit") }
}

func chargeToFull() {
  guard let client = client(), client.isMCLSupported() else { fail("this Mac has no Charge Limit") }
  var error: NSError?
  guard client.temporarilyDisableMCL(&error) else { fail(error?.localizedDescription ?? "can't charge to full") }
}

// Coalesce the bursts of notifications, e.g. when the adapter is plugged in
var pending: DispatchWorkItem?
func trigger() {
  pending?.cancel()
  let trigger = DispatchWorkItem {
    let sketchybar = Process()
    sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    sketchybar.arguments = ["sketchybar", "--trigger", "battery_change"]
    try? sketchybar.run()
  }
  pending = trigger
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: trigger)
}

// IOKit notifies any change of the battery: the adapter, the percentage, charging or not and the
// time left; PowerUIAgent posts mclstatuschanged when the Charge Limit changes, also in System
// Settings
func watch() -> Never {
  guard let source = IOPSNotificationCreateRunLoopSource({ _ in trigger() }, nil)?.takeRetainedValue() else {
    fail("can't watch the battery")
  }
  CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
  var token: Int32 = 0
  notify_register_dispatch("com.apple.powerui.mclstatuschanged", &token, .main) { _ in trigger() }
  CFRunLoopRun()
  exit(0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("status", 1): printStatus()
case ("limit", 2): setLimit(arguments[1])
case ("full", 1): chargeToFull()
case ("watch", 1): watch()
default: fail("usage: battery_charge status|full|watch, limit <percent>")
}
