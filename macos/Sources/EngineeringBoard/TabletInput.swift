import AppKit
import SwiftUI

/// AppKit delivers normalised driver pressure. No vendor packets or force units are inferred here.
enum TabletPenRole: String, Codable, CaseIterable, Identifiable {
    case unassigned = "Driver pen", threeButton = "3-button pen", thin = "Thin pen"
    var id: String { rawValue }
}

struct PenPressureResponse: Codable, Equatable {
    var activationThreshold: Double = 0
    var fullPressure: Double = 1
    var gamma: Double = 1
    var isValid: Bool {
        activationThreshold.isFinite && fullPressure.isFinite && gamma.isFinite &&
        (0...0.8).contains(activationThreshold) && (0.1...1).contains(fullPressure) &&
        fullPressure > activationThreshold + 0.01 && (0.25...4).contains(gamma)
    }
    func allowsContact(_ raw: Double) -> Bool { raw.isFinite && raw > max(0, activationThreshold) }
    func map(_ raw: Double) -> Double {
        guard isValid, raw.isFinite else { return 0 }
        let normal = min(1, max(0, (raw - activationThreshold) / (fullPressure - activationThreshold)))
        return pow(normal, gamma)
    }
}

enum TabletBarrelAction: String, Codable, CaseIterable, Identifiable {
    case driverControlled = "Use driver mapping", context = "Pen menu", straighten = "Toggle straightening"
    case colour = "Colour menu", dimension = "Dimension menu"
    var id: String { rawValue }
}

enum TabletWorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case general = "Drawing", math = "Math", circuits = "Circuits"
    var id: String { rawValue }
}

struct TabletDeviceIdentity: Identifiable, Equatable {
    let deviceID: Int
    let vendorID: Int
    let uniqueID: UInt64
    let serialNumber: Int
    let pointingDeviceID: Int
    let eraser: Bool
    var id: String { key }
    var key: String {
        if uniqueID != 0 { return "tool:\(vendorID):\(uniqueID)" }
        if serialNumber != 0 { return "serial:\(vendorID):\(serialNumber):\(pointingDeviceID)" }
        // A driver may expose no persistent tool ID. Do not pretend the transient fallback identifies a model.
        return "session:\(vendorID):\(deviceID):\(pointingDeviceID)"
    }
    var isPersistent: Bool { uniqueID != 0 || serialNumber != 0 }
    var label: String { "\(eraser ? "Eraser" : "Pen") • device \(deviceID)\(isPersistent ? "" : " • temporary ID")" }
}

struct TabletPreferences: Codable, Equatable {
    var showHover = true
    var rejectPointerWhileHovering = true
    var disableMouseCoalescing = false
    var lowerButton: TabletBarrelAction = .driverControlled
    var upperButton: TabletBarrelAction = .driverControlled
    var manualPen: TabletPenRole = .unassigned
    var boundRoles: [String: TabletPenRole] = [:]
    var responses: [String: PenPressureResponse] = [:]
    private static let storageKey = "engineeringboard.tabletPreferences.v1"
    static func responseKey(role: TabletPenRole, brush: PenKind) -> String { "\(role.rawValue)|\(brush.rawValue)" }
    func response(role: TabletPenRole, brush: PenKind) -> PenPressureResponse {
        let response = responses[Self.responseKey(role: role, brush: brush)] ?? PenPressureResponse()
        return response.isValid ? response : PenPressureResponse()
    }
    mutating func setResponse(_ response: PenPressureResponse, role: TabletPenRole, brush: PenKind) {
        guard response.isValid else { return }
        responses[Self.responseKey(role: role, brush: brush)] = response
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.storageKey) } }
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        value.responses = value.responses.filter { $0.value.isValid && $0.key.utf8.count < 200 }
        // Transient device IDs must never be restored as a persistent physical pen binding.
        value.boundRoles = value.boundRoles.filter { !$0.key.hasPrefix("session:") && $0.key.utf8.count < 255 }
        return value
    }
}

enum TabletShortcutAction: String, CaseIterable {
    case zoomIn, zoomOut, brushLarger, brushSmaller, nextPen, previousPen
    case ink, eraser, select, undo, redo, toggleRuler, toggleStraighten, context, mathMode, circuitMode
    var label: String {
        switch self {
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .brushLarger: return "Larger brush"
        case .brushSmaller: return "Smaller brush"
        case .nextPen: return "Next pen"
        case .previousPen: return "Previous pen"
        case .ink: return "Draw"
        case .eraser: return "Erase"
        case .select: return "Select"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .toggleRuler: return "Ruler"
        case .toggleStraighten: return "Straighten"
        case .context: return "Pen menu"
        case .mathMode: return "Math mode"
        case .circuitMode: return "Circuit mode"
        }
    }
    var key: String {
        switch self {
        case .zoomIn: return "="
        case .zoomOut: return "-"
        case .brushLarger: return "]"
        case .brushSmaller: return "["
        case .nextPen: return "."
        case .previousPen: return ","
        case .ink: return "b"
        case .eraser: return "e"
        case .select: return "v"
        case .undo: return "z"
        case .redo: return "y"
        case .toggleRuler: return "r"
        case .toggleStraighten: return "s"
        case .context: return "p"
        case .mathMode: return "m"
        case .circuitMode: return "c"
        }
    }
    var shortcutLabel: String { "⌥⌘\(key.uppercased())" }
    static func from(event: NSEvent) -> Self? {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        guard event.modifierFlags.intersection([.function, .help]).isEmpty else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == [.command, .option], let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        return allCases.first { $0.key == key }
    }
}

@MainActor
extension DrawingSession {
    func observeTabletProximity(_ event: NSEvent) {
        let id = event.deviceID
        if event.isEnteringProximity {
            let identity = TabletDeviceIdentity(deviceID: id, vendorID: event.vendorID, uniqueID: event.uniqueID,
                serialNumber: event.pointingDeviceSerialNumber, pointingDeviceID: event.pointingDeviceID,
                eraser: event.pointingDeviceType == .eraser)
            tabletDeviceKeys[id] = identity.key
            if let index = observedTabletDevices.firstIndex(where: { $0.key == identity.key }) {
                observedTabletDevices[index] = identity
            } else {
                if observedTabletDevices.count >= 32 { observedTabletDevices.removeFirst() }
                observedTabletDevices.append(identity)
            }
            tabletProximityIDs.insert(id); activeTabletDeviceID = id
            tabletDetected = true
        } else {
            tabletProximityIDs.remove(id)
            if activeTabletDeviceID == id { activeTabletDeviceID = tabletProximityIDs.first }
        }
        tabletInProximity = !tabletProximityIDs.isEmpty
        if !tabletInProximity { tabletRawPressure = 0; livePressure = 0; tabletTilt = .zero }
        publishTabletTelemetry(force: true)
    }
    func observeTabletSample(_ event: NSEvent) {
        if !tabletDetected { tabletDetected = true }
        if activeTabletDeviceID != event.deviceID { activeTabletDeviceID = event.deviceID }
        let raw = Double(event.pressure)
        tabletRawPressure = raw.isFinite ? min(1, max(0, raw)) : 0
        let tilt = event.tilt
        tabletTilt = CGPoint(x: tilt.x.isFinite ? min(1, max(-1, tilt.x)) : 0,
                             y: tilt.y.isFinite ? min(1, max(-1, tilt.y)) : 0)
        livePressure = calibratedPressure(raw: tabletRawPressure, deviceID: event.deviceID)
        publishTabletTelemetry()
    }
    func tabletInputKey(deviceID: Int) -> String? { tabletDeviceKeys[deviceID] }
    func tabletPenRole(deviceID: Int?) -> TabletPenRole {
        if let deviceID, let key = tabletDeviceKeys[deviceID], let role = tabletPreferences.boundRoles[key] { return role }
        return tabletPreferences.manualPen
    }
    func calibratedPressure(raw: Double, deviceID: Int) -> Double {
        tabletPreferences.response(role: tabletPenRole(deviceID: deviceID), brush: pen).map(raw)
    }
    func tabletContactAllowed(raw: Double, deviceID: Int) -> Bool {
        tabletPreferences.response(role: tabletPenRole(deviceID: deviceID), brush: pen).allowsContact(raw)
    }
    func clearTabletProximity() {
        tabletProximityIDs.removeAll(); tabletInProximity = false; activeTabletDeviceID = nil
        tabletRawPressure = 0; livePressure = 0; tabletTilt = .zero
        publishTabletTelemetry(force: true)
    }
    func performTabletAction(_ action: TabletShortcutAction) {
        tabletActionWillPerform?(action)
        switch action {
        case .zoomIn: zoom = min(16, zoom * 1.08)
        case .zoomOut: zoom = max(0.05, zoom / 1.08)
        case .brushLarger: resizeTabletBrush(factor: 1.08)
        case .brushSmaller: resizeTabletBrush(factor: 1 / 1.08)
        case .nextPen, .previousPen:
            pendingStampSymbolID = nil
            let index = pen.renderID; let delta = action == .nextPen ? 1 : -1
            pen = PenKind.allCases[(index + delta + PenKind.allCases.count) % PenKind.allCases.count]; tool = .ink
        case .ink: pendingStampSymbolID = nil; tool = .ink
        case .eraser: tool = .eraser
        case .select: tool = .select
        case .undo: undo()
        case .redo: redo()
        case .toggleRuler: showRuler.toggle()
        case .toggleStraighten: autoShape.toggle()
        case .context: contextMenuRequest += 1
        case .mathMode: tabletWorkspaceMode = .math
        case .circuitMode: tabletWorkspaceMode = .circuits
        }
        status = action.label
    }
    private func resizeTabletBrush(factor: Double) {
        var settings = brushSettings
        let next = min(100, max(0.2, settings.maxWidth * factor))
        let ratio = next / settings.maxWidth
        settings.minWidth = min(next, max(0.1, settings.minWidth * ratio)); settings.maxWidth = next
        if pen == .technical { settings.minWidth = next }
        brushSettings = settings
    }
}

extension InkColor {
    var hexString: String {
        String(format: "#%02X%02X%02X", Int((min(1, max(0, r)) * 255).rounded()),
               Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded()))
    }
    static func parseHex(_ input: String) -> InkColor? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard [6, 8].contains(text.count), text.allSatisfy({ $0.isHexDigit }), let number = UInt64(text, radix: 16) else { return nil }
        let rgb = text.count == 8 ? number >> 8 : number
        return InkColor(r: Double((rgb >> 16) & 255) / 255, g: Double((rgb >> 8) & 255) / 255,
                        b: Double(rgb & 255) / 255, a: text.count == 8 ? Double(number & 255) / 255 : 1)
    }
}
