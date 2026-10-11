import SwiftUI
import Foundation

enum CalculationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

// An arithmetic parser, not evaluation of executable code.
struct ExpressionParser {
    private var characters: [Character]
    private var index = 0
    private var x: Double
    init(_ source: String, x: Double = 0) { characters = Array(source.lowercased().filter { !$0.isWhitespace }); self.x = x }
    mutating func evaluate() throws -> Double {
        guard !characters.isEmpty else { throw CalculationError.invalid("Enter a calculation.") }
        let result = try sum()
        guard index == characters.count else { throw CalculationError.invalid("Unexpected symbol near \(characters[index...]).") }
        guard result.isFinite else { throw CalculationError.invalid("This expression has no finite real result.") }
        return result
    }
    private var current: Character? { index < characters.count ? characters[index] : nil }
    private mutating func consume(_ c: Character) -> Bool { if current == c { index += 1; return true }; return false }
    private mutating func sum() throws -> Double {
        var a = try product()
        while let c = current, c == "+" || c == "-" { index += 1; let b = try product(); a = c == "+" ? a + b : a - b }
        return a
    }
    private mutating func product() throws -> Double {
        var a = try unary()
        while let c = current, c == "*" || c == "/" { index += 1; let b = try unary(); if c == "/" && b == 0 { throw CalculationError.invalid("Cannot divide by zero.") }; a = c == "*" ? a * b : a / b }
        return a
    }
    private mutating func unary() throws -> Double {
        if consume("+") { return try unary() }
        if consume("-") { return try -unary() }
        return try power()
    }
    private mutating func power() throws -> Double {
        let a = try atom()
        if consume("^") { return try pow(a, unary()) }
        return a
    }
    private mutating func atom() throws -> Double {
        if consume("(") { let a = try sum(); guard consume(")") else { throw CalculationError.invalid("Missing closing bracket.") }; return a }
        guard let c = current else { throw CalculationError.invalid("The expression is incomplete.") }
        if c.isNumber || c == "." {
            let start = index
            while let q = current, q.isNumber || q == "." { index += 1 }
            if current == "e", index + 1 < characters.count, characters[index + 1].isNumber || characters[index + 1] == "+" || characters[index + 1] == "-" {
                index += 1
                if current == "+" || current == "-" { index += 1 }
                while let q = current, q.isNumber { index += 1 }
            }
            guard let value = Double(String(characters[start..<index])) else { throw CalculationError.invalid("Invalid number.") }; return value
        }
        if c.isLetter || c == "π" {
            let start = index
            while let q = current, q.isLetter || q == "π" { index += 1 }
            let name = String(characters[start..<index])
            switch name { case "x": return x; case "pi", "π": return .pi; case "e": return M_E; default: break }
            guard consume("(") else { throw CalculationError.invalid("Use a function such as sqrt(16) or sin(pi/2).") }
            let a = try sum(); guard consume(")") else { throw CalculationError.invalid("Missing function closing bracket.") }
            switch name {
            case "sin": return sin(a); case "cos": return cos(a); case "tan": return tan(a)
            case "sqrt": return sqrt(a); case "abs": return abs(a); case "ln": return log(a); case "log": return log10(a)
            case "exp": return exp(a); case "asin": return asin(a); case "acos": return acos(a); case "atan": return atan(a)
            default: throw CalculationError.invalid("Unknown function: \(name).")
            }
        }
        throw CalculationError.invalid("Use numbers, brackets, + − * / ^ and the listed functions.")
    }
}

enum UnitFamily: String, CaseIterable {
    case length = "Length", angle = "Angle", force = "Force", pressure = "Pressure"
    var units: [(String, Double)] {
        switch self {
        case .length: return [("mm", 0.001), ("cm", 0.01), ("m", 1), ("in", 0.0254), ("ft", 0.3048)]
        case .angle: return [("deg", .pi / 180), ("rad", 1)]
        case .force: return [("N", 1), ("kN", 1000), ("lbf", 4.4482216152605)]
        case .pressure: return [("Pa", 1), ("kPa", 1000), ("MPa", 1_000_000), ("bar", 100_000), ("psi", 6894.757293168)]
        }
    }
    func convert(_ value: Double, from: String, to: String) throws -> Double {
        guard let a = units.first(where: { $0.0 == from })?.1, let b = units.first(where: { $0.0 == to })?.1 else { throw CalculationError.invalid("Choose compatible units.") }
        return value * a / b
    }
}

struct EngineeringCalculator: View {
    @ObservedObject var session: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var expression = ""
    @State private var result = ""
    @State private var family = UnitFamily.length
    @State private var from = "mm"
    @State private var to = "m"
    @State private var input = "1000"
    @State private var conversion = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("Engineering calculator").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Offline arithmetic · trigonometric functions use radians").font(.caption).foregroundStyle(.secondary)
            HStack { TextField("e.g. (12^2 + 5^2)^0.5", text: $expression).onSubmit { calculate() }; Button("Calculate") { calculate() } }
            Text(result.isEmpty ? "sqrt · sin · cos · tan · ln · log · abs · exp · pi" : result).font(.system(size: 16, design: .monospaced)).textSelection(.enabled)
            Button("Add result to drawing") { session.add(DrawingElement(kind: .text, points: [.init(x: session.cameraOffset.x + 140, y: session.cameraOffset.y + 180)], color: session.color, text: "\(expression) = \(result)")); dismiss() }.disabled(result.isEmpty || result.hasPrefix("Error:"))
            Divider()
            Text("Unit conversion").font(.headline)
            Picker("Quantity", selection: $family) { ForEach(UnitFamily.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.onChange(of: family) { _, new in from = new.units.first!.0; to = new.units.last!.0; conversion = "" }
            HStack {
                TextField("Value", text: $input).frame(width: 110)
                Picker("From", selection: $from) { ForEach(family.units, id: \.0) { Text($0.0).tag($0.0) } }.labelsHidden()
                Image(systemName: "arrow.right")
                Picker("To", selection: $to) { ForEach(family.units, id: \.0) { Text($0.0).tag($0.0) } }.labelsHidden()
                Button("Convert") { convert() }
            }
            Text(conversion).font(.system(size: 17, weight: .medium, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }.padding(26)
    }
    func calculate() { do { var p = ExpressionParser(expression); result = String(format: "%.10g", try p.evaluate()) } catch { result = "Error: " + error.localizedDescription } }
    func convert() { do { var p = ExpressionParser(input); let value = try family.convert(p.evaluate(), from: from, to: to); conversion = String(format: "%.10g", value) + " " + to } catch { conversion = error.localizedDescription } }
}

struct GraphPlotView: View {
    @ObservedObject var session: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var formula = "sin(x)"
    @State private var xmin = -10.0
    @State private var xmax = 10.0
    @State private var ymin = -5.0
    @State private var ymax = 5.0
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Plot a function").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() } }
            TextField("y =", text: $formula)
            Text("Use x, + − * / ^, pi, sin(x), cos(x), sqrt(x), log(x) or abs(x). Angles use radians.").font(.caption).foregroundStyle(.secondary)
            HStack { Text("x range"); TextField("Min", value: $xmin, format: .number); TextField("Max", value: $xmax, format: .number) }
            HStack { Text("y range"); TextField("Min", value: $ymin, format: .number); TextField("Max", value: $ymax, format: .number) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Spacer()
            Button("Insert graph") { plot() }.buttonStyle(.borderedProminent)
        }.padding(26)
    }
    func plot() {
        guard xmin.isFinite, xmax.isFinite, ymin.isFinite, ymax.isFinite, xmax > xmin, ymax > ymin else { error = "Maximum values must be greater than minimum values."; return }
        let w = max(300, min(session.board.width - 280, 1100)), h = max(220, min(session.board.height - 300, 650))
        let origin = CGPoint(x: session.cameraOffset.x + 140, y: session.cameraOffset.y + 140)
        func map(_ x: Double, _ y: Double) -> InkPoint { .init(x: origin.x + (x - xmin) / (xmax - xmin) * w, y: origin.y + (ymax - y) / (ymax - ymin) * h) }
        var paths: [[InkPoint]] = []; var current: [InkPoint] = []
        for n in 0...800 {
            let x = xmin + (xmax - xmin) * Double(n) / 800
            var parser = ExpressionParser(formula, x: x)
            if let y = try? parser.evaluate(), y >= ymin, y <= ymax {
                let p = map(x, y)
                if let previous = current.last, abs(p.y - previous.y) > h * 0.4 { if current.count > 1 { paths.append(current) }; current = [] }
                current.append(p)
            } else { if current.count > 1 { paths.append(current) }; current = [] }
        }
        if current.count > 1 { paths.append(current) }
        guard !paths.isEmpty else { error = "No finite points in this range. Check the function and axis limits."; return }
        session.checkpoint()
        session.board.elements.append(DrawingElement(kind: .rectangle, points: [map(xmin, ymax), map(xmax, ymin)], color: .graphite, width: 1))
        if xmin <= 0 && xmax >= 0 { session.board.elements.append(.init(kind: .arrow, points: [map(0, ymin), map(0, ymax)], color: .graphite, width: 2)) }
        if ymin <= 0 && ymax >= 0 { session.board.elements.append(.init(kind: .arrow, points: [map(xmin, 0), map(xmax, 0)], color: .graphite, width: 2)) }
        for i in 0...10 {
            let x = xmin + (xmax - xmin) * Double(i) / 10
            let y = ymin + (ymax - ymin) * Double(i) / 10
            let vx = map(x, ymin), vy = map(xmin, y)
            session.board.elements.append(.init(kind: .text, points: [.init(x: vx.x - 12, y: vx.y + 12)], color: .graphite, text: String(format: "%.2g", x), fontSize: 17))
            session.board.elements.append(.init(kind: .text, points: [.init(x: vy.x - 52, y: vy.y - 9)], color: .graphite, text: String(format: "%.2g", y), fontSize: 17))
        }
        for path in paths { session.board.elements.append(.init(kind: .stroke, points: path, color: session.color, width: 3)) }
        session.board.elements.append(.init(kind: .text, points: [.init(x: origin.x, y: origin.y - 40)], color: session.color, text: "y = \(formula)", fontSize: 26))
        session.changed(); dismiss()
    }
}
