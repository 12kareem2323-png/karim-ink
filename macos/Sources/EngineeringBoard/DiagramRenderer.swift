import AppKit

/// Small, editable teaching diagrams. These aren't a circuit simulator or a
/// substitute for a project's required IEC/ISO drawing convention.
@MainActor
enum DiagramRenderer {
    static func image(definition: SymbolDefinition, size: CGSize = CGSize(width: 200, height: 150), color: NSColor = .labelColor, phase: Double = 0) -> NSImage {
        NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(definition: definition, in: CGRect(origin: .zero, size: size), context: context, color: color, phase: phase)
            return true
        }
    }

    // The caller owns its CGContext and supplies a thread-local NSGraphicsContext
    // when glyphs/captions are drawn. This routine has no views or shared images.
    nonisolated static func draw(definition: SymbolDefinition, in rect: CGRect, context: CGContext, color: NSColor, phase: Double = 0) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 200, y: rect.height / 150)
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(2); context.setLineCap(.round); context.setLineJoin(.round); context.setLineDash(phase: 0, lengths: [])
        let variant = definition.variant
        func line(_ points: [CGPoint]) {
            guard let first = points.first else { return }
            context.beginPath(); context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        func segment(_ x: Double, _ y: Double, _ u: Double, _ v: Double) { line([p(x, y), p(u, v)]) }
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.stroke(CGRect(x: x, y: y, width: w, height: h)) }
        func circle(_ x: Double, _ y: Double, _ r: Double, fill: Bool = false) {
            let rect = CGRect(x: x-r, y: y-r, width: r*2, height: r*2)
            if fill { context.fillEllipse(in: rect) } else { context.strokeEllipse(in: rect) }
        }
        func arrow(_ x: Double, _ y: Double, _ u: Double, _ v: Double, head: Double = 9) {
            segment(x, y, u, v)
            let angle = atan2(v-y, u-x)
            line([p(u-head*cos(angle - .pi/6), v-head*sin(angle - .pi/6)), p(u,v), p(u-head*cos(angle + .pi/6), v-head*sin(angle + .pi/6))])
        }
        func text(_ value: String, _ x: Double, _ y: Double, size: Double = 16, center: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color]
            let string = value as NSString
            let width = string.size(withAttributes: attributes).width
            string.draw(at: p(center ? x-width/2 : x, y), withAttributes: attributes)
        }
        func triangle(_ points: [CGPoint], filled: Bool = false) {
            context.beginPath(); context.addLines(between: points); context.closePath()
            context.drawPath(using: filled ? .fillStroke : .stroke)
        }
        func leads(_ left: Double = 75, _ right: Double = 145, y: Double = 57) { segment(15, y, left, y); segment(right, y, 185, y) }
        func support(_ x: Double) {
            triangle([p(x, 80), p(x-13, 101), p(x+13, 101)])
            segment(x-19, 106, x+19, 106)
        }
        func beam(_ style: DiagramKind = .beamSimple) {
            box(30, 69, 145, 10)
            if style == .beamSimple { support(40); support(165) }
            if style == .beamCantilever || style == .beamFixed {
                segment(30, 47, 30, 99)
                for y in stride(from: 48.0, through: 98, by: 8) { segment(20, y+7, 30, y) }
            }
            if style == .beamFixed {
                segment(175, 47, 175, 99)
                for y in stride(from: 48.0, through: 98, by: 8) { segment(175, y, 185, y+7) }
            }
        }
        func gear(_ x: Double, _ y: Double, radius: Double, rotation: Double) {
            var points: [CGPoint] = []
            for index in 0..<48 {
                let angle = Double(index) * .pi * 2 / 48 + rotation
                let r = radius * (index % 4 < 2 ? 1 : 0.83)
                points.append(p(x + cos(angle)*r, y + sin(angle)*r))
            }
            points.append(points[0]); line(points); circle(x, y, radius*0.25)
            segment(x-radius*0.6*cos(rotation), y-radius*0.6*sin(rotation), x+radius*0.6*cos(rotation), y+radius*0.6*sin(rotation))
        }
        func diodeBody(_ kind: DiagramKind) {
            leads(82, 125)
            triangle([p(82, 32), p(82, 82), p(122, 57)])
            segment(125, 31, 125, 83)
            if kind == .zener { segment(116, 31, 125, 31); segment(125, 83, 134, 83) }
            if kind == .schottky { line([p(135,38), p(125,31), p(115,38)]); line([p(115,76),p(125,83),p(135,76)]) }
            if kind == .led { arrow(120, 25, 144, 7); arrow(138, 30, 163, 12) }
            if kind == .photodiode { arrow(149, 7, 125, 25); arrow(169, 15, 145, 33) }
            if kind == .thyristor { line([p(145, 101), p(120, 78), p(107, 78)]); text("G",151,86,size:12) }
        }
        func valve(_ type: String) {
            leads(70,150)
            triangle([p(70,35),p(70,80),p(110,57)]); triangle([p(150,35),p(150,80),p(110,57)])
            if type == "control" { segment(110,57,110,17); circle(110,15,13); text("C",110,6,size:12,center:true) }
            if type == "relief" { segment(110,57,110,25); line([p(92,25),p(101,17),p(110,25),p(119,17),p(128,25)]); arrow(154,36,175,18) }
            if type == "ball" { circle(110,57,15); segment(96,57,124,57); segment(110,42,110,15); segment(91,15,131,15) }
            if type == "butterfly" { segment(100,34,121,82); circle(110,57,4,fill:true); segment(110,35,110,15) }
            if type == "needle" { triangle([p(103,16),p(117,16),p(110,53)]); segment(110,16,110,5) }
            if type == "gate" { box(98,25,24,60); segment(110,25,110,8); segment(93,8,127,8) }
        }
        func processBlock(_ label: String) {
            box(40,30,125,55); arrow(8,57,40,57); arrow(165,57,194,57)
            text(label,102,46,size:13,center:true)
        }

        switch definition.diagram {
        case .glyph:
            let glyph = definition.glyph
            let maxSize: CGFloat = glyph.count > 20 ? 24 : (glyph.count > 8 ? 34 : 58)
            var font = NSFont(name: "STIX Two Math", size: maxSize) ?? NSFont.systemFont(ofSize: maxSize, weight: .regular)
            let width = (glyph as NSString).size(withAttributes: [.font: font]).width
            if width > 185 { font = NSFont.systemFont(ofSize: max(15, maxSize * 185 / width)) }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (glyph as NSString).size(withAttributes: attributes)
            (glyph as NSString).draw(at: p((200-size.width)/2, (105-size.height)/2), withAttributes: attributes)
        case .resistor, .variableResistor, .thermistor, .ldr:
            leads()
            if variant == "zigzag" {
                line([p(75,57),p(82,42),p(95,72),p(108,42),p(121,72),p(134,42),p(145,57)])
            } else { box(75,40,70,34) }
            if definition.diagram == .variableResistor {
                if variant == "potentiometer" { arrow(110,103,110,75) }
                else { arrow(62,91,158,22) }
            }
            if definition.diagram == .thermistor { line([p(63,92),p(75,92),p(156,23)]); text("−t°",145,83,size:13) }
            if definition.diagram == .ldr { circle(110,57,50); arrow(24,8,57,31); arrow(13,28,46,49) }
        case .capacitor, .polarizedCapacitor, .variableCapacitor:
            leads(95,definition.diagram == .polarizedCapacitor ? 129:120); segment(95,27,95,87)
            if definition.diagram == .polarizedCapacitor { text("+",78,10,size:18); context.beginPath(); context.move(to:p(120,27)); context.addQuadCurve(to:p(120,87),control:p(138,57)); context.strokePath() }
            else { segment(120,27,120,87) }
            if definition.diagram == .variableCapacitor { arrow(78,96,141,17) }
        case .inductor:
            leads(66,151)
            context.beginPath(); context.move(to:p(66,57))
            for index in 0..<4 { let x = 66 + Double(index)*21; context.addCurve(to:p(x+21,57),control1:p(x,15),control2:p(x+21,15)) }
            context.strokePath()
        case .transformer:
            for x in [72.0,132.0] {
                segment(x,10,x,25); segment(x,90,x,105)
                for y in stride(from:25.0,through:75,by:16) { context.beginPath(); context.move(to:p(x,y)); context.addCurve(to:p(x,y+16),control1:p(x+(x<100 ? 25:-25),y),control2:p(x+(x<100 ? 25:-25),y+16)); context.strokePath() }
            }
            segment(99,18,99,98); segment(106,18,106,98)
        case .cell, .battery:
            let count = definition.diagram == .cell ? 1 : 3
            leads(80,80+Double(count-1)*20+10)
            for index in 0..<count { let x = 80 + Double(index)*20; segment(x,25,x,90); segment(x+10,40,x+10,75) }
            text("+",68,7,size:15); text("−",145,7,size:15)
        case .ground, .earth:
            segment(110,12,110,50)
            if definition.diagram == .ground { triangle([p(78,50),p(142,50),p(110,87)]) }
            else { segment(76,50,144,50); segment(87,65,133,65); segment(99,80,121,80) }
        case .acSource, .dcSource, .currentSource, .ammeter, .voltmeter, .ohmmeter, .motor, .generator, .lamp:
            leads(75,145); circle(110,57,35)
            switch definition.diagram {
            case .acSource:
                context.beginPath(); context.move(to:p(86,57)); context.addCurve(to:p(110,57),control1:p(92,25),control2:p(104,25)); context.addCurve(to:p(134,57),control1:p(116,88),control2:p(128,88)); context.strokePath()
                if variant == "3~" { text("3~",110,95,size:13,center:true) }
            case .dcSource: text("+",110,30,size:18,center:true); text("−",110,62,size:18,center:true)
            case .currentSource: arrow(91,57,131,57)
            case .lamp: segment(86,33,134,81); segment(134,33,86,81)
            case .motor, .generator:
                text(definition.diagram == .motor ? "M" : "G",110,variant.isEmpty ? 43:35,size:24,center:true)
                if variant == "AC" || variant == "DC" || variant == "3~" { text(variant == "AC" ? "~" : (variant == "DC" ? "⎓" : "3~"),110,70,size:12,center:true) }
                if variant == "3~" { segment(15,41,76,41); segment(15,73,76,73) }
                if variant == "stepper" { for (x,y) in [(110.0,18.0),(151,57),(110,97),(68,57)] { box(x-6,y-6,12,12) }; text("steps",110,71,size:10,center:true) }
                if variant == "servo" { line([p(166,57),p(166,106),p(49,106),p(49,78)]); arrow(49,78,64,78,head:7) }
                if phase > 0 { let angle = phase * 2 * .pi; arrow(110+cos(angle)*46,57+sin(angle)*46,110+cos(angle+0.3)*46,57+sin(angle+0.3)*46,head:6) }
            default: text(definition.diagram == .ammeter ? "A" : (definition.diagram == .voltmeter ? "V" : "Ω"),110,40,size:26,center:true)
            }
        case .switchOpen, .switchClosed, .switchChangeover, .pushButton:
            leads(78,142); circle(78,57,3); circle(142,57,3)
            if definition.diagram == .switchClosed || (definition.diagram == .pushButton && variant == "NC") { segment(78,57,142,57) }
            else if definition.diagram == .pushButton { segment(80,37,140,37) }
            else { segment(78,57,133,26) }
            if definition.diagram == .pushButton { segment(110,15,110,37); segment(94,15,126,15) }
            if variant == "relay" {
                context.setLineDash(phase:0,lengths:[3,4]); segment(110,43,110,87); context.setLineDash(phase:0,lengths:[])
                box(90,87,40,23); text("K",110,89,size:15,center:true)
            }
            if definition.diagram == .switchChangeover { circle(142,25,3); segment(142,25,185,25) }
        case .fuse: leads(); box(75,42,70,30); segment(75,57,145,57)
        case .junction: segment(25,57,185,57); segment(110,15,110,100); circle(110,57,5,fill:true)
        case .crossing:
            segment(25,57,98,57); segment(122,57,185,57); segment(110,15,110,100)
            context.beginPath(); context.move(to:p(98,57)); context.addCurve(to:p(122,57),control1:p(98,35),control2:p(122,35)); context.strokePath()
        case .diode, .led, .photodiode, .zener, .schottky, .thyristor: diodeBody(definition.diagram)
        case .transistorNPN, .transistorPNP:
            circle(110,57,45); segment(20,57,90,57); segment(90,27,90,87)
            line([p(90,42),p(135,22),p(135,5)]); line([p(90,73),p(135,93),p(135,109)])
            if definition.diagram == .transistorNPN { arrow(108,81,134,93,head:8) } else { arrow(134,93,108,81,head:8) }
            text("B",38,36,size:12); text("C",148,5,size:12); text("E",148,91,size:12)
            if variant == "photo" { arrow(30,9,70,27); arrow(21,27,60,44) }
        case .mosfetN, .mosfetP:
            segment(20,57,80,57); segment(80,28,80,88); segment(96,28,96,88)
            line([p(96,30),p(135,30),p(135,6)]); line([p(96,86),p(135,86),p(135,110)])
            if definition.diagram == .mosfetN { arrow(116,57,96,57,head:7) } else { arrow(96,57,116,57,head:7) }
            text("G",42,37,size:12); text("D",148,6,size:12); text("S",148,92,size:12)
        case .opAmp:
            triangle([p(75,24),p(75,92),p(152,58)]); segment(20,42,75,42); segment(152,58,189,58)
            if variant == "differentiator" { segment(20,75,36,75); segment(44,75,75,75); segment(36,64,36,84); segment(44,64,44,84); text("C",38,85,size:10,center:true) }
            else if variant == "inverting" || variant == "integrator" { segment(20,75,30,75); segment(55,75,75,75); box(30,67,25,16); text("Rin",26,83,size:9) }
            else { segment(20,75,75,75) }
            text("+",83,31,size:16); text("−",83,66,size:16)
            if variant == "comparator" { text("cmp",106,50,size:12,center:true) }
            if variant != "" && variant != "comparator" {
                if variant == "integrator" {
                    line([p(175,58),p(175,9),p(125,9)]); line([p(109,9),p(55,9),p(55,75)])
                    segment(109,0,109,19); segment(125,0,125,19); text("C",115,20,size:11)
                } else {
                    line([p(175,58),p(175,9),p(138,9)]); line([p(103,9),p(55,9),p(55,75)])
                    box(103,2,35,14); text("R",120,20,size:11,center:true)
                }
                text(variant == "noninverting" ? "Vin +" : "Vin −",21,94,size:10)
                if variant == "noninverting" { segment(55,75,55,91); box(44,91,22,15); segment(55,106,55,110); segment(44,110,66,110); segment(49,114,61,114) }
            }
        case .relay:
            box(23,31,49,52); text("coil",47,47,size:12,center:true); segment(5,57,23,57); segment(72,57,89,57)
            context.setLineDash(phase:0,lengths:[4,4]); segment(72,24,145,24); context.setLineDash(phase:0,lengths:[])
            line([p(119,86),p(119,55),p(154,34)]); circle(159,55,3); segment(159,55,187,55)
        case .rectifier:
            if variant == "half" { diodeBody(.diode); box(154,57,25,35); text("~",25,22,size:25); text("R",166,63,size:15,center:true) }
            else {
                func diodeLeg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) {
                    let angle=atan2(by-ay,bx-ax), cx=(ax+bx)/2, cy=(ay+by)/2
                    segment(ax,ay,cx-13*cos(angle),cy-13*sin(angle)); segment(cx+13*cos(angle),cy+13*sin(angle),bx,by)
                    context.saveGState(); context.translateBy(x:cx,y:cy); context.rotate(by:angle)
                    triangle([p(-11,-8),p(-11,8),p(9,0)]); segment(12,-9,12,9); context.restoreGState()
                }
                diodeLeg(65,57,110,15); diodeLeg(110,15,155,57); diodeLeg(65,57,110,100); diodeLeg(110,100,155,57)
                text("~",110,0,size:18,center:true); text("~",110,99,size:18,center:true); text("+",172,47,size:18); text("−",28,47,size:18)
            }
        case .logicAnd, .logicNand, .logicOr, .logicNor, .logicXor, .logicXnor, .logicNot, .logicBuffer:
            let inverter = [.logicNand,.logicNor,.logicXnor,.logicNot].contains(definition.diagram)
            if definition.diagram == .logicNot || definition.diagram == .logicBuffer {
                segment(20,57,70,57); triangle([p(70,23),p(70,91),p(144,57)])
            } else {
                segment(20,40,70,40); segment(20,77,70,77)
                context.beginPath()
                if definition.diagram == .logicAnd || definition.diagram == .logicNand {
                    context.move(to:p(70,23)); context.addLine(to:p(106,23)); context.addCurve(to:p(106,91),control1:p(157,23),control2:p(157,91)); context.addLine(to:p(70,91)); context.closePath()
                } else {
                    context.move(to:p(67,23)); context.addCurve(to:p(147,57),control1:p(102,17),control2:p(130,29)); context.addCurve(to:p(67,91),control1:p(130,85),control2:p(102,97)); context.addQuadCurve(to:p(67,23),control:p(96,57))
                }
                context.strokePath()
                if definition.diagram == .logicXor || definition.diagram == .logicXnor {
                    context.beginPath(); context.move(to:p(58,23)); context.addQuadCurve(to:p(58,91),control:p(86,57)); context.strokePath()
                }
            }
            if inverter { circle(153,57,5); segment(158,57,190,57) } else { segment(145,57,190,57) }
        case .logicBlock:
            box(55,20,97,83)
            let values = variant.split(separator:"|").map(String.init)
            for index in 0..<2 { let y = 40.0+Double(index)*38; segment(14,y,55,y); segment(152,y,190,y)
                text(index < values.count ? values[index] : "",61,y-8,size:14)
                text(index+2 < values.count ? values[index+2] : "",144,y-8,size:14,center:true)
            }
            if let clock = values.prefix(2).firstIndex(of:"CLK") { let y=40.0+Double(clock)*38; line([p(55,y-8),p(63,y),p(55,y+8)]) }
            if definition.id == "Digital logic-jk-flipflop" { line([p(97,115),p(97,103)]); triangle([p(90,103),p(104,103),p(97,95)]); text("CLK",104,92,size:9) }
        case .clock:
            line([p(15,85),p(38,85),p(38,28),p(65,28),p(65,85),p(92,85),p(92,28),p(119,28),p(119,85),p(146,85),p(146,28),p(176,28)])
        case .beamSimple, .beamCantilever, .beamFixed: beam(definition.diagram)
        case .pointLoad: beam(); arrow(105,12,105,66); text("F",115,20,size:16)
        case .distributedLoad:
            beam()
            for x in stride(from:40.0,through:165,by:18) { let top = variant == "triangular" ? 58-(x-40)*0.34 : 18; arrow(x,top,x,65,head:6) }
            segment(40,variant == "triangular" ? 58:18,165,18); text("w",174,20,size:16)
        case .forceArrow: arrow(27,82,170,30,head:13); text(variant,101,30,size:23,center:true)
        case .moment:
            context.beginPath(); context.addArc(center:p(105,59),radius:39,startAngle:.pi*0.1,endAngle:.pi*1.65,clockwise:false); context.strokePath()
            arrow(117,21,135,31,head:9); text(variant,105,47,size:18,center:true)
        case .tension, .compression:
            box(67,42,78,30)
            if definition.diagram == .tension { arrow(67,57,16,57); arrow(145,57,192,57) }
            else { arrow(16,57,66,57); arrow(192,57,145,57) }
        case .shear: box(76,29,58,64); arrow(42,17,137,17); arrow(159,105,63,105)
        case .spring:
            line([p(15,57),p(45,57),p(54,35),p(70,80),p(86,35),p(102,80),p(118,35),p(134,80),p(146,57),p(186,57)]); text(variant,108,9,size:19)
        case .damper:
            line([p(18,57),p(77,57),p(77,33),p(132,33)]); line([p(77,57),p(77,83),p(132,83)]); segment(119,39,119,77); segment(119,57,186,57); text(variant,103,7,size:19)
        case .mass: box(59,22,94,71); text(variant,106,43,size:29,center:true); segment(43,100,171,100)
        case .pulley: circle(106,42,30); circle(106,42,5); line([p(76,42),p(76,98)]); line([p(136,42),p(136,98)]); box(58,98,35,13); box(121,98,31,13); segment(106,12,106,1)
        case .gear: gear(105,58,radius:46,rotation:0)
        case .gearPair: gear(70,56,radius:35,rotation:phase*2 * .pi); gear(137,56,radius:35,rotation:-phase*2 * .pi + .pi/12)
        case .shaft: box(26,43,151,30); segment(5,58,195,58); circle(177,58,15)
        case .bearing:
            circle(108,57,47); circle(108,57,29); circle(108,57,17)
            for index in 0..<8 { let angle = Double(index) * .pi/4; circle(108+cos(angle)*38,57+sin(angle)*38,7) }
        case .lever: segment(26,55,181,55); support(94); arrow(36,7,36,52); arrow(169,96,169,58); text("F",41,11,size:17)
        case .friction: box(71,40,69,40); segment(20,83,187,83); arrow(139,60,186,60); arrow(71,68,24,68); text("F",172,35,size:14); text("friction",19,91,size:12)
        case .freeBody: box(84,43,50,37); arrow(109,43,109,6); arrow(109,80,109,112); arrow(134,62,184,62); arrow(84,62,29,62); text("R",115,3,size:12); text("W",115,96,size:12)
        case .inclinedPlane:
            triangle([p(21,98),p(181,98),p(181,28)]); line([p(88,68),p(120,54),p(131,79),p(99,94),p(88,68)]); arrow(111,75,111,108); text("θ",160,80,size:16)
        case .pipeFlow:
            segment(14,31,186,31); segment(14,87,186,87)
            for index in 0..<3 { let x = 25 + (Double(index)*53 + phase*53).truncatingRemainder(dividingBy:159); arrow(x,59,x+24,59,head:7) }
        case .pump, .turbine, .compressor:
            leads(74,146); circle(110,57,36)
            let trianglePoints = definition.diagram == .turbine ? [p(144,35),p(144,79),p(86,57)] : [p(80,35),p(80,79),p(142,57)]
            triangle(trianglePoints,filled:definition.diagram != .compressor)
            if phase > 0 { circle(110+cos(phase*2 * .pi)*44,57+sin(phase*2 * .pi)*44,3,fill:true) }
        case .valve: valve(variant)
        case .checkValve: leads(76,126); triangle([p(76,33),p(76,81),p(123,57)]); segment(126,29,126,85); text("flow →",111,92,size:12,center:true)
        case .tank:
            line([p(51,24),p(51,93),p(167,93),p(167,24)]); segment(51,59,167,59)
            if variant == "closed" { segment(51,24,167,24) }
            if variant == "reservoir" { line([p(75,5),p(75,78)]); line([p(142,5),p(142,42)]) }
        case .piston:
            box(35,25,122,65); segment(102,26,102,89); segment(102,57,190,57); line([p(47,90),p(47,106),p(18,106)])
            if variant == "double" { line([p(143,90),p(143,106),p(181,106)]) }
            else { line([p(119,36),p(127,76),p(135,36),p(143,76)]) }
        case .filter:
            leads(68,153); line([p(110,16),p(153,57),p(110,99),p(68,57),p(110,16)])
            context.setLineDash(phase:0,lengths:[3,4]); segment(90,37,130,77); context.setLineDash(phase:0,lengths:[])
        case .heatExchanger:
            box(51,25,116,65); line([p(14,40),p(170,40),p(170,74),p(14,74)]); arrow(14,40,45,40); arrow(184,100,111,100); text("hot",107,45,size:12,center:true); text("cold",108,80,size:12,center:true)
        case .nozzle, .venturi:
            if variant == "orifice" { segment(20,30,180,30); segment(20,88,180,88); segment(105,30,105,48); segment(105,70,105,88) }
            else if definition.diagram == .venturi { line([p(15,25),p(57,25),p(92,45),p(117,45),p(153,25),p(190,25)]); line([p(15,91),p(57,91),p(92,72),p(117,72),p(153,91),p(190,91)]); segment(104,45,104,5) }
            else if variant == "diverging" { line([p(20,45),p(74,45),p(179,18)]); line([p(20,73),p(74,73),p(179,100)]) }
            else { line([p(20,18),p(128,45),p(182,45)]); line([p(20,100),p(128,73),p(182,73)]) }
            arrow(64,59,142,59)
        case .pressureGauge: circle(110,44,34); segment(110,78,110,108); segment(91,69,128,69); arrow(110,54,128,29); text("p",84,28,size:17)
        case .centreLine, .hiddenLine:
            context.setLineDash(phase:0,lengths:definition.diagram == .centreLine ? [24,6,3,6] : [10,7]); segment(12,59,188,59); context.setLineDash(phase:0,lengths:[])
        case .dimension:
            segment(35,32,35,90); segment(168,32,168,90); arrow(101,66,35,66,head:7); arrow(101,66,168,66,head:7); text("100 mm",101,39,size:17,center:true)
        case .angularDimension:
            line([p(23,91),p(47,91),p(167,29)]); segment(47,91,179,91)
            context.beginPath(); context.addArc(center:p(47,91),radius:57,startAngle: -.pi/6,endAngle:0,clockwise:false); context.strokePath(); text("30°",111,63,size:19)
        case .diameter:
            circle(76,62,38); arrow(138,19,91,43); text("⌀30",148,8,size:21)
        case .radius:
            context.beginPath(); context.addArc(center:p(79,70),radius:42,startAngle:.pi,endAngle:0,clockwise:false); context.strokePath(); arrow(79,70,107,39); text("R20",128,22,size:21)
        case .sectionHatch:
            box(41,20,125,85); context.saveGState(); context.clip(to:CGRect(x:41,y:20,width:125,height:85))
            for x in stride(from:-45.0,through:200,by:14) { segment(x,105,x+100,5) }; context.restoreGState()
        case .cuttingPlane:
            context.setLineDash(phase:0,lengths:[25,7,4,7]); segment(25,57,173,57); context.setLineDash(phase:0,lengths:[])
            arrow(25,22,25,57); arrow(173,22,173,57); text("A",18,78,size:17); text("A",165,78,size:17)
        case .datum: segment(21,80,181,80); triangle([p(78,80),p(68,59),p(88,59)],filled:true); segment(78,59,78,36); box(59,5,38,31); text(variant,78,9,size:22,center:true)
        case .surfaceFinish: line([p(49,50),p(80,80),p(112,21),p(165,21)]); text(variant,125,31,size:20); segment(22,81,178,81)
        case .weld:
            line([p(16,96),p(61,61),p(171,61),p(188,45)]); segment(171,61,188,76)
            if variant == "fillet" { triangle([p(95,61),p(95,38),p(118,61)]) }
            else { line([p(94,40),p(108,61),p(122,40)]); text("butt",112,73,size:12,center:true) }
        case .toleranceFrame:
            let values = variant.split(separator:"|").map(String.init); let cellWidth = min(65.0,170/Double(max(1,values.count)))
            for (index,value) in values.enumerated() { let x = 15+Double(index)*cellWidth; box(x,40,cellWidth,37); text(value,x+cellWidth/2,45,size:19,center:true) }
        case .projection:
            let x = variant == "first" ? 23.0 : 91.0
            line([p(x,30),p(x+52,43),p(x+52,75),p(x,88),p(x,30)]); segment(x,59,x+52,59)
            let cx = variant == "first" ? 157.0 : 43.0; circle(cx,59,28); circle(cx,59,16); segment(cx-36,59,cx+36,59)
        case .voltageDivider:
            line([p(100,8),p(100,24)]); box(87,24,26,26); segment(100,50,100,65); box(87,65,26,26); segment(100,91,100,109)
            circle(100,57,4,fill:true); arrow(100,57,176,57); text("Vout",146,33,size:13); text("Vin",42,5,size:14); text("0 V",42,94,size:14)
        case .bridge:
            segment(65,12,144,12); segment(65,106,144,106)
            for x in [65.0,144.0] { segment(x,12,x,25); box(x-10,25,20,23); segment(x,48,x,73); box(x-10,73,20,23); segment(x,96,x,106); circle(x,59,3,fill:true) }
            segment(65,59,92,59); segment(117,59,144,59); circle(104,59,13); text("V",104,49,size:16,center:true)
            text("R₁",34,28,size:11); text("R₂",161,28,size:11); text("R₃",34,77,size:11); text("R₄",161,77,size:11)
        case .breaker:
            leads(72,144); circle(73,57,3); circle(144,57,3); segment(73,57,134,29); box(88,14,37,20); text("trip",106,15,size:12,center:true)
            context.setLineDash(phase:0,lengths:[3,3]); segment(106,34,106,46); context.setLineDash(phase:0,lengths:[])
        case .jfet:
            segment(106,29,106,88); line([p(106,30),p(145,30),p(145,8)]); line([p(106,87),p(145,87),p(145,108)]); segment(19,57,89,57)
            if variant == "N" { arrow(83,57,105,57) } else { arrow(105,57,83,57) }; text("G",34,36,size:12); text("D",153,8,size:12); text("S",153,90,size:12)
        case .optocoupler:
            box(25,16,156,85); triangle([p(49,35),p(49,73),p(77,54)]); segment(80,33,80,75); arrow(84,43,112,30); arrow(86,65,114,52)
            segment(129,31,129,80); line([p(129,43),p(153,27),p(153,17)]); line([p(129,66),p(153,85),p(153,98)]); arrow(134,69,151,83,head:6)
        case .triac:
            leads(71,148); triangle([p(75,35),p(75,65),p(113,50)]); segment(117,33,117,67)
            triangle([p(145,55),p(145,85),p(108,70)]); segment(104,53,104,87)
            if variant == "TRIAC" { line([p(139,109),p(120,89),p(111,84)]); text("G",147,92,size:11) }
        case .crystal: leads(80,140); segment(80,27,80,87); segment(140,27,140,87); box(94,26,32,62)
        case .speaker: line([p(22,43),p(68,43),p(68,74),p(22,74)]); box(68,37,24,43); line([p(92,37),p(146,18),p(146,99),p(92,80)])
            for x in [160.0,176.0] { context.beginPath(); context.move(to:p(x,32)); context.addQuadCurve(to:p(x,83),control:p(x+20,57)); context.strokePath() }
        case .sensor: box(61,26,101,60); arrow(15,55,59,55); arrow(162,55,190,55); text(variant,111,43,size:22,center:true)
            if variant == "Hall" { text("B →",9,25,size:13) } else { text("°C",19,25,size:13) }
        case .support:
            segment(24,30,176,30)
            if variant == "fixed" { segment(106,30,106,105); for y in stride(from:34.0,through:103,by:11) { segment(89,y+9,106,y) } }
            else { triangle([p(105,30),p(71,77),p(139,77)]); circle(105,30,4)
                if variant == "roller" { circle(83,86,8); circle(127,86,8); segment(66,97,145,97) }
                else { segment(65,83,146,83); if variant == "pivot" { circle(105,39,12); text("pivot",145,50,size:12) } }
            }
        case .rackPinion:
            gear(103,39,radius:28,rotation:0); box(22,77,164,16)
            for x in stride(from:26.0,through:175,by:15) { line([p(x,77),p(x+5,66),p(x+10,66),p(x+15,77)]) }; arrow(30,108,170,108)
        case .wormGear:
            gear(127,64,radius:34,rotation:0); box(25,23,124,19)
            for x in stride(from:28.0,through:140,by:12) { segment(x,23,x+8,42) }; text("worm",52,3,size:12); text("wheel",153,94,size:12)
        case .bevelGear:
            line([p(103,15),p(76,69),p(130,69),p(103,15)]); line([p(163,60),p(112,39),p(112,82),p(163,60)]); segment(103,15,103,0); segment(163,60,190,60)
            for x in stride(from:83.0,through:122,by:10) { segment(103,22,x,68) }
        case .planetaryGear:
            circle(107,56,50); gear(107,56,radius:17,rotation:0)
            for index in 0..<3 { let angle = Double(index)*2 * .pi/3; gear(107+cos(angle)*31,56+sin(angle)*31,radius:14,rotation:0) }
        case .belt, .chain:
            circle(57,58,30); circle(153,58,20)
            if variant == "crossed" { segment(49,29,159,78); segment(49,87,159,38) }
            else { segment(54,28,153,38); segment(54,88,153,78) }
            if definition.diagram == .chain { for x in stride(from:58.0,through:149,by:13) { circle(x,29+(x-58)*0.10,3); circle(x,87-(x-58)*0.10,3) }; circle(57,58,8); circle(153,58,5) }
            else { text("↻",49,45,size:23); text(variant == "crossed" ? "↺":"↻",145,46,size:20) }
        case .cam:
            context.beginPath(); context.move(to:p(57,68)); context.addCurve(to:p(137,73),control1:p(48,101),control2:p(144,106)); context.addCurve(to:p(72,37),control1:p(163,36),control2:p(68,2)); context.addCurve(to:p(57,68),control1:p(48,36),control2:p(45,55)); context.strokePath()
            circle(99,73,8); circle(108,20,10); segment(108,10,108,0); text("follower",131,5,size:11)
        case .crank:
            circle(59,59,32); circle(59,59,5); line([p(59,59),p(76,33),p(149,63)]); box(137,50,39,26); segment(120,44,189,44); segment(120,83,189,83); circle(76,33,4)
        case .scissor: segment(24,98,178,98); segment(24,16,178,16); line([p(34,98),p(165,16)]); line([p(165,98),p(34,16)]); circle(100,57,6)
        case .leafSpring:
            for offset in [0.0,9.0,18.0] { context.beginPath(); context.move(to:p(30,34+offset)); context.addQuadCurve(to:p(175,34+offset),control:p(103,105+offset)); context.strokePath() }; circle(30,34,7); circle(175,34,7); box(98,56,13,41)
        case .joint:
            if variant == "ball" { circle(108,57,26); segment(14,57,82,57); line([p(126,26),p(149,26),p(149,89),p(126,89)]); segment(149,57,188,57) }
            else { line([p(15,47),p(69,47),p(69,30),p(107,30),p(107,84),p(69,84),p(69,67),p(15,67)]); line([p(107,44),p(143,44),p(143,70),p(107,70)]); segment(143,57,190,57); circle(107,57,7) }
        case .coupling:
            box(17,44,65,25); box(132,44,57,25); box(82,29,23,54); box(109,29,23,54)
            if variant == "flexible" { line([p(105,30),p(99,43),p(113,55),p(99,67),p(109,82)]) } else { segment(105,40,109,40); segment(105,74,109,74) }
        case .chuck:
            circle(104,57,48); circle(104,57,17)
            for index in 0..<3 { let angle = Double(index)*2 * .pi/3; let x=104+cos(angle)*32,y=57+sin(angle)*32; box(x-8,y-10,16,20) }
        case .manometer:
            line([p(53,13),p(53,86),p(68,101),p(132,101),p(147,86),p(147,13)]); line([p(68,13),p(68,80),p(78,87),p(122,87),p(132,80),p(132,13)])
            let displacement = phase == 0 ? 0 : sin(phase * 2 * .pi) * 9 * pow(max(0, 1-phase), 2)
            let leftLevel = 55-displacement, rightLevel = 35+displacement
            segment(53,leftLevel,68,leftLevel); segment(132,rightLevel,147,rightLevel)
            arrow(175,rightLevel,175,leftLevel,head:5); text("h",183,(rightLevel+leftLevel)/2-8,size:14)
            text(variant == "differential" ? "p₁":"p",44,0,size:14); text(variant == "differential" ? "p₂":"open",137,0,size:13)
        case .hydraulicPress:
            line([p(37,27),p(37,90),p(157,90),p(157,27)]); line([p(56,27),p(56,72),p(124,72),p(124,27)])
            segment(38,50,55,50); segment(124,44,157,44); arrow(46,4,46,47,head:7); arrow(141,44,141,6,head:7); text("F₁",18,13,size:13); text("F₂",164,13,size:13)
        case .accumulator:
            box(71,11,75,84); segment(72,52,145,52); segment(108,95,108,114)
            text("gas",108,22,size:15,center:true); text("fluid",108,66,size:13,center:true)
        case .directionalValve:
            let count = variant == "4/3" ? 3 : 2, size = count == 3 ? 47.0:62.0
            for index in 0..<count { let x=24+Double(index)*size; box(x,31,size,58)
                if count==3 && index==1 { for y in [44.0,75.0] { segment(x+10,y,x+37,y) } }
                else if variant == "2/2" && index==1 { segment(x+15,44,x+45,44); segment(x+15,76,x+45,76) }
                else if index==0 { arrow(x+size*0.3,80,x+size*0.3,41,head:6); if variant != "2/2" { arrow(x+size*0.7,40,x+size*0.7,79,head:6) } }
                else { arrow(x+10,79,x+size-10,41,head:6); if variant.hasPrefix("4") { arrow(x+10,41,x+size-10,79,head:6) } }
            }
            text("P",39,94,size:12); text("A",40,12,size:12); if variant != "2/2" { text("R",82,94,size:12) }; if variant.hasPrefix("4") { text("B",82,12,size:12) }
        case .flowMeter: leads(73,147); circle(110,57,36); arrow(82,57,137,57); text("Q",110,23,size:19,center:true)
        case .frl:
            for (index,name) in ["F","R","L"].enumerated() { let x=22+Double(index)*54; box(x,34,44,45); text(name,x+22,46,size:22,center:true) }; segment(5,57,22,57); segment(66,57,76,57); segment(120,57,130,57); segment(174,57,195,57)
        case .fluidBranch:
            if variant == "tee" { line([p(21,38),p(174,38)]); line([p(21,62),p(90,62),p(90,108)]); line([p(174,62),p(114,62),p(114,108)]) }
            else { line([p(24,29),p(149,29),p(149,107)]); line([p(24,53),p(125,53),p(125,107)]) }
        case .holeDetail:
            line([p(24,35),p(77,35)]); line([p(137,35),p(184,35)]); segment(24,98,184,98)
            if variant == "counterbore" { line([p(77,35),p(77,59),p(91,59),p(91,98)]); line([p(137,35),p(137,59),p(123,59),p(123,98)]); text("⌴",105,2,size:25,center:true) }
            else if variant == "countersink" { line([p(77,35),p(94,58),p(94,98)]); line([p(137,35),p(120,58),p(120,98)]); text("⌵",106,2,size:25,center:true) }
            else if variant == "depth" { line([p(91,35),p(91,75),p(107,86),p(123,75),p(123,35)]); arrow(161,36,161,86,head:6); text("depth",174,50,size:10) }
            else { line([p(24,35),p(24,98)]); line([p(164,35),p(184,56),p(184,98)]); arrow(166,7,175,43,head:6); text("45°",124,4,size:16) }
        case .welding:
            box(29,75,75,12); box(104,75,75,12)
            if variant == "spot" { box(95,28,19,44); box(95,90,19,20); arrow(106,4,106,25,head:6); arrow(106,112,106,92,head:6); circle(106,81,6,fill:true) }
            else if variant == "TIG" { box(98,8,20,40); segment(108,48,108,70); line([p(45,33),p(99,71)]); text("filler",19,9,size:11); text("TIG",131,21,size:12) }
            else if variant == "brazing" { line([p(35,16),p(57,26),p(83,57)]); triangle([p(80,55),p(97,62),p(105,73)]); text("filler",134,33,size:11); segment(170,23,116,74) }
            else { line([p(165,8),p(132,33),p(110,62)]); segment(106,64,104,74); text("wire + gas",15,16,size:12) }
            if variant != "spot" { for angle in [0.3,1.0,2.3] { let x=106+cos(angle)*21,y=72-sin(angle)*21; segment(106,72,x,y) } }
        case .cuttingBeam:
            box(82,11,39,29); box(23,75,160,12); segment(103,40,103,75)
            if variant == "laser" { segment(98,40,98,70); segment(108,40,108,70); text("beam",133,38,size:12) }
            else if variant == "plasma" { triangle([p(93,40),p(113,40),p(103,75)]); text("ionised gas",123,42,size:11) }
            else { context.setLineDash(phase:0,lengths:[3,3]); segment(97,40,97,74); segment(109,40,109,74); context.setLineDash(phase:0,lengths:[]); box(48,97,110,13); text("catch tank",109,95,size:10,center:true) }
        case .rolling:
            circle(110,28,23); circle(110,85,23); line([p(15,52),p(83,52),p(134,55),p(186,55)]); line([p(15,66),p(83,66),p(134,62),p(186,62)]); arrow(19,37,64,37); text("↻",102,15,size:20); text("↺",102,73,size:20)
        case .bending:
            triangle([p(82,8),p(128,8),p(105,57)]); line([p(35,88),p(80,88),p(105,107),p(130,88),p(178,88)]); line([p(39,67),p(84,67),p(105,83),p(128,67),p(169,67)]); arrow(150,10,150,51)
        case .stamping:
            box(78,10,53,38); arrow(160,8,160,56); line([p(24,66),p(84,66),p(84,81),p(128,81),p(128,66),p(184,66)]); box(24,91,160,17); text("punch",42,19,size:12)
        case .inspection:
            box(55,58,102,30); line([p(31,32),p(176,32),p(176,54)]); line([p(53,20),p(53,97),p(73,97)]); line([p(159,32),p(159,97),p(140,97)]); text("mm",98,7,size:18,center:true)
        case .tensileTest:
            line([p(43,35),p(75,35),p(90,48),p(127,48),p(142,35),p(174,35),p(174,82),p(142,82),p(127,68),p(90,68),p(75,82),p(43,82),p(43,35)]); arrow(43,59,10,59); arrow(174,59,197,59); text("F",22,30,size:16); text("F",184,30,size:16)
        case .processBox: processBlock(variant)
        case .lathe:
            box(23,32,34,54); box(57,42,114,32); segment(16,96,185,96); triangle([p(107,98),p(130,70),p(149,98)]); text("rotates ↻",114,14,size:13,center:true)
        case .milling:
            box(29,78,149,26); box(79,20,50,33); for x in stride(from:81.0,through:128,by:9) { triangle([p(x,52),p(x+4,65),p(x+8,52)]) }; arrow(30,69,70,69); text("↻",104,0,size:23,center:true)
        case .drill:
            box(40,82,126,25); line([p(94,12),p(94,63),p(109,80),p(124,63),p(124,12)]); segment(94,30,124,48); segment(94,49,120,66); arrow(156,20,156,64)
        case .saw:
            box(33,83,137,23); segment(18,46,181,46)
            for x in stride(from:19.0,through:170,by:14) { triangle([p(x,46),p(x+7,64),p(x+14,46)]) }; arrow(25,23,160,23)
        case .grinding: circle(105,43,33); circle(105,43,6); box(28,81,150,22); text("↻",154,20,size:24); arrow(35,69,72,69)
        case .press, .forging:
            box(61,20,92,25); box(33,91,147,18); arrow(106,47,106,76)
            if definition.diagram == .press { line([p(49,75),p(82,75),p(96,85),p(121,85),p(135,75),p(169,75)]) }
            else { box(74,77,64,13); text("hot stock",108,2,size:12,center:true) }
        case .mould:
            box(64,24,116,75); context.strokeEllipse(in:CGRect(x:88,y:43,width:65,height:38)); segment(122,24,122,99)
            line([p(15,47),p(64,47)]); arrow(10,63,83,63); text("melt",21,29,size:12)
        case .casting:
            box(47,63,127,43); line([p(98,64),p(98,84),p(133,84),p(133,100)]); line([p(60,13),p(92,22),p(88,47),p(65,40),p(60,13)]); arrow(91,37,101,61); text("pour",124,27,size:13)
        case .extrusion:
            box(20,29,104,61); box(124,23,19,73); box(143,48,45,23); arrow(29,59,88,59); text("die",132,3,size:13,center:true)
        case .additive:
            for index in 0..<4 { box(49+Double(index)*5,94-Double(index)*11,116-Double(index)*10,9) }
            line([p(95,8),p(121,8),p(116,38),p(110,45),p(104,38),p(95,8)]); segment(110,45,110,56); arrow(148,36,179,36)
        }
        let caption = definition.name
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byWordWrapping
        (caption as NSString).draw(in:CGRect(x:5,y:116,width:190,height:34),withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:style])
    }
}
