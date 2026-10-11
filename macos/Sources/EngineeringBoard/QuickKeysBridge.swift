import AppKit
import Combine
import IOKit.hid

// Packet layout adapted from Julian Waller's MIT-licensed node-xencelabs-quick-keys.
// Source commit and complete license: Resources/QuickKeys/PROVENANCE.md and LICENSE.txt.
// This optional community bridge uses output reports, never private driver IPC.
enum QuickKeysPacketCodec {
    static let vendorID = 0x28bd
    static let wiredProductID = 0x5202
    static let wirelessProductID = 0x5203
    static let usagePage = 0xff0a
    static let usage = 0x01
    static let reportID: UInt8 = 0x02

    enum CodecError: Error { case invalidKey, invalidText, invalidWirelessID }
    enum Input: Equatable {
        case keys(UInt16), wheelRight, wheelLeft, battery(UInt8)
        case wirelessStatus(state: UInt8, id: [UInt8])
    }

    /// Input payload excludes the report-ID byte, matching the upstream core API.
    static func decode(reportID: UInt8, payload: [UInt8]) -> Input? {
        guard reportID == Self.reportID, let command = payload.first else { return nil }
        switch command {
        case 0xf0:
            guard payload.count >= 7 else { return nil }
            if payload[6] & 1 != 0 { return .wheelRight }
            if payload[6] & 2 != 0 { return .wheelLeft }
            guard payload[6] == 0 else { return nil }
            return .keys(UInt16(payload[1]) | UInt16(payload[2]) << 8)
        case 0xf2:
            guard payload.count >= 3, payload[1] == 1, payload[2] <= 100 else { return nil }
            return .battery(payload[2])
        case 0xf8:
            guard payload.count >= 15 else { return nil }
            return .wirelessStatus(state: payload[1], id: Array(payload[9..<15]))
        default: return nil
        }
    }

    /// Reports include their ID in byte zero, as required by IOHIDDeviceSetReport.
    static func packet(command: UInt8, wirelessID: [UInt8]? = nil) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = reportID
        bytes[1] = command
        if let wirelessID {
            guard wirelessID.count == 6 else { throw CodecError.invalidWirelessID }
            bytes.replaceSubrange(10..<16, with: wirelessID)
        }
        return bytes
    }

    static func subscriptions(wirelessID: [UInt8]? = nil) throws -> [[UInt8]] {
        var keys = try packet(command: 0xb0, wirelessID: wirelessID)
        keys[2] = 0x04
        var battery = try packet(command: 0xb4, wirelessID: wirelessID)
        battery[2] = 0x10
        return [keys, battery]
    }

    static func discovery() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = reportID; bytes[1] = 0xb8; bytes[2] = 1
        return bytes
    }

    static func keyLabel(index: Int, text: String, wirelessID: [UInt8]? = nil) throws -> [UInt8] {
        guard (0..<8).contains(index) else { throw CodecError.invalidKey }
        let units = Array(text.utf16)
        guard units.count <= 8, !units.contains(0) else { throw CodecError.invalidText }
        var bytes = try packet(command: 0xb1, wirelessID: wirelessID)
        bytes[3] = UInt8(index + 1); bytes[5] = UInt8(units.count * 2)
        write(units: units, into: &bytes)
        return bytes
    }

    static func wheelColor(red: UInt8, green: UInt8, blue: UInt8, wirelessID: [UInt8]? = nil) throws -> [UInt8] {
        var bytes = try packet(command: 0xb4, wirelessID: wirelessID)
        bytes[2] = 1; bytes[3] = 1
        bytes[6] = red; bytes[7] = green; bytes[8] = blue
        return bytes
    }

    static func overlay(text: String, duration: UInt8 = 2, wirelessID: [UInt8]? = nil) throws -> [[UInt8]] {
        let units = Array(text.utf16)
        guard duration > 0, units.count <= 32, !units.contains(0) else { throw CodecError.invalidText }
        // Upstream always writes an initial chunk and one continuation, including an empty one.
        var result: [[UInt8]] = []
        let chunkCount = max(2, (units.count + 7) / 8)
        for chunk in 0..<chunkCount {
            var bytes = try packet(command: 0xb1, wirelessID: wirelessID)
            bytes[2] = chunk == 0 ? 0x05 : 0x06; bytes[3] = duration
            let start = min(units.count, chunk * 8), end = min(units.count, (chunk + 1) * 8)
            let content = Array(units[start..<end])
            bytes[5] = UInt8(content.count * 2)
            bytes[6] = chunk > 0 && units.count > end ? 1 : 0
            write(units: content, into: &bytes)
            result.append(bytes)
        }
        return result
    }

    static func wirelessRoute(payload: [UInt8]) -> [UInt8]? {
        guard payload.count >= 17 else { return nil }
        return Array(payload[11..<17])
    }

    private static func write(units: [UInt16], into bytes: inout [UInt8]) {
        for (offset, unit) in units.enumerated() {
            bytes[16 + offset * 2] = UInt8(truncatingIfNeeded: unit)
            bytes[17 + offset * 2] = UInt8(truncatingIfNeeded: unit >> 8)
        }
    }
}

/// Pure queue state: no HID calls, timers or application state. The active packet
/// counts towards the bound; replacing a display batch keeps only the newest mode.
struct QuickKeysOutputQueue {
    enum Kind { case control, display }
    struct Entry {
        let token: UInt64
        let generation: UInt64
        let kind: Kind
        let bytes: [UInt8]
    }
    private(set) var generation: UInt64 = 0
    private(set) var pending: [Entry] = []
    private(set) var inFlight: Entry?
    private var nextToken: UInt64 = 0
    var count: Int { pending.count + (inFlight == nil ? 0 : 1) }

    mutating func enqueue(_ packets: [[UInt8]], kind: Kind) -> Bool {
        guard !packets.isEmpty, packets.count <= 32,
              packets.allSatisfy({ $0.count == 32 && $0.first == QuickKeysPacketCodec.reportID }) else { return false }
        let kept = kind == .display ? pending.filter { $0.kind != .display } : pending
        guard kept.count + packets.count + (inFlight == nil ? 0 : 1) <= 32 else { return false }
        pending = kept
        for bytes in packets {
            nextToken &+= 1
            pending.append(Entry(token: nextToken, generation: generation, kind: kind, bytes: bytes))
        }
        return true
    }

    mutating func takeNext() -> Entry? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        let entry = pending.removeFirst()
        inFlight = entry
        return entry
    }

    mutating func complete(token: UInt64, generation: UInt64) -> Bool {
        guard self.generation == generation, let entry = inFlight,
              entry.token == token, entry.generation == generation else { return false }
        inFlight = nil
        return true
    }

    mutating func retire() {
        generation &+= 1
        pending.removeAll(); inFlight = nil
    }

    /// Discard reports addressed to a child that left the receiver. Keep the
    /// accepted report alive until its callback releases the packet storage.
    mutating func discardPending() { pending.removeAll() }
}

/// The asynchronous IOKit callback owns this ticket until completion. It keeps
/// packet storage alive even if Stop retires the bridge or the owner is released.
fileprivate final class QuickKeysOutputFlight {
    let entry: QuickKeysOutputQueue.Entry
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>
    weak var owner: QuickKeysBridge?
    var retiredManager: IOHIDManager?

    init(entry: QuickKeysOutputQueue.Entry, device: IOHIDDevice, owner: QuickKeysBridge) {
        self.entry = entry; self.device = device; self.owner = owner
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        entry.bytes.withUnsafeBufferPointer { buffer.initialize(from: $0.baseAddress!, count: 32) }
    }

    func closeRetiredManager() {
        if let retiredManager {
            IOHIDManagerUnscheduleFromRunLoop(retiredManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(retiredManager, IOOptionBits(0))
            self.retiredManager = nil
        }
    }

    deinit { buffer.deallocate() }
}

@MainActor
final class QuickKeysBridge: ObservableObject {
    @Published private(set) var status = "Direct Quick Keys is off."
    @Published private(set) var connected = false
    @Published private(set) var isRunning = false
    @Published private(set) var dialMode = "Zoom"
    var onAction: ((TabletShortcutAction) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var wireless = false
    private var wirelessID: [UInt8]?
    private var keyMask: UInt16 = 0
    private var wheelMode = 0
    private var workspace: TabletWorkspaceMode = .general
    private var inactiveObserver: NSObjectProtocol?
    private var inputTimeout: DispatchWorkItem?
    private var outputQueue = QuickKeysOutputQueue()
    private var outputFlight: QuickKeysOutputFlight?

    init() {
        inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stop()
                self.status = "Direct Quick Keys stopped because Engineering Board lost focus."
            }
        }
    }

    deinit {
        inputTimeout?.cancel()
        if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
        if let device, let inputBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 512, nil, nil)
        }
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            if let outputFlight {
                outputFlight.retiredManager = manager
            } else {
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(0))
            }
        }
        inputBuffer?.deallocate()
    }

    /// Explicit opt-in only. No initialization, workspace change or device scan calls this automatically.
    func start() {
        guard !isRunning else { return }
        guard NSApp?.isActive == true else {
            status = "Bring Engineering Board to the front, then start direct Quick Keys."
            return
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        self.manager = manager
        let matches = [QuickKeysPacketCodec.wiredProductID, QuickKeysPacketCodec.wirelessProductID].map { product in
            [kIOHIDVendorIDKey: QuickKeysPacketCodec.vendorID,
             kIOHIDProductIDKey: product,
             kIOHIDDeviceUsagePageKey: QuickKeysPacketCodec.usagePage,
             kIOHIDDeviceUsageKey: QuickKeysPacketCodec.usage]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, quickKeysMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, quickKeysRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        isRunning = true
        status = "Waiting for a supported Quick Keys. Direct hardware control is unverified."
        // Zero options deliberately avoids kIOHIDOptionsTypeSeizeDevice.
        let result = IOHIDManagerOpen(manager, IOOptionBits(0))
        if result != kIOReturnSuccess { fail(result, operation: "open non-exclusive access") }
    }

    func stop() {
        inputTimeout?.cancel(); inputTimeout = nil
        outputQueue.retire()
        if let device, let inputBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 512, nil, nil)
        }
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            if let outputFlight {
                // Keep completion scheduling alive while the accepted async write
                // owns its packet buffer. Input callbacks are already removed.
                outputFlight.retiredManager = manager
            } else {
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(0))
            }
        }
        outputFlight = nil
        device = nil; manager = nil
        inputBuffer?.deallocate(); inputBuffer = nil
        wirelessID = nil; keyMask = 0
        connected = false; isRunning = false
        // The community source has no documented restore-mode or previous-label readback command.
        status = "Direct Quick Keys stopped. Previous OLED labels cannot be restored by this bridge."
    }

    func setMode(_ mode: TabletWorkspaceMode) {
        workspace = mode
        if connected && isRunning && NSApp?.isActive == true { updateDisplay() }
    }

    fileprivate func matched(_ matched: IOHIDDevice, result: IOReturn) {
        guard isRunning, device == nil else { return }
        guard NSApp?.isActive == true else { stop(); return }
        guard result == kIOReturnSuccess else { fail(result, operation: "open the device"); return }
        guard number(matched, kIOHIDVendorIDKey) == QuickKeysPacketCodec.vendorID,
              let product = number(matched, kIOHIDProductIDKey),
              [QuickKeysPacketCodec.wiredProductID, QuickKeysPacketCodec.wirelessProductID].contains(product)
        else { return }
        // Match the community WebHID usage pair. If USB interface metadata is exposed,
        // additionally require its documented interface 2; never touch keyboard/mouse interfaces.
        if let interface = number(matched, "bInterfaceNumber"), interface != 2 { return }
        device = matched
        wireless = product == QuickKeysPacketCodec.wirelessProductID
        wirelessID = nil; keyMask = 0
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
        buffer.initialize(repeating: 0, count: 512)
        inputBuffer = buffer
        IOHIDDeviceRegisterInputReportCallback(matched, buffer, 512, quickKeysInput, Unmanaged.passUnretained(self).toOpaque())
        if wireless {
            status = "Receiver opened; waiting for a Quick Keys discovery response."
            _ = send(QuickKeysPacketCodec.discovery())
            armTimeout()
        } else {
            configure()
        }
    }

    fileprivate func removed(_ removed: IOHIDDevice) {
        guard let device, CFEqual(device, removed) else { return }
        stop()
        status = "Quick Keys disconnected. Reconnect it, then start again."
    }

    fileprivate func received(result: IOReturn, reportID: UInt32, bytes: [UInt8]) {
        guard isRunning, NSApp?.isActive == true else { return }
        guard result == kIOReturnSuccess else { fail(result, operation: "read input"); return }
        guard reportID == UInt32(QuickKeysPacketCodec.reportID) else { return }
        // macOS supplies the report ID separately; numbered reports may also contain it.
        let payload = bytes.first == QuickKeysPacketCodec.reportID ? Array(bytes.dropFirst()) : bytes
        guard let input = QuickKeysPacketCodec.decode(reportID: QuickKeysPacketCodec.reportID, payload: payload) else { return }
        if case let .wirelessStatus(state, id) = input {
            guard wireless else { return }
            if state == 2 || state == 3 {
                guard wirelessID == nil || wirelessID == id else { return }
                // State 2 is a fresh connection notification, including for a known
                // child. Upstream resubscribes on every matching state-2 report.
                if wirelessID == nil || state == 2 { wirelessID = id; configure() }
            } else if state == 4, wirelessID == id {
                wirelessID = nil; connected = false; keyMask = 0
                outputQueue.discardPending()
                inputTimeout?.cancel(); inputTimeout = nil
                status = "Quick Keys left the receiver. Waiting for reconnection."
            }
            return
        }
        if wireless {
            guard let wirelessID, QuickKeysPacketCodec.wirelessRoute(payload: payload) == wirelessID else { return }
        }
        inputTimeout?.cancel(); inputTimeout = nil
        switch input {
        case let .keys(mask):
            let pressed = mask & ~keyMask
            keyMask = mask
            for key in 0..<10 where pressed & (1 << key) != 0 { press(key) }
        case .wheelRight: onAction?(dialActions.0)
        case .wheelLeft: onAction?(dialActions.1)
        case .battery: break
        case .wirelessStatus: break
        }
    }

    private func configure() {
        do {
            guard enqueue(try QuickKeysPacketCodec.subscriptions(wirelessID: wirelessID), kind: .control) else { return }
            connected = true
            status = "Direct Quick Keys opened. Hardware behavior and driver coexistence are unverified."
            updateDisplay()
            armTimeout()
        } catch { codecFailure() }
    }

    private func armTimeout() {
        inputTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.status = "No Quick Keys input received yet. The device may be asleep or unavailable to this bridge."
            }
        }
        inputTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
    }

    private var keyActions: [TabletShortcutAction] {
        switch workspace {
        case .general: return [.ink, .eraser, .select, .undo, .redo, .toggleRuler, .mathMode, .context]
        case .math: return [.ink, .eraser, .select, .undo, .redo, .toggleStraighten, .circuitMode, .context]
        case .circuits: return [.ink, .eraser, .select, .undo, .redo, .toggleRuler, .mathMode, .context]
        }
    }

    private var labels: [String] {
        switch workspace {
        case .general: return ["Ink", "Eraser", "Select", "Undo", "Redo", "Ruler", "Math", "Menu"]
        case .math: return ["Ink", "Eraser", "Select", "Undo", "Redo", "Straight", "Circuits", "Menu"]
        case .circuits: return ["Ink", "Eraser", "Select", "Undo", "Redo", "Ruler", "Math", "Menu"]
        }
    }

    private var dialActions: (TabletShortcutAction, TabletShortcutAction) {
        switch wheelMode {
        case 1: return (.brushLarger, .brushSmaller)
        case 2: return (.nextPen, .previousPen)
        case 3: return (.redo, .undo)
        default: return (.zoomIn, .zoomOut)
        }
    }

    private func press(_ key: Int) {
        if key < 8 { onAction?(keyActions[key]) }
        else if key == 8 { onAction?(workspace == .math ? .circuitMode : .mathMode) }
        else if key == 9 {
            wheelMode = (wheelMode + 1) % 4
            dialMode = ["Zoom", "Width", "Pens", "History"][wheelMode]
            updateDisplay()
        }
    }

    private func updateDisplay() {
        guard connected, isRunning, NSApp?.isActive == true else { return }
        do {
            var packets: [[UInt8]] = []
            for (index, label) in labels.enumerated() {
                packets.append(try QuickKeysPacketCodec.keyLabel(index: index, text: label, wirelessID: wirelessID))
            }
            let rgb: (UInt8, UInt8, UInt8)
            switch workspace { case .general: rgb = (35, 150, 230); case .math: rgb = (150, 80, 230); case .circuits: rgb = (30, 190, 110) }
            packets.append(try QuickKeysPacketCodec.wheelColor(red: rgb.0, green: rgb.1, blue: rgb.2, wirelessID: wirelessID))
            packets.append(contentsOf: try QuickKeysPacketCodec.overlay(text: "\(workspace.rawValue): \(dialMode)", wirelessID: wirelessID))
            _ = enqueue(packets, kind: .display)
        } catch { codecFailure() }
    }

    private func send(_ bytes: [UInt8]) -> Bool {
        enqueue([bytes], kind: .control)
    }

    private func enqueue(_ packets: [[UInt8]], kind: QuickKeysOutputQueue.Kind) -> Bool {
        guard isRunning, NSApp?.isActive == true, device != nil else { return false }
        guard outputQueue.enqueue(packets, kind: kind) else {
            stop()
            status = "Quick Keys output queue reached its safe limit. Reconnect direct control to retry."
            return false
        }
        pumpOutput()
        return isRunning
    }

    private func pumpOutput() {
        guard isRunning, NSApp?.isActive == true, let device,
              outputFlight == nil, let entry = outputQueue.takeNext() else { return }
        let flight = QuickKeysOutputFlight(entry: entry, device: device, owner: self)
        outputFlight = flight
        let context = Unmanaged.passRetained(flight).toOpaque()
        // Public SDK and Apple's wrapper pass milliseconds to the HID plugin.
        // This submits asynchronously: completion owns the storage until timeout/success.
        let result = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput,
            CFIndex(QuickKeysPacketCodec.reportID), flight.buffer, 32, 250,
            quickKeysOutputComplete, context)
        if result != kIOReturnSuccess {
            // An immediate submission failure does not schedule a callback.
            Unmanaged<QuickKeysOutputFlight>.fromOpaque(context).release()
            outputFlight = nil
            _ = outputQueue.complete(token: entry.token, generation: entry.generation)
            fail(result, operation: "submit an output report")
        }
    }

    fileprivate func outputCompleted(_ flight: QuickKeysOutputFlight, result: IOReturn) {
        flight.closeRetiredManager()
        guard isRunning, outputQueue.complete(token: flight.entry.token, generation: flight.entry.generation) else { return }
        outputFlight = nil
        guard result == kIOReturnSuccess else { fail(result, operation: "complete an output report"); return }
        pumpOutput()
    }

    private func number(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func fail(_ result: IOReturn, operation: String) {
        stop()
        let code = String(UInt32(bitPattern: result), radix: 16)
        status = "Could not \(operation) (IOKit 0x\(code)). The official driver or macOS access policy may block direct access. Driver shortcuts remain available."
    }

    private func codecFailure() {
        stop()
        status = "Quick Keys packet could not be prepared. Driver shortcuts remain available."
    }
}

private let quickKeysMatched: IOHIDDeviceCallback = { context, result, _, device in
    guard let context else { return }
    MainActor.assumeIsolated { Unmanaged<QuickKeysBridge>.fromOpaque(context).takeUnretainedValue().matched(device, result: result) }
}
private let quickKeysRemoved: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    MainActor.assumeIsolated { Unmanaged<QuickKeysBridge>.fromOpaque(context).takeUnretainedValue().removed(device) }
}
private let quickKeysInput: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
    guard let context, length >= 0, length <= 512 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    MainActor.assumeIsolated {
        Unmanaged<QuickKeysBridge>.fromOpaque(context).takeUnretainedValue().received(result: result, reportID: reportID, bytes: bytes)
    }
}
private let quickKeysOutputComplete: IOHIDReportCallback = { context, result, _, _, _, _, _ in
    guard let context else { return }
    let flight = Unmanaged<QuickKeysOutputFlight>.fromOpaque(context).takeRetainedValue()
    MainActor.assumeIsolated {
        if let owner = flight.owner { owner.outputCompleted(flight, result: result) }
        else { flight.closeRetiredManager() }
    }
}
