import Foundation

enum SymbolCategory: String, Codable, CaseIterable, Identifiable {
    case algebra = "Algebra", calculus = "Calculus", greek = "Greek letters", geometry = "Geometry", statistics = "Statistics"
    case electrical = "Electrical", electronics = "Electronics", logic = "Digital logic", mechanics = "Mechanics"
    case fluids = "Fluids", drawing = "Technical drawing", manufacturing = "Manufacturing"
    var id: String { rawValue }
    var topic: String {
        switch self {
        case .algebra, .geometry: return "Engineering maths and trigonometry"
        case .calculus: return "Calculus and engineering functions"
        case .greek: return "Mathematical notation and engineering quantities"
        case .statistics: return "Measurement, statistics and quality"
        case .electrical: return "Electrical principles and circuit diagrams"
        case .electronics: return "Electronic devices and circuits"
        case .logic: return "Digital circuits and control"
        case .mechanics: return "Mechanical principles and forces"
        case .fluids: return "Fluid systems and thermodynamics"
        case .drawing: return "Technical product drawings"
        case .manufacturing: return "Materials and manufacturing processes"
        }
    }
}

enum DiagramKind: String, Codable {
    case glyph
    case resistor, variableResistor, thermistor, ldr, capacitor, polarizedCapacitor, variableCapacitor, inductor, transformer
    case cell, battery, ground, earth, acSource, dcSource, currentSource, switchOpen, switchClosed, switchChangeover, pushButton, fuse, lamp
    case ammeter, voltmeter, ohmmeter, motor, generator, junction, crossing
    case diode, led, photodiode, zener, schottky, transistorNPN, transistorPNP, mosfetN, mosfetP, opAmp, relay, rectifier, thyristor
    case logicAnd, logicOr, logicNot, logicNand, logicNor, logicXor, logicXnor, logicBuffer, logicBlock, clock
    case beamSimple, beamCantilever, beamFixed, pointLoad, distributedLoad, forceArrow, moment, tension, compression, shear
    case spring, damper, mass, pulley, gear, gearPair, shaft, bearing, lever, friction, freeBody, inclinedPlane
    case pipeFlow, pump, turbine, valve, checkValve, tank, piston, filter, heatExchanger, nozzle, venturi, pressureGauge, compressor
    case centreLine, hiddenLine, dimension, angularDimension, diameter, radius, sectionHatch, cuttingPlane, datum, surfaceFinish, weld, toleranceFrame, projection
    case processBox, lathe, milling, drill, saw, grinding, press, mould, casting, extrusion, forging, additive
    case voltageDivider, bridge, breaker, jfet, optocoupler, triac, crystal, speaker, sensor
    case support, rackPinion, wormGear, bevelGear, planetaryGear, belt, chain, cam, crank, scissor, leafSpring, joint, coupling, chuck
    case manometer, hydraulicPress, accumulator, directionalValve, flowMeter, frl, fluidBranch
    case holeDetail, welding, cuttingBeam, rolling, bending, stamping, inspection, tensileTest
    var animated: Bool { [.motor, .generator, .gearPair, .pipeFlow, .pump, .turbine, .manometer].contains(self) }
}

struct SymbolDefinition: Codable, Identifiable, Hashable {
    var id: String
    var category: SymbolCategory
    var name: String
    var keywords: [String]
    var diagram: DiagramKind
    var glyph: String = ""
    var variant: String = ""
    var source: String { category == .electrical || category == .electronics || category == .logic ? "Teaching schematic; check the required circuit convention." : "Learning diagram; check the convention required by your project." }
}

enum SymbolCatalog {
    // This is a curated teaching toolbox, not a popularity ranking or a certified
    // implementation of IEC/ISO symbols. Entries have stable, independent IDs.
    static let referenceURLs: [(String, String)] = [
        ("IEC 60617: official diagram-symbol database", "https://webstore.iec.ch/en/publication/2723")
    ]

    private static func glyphs(_ category: SymbolCategory, _ source: String) -> [SymbolDefinition] {
        source.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            let keywords = fields.count > 3 ? fields[3].split(separator: ",").map(String.init) : []
            return SymbolDefinition(id: "\(category.id)-\(fields[0])", category: category, name: fields[1], keywords: keywords,
                                    diagram: .glyph, glyph: fields[2])
        }
    }

    private static func diagrams(_ category: SymbolCategory, _ entries: [(String, String, DiagramKind, String)]) -> [SymbolDefinition] {
        entries.map { SymbolDefinition(id: "\(category.id)-\($0.0)", category: category, name: $0.1,
                                      keywords: ($0.0 + " " + $0.1 + " " + category.topic).lowercased().split(separator: " ").map(String.init),
                                      diagram: $0.2, variant: $0.3) }
    }

    static let all: [SymbolDefinition] = {
        var items: [SymbolDefinition] = []
        items += glyphs(.algebra, """
        plus|Addition|+|sum,add
        minus|Subtraction|−|subtract,difference
        multiply|Multiplication|×|product,times
        divide|Division|÷|ratio,divide
        equals|Equality|=|equal
        unequal|Not equal|≠|inequality
        approximately|Approximately equal|≈|estimate,rounding
        equivalent|Equivalent|≡|identity
        proportional|Proportional to|∝|proportionality
        less|Less than|<|inequality
        greater|Greater than|>|inequality
        less-equal|Less than or equal|≤|inequality
        greater-equal|Greater than or equal|≥|inequality
        plus-minus|Plus or minus|±|tolerance,uncertainty
        minus-plus|Minus or plus|∓|paired sign
        square-root|Square root|√x|root
        cube-root|Cube root|∛x|root
        nth-root|Nth root|ⁿ√x|root
        square|Square power|x²|power,index
        cube|Cube power|x³|power,index
        power|General power|xⁿ|index,exponent
        fraction|Fraction|a/b|ratio,numerator,denominator
        percent|Percentage|%|ratio
        infinity|Infinity|∞|limit
        absolute|Absolute value|∣x∣|magnitude
        factorial|Factorial|n!|combinations
        natural-log|Natural logarithm|ln x|logarithm
        decimal-log|Base-ten logarithm|log₁₀ x|logarithm
        exponential|Exponential function|eˣ|growth
        vector|Vector notation|v⃗|direction,magnitude
        dot-product|Scalar product|a · b|dot product
        cross-product|Vector product|a × b|cross product
        matrix|Matrix|A = [a b; c d]|array
        determinant|Determinant|det A|matrix
        transpose|Transpose|Aᵀ|matrix
        inverse|Inverse matrix|A⁻¹|matrix
        identity-matrix|Identity matrix|I₂ = [1 0; 0 1]|matrix
        implication|Implies|⇒|logic
        equivalence|If and only if|⇔|logic
        belongs|Element of|∈|set
        union|Set union|∪|set
        intersection|Set intersection|∩|set
        empty-set|Empty set|∅|set
        real-numbers|Real numbers|ℝ|set
        complex-numbers|Complex numbers|ℂ|set
        integers|Integers|ℤ|set
        imaginary|Imaginary unit|j = √−1|electrical,complex
        conjugate|Complex conjugate|z̄|complex
        """)
        items += glyphs(.calculus, """
        derivative|First derivative|dy/dx|rate,gradient
        second-derivative|Second derivative|d²y/dx²|acceleration
        nth-derivative|Nth derivative|dⁿy/dxⁿ|derivative
        partial|Partial derivative|∂f/∂x|multivariable
        time-derivative|Time derivative|ẋ|velocity
        second-time|Second time derivative|ẍ|acceleration
        indefinite-integral|Indefinite integral|∫ f(x) dx|integration
        definite-integral|Definite integral|∫ₐᵇ f(x) dx|area
        double-integral|Double integral|∬ f dA|area
        triple-integral|Triple integral|∭ f dV|volume
        contour-integral|Closed-path integral|∮ f ds|contour
        limit|Limit|lim x→a|continuity
        gradient|Gradient operator|∇f|vector calculus
        divergence|Divergence|∇ · F|vector calculus
        curl|Curl|∇ × F|vector calculus
        laplacian|Laplacian|∇²f|differential
        summation|Summation|∑ₖ aₖ|series
        product|Product notation|∏ₖ aₖ|series
        differential|Differential|dx|small change
        delta|Finite change|Δx|change
        differential-equation|First-order ODE|dy/dx + ay = b|differential equation
        taylor|Taylor expansion|f(a) + f′(a)(x−a) + …|series
        """)
        let greek: [(String, String, String)] = [
            ("alpha", "α", "Α"), ("beta", "β", "Β"), ("gamma", "γ", "Γ"), ("delta", "δ", "Δ"),
            ("epsilon", "ε", "Ε"), ("zeta", "ζ", "Ζ"), ("eta", "η", "Η"), ("theta", "θ", "Θ"),
            ("iota", "ι", "Ι"), ("kappa", "κ", "Κ"), ("lambda", "λ", "Λ"), ("mu", "μ", "Μ"),
            ("nu", "ν", "Ν"), ("xi", "ξ", "Ξ"), ("omicron", "ο", "Ο"), ("pi", "π", "Π"),
            ("rho", "ρ", "Ρ"), ("sigma", "σ", "Σ"), ("tau", "τ", "Τ"), ("upsilon", "υ", "Υ"),
            ("phi", "φ", "Φ"), ("chi", "χ", "Χ"), ("psi", "ψ", "Ψ"), ("omega", "ω", "Ω")
        ]
        for (name, lower, upper) in greek {
            items.append(SymbolDefinition(id: "greek-\(name)-lower", category: .greek, name: "\(name.capitalized) · lowercase", keywords: [name, "greek", "lowercase"], diagram: .glyph, glyph: lower))
            items.append(SymbolDefinition(id: "greek-\(name)-upper", category: .greek, name: "\(name.capitalized) · uppercase", keywords: [name, "greek", "uppercase"], diagram: .glyph, glyph: upper))
        }
        items += glyphs(.geometry, """
        angle|Angle|∠ABC|degrees
        right-angle|Right angle|90°|perpendicular
        degree|Degree|°|angle
        radians|Radians|rad|angle
        parallel|Parallel|∥|lines
        perpendicular|Perpendicular|⊥|lines
        congruent|Congruent|≅|same shape
        similar|Similar|∼|shape
        pi|Pi constant|π|circle
        sine|Sine ratio|sin θ = O/H|triangle
        cosine|Cosine ratio|cos θ = A/H|triangle
        tangent|Tangent ratio|tan θ = O/A|triangle
        pythagoras|Pythagoras|a² + b² = c²|right triangle
        circle-area|Circle area|A = πr²|circle
        circumference|Circumference|C = 2πr|circle
        triangle-area|Triangle area|A = ½bh|triangle
        sphere-volume|Sphere volume|V = ⁴⁄₃πr³|volume
        cylinder-volume|Cylinder volume|V = πr²h|volume
        sine-rule|Sine rule|a/sin A = b/sin B|triangle
        cosine-rule|Cosine rule|c² = a²+b²−2ab cos C|triangle
        """)
        items += glyphs(.statistics, """
        mean|Mean|x̄ = ∑x/n|average
        median|Median|median(x)|middle,average
        variance|Population variance|σ²|spread
        standard-deviation|Standard deviation|σ|spread
        sample-deviation|Sample standard deviation|s|sample
        probability|Probability|P(A)|chance
        conditional|Conditional probability|P(A given B)|chance
        expected|Expected value|E[X]|probability
        covariance|Covariance|Cov(X,Y)|correlation
        correlation|Correlation coefficient|r|relationship
        regression|Linear regression|y = mx + c|best fit
        normal|Normal distribution|N(μ,σ²)|gaussian
        sample-size|Sample size|n|sample
        range|Range|xₘₐₓ − xₘᵢₙ|spread
        uncertainty|Measurement uncertainty|x ± u|measurement
        confidence|Confidence interval|CI|estimate
        upper-limit|Upper control limit|UCL|quality
        lower-limit|Lower control limit|LCL|quality
        """)
        items += diagrams(.electrical, [
            ("resistor", "Resistor · rectangular", .resistor, "rectangle"), ("resistor-zigzag", "Resistor · zigzag", .resistor, "zigzag"),
            ("variable-resistor", "Variable resistor", .variableResistor, ""), ("potentiometer", "Potentiometer", .variableResistor, "potentiometer"),
            ("thermistor", "Thermistor", .thermistor, ""), ("ldr", "Light-dependent resistor", .ldr, ""),
            ("capacitor", "Capacitor", .capacitor, ""), ("polarized-capacitor", "Polarised capacitor", .polarizedCapacitor, ""),
            ("variable-capacitor", "Variable capacitor", .variableCapacitor, ""), ("inductor", "Inductor", .inductor, ""),
            ("transformer", "Transformer", .transformer, ""), ("cell", "Cell", .cell, ""), ("battery", "Battery", .battery, ""),
            ("signal-ground", "Signal ground", .ground, ""), ("protective-earth", "Protective earth", .earth, ""),
            ("ac-source", "AC voltage source", .acSource, ""), ("dc-source", "DC voltage source", .dcSource, ""),
            ("current-source", "Current source", .currentSource, ""), ("open-switch", "Open switch", .switchOpen, ""),
            ("closed-switch", "Closed switch", .switchClosed, ""), ("changeover-switch", "Changeover switch", .switchChangeover, ""),
            ("pushbutton-no", "Pushbutton · normally open", .pushButton, "NO"), ("pushbutton-nc", "Pushbutton · normally closed", .pushButton, "NC"),
            ("fuse", "Fuse", .fuse, ""), ("lamp", "Lamp", .lamp, ""), ("ammeter", "Ammeter", .ammeter, ""),
            ("voltmeter", "Voltmeter", .voltmeter, ""), ("ohmmeter", "Ohmmeter", .ohmmeter, ""),
            ("motor", "Motor", .motor, ""), ("generator", "Generator", .generator, ""),
            ("wire-junction", "Connected wire junction", .junction, ""), ("wire-crossing", "Unconnected wire crossing", .crossing, "")
        ])
        items += diagrams(.electronics, [
            ("diode", "Diode", .diode, ""), ("led", "Light-emitting diode", .led, ""),
            ("photodiode", "Photodiode", .photodiode, ""), ("zener", "Zener diode", .zener, ""), ("schottky", "Schottky diode", .schottky, ""),
            ("npn", "NPN transistor", .transistorNPN, ""), ("pnp", "PNP transistor", .transistorPNP, ""),
            ("nmos", "N-channel MOSFET", .mosfetN, ""), ("pmos", "P-channel MOSFET", .mosfetP, ""),
            ("opamp", "Operational amplifier", .opAmp, ""), ("comparator", "Comparator", .opAmp, "comparator"),
            ("relay", "Relay coil and contact", .relay, ""), ("bridge", "Bridge rectifier", .rectifier, "bridge"),
            ("half-wave", "Half-wave rectifier circuit", .rectifier, "half"), ("thyristor", "Thyristor", .thyristor, ""),
            ("inverting", "Inverting amplifier", .opAmp, "inverting"), ("noninverting", "Non-inverting amplifier", .opAmp, "noninverting"),
            ("integrator", "Integrator amplifier", .opAmp, "integrator"), ("differentiator", "Differentiator amplifier", .opAmp, "differentiator"),
            ("rc-lowpass", "RC low-pass filter", .processBox, "RC low-pass"), ("rc-highpass", "RC high-pass filter", .processBox, "RC high-pass")
        ])
        items += diagrams(.logic, [
            ("and", "AND gate", .logicAnd, ""), ("or", "OR gate", .logicOr, ""), ("not", "NOT gate", .logicNot, ""),
            ("nand", "NAND gate", .logicNand, ""), ("nor", "NOR gate", .logicNor, ""), ("xor", "XOR gate", .logicXor, ""),
            ("xnor", "XNOR gate", .logicXnor, ""), ("buffer", "Buffer gate", .logicBuffer, ""),
            ("d-flipflop", "D-type flip-flop", .logicBlock, "D|CLK|Q|Q̄"), ("sr-latch", "SR latch", .logicBlock, "S|R|Q|Q̄"),
            ("jk-flipflop", "JK flip-flop", .logicBlock, "J|K|Q|Q̄"), ("multiplexer", "2-to-1 multiplexer", .logicBlock, "0|1|Y|S"),
            ("clock", "Clock signal", .clock, ""), ("counter", "Binary counter", .logicBlock, "CLK|RST|Q₀|Q₁")
        ])
        items += diagrams(.mechanics, [
            ("simple-beam", "Simply supported beam", .beamSimple, ""), ("cantilever", "Cantilever beam", .beamCantilever, ""),
            ("fixed-beam", "Fixed-ended beam", .beamFixed, ""), ("point-load", "Beam with point load", .pointLoad, ""),
            ("udl", "Uniformly distributed load", .distributedLoad, "uniform"), ("triangular-load", "Triangular distributed load", .distributedLoad, "triangular"),
            ("force", "Force vector", .forceArrow, "F"), ("weight", "Weight force", .forceArrow, "W = mg"),
            ("reaction", "Reaction force", .forceArrow, "R"), ("moment", "Moment", .moment, "M = Fd"),
            ("torque", "Shaft torque", .moment, "T"), ("tension", "Tension", .tension, ""), ("compression", "Compression", .compression, ""),
            ("shear", "Shear loading", .shear, ""), ("spring", "Spring", .spring, "k"), ("damper", "Viscous damper", .damper, "c"),
            ("mass", "Mass block", .mass, "m"), ("pulley", "Fixed pulley", .pulley, ""), ("gear", "Gear wheel", .gear, ""),
            ("gear-pair", "Meshing gears", .gearPair, ""), ("shaft", "Shaft", .shaft, ""), ("bearing", "Rolling bearing", .bearing, ""),
            ("lever", "Lever and fulcrum", .lever, ""), ("friction", "Friction on a surface", .friction, ""),
            ("free-body", "Free-body diagram", .freeBody, ""), ("inclined-plane", "Inclined plane", .inclinedPlane, "")
        ])
        items += diagrams(.fluids, [
            ("flow", "Flow through a pipe", .pipeFlow, ""), ("pump", "Pump", .pump, ""), ("turbine", "Turbine", .turbine, ""),
            ("shutoff", "Shut-off valve", .valve, "shut-off"), ("control-valve", "Control valve", .valve, "control"),
            ("check-valve", "Non-return valve", .checkValve, ""), ("relief-valve", "Pressure-relief valve", .valve, "relief"),
            ("tank-open", "Open tank", .tank, "open"), ("tank-closed", "Closed tank", .tank, "closed"),
            ("single-cylinder", "Single-acting cylinder", .piston, "single"), ("double-cylinder", "Double-acting cylinder", .piston, "double"),
            ("filter", "Fluid filter", .filter, ""), ("heat-exchanger", "Heat exchanger", .heatExchanger, ""),
            ("nozzle", "Converging nozzle", .nozzle, "converging"), ("diffuser", "Diverging diffuser", .nozzle, "diverging"),
            ("venturi", "Venturi tube", .venturi, ""), ("pressure-gauge", "Pressure gauge", .pressureGauge, ""),
            ("compressor", "Compressor", .compressor, ""), ("reservoir", "Hydraulic reservoir", .tank, "reservoir"),
            ("orifice", "Orifice restriction", .nozzle, "orifice")
        ])
        items += diagrams(.drawing, [
            ("centre-line", "Centre line", .centreLine, ""), ("hidden-line", "Hidden line", .hiddenLine, ""),
            ("linear-dimension", "Linear dimension", .dimension, ""), ("angular-dimension", "Angular dimension", .angularDimension, ""),
            ("diameter", "Diameter callout", .diameter, ""), ("radius", "Radius callout", .radius, ""),
            ("section", "Section hatching", .sectionHatch, ""), ("cutting-plane", "Cutting plane A–A", .cuttingPlane, ""),
            ("datum", "Datum marker", .datum, "A"), ("surface-finish", "Surface texture mark", .surfaceFinish, "Ra"),
            ("fillet-weld", "Fillet weld callout", .weld, "fillet"), ("butt-weld", "Butt weld callout", .weld, "butt"),
            ("position-tolerance", "Position tolerance frame", .toleranceFrame, "⌖|0.1|A"),
            ("flatness-tolerance", "Flatness tolerance frame", .toleranceFrame, "▱|0.05"),
            ("parallel-tolerance", "Parallelism tolerance frame", .toleranceFrame, "∥|0.1|A"),
            ("perpendicular-tolerance", "Perpendicularity tolerance frame", .toleranceFrame, "⊥|0.1|A"),
            ("concentric-tolerance", "Concentricity tolerance frame", .toleranceFrame, "◎|0.1|A"),
            ("first-angle", "First-angle projection teaching diagram", .projection, "first"),
            ("third-angle", "Third-angle projection teaching diagram", .projection, "third")
        ])
        items += diagrams(.manufacturing, [
            ("turning", "Turning process sketch", .lathe, ""), ("milling", "Milling process sketch", .milling, ""),
            ("drilling", "Drilling process sketch", .drill, ""), ("sawing", "Sawing process sketch", .saw, ""),
            ("grinding", "Grinding process sketch", .grinding, ""), ("pressing", "Sheet pressing sketch", .press, ""),
            ("injection-moulding", "Injection moulding sketch", .mould, ""), ("casting", "Casting process sketch", .casting, ""),
            ("extrusion", "Extrusion process sketch", .extrusion, ""), ("forging", "Forging process sketch", .forging, ""),
            ("additive", "Additive layer process sketch", .additive, ""), ("heat-treatment", "Heat treatment process block", .processBox, "Heat → hold → cool")
        ])
        items += diagrams(.electrical, [
            ("motor-ac", "AC motor", .motor, "AC"), ("motor-dc", "DC motor", .motor, "DC"),
            ("motor-three-phase", "Three-phase motor", .motor, "3~"), ("stepper", "Stepper motor teaching sketch", .motor, "stepper"),
            ("servo", "Servo motor with feedback", .motor, "servo"), ("three-phase-source", "Three-phase supply", .acSource, "3~"),
            ("circuit-breaker", "Circuit breaker", .breaker, ""), ("relay-no", "Relay contact · normally open", .switchOpen, "relay"),
            ("voltage-divider", "Voltage divider", .voltageDivider, ""), ("wheatstone", "Wheatstone bridge", .bridge, "resistors")
        ])
        items += diagrams(.electronics, [
            ("jfet-n", "N-channel JFET", .jfet, "N"), ("jfet-p", "P-channel JFET", .jfet, "P"),
            ("phototransistor", "Phototransistor", .transistorNPN, "photo"), ("optocoupler", "Optocoupler", .optocoupler, ""),
            ("triac", "TRIAC", .triac, "TRIAC"), ("diac", "DIAC", .triac, "DIAC"),
            ("crystal", "Quartz crystal", .crystal, ""), ("speaker", "Loudspeaker", .speaker, ""),
            ("hall-sensor", "Hall-effect sensor", .sensor, "Hall"), ("temperature-sensor", "Temperature sensor", .sensor, "T°")
        ])
        items += diagrams(.mechanics, [
            ("pin-support", "Pinned support", .support, "pin"), ("roller-support", "Roller support", .support, "roller"),
            ("fixed-support", "Fixed support", .support, "fixed"), ("pivot", "Pivot and fulcrum", .support, "pivot"),
            ("rack-pinion", "Rack and pinion", .rackPinion, ""), ("worm-gear", "Worm gear teaching sketch", .wormGear, ""),
            ("bevel-gear", "Bevel gear teaching sketch", .bevelGear, ""), ("planetary-gear", "Planetary gear train", .planetaryGear, ""),
            ("belt-drive", "Belt drive", .belt, "open"), ("crossed-belt", "Crossed belt drive", .belt, "crossed"),
            ("chain-drive", "Chain and sprockets", .chain, ""), ("cam-follower", "Cam and follower", .cam, ""),
            ("slider-crank", "Slider-crank mechanism", .crank, ""), ("scissor", "Scissor linkage", .scissor, ""),
            ("leaf-spring", "Leaf spring", .leafSpring, ""), ("universal-joint", "Universal joint", .joint, "universal"),
            ("ball-joint", "Ball joint", .joint, "ball"), ("rigid-coupling", "Rigid shaft coupling", .coupling, "rigid"),
            ("flexible-coupling", "Flexible shaft coupling", .coupling, "flexible"), ("three-jaw-chuck", "Three-jaw chuck", .chuck, "")
        ])
        items += diagrams(.fluids, [
            ("u-manometer", "U-tube manometer", .manometer, "open"), ("differential-manometer", "Differential manometer", .manometer, "differential"),
            ("hydraulic-press", "Hydraulic press", .hydraulicPress, ""), ("accumulator", "Hydraulic accumulator", .accumulator, ""),
            ("valve22", "2/2 directional valve teaching diagram", .directionalValve, "2/2"),
            ("valve32", "3/2 directional valve teaching diagram", .directionalValve, "3/2"),
            ("valve42", "4/2 directional valve teaching diagram", .directionalValve, "4/2"),
            ("valve43", "4/3 directional valve teaching diagram", .directionalValve, "4/3"),
            ("ball-valve", "Ball valve teaching sketch", .valve, "ball"), ("butterfly-valve", "Butterfly valve teaching sketch", .valve, "butterfly"),
            ("needle-valve", "Needle valve teaching sketch", .valve, "needle"), ("gate-valve", "Gate valve teaching sketch", .valve, "gate"),
            ("flow-meter", "Flow meter", .flowMeter, ""), ("frl-unit", "Filter regulator lubricator unit", .frl, ""),
            ("tee-branch", "Tee pipe branch", .fluidBranch, "tee"), ("pipe-elbow", "Pipe elbow", .fluidBranch, "elbow")
        ])
        items += diagrams(.drawing, [
            ("counterbore", "Counterbore detail", .holeDetail, "counterbore"), ("countersink", "Countersink detail", .holeDetail, "countersink"),
            ("blind-depth", "Blind-hole depth detail", .holeDetail, "depth"), ("chamfer", "Chamfer detail", .holeDetail, "chamfer"),
            ("roundness", "Roundness tolerance teaching frame", .toleranceFrame, "○|0.05"),
            ("cylindricity", "Cylindricity tolerance teaching frame", .toleranceFrame, "⌭|0.05"),
            ("straightness", "Straightness tolerance teaching frame", .toleranceFrame, "—|0.05"),
            ("line-profile", "Line-profile tolerance teaching frame", .toleranceFrame, "⌒|0.1|A"),
            ("surface-profile", "Surface-profile tolerance teaching frame", .toleranceFrame, "⌓|0.1|A"),
            ("angularity", "Angularity tolerance teaching frame", .toleranceFrame, "∠|0.1|A"),
            ("circular-runout", "Circular-runout tolerance teaching frame", .toleranceFrame, "↗|0.1|A"),
            ("total-runout", "Total-runout tolerance teaching frame", .toleranceFrame, "⇗|0.1|A")
        ])
        items += diagrams(.manufacturing, [
            ("mig", "MIG welding teaching sketch", .welding, "MIG"), ("tig", "TIG welding teaching sketch", .welding, "TIG"),
            ("resistance-weld", "Resistance spot welding sketch", .welding, "spot"), ("brazing", "Brazing teaching sketch", .welding, "brazing"),
            ("laser-cut", "Laser cutting sketch", .cuttingBeam, "laser"), ("plasma-cut", "Plasma cutting sketch", .cuttingBeam, "plasma"),
            ("waterjet", "Waterjet cutting sketch", .cuttingBeam, "waterjet"), ("rolling", "Rolling process sketch", .rolling, ""),
            ("bending", "Sheet bending sketch", .bending, ""), ("stamping", "Stamping process sketch", .stamping, ""),
            ("inspection", "Dimensional inspection sketch", .inspection, ""), ("tensile-test", "Tensile testing sketch", .tensileTest, "")
        ])
        return items
    }()

    private static let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func definition(id: String) -> SymbolDefinition? { index[id] }
    static func search(_ query: String, category: SymbolCategory? = nil) -> [SymbolDefinition] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return all.filter { item in
            guard category == nil || item.category == category else { return false }
            let text = ([item.name, item.glyph, item.category.rawValue, item.category.topic] + item.keywords).joined(separator: " ")
            return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }
}
