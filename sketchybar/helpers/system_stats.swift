// CPU, GPU and memory usage for SketchyBar
//   system_stats watch   trigger system_stats_change every 2 seconds, when a value changes, with CPU,
//                        the percentage of the time the CPUs worked since the last time, GPU, the
//                        utilization of the GPU (empty when macOS doesn't report it), RAM, the
//                        memory used as Activity Monitor counts it (app memory, wired and
//                        compressed) out of all the memory, and PRESSURE, the memory pressure of
//                        Activity Monitor (normal, warning or critical)
// No root needed: the CPU ticks and the memory pages are those of top and vm_stat, the GPU
// utilization the one of the GPU driver in the IORegistry (ioreg -c IOAccelerator)
// sketchybarrc compiles it with: swiftc -O system_stats.swift -o system_stats

import Foundation
import IOKit

let interval = 2.0

// The ticks of all the CPUs since boot, in user, system, idle and nice. They are 32 bits and
// wrap around after about a month with 12 CPUs, hence the deltas with &-
func cpuTicks() -> [UInt32]? {
  var load = host_cpu_load_info()
  var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &load) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { return nil }
  let ticks = load.cpu_ticks
  return [ticks.0, ticks.1, ticks.2, ticks.3]
}

func cpuPercent(from old: [UInt32], to new: [UInt32]) -> Int {
  let delta = zip(new, old).map { UInt64($0 &- $1) }
  let total = delta.reduce(0, +)
  guard total > 0 else { return 0 }
  let busy = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_SYSTEM)] + delta[Int(CPU_STATE_NICE)]
  return Int((Double(busy) / Double(total) * 100).rounded())
}

// The busiest GPU, for Macs with two of them
func gpuPercent() -> Int? {
  var iterator = io_iterator_t()
  guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
    return nil
  }
  defer { IOObjectRelease(iterator) }
  var percent: Int?
  while case let service = IOIteratorNext(iterator), service != 0 {
    defer { IOObjectRelease(service) }
    if let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
         .takeRetainedValue() as? [String: Any],
       let utilization = statistics["Device Utilization %"] as? Int {
      percent = max(percent ?? 0, utilization)
    }
  }
  return percent.map { min($0, 100) }
}

func memoryPercent() -> Int? {
  var stats = vm_statistics64()
  var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &stats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
    }
  }
  var pageSize = vm_size_t()
  guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
  // App memory is the anonymous pages that can't be purged
  let pages = Double(stats.internal_page_count) - Double(stats.purgeable_count)
            + Double(stats.wire_count) + Double(stats.compressor_page_count)
  let used = pages * Double(pageSize)
  return Int((used / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded())
}

func memoryPressure() -> String {
  var level: Int32 = 0
  var size = MemoryLayout<Int32>.size
  sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
  switch level {
  case 2: return "warning"
  case 4: return "critical"
  default: return "normal"
  }
}

func watch() -> Never {
  var ticks = cpuTicks()
  var sent: [String]?
  // The first one soon, so the items don't wait 2 seconds for their numbers after a reload
  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.schedule(deadline: .now() + 0.5, repeating: interval, leeway: .milliseconds(200))
  timer.setEventHandler {
    let new = cpuTicks()
    let cpu = ticks.flatMap { old in new.map { cpuPercent(from: old, to: $0) } }
    ticks = new
    let values = zip(["CPU", "GPU", "RAM"], [cpu, gpuPercent(), memoryPercent()]).map { "\($0)=\($1.map(String.init) ?? "")" }
               + ["PRESSURE=\(memoryPressure())"]
    guard values != sent else { return }
    sent = values
    let sketchybar = Process()
    sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    sketchybar.arguments = ["sketchybar", "--trigger", "system_stats_change"] + values
    try? sketchybar.run()
  }
  timer.resume()
  dispatchMain()
}

if CommandLine.arguments.dropFirst() == ["watch"] {
  watch()
}
FileHandle.standardError.write("usage: system_stats watch\n".data(using: .utf8)!)
exit(1)
