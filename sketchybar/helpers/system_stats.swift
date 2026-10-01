// CPU, GPU and memory usage for SketchyBar
//   system_stats watch   trigger system_stats_change every 2 seconds, when a value changes, with CPU,
//                        the percentage of the time the CPUs worked since the last time, GPU, the
//                        utilization of the GPU (empty when macOS doesn't report it), RAM, the
//                        memory used as Activity Monitor counts it (app memory, wired and
//                        compressed) out of all the memory, and PRESSURE, the memory pressure of
//                        Activity Monitor (normal, warning or critical).
//                        After SIGUSR1, until SIGUSR2, at each update also the details for the popup
//                        of system.sh, in tenths of a percent and in MB:
//                          CPU_SYSTEM, CPU_USER, CPU_IDLE   how the CPUs spent the time
//                          GPU_MODEL, GPU_CORES             e.g. Apple M4 Pro and 16
//                          MEMORY_USED, MEMORY_TOTAL, MEMORY_APP, MEMORY_WIRED, MEMORY_COMPRESSED, SWAP_USED
//                          CPU_TOP, GPU_TOP, MEMORY_TOP     the apps that use it most, a line for each
//                                                           with "<bundle id>\x1f<name>\x1f<value>"
//                        The processes of an app count together, under the outermost .app of their
//                        path, e.g. the helpers of Google Chrome; the others by their name
// No root needed: the CPU ticks and the memory pages are those of top and vm_stat, the GPU
// utilization and the GPU time of each process are in the IORegistry (ioreg -c IOAccelerator), the
// CPU of each process is that of ps, which is setuid and sees all of them. The memory of a process
// (its footprint, as in Activity Monitor) is readable only for the processes of the user, so
// MEMORY_TOP has no system processes
// sketchybarrc compiles it with: swiftc -O system_stats.swift -o system_stats

import CoreText
import Foundation
import IOKit

let interval = 2.0
let topCount = 5  // the rows of each list in the popup of system.sh
// The names are cut with … to fit the column of the popup of system.sh, in its font
let nameFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 13, nil)
let nameWidth = 190.0

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

// The share of the time between two readings in user (with nice), system and idle, from 0 to 1
func cpuTime(from old: [UInt32], to new: [UInt32]) -> (user: Double, system: Double, idle: Double) {
  let delta = zip(new, old).map { Double($0 &- $1) }
  let total = delta.reduce(0, +)
  guard total > 0 else { return (0, 0, 1) }
  return ((delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]) / total,
          delta[Int(CPU_STATE_SYSTEM)] / total, delta[Int(CPU_STATE_IDLE)] / total)
}

func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
  IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

func forEach(_ iterator: io_iterator_t, _ body: (io_object_t) -> Void) {
  while case let object = IOIteratorNext(iterator), object != 0 {
    body(object)
    IOObjectRelease(object)
  }
  IOObjectRelease(iterator)
}

func forEachGPU(_ body: (io_service_t) -> Void) {
  var iterator = io_iterator_t()
  guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
    return
  }
  forEach(iterator, body)
}

// The utilization of the busiest GPU, for Macs with two of them, and with clients the GPU time of
// each process in ns, which the driver keeps in the connections the process opened to it
func readGPU(clients: Bool) -> (percent: Int?, times: [pid_t: UInt64]) {
  var percent: Int?
  var times: [pid_t: UInt64] = [:]
  forEachGPU { gpu in
    if let statistics = property(gpu, "PerformanceStatistics") as? [String: Any],
       let utilization = statistics["Device Utilization %"] as? Int {
      percent = max(percent ?? 0, utilization)
    }
    var children = io_iterator_t()
    guard clients, IORegistryEntryGetChildIterator(gpu, kIOServicePlane, &children) == KERN_SUCCESS else { return }
    forEach(children) { client in
      // "pid 407, WindowServer"
      guard let creator = property(client, "IOUserClientCreator") as? String, creator.hasPrefix("pid "),
            let pid = pid_t(creator.dropFirst(4).prefix { $0.isNumber }),
            let usage = property(client, "AppUsage") as? [[String: Any]] else { return }
      times[pid, default: 0] += usage.reduce(0) { $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
    }
  }
  return (percent.map { min($0, 100) }, times)
}

// e.g. ("Apple M4 Pro", "16"), empty where the driver doesn't say
func gpuModel() -> (model: String, cores: String) {
  var model = "", cores = ""
  forEachGPU { gpu in
    if model.isEmpty, let name = property(gpu, "model") as? String { model = name }
    if cores.isEmpty, let count = property(gpu, "gpu-core-count") as? Int { cores = String(count) }
  }
  return (model, cores)
}

// In bytes, as Activity Monitor counts them: app memory is the anonymous pages that can't be purged
func memory() -> (used: Double, app: Double, wired: Double, compressed: Double)? {
  var stats = vm_statistics64()
  var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &stats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
    }
  }
  var pageSize = vm_size_t()
  guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
  let page = Double(pageSize)
  let app = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
  let wired = Double(stats.wire_count) * page
  let compressed = Double(stats.compressor_page_count) * page
  return (app + wired + compressed, app, wired, compressed)
}

let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)

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

func swapUsed() -> Double {
  var swap = xsw_usage()
  var size = MemoryLayout<xsw_usage>.size
  return sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? Double(swap.xsu_used) : 0
}

func allPids() -> [pid_t] {
  var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
  let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
  return Array(pids.prefix(max(0, Int(count))))
}

// The percentage of a CPU core each process used lately, from ps
func processCPU() -> [pid_t: Double] {
  let ps = Process()
  ps.executableURL = URL(fileURLWithPath: "/bin/ps")
  ps.arguments = ["-Ao", "pid=,pcpu="]
  let pipe = Pipe()
  ps.standardOutput = pipe
  guard (try? ps.run()) != nil else { return [:] }
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  ps.waitUntilExit()
  var cpu: [pid_t: Double] = [:]
  for line in output.split(separator: "\n") {
    let fields = line.split(separator: " ")
    if fields.count == 2, let pid = pid_t(fields[0]), let percent = Double(fields[1]) { cpu[pid] = percent }
  }
  return cpu
}

// The memory of each process of the user, as in Activity Monitor
func processMemory() -> [pid_t: Double] {
  var memory: [pid_t: Double] = [:]
  for pid in allPids() {
    var info = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
    }
    if result == 0 { memory[pid] = Double(info.ri_phys_footprint) }
  }
  return memory
}

// The app a process belongs to, by the path of its executable
struct Owner: Hashable {
  let bundle: String  // empty for the processes outside of an app
  let name: String
}
var owners: [String: Owner] = [:]

func owner(of pid: pid_t) -> Owner? {
  var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
  guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
  let path = String(cString: buffer)
  if let owner = owners[path] { return owner }
  let owner: Owner
  if let app = path.range(of: ".app/") {
    // The name of the app as the Finder shows it, e.g. Monitoraggio Attività
    let app = String(path[..<app.lowerBound]) + ".app"
    owner = Owner(bundle: Bundle(path: app)?.bundleIdentifier ?? "", name: FileManager.default.displayName(atPath: app))
  } else {
    owner = Owner(bundle: "", name: (path as NSString).lastPathComponent)
  }
  owners[path] = owner
  return owner
}

func width(_ text: String) -> Double {
  let string = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: nameFont])
  return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)
}

func fitted(_ name: String) -> String {
  guard width(name) > nameWidth else { return name }
  var text = Substring(name)
  while !text.isEmpty && width(String(text) + "…") > nameWidth { text = text.dropLast() }
  return text.trimmingCharacters(in: .whitespaces) + "…"
}

// The lines of CPU_TOP, GPU_TOP and MEMORY_TOP: the apps with the largest sums of the values of
// their processes, once rounded to whole units of the line
func top(_ values: [pid_t: Double], unit: Double) -> String {
  var sums: [Owner: Double] = [:]
  for (pid, value) in values where value > 0 {
    if let owner = owner(of: pid) { sums[owner, default: 0] += value }
  }
  return sums.map { ($0.key, Int(($0.value / unit).rounded())) }.filter { $0.1 > 0 }
    .sorted { $0.1 > $1.1 }.prefix(topCount)
    .map { "\($0.0.bundle)\u{1f}\(fitted($0.0.name))\u{1f}\($0.1)" }.joined(separator: "\n")
}

let megabyte = 1024.0 * 1024

func details(cpu time: (user: Double, system: Double, idle: Double),
             gpuTimes: (before: [pid_t: UInt64], after: [pid_t: UInt64], seconds: Double),
             memory: (used: Double, app: Double, wired: Double, compressed: Double)?) -> [String] {
  // ps counts each core as 100%, the bar all of them
  let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
  // Only the processes that were already there: the time of a new one counts from its start
  var gpu: [pid_t: Double] = [:]
  for (pid, after) in gpuTimes.after {
    if let before = gpuTimes.before[pid], after >= before {
      gpu[pid] = Double(after - before) / 1e9 / gpuTimes.seconds * 100
    }
  }
  let (model, gpuCores) = gpuModel()
  let sizes = memory.map { [$0.used, totalMemory, $0.app, $0.wired, $0.compressed, swapUsed()] } ?? []
  return [
    "CPU_SYSTEM=\(Int((time.system * 1000).rounded()))", "CPU_USER=\(Int((time.user * 1000).rounded()))",
    "CPU_IDLE=\(Int((time.idle * 1000).rounded()))",
    "CPU_TOP=\(top(processCPU(), unit: 0.1 * cores))",
    "GPU_MODEL=\(model)", "GPU_CORES=\(gpuCores)", "GPU_TOP=\(top(gpu, unit: 0.1))",
  ] + zip(["MEMORY_USED", "MEMORY_TOTAL", "MEMORY_APP", "MEMORY_WIRED", "MEMORY_COMPRESSED", "SWAP_USED"], sizes)
    .map { "\($0)=\(Int(($1 / megabyte).rounded()))" }
  + ["MEMORY_TOP=\(top(processMemory(), unit: megabyte))"]
}

func watch() -> Never {
  var ticks = cpuTicks()
  var sent: [String]?
  // With the popup open: the GPU time of each process at the last update
  var gpuTimes: (times: [pid_t: UInt64], at: DispatchTime)?

  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.setEventHandler {
    let new = cpuTicks()
    let time = ticks.flatMap { old in new.map { cpuTime(from: old, to: $0) } }
    ticks = new
    let now = DispatchTime.now()
    let gpu = readGPU(clients: gpuTimes != nil)
    let ram = memory()
    var values = zip(["CPU", "GPU", "RAM"], [time.map { Int(((1 - $0.idle) * 100).rounded()) }, gpu.percent,
                                              ram.map { Int(($0.used / totalMemory * 100).rounded()) }])
                   .map { "\($0)=\($1.map(String.init) ?? "")" }
               + ["PRESSURE=\(memoryPressure())"]
    if let before = gpuTimes, let time {
      values += details(cpu: time, gpuTimes: (before.times, gpu.times, Double(now.uptimeNanoseconds - before.at.uptimeNanoseconds) / 1e9),
                        memory: ram)
      gpuTimes = (gpu.times, now)
    }
    guard values != sent else { return }
    sent = values
    let sketchybar = Process()
    sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    sketchybar.arguments = ["sketchybar", "--trigger", "system_stats_change"] + values
    try? sketchybar.run()
  }
  // The first update soon, so the items don't wait 2 seconds for their numbers after a reload,
  // nor the popup for its details: the GPU time of the processes needs two readings
  func updateSoon() {
    timer.schedule(deadline: .now() + 0.25, repeating: interval, leeway: .milliseconds(200))
  }

  signal(SIGUSR1, SIG_IGN)
  signal(SIGUSR2, SIG_IGN)
  let popupOpened = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
  popupOpened.setEventHandler {
    gpuTimes = (readGPU(clients: true).times, .now())
    updateSoon()
  }
  let popupClosed = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
  popupClosed.setEventHandler { gpuTimes = nil }
  popupOpened.resume()
  popupClosed.resume()

  updateSoon()
  timer.resume()
  dispatchMain()
}

if CommandLine.arguments.dropFirst() == ["watch"] {
  watch()
}
FileHandle.standardError.write("usage: system_stats watch\n".data(using: .utf8)!)
exit(1)
