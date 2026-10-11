import AppKit
import SwiftUI

/// A native, editable subset of maths notation. It does not execute TeX code.
indirect enum MathNode {
    case text(String)
    case row([MathNode])
    case fraction(MathNode, MathNode)
    case root(MathNode)
    case scripts(MathNode, MathNode?, MathNode?)
}

struct MathParser {
    private let source: String
    private var chars: [Character]
    private var position = 0
    private var depth = 0
    private var failure: String?
    static let maximumSourceLength = 4096
    static let commands = ["alpha":"α", "beta":"β", "gamma":"γ", "delta":"δ", "epsilon":"ε", "theta":"θ", "lambda":"λ", "mu":"μ", "nu":"ν", "pi":"π", "rho":"ρ", "sigma":"σ", "tau":"τ", "phi":"φ", "omega":"ω", "Delta":"Δ", "Sigma":"Σ", "Omega":"Ω", "Phi":"Φ", "int":"∫", "iint":"∬", "sum":"∑", "prod":"∏", "infty":"∞", "times":"×", "cdot":"·", "pm":"±", "leq":"≤", "geq":"≥", "neq":"≠", "approx":"≈", "partial":"∂", "nabla":"∇", "degree":"°", "rightarrow":"→", "leftarrow":"←", "sin":"sin", "cos":"cos", "tan":"tan", "ln":"ln", "log":"log"]
    init(_ source: String) {
        self.source = source
        chars = source.prefix(Self.maximumSourceLength + 1).count > Self.maximumSourceLength ? [] : Array(source)
    }
    static func validationError(for source: String) -> String? {
        var parser = Self(source)
        _ = parser.parseSource()
        return parser.failure
    }
    mutating func parse() -> MathNode {
        let node = parseSource()
        return failure == nil ? node : .text(source)
    }
    private mutating func parseSource() -> MathNode {
        guard source.prefix(Self.maximumSourceLength + 1).count <= Self.maximumSourceLength else {
            failure = "Maths source exceeds 4096 characters. The original source has been kept; shorten it before inserting."
            return .text(source)
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failure = "Enter some maths notation."
            return .text(source)
        }
        return row(inGroup: false)
    }
    private mutating func fail(_ message: String) { if failure == nil { failure = message } }
    private var current: Character? { position < chars.count ? chars[position] : nil }
    private mutating func row(inGroup: Bool) -> MathNode {
        var result: [MathNode] = []
        while let c = current {
            if c == "}" {
                if inGroup { break }
                fail("There's a closing brace without an opening brace.")
                position += 1
                continue
            }
            var node = atom()
            var sup: MathNode?, sub: MathNode?
            while current == "^" || current == "_" {
                let sign = current!; position += 1
                let value = argument()
                if sign == "^" {
                    if sup != nil { fail("A base has more than one superscript. Use braces to make the intended nesting clear.") }
                    else { sup = value }
                } else {
                    if sub != nil { fail("A base has more than one subscript. Use braces to make the intended nesting clear.") }
                    else { sub = value }
                }
            }
            if sup != nil || sub != nil { node = .scripts(node, sup, sub) }
            result.append(node)
        }
        return .row(result)
    }
    private mutating func atom() -> MathNode {
        guard let c = current else { return .text("") }
        position += 1
        if c == "^" || c == "_" {
            fail("A superscript or subscript needs a base and a value.")
            return .text(String(c))
        }
        if c == "{" {
            depth += 1
            guard depth <= 24 else {
                fail("Maths groups are nested too deeply. Simplify this expression.")
                depth -= 1
                return .text("{")
            }
            let n = row(inGroup: true)
            if current == "}" { position += 1 } else { fail("There's an opening brace without a closing brace.") }
            depth -= 1
            return n
        }
        if c == "\\" {
            var name = ""
            while let q = current, q.isLetter { name.append(q); position += 1 }
            if name == "frac" { let top = argument(); let bottom = argument(); return .fraction(top, bottom) }
            if name == "sqrt" {
                skipWhitespace()
                if current == "[" { fail("Indexed roots aren't supported in this native subset. The source is shown literally.") }
                return .root(argument())
            }
            if name == "text" || name == "mathrm" { return literalArgument() }
            if name == "left" || name == "right" { return argument() }
            if name.isEmpty, let q = current {
                position += 1
                if ["{", "}", "_", "^", "%", "#", "&", "\\", " "].contains(q) { return .text(String(q)) }
                fail("Unsupported escape \\" + String(q) + ". The source is shown literally.")
                return .text("\\" + String(q))
            }
            if let text = Self.commands[name] { return .text(text) }
            fail("Unsupported command \\" + name + ". The source is shown literally; edit it before inserting.")
            return .text("\\" + name)
        }
        return .text(String(c))
    }
    private mutating func skipWhitespace() { while let c = current, c.isWhitespace { position += 1 } }
    private mutating func argument() -> MathNode {
        skipWhitespace()
        guard let c = current, c != "}" else {
            fail("A command or script is missing its value.")
            return .text("")
        }
        return atom()
    }
    private mutating func literalArgument() -> MathNode {
        skipWhitespace()
        guard current == "{" else { fail("Use braces around text or roman notation."); return argument() }
        position += 1
        var text = "", nesting = 1
        while let c = current {
            position += 1
            if c == "\\", let escaped = current, ["{", "}", "_", "^", "%", "#", "&", "\\"].contains(escaped) {
                text.append(escaped); position += 1; continue
            }
            if c == "{" { nesting += 1 }
            if c == "}" {
                nesting -= 1
                if nesting == 0 { return .text(text) }
            }
            text.append(c)
        }
        fail("The text group is missing its closing brace.")
        return .text(text)
    }
}

@MainActor
enum NativeMathRenderer {
    private static func font(_ size: CGFloat) -> NSFont { NSFont(name: "STIX Two Math", size: size) ?? NSFont(name: "TimesNewRomanPSMT", size: size) ?? .systemFont(ofSize: size) }
    static func size(_ node: MathNode, fontSize f: CGFloat) -> CGSize {
        switch node {
        case .text(let s): return (s as NSString).size(withAttributes: [.font: font(f)])
        case .row(let nodes): let sizes = nodes.map { size($0, fontSize: f) }; return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? f)
        case .fraction(let a, let b): let top = size(a, fontSize: f * 0.85), bottom = size(b, fontSize: f * 0.85); return CGSize(width: max(top.width, bottom.width) + 12, height: top.height + bottom.height + 12)
        case .root(let a): let s = size(a, fontSize: f); return CGSize(width: s.width + f * 0.8, height: s.height + 5)
        case .scripts(let a, let sup, let sub): let base = size(a, fontSize: f), top = sup.map { size($0, fontSize: f * 0.62) } ?? .zero, bottom = sub.map { size($0, fontSize: f * 0.62) } ?? .zero; return CGSize(width: base.width + max(top.width, bottom.width), height: max(base.height, base.height * 0.6 + top.height + bottom.height * 0.6))
        }
    }
    static func draw(latex: String, in rect: CGRect, context: CGContext, color: NSColor) {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return }
        if latex.prefix(MathParser.maximumSourceLength + 1).count > MathParser.maximumSourceLength {
            ("Maths source is too long. Edit the original source to shorten it." as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: color])
            return
        }
        var parser = MathParser(latex); let node = parser.parse()
        let measure = size(node, fontSize: 36)
        let scale = min(rect.width / max(1, measure.width), rect.height / max(1, measure.height))
        guard scale.isFinite, scale > 0 else { return }
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.minY); context.scaleBy(x: scale, y: scale)
        draw(node, at: .zero, f: 36, color: color, context: context); context.restoreGState()
    }
    private static func draw(_ node: MathNode, at p: CGPoint, f: CGFloat, color: NSColor, context: CGContext) {
        let own = size(node, fontSize: f)
        switch node {
        case .text(let s): (s as NSString).draw(at: p, withAttributes: [.font: font(f), .foregroundColor: color])
        case .row(let nodes):
            var x = p.x
            for n in nodes { let sz = size(n, fontSize: f); draw(n, at: CGPoint(x: x, y: p.y + (own.height - sz.height) / 2), f: f, color: color, context: context); x += sz.width }
        case .fraction(let a, let b):
            let top = size(a, fontSize: f * 0.85), bottom = size(b, fontSize: f * 0.85)
            draw(a, at: CGPoint(x: p.x + (own.width - top.width) / 2, y: p.y), f: f * 0.85, color: color, context: context)
            draw(b, at: CGPoint(x: p.x + (own.width - bottom.width) / 2, y: p.y + top.height + 12), f: f * 0.85, color: color, context: context)
            context.setStrokeColor(color.cgColor); context.setLineWidth(1.4); context.move(to: CGPoint(x: p.x, y: p.y + top.height + 6)); context.addLine(to: CGPoint(x: p.x + own.width, y: p.y + top.height + 6)); context.strokePath()
        case .root(let a):
            ("√" as NSString).draw(at: p, withAttributes: [.font: font(f), .foregroundColor: color])
            draw(a, at: CGPoint(x: p.x + f * 0.75, y: p.y + 4), f: f, color: color, context: context)
            context.setStrokeColor(color.cgColor); context.setLineWidth(1.2); context.move(to: CGPoint(x: p.x + f * 0.75, y: p.y + 4)); context.addLine(to: CGPoint(x: p.x + own.width, y: p.y + 4)); context.strokePath()
        case .scripts(let a, let sup, let sub):
            let base = size(a, fontSize: f)
            draw(a, at: CGPoint(x: p.x, y: p.y + (sup == nil ? 0 : f * 0.18)), f: f, color: color, context: context)
            if let sup { draw(sup, at: CGPoint(x: p.x + base.width, y: p.y), f: f * 0.62, color: color, context: context) }
            if let sub { draw(sub, at: CGPoint(x: p.x + base.width, y: p.y + base.height * 0.67), f: f * 0.62, color: color, context: context) }
        }
    }
}

struct MathEditor: View {
    @ObservedObject var session: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var source = "\\sigma = \\frac{F}{A}"
    private var validationError: String? { MathParser.validationError(for: source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Maths notation").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() } }
            TextField("LaTeX source", text: $source).font(.system(.body, design: .monospaced))
            Text("Native subset: fractions, roots, powers, subscripts and common Greek/operators. Invalid or unsupported notation is shown as source text; fix it before insertion.").font(.caption).foregroundStyle(.secondary)
            MathPreview(latex: source).frame(height: 120).background(.white, in: RoundedRectangle(cornerRadius: 12))
            if let validationError { Text(validationError).font(.caption).foregroundStyle(.red) }
            Button("Insert editable maths") {
                guard validationError == nil else { return }
                session.add(DrawingElement(kind: .symbol, points: [.init(x: session.cameraOffset.x + 160, y: session.cameraOffset.y + 160), .init(x: session.cameraOffset.x + 720, y: session.cameraOffset.y + 280)], color: session.color, text: "mathlatex:" + source))
                dismiss()
            }.buttonStyle(.borderedProminent).disabled(validationError != nil)
        }.padding(24).frame(width: 600, height: 370)
    }
}

struct MathPreview: NSViewRepresentable {
    let latex: String
    func makeNSView(context: Context) -> MathPreviewView { MathPreviewView() }
    func updateNSView(_ view: MathPreviewView, context: Context) { view.latex = latex; view.needsDisplay = true }
}
final class MathPreviewView: NSView {
    var latex = ""
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { if let context = NSGraphicsContext.current?.cgContext { NativeMathRenderer.draw(latex: latex, in: bounds.insetBy(dx: 18, dy: 18), context: context, color: InkColor.graphite.ns) } }
}
