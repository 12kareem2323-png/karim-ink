import SwiftUI
import AppKit

struct TabletSettingsPanel: View {
    @ObservedObject var session: DrawingSession
    @ObservedObject var quickKeys: QuickKeysBridge
    @Environment(\.dismiss) private var dismiss
    @State private var role: TabletPenRole = .threeButton
    @State private var tab = "Pen setup"
    @StateObject private var probe = DrawingSession(board: Board(title: "Pen test"), storesPreferences: false)
    private var response: PenPressureResponse { session.tabletPreferences.response(role: role, brush: session.pen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your drawing tablet").font(.system(size: 23, weight: .semibold))
                    Text("Pen response, live testing and Quick Keys").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Picker("Tablet section", selection: $tab) {
                Text("Pen setup").tag("Pen setup"); Text("Quick Keys").tag("Quick Keys"); Text("Input controls").tag("Input controls")
            }.pickerStyle(.segmented)
            ScrollView {
                if tab == "Pen setup" { penSetup }
                else if tab == "Quick Keys" { quickKeysSetup }
                else { inputControls }
            }
            Text("Core drawing and pen settings work offline. Pressure is the value delivered by the macOS driver, not a force measurement.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 800, height: 730).background(GlassSurface(material: .hudWindow))
        .onAppear { syncProbe() }
        .onChange(of: session.tabletPreferences) { _, _ in syncProbe() }
        .onChange(of: session.pen) { _, _ in syncProbe() }
        .onChange(of: role) { _, _ in syncProbe() }
        .onChange(of: session.brushSettings) { _, _ in syncProbe() }
        .onChange(of: probe.observedTabletDevices) { _, devices in
            for device in devices {
                session.tabletDeviceKeys[device.deviceID] = device.key
                if !session.observedTabletDevices.contains(where: { $0.key == device.key }) { session.observedTabletDevices.append(device) }
            }
        }
    }

    private var penSetup: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 15) {
                Label("Independent pen profiles", systemImage: "pencil.tip.crop.circle").font(.headline)
                Picker("Physical pen", selection: $role) { ForEach(TabletPenRole.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Brush", selection: $session.pen) { ForEach(PenKind.allCases) { Text($0.name).tag($0) } }
                pressureSlider("Start drawing at", keyPath: \.activationThreshold, range: 0...min(0.8, response.fullPressure - 0.02), percent: true)
                pressureSlider("Full output at", keyPath: \.fullPressure, range: max(0.1, response.activationThreshold + 0.02)...1, percent: true)
                pressureSlider("Response curve", keyPath: \.gamma, range: 0.25...4, percent: false)
                PenResponseGraph(response: response).frame(height: 85)
                HStack { Text("Light touch"); Spacer(); Text("Full pressure") }.font(.caption2).foregroundStyle(.secondary)
                Text("These settings apply to this pen and this brush. Your brush's width and opacity settings are applied afterwards.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Reset this response") { setResponse(PenPressureResponse()) }.buttonStyle(.borderless)
                Divider()
                Text("Identify your pen").font(.headline)
                if session.observedTabletDevices.isEmpty {
                    Text("Hover and draw in the test area. If the driver exposes a tool ID, it will appear here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(session.observedTabletDevices.filter { !$0.eraser }) { device in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.label).font(.caption)
                        Picker("Assign pen", selection: Binding(get: { session.tabletPreferences.boundRoles[device.key] ?? .unassigned }, set: { session.tabletPreferences.boundRoles[device.key] = $0 })) {
                            ForEach(TabletPenRole.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                    }
                }
                Picker("Fallback when no pen ID", selection: $session.tabletPreferences.manualPen) {
                    ForEach(TabletPenRole.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Choose the matching pen yourself. A tool ID doesn't identify the Xencelabs pen model. Temporary IDs are not restored after restart.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 305)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Live pen test", systemImage: "waveform.path").font(.headline)
                    Spacer(); Button("Clear") { probe.board.elements.removeAll(); probe.changed() }
                }
                BoardCanvas(session: probe).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.teal.opacity(0.25)))
                HStack {
                    metric("Driver", "\(Int(probe.tabletRawPressure * 100))%")
                    metric("Mapped", "\(Int(probe.livePressure * 100))%")
                    metric("Hover", probe.tabletInProximity ? "In range" : "Out of range")
                }
                ProgressView(value: probe.livePressure).tint(.teal)
                Text("Testing: \(probe.tabletPenRole(deviceID: probe.activeTabletDeviceID).rawValue)").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "Tilt X %+.3f   Y %+.3f", probe.tabletTilt.x, probe.tabletTilt.y))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text("Test light and firm pressure, tilt with the pencil, the eraser end and both side buttons. Test strokes stay here and aren't saved to your drawing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Physical tablet verification is still needed. This app preserves fractional input; the display above doesn't measure all 8,192 hardware levels.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
        }.padding(.top, 5)
    }

    private var quickKeysSetup: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Official driver shortcuts", systemImage: "keyboard").font(.headline)
            Text("In Xencelabs Settings, add Engineering Board as an application. Give the keys the shortcuts below. Set a dial mode to zoom and another to brush size; use the corresponding two shortcuts for its directions. The driver lets you name the OLED labels.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TabletShortcutAction.allCases, id: \.rawValue) { action in
                    HStack { Text(action.label); Spacer(); Text(action.shortcutLabel).monospaced() }
                        .font(.caption).padding(9).background(.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Button("Open Xencelabs Settings") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xencelabs/Xencelabs.app")) }
            Divider()
            Label("Experimental direct Quick Keys", systemImage: "dot.radiowaves.left.and.right").font(.headline)
            Text("An optional native USB/HID connection can read keys and the dial, and send Drawing, Math or Circuits labels to the OLED. It uses a community protocol, not a Xencelabs SDK. The official driver may hold the interface or conflict with it.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                if quickKeys.isRunning { Button("Disconnect direct control") { quickKeys.stop() } }
                else { Button("Connect direct control") { quickKeys.start(); quickKeys.setMode(session.tabletWorkspaceMode) } }
                Spacer()
                Picker("Mode", selection: $session.tabletWorkspaceMode) { ForEach(TabletWorkspaceMode.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 220)
            }
            Text(quickKeys.status).font(.caption).foregroundStyle(quickKeys.connected ? Color.teal : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if quickKeys.connected { Text("Dial: \(quickKeys.dialMode)").font(.caption) }
            Text("Direct control stays off until you connect it. It doesn't stop or modify your driver. Disconnect releases the device; it cannot restore the previous OLED labels. Direct hardware operation hasn't been verified on your remote.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Hover and input", systemImage: "cursorarrow.rays").font(.headline)
            Toggle("Show brush footprint while the pen hovers", isOn: $session.tabletPreferences.showHover)
            Toggle("Ignore mouse and trackpad drawing while the pen is in range", isOn: $session.tabletPreferences.rejectPointerWhileHovering)
            Text("The hover outline uses the configured brush size and the most recent contact pressure; a new pen starts at maximum width. A hovering pen normally reports zero pressure, so the outline is a preview. Toolbars and Quick Keys stay available.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Label("Barrel buttons", systemImage: "computermouse").font(.headline)
            Picker("Lower side button", selection: $session.tabletPreferences.lowerButton) { ForEach(TabletBarrelAction.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Upper side button", selection: $session.tabletPreferences.upperButton) { ForEach(TabletBarrelAction.allCases) { Text($0.rawValue).tag($0) } }
            Text("Driver mapping is the default. Native mappings require real side-button mask events; a button configured as a keyboard shortcut may not supply them. A right-click over the canvas opens the pen menu. Avoid mapping the same button in both places.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Deliver movement without AppKit mouse coalescing", isOn: $session.tabletPreferences.disableMouseCoalescing)
            Text("An optional app-wide event setting, active only while the pen is in range on a canvas. The previous setting is restored on exit or focus loss. This can increase CPU work and needs a physical latency test; it doesn't bypass the Xencelabs driver or guarantee zero jitter.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 8)
    }

    private func pressureSlider(_ name: String, keyPath: WritableKeyPath<PenPressureResponse, Double>, range: ClosedRange<Double>, percent: Bool) -> some View {
        VStack(spacing: 4) {
            HStack { Text(name); Spacer(); Text(percent ? "\(Int(response[keyPath: keyPath] * 100))%" : String(format: "%.2f", response[keyPath: keyPath])).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: Binding(get: { response[keyPath: keyPath] }, set: { value in var next = response; next[keyPath: keyPath] = value; setResponse(next) }), in: range)
        }
    }
    private func setResponse(_ value: PenPressureResponse) { session.tabletPreferences.setResponse(value, role: role, brush: session.pen) }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func syncProbe() {
        probe.tabletPreferences = session.tabletPreferences; probe.pen = session.pen
        probe.tabletPreferences.manualPen = role
        probe.brushSettings = session.brushSettings; probe.color = session.color; probe.zoom = 1
        probe.autoShape = false; probe.tabletDeviceKeys.merge(session.tabletDeviceKeys) { _, new in new }
    }
}

private struct PenResponseGraph: View {
    let response: PenPressureResponse
    var body: some View {
        Canvas { context, size in
            var curve = Path()
            for index in 0...128 {
                let raw = Double(index) / 128
                let point = CGPoint(x: raw * size.width, y: (1 - response.map(raw)) * size.height)
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(.teal), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }.padding(8).background(.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PenContextPanel: View {
    @ObservedObject var session: DrawingSession
    var onDismiss: () -> Void
    @State private var hex = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Pen menu").font(.headline); Spacer(); Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain) }
            Picker("Brush", selection: $session.pen) { ForEach(PenKind.allCases) { Text($0.name).tag($0) } }
            ColorPicker("Colour wheel", selection: Binding(get: { session.color.swift }, set: { value in
                if let c = NSColor(value).usingColorSpace(.sRGB) { session.color = InkColor(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent) }
            }))
            HStack {
                TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                Button("Set") { if let colour = InkColor.parseHex(hex) { session.color = colour } else { session.status = "Enter a hex colour such as #147D91" } }
            }
            Toggle("Hold to straighten", isOn: $session.autoShape)
            HStack { Text("New line length"); TextField("mm", value: $session.fixedLineLengthMM, format: .number).textFieldStyle(.roundedBorder).frame(width: 80); Text("mm") }.font(.caption)
            Text("Set 0 for free length. Hold at the end to snap; the last line's exact length can be edited below.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Dimension last line") {
                if let line = session.board.elements.last(where: { [.line, .dimension].contains($0.kind) }) { session.pendingDimensionID = line.id; onDismiss() }
                else { session.status = "Draw or straighten a line first" }
            }
        }.padding(18).frame(width: 310).background(GlassSurface())
        .onAppear { hex = session.color.hexString }
        .onChange(of: session.color) { _, _ in hex = session.color.hexString }
    }
}
