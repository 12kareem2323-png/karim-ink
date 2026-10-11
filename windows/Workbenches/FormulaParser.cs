namespace KarimEldamatyWindows;

internal abstract record FormulaNode;
internal sealed record FormulaText(string Text) : FormulaNode;
internal sealed record FormulaRow(List<FormulaNode> Children) : FormulaNode;
internal sealed record FormulaFraction(FormulaNode Numerator, FormulaNode Denominator) : FormulaNode;
internal sealed record FormulaRoot(FormulaNode Value) : FormulaNode;
internal sealed record FormulaScripts(FormulaNode Base, FormulaNode? Super, FormulaNode? Sub) : FormulaNode;

internal sealed class FormulaParser
{
    private readonly string _source;
    private int _position;
    private int _depth;
    internal static readonly Dictionary<string, string> Commands = new(StringComparer.Ordinal)
    {
        ["alpha"]="α", ["beta"]="β", ["gamma"]="γ", ["delta"]="δ", ["epsilon"]="ε", ["varepsilon"]="ϵ", ["zeta"]="ζ", ["eta"]="η", ["theta"]="θ", ["vartheta"]="ϑ", ["iota"]="ι", ["kappa"]="κ", ["lambda"]="λ", ["mu"]="μ", ["nu"]="ν", ["xi"]="ξ", ["pi"]="π", ["varpi"]="ϖ", ["rho"]="ρ", ["sigma"]="σ", ["varsigma"]="ς", ["tau"]="τ", ["upsilon"]="υ", ["phi"]="φ", ["varphi"]="ϕ", ["chi"]="χ", ["psi"]="ψ", ["omega"]="ω",
        ["Gamma"]="Γ", ["Delta"]="Δ", ["Theta"]="Θ", ["Lambda"]="Λ", ["Xi"]="Ξ", ["Pi"]="Π", ["Sigma"]="Σ", ["Upsilon"]="Υ", ["Phi"]="Φ", ["Psi"]="Ψ", ["Omega"]="Ω",
        ["int"]="∫", ["iint"]="∬", ["iiint"]="∭", ["oint"]="∮", ["sum"]="∑", ["prod"]="∏", ["infty"]="∞", ["times"]="×", ["div"]="÷", ["cdot"]="·", ["pm"]="±", ["mp"]="∓", ["leq"]="≤", ["le"]="≤", ["geq"]="≥", ["ge"]="≥", ["neq"]="≠", ["ne"]="≠", ["approx"]="≈", ["equiv"]="≡", ["propto"]="∝", ["partial"]="∂", ["nabla"]="∇", ["degree"]="°", ["rightarrow"]="→", ["leftarrow"]="←", ["leftrightarrow"]="↔", ["Rightarrow"]="⇒", ["Leftarrow"]="⇐", ["Leftrightarrow"]="⇔", ["in"]="∈", ["notin"]="∉", ["subset"]="⊂", ["subseteq"]="⊆", ["cup"]="∪", ["cap"]="∩", ["emptyset"]="∅", ["forall"]="∀", ["exists"]="∃", ["neg"]="¬", ["land"]="∧", ["lor"]="∨", ["perp"]="⊥", ["parallel"]="∥", ["angle"]="∠", ["sin"]="sin", ["cos"]="cos", ["tan"]="tan", ["ln"]="ln", ["log"]="log", ["exp"]="exp", ["lim"]="lim", ["min"]="min", ["max"]="max"
    };
    public FormulaParser(string source)
    {
        _source = source;
        if (source.Length > 4096) throw new FormatException("Maths source exceeds 4096 characters. Shorten it before inserting.");
        if (string.IsNullOrWhiteSpace(source)) throw new FormatException("Enter some maths notation.");
    }
    private char Current => _position < _source.Length ? _source[_position] : '\0';
    public FormulaNode Parse() => Row(false);
    private FormulaNode Row(bool inGroup)
    {
        var result = new List<FormulaNode>();
        while (Current != '\0')
        {
            if (Current == '}') { if (inGroup) break; throw new FormatException("A closing brace has no opening brace."); }
            var node = Atom(); FormulaNode? super = null; FormulaNode? sub = null;
            while (Current is '^' or '_')
            {
                var sign = Current; _position++; var argument = Argument();
                if (sign == '^') { if (super != null) throw new FormatException("A base has more than one superscript. Use braces for nesting."); super = argument; }
                else { if (sub != null) throw new FormatException("A base has more than one subscript. Use braces for nesting."); sub = argument; }
            }
            if (super != null || sub != null) node = new FormulaScripts(node, super, sub);
            result.Add(node);
        }
        return new FormulaRow(result);
    }
    private FormulaNode Atom()
    {
        var c = Current;
        if (c == '\0') throw new FormatException("A command or script is missing its value.");
        _position++;
        if (c is '^' or '_') throw new FormatException("A superscript or subscript needs a base.");
        if (c == '{')
        {
            if (++_depth > 24) throw new FormatException("Maths groups are nested too deeply.");
            var row = Row(true); if (Current != '}') throw new FormatException("An opening brace has no closing brace."); _position++; _depth--; return row;
        }
        if (c != '\\') return new FormulaText(c.ToString());
        var start = _position; while (char.IsLetter(Current)) _position++;
        var name = _source[start.._position];
        if (name == "frac") return new FormulaFraction(Argument(), Argument());
        if (name == "sqrt") { SkipWhite(); if (Current == '[') throw new FormatException("Indexed roots are outside the native formula subset. Use a power such as x^{1/3}."); return new FormulaRoot(Argument()); }
        if (name is "text" or "mathrm") return Literal();
        if (name is "left" or "right") return Argument();
        if (name.Length == 0)
        {
            c = Current; if (c == '\0') throw new FormatException("The escape at the end needs a value."); _position++;
            if (c is ',' or ';' or ' ' or ':') return new FormulaText(" "); if (c == '!') return new FormulaText("");
            if ("{}_^%#&\\".Contains(c)) return new FormulaText(c.ToString());
            throw new FormatException("Unsupported escape \\" + c + ".");
        }
        if (Commands.TryGetValue(name, out var unicode)) return new FormulaText(unicode);
        var fallback = MathSymbolCatalog.ToUnicode("\\" + name);
        if (!string.IsNullOrEmpty(fallback)) return new FormulaText(fallback);
        throw new FormatException("Unsupported command \\" + name + ". Copy it to a LaTeX editor, or choose a supported symbol.");
    }
    private void SkipWhite() { while (char.IsWhiteSpace(Current)) _position++; }
    private FormulaNode Argument()
    {
        SkipWhite(); if (Current is '\0' or '}') throw new FormatException("A command or script is missing its value.");
        if (++_depth > 24) throw new FormatException("Maths notation is nested too deeply.");
        try { return Atom(); } finally { _depth--; }
    }
    private FormulaNode Literal()
    {
        SkipWhite(); if (Current != '{') throw new FormatException("Use braces around text or roman notation."); _position++;
        var text = new System.Text.StringBuilder(); var nesting = 1;
        while (Current != '\0')
        {
            var c = Current; _position++;
            if (c == '\\' && "{}_^%#&\\".Contains(Current)) { text.Append(Current); _position++; continue; }
            if (c == '{') nesting++;
            if (c == '}' && --nesting == 0) return new FormulaText(text.ToString());
            text.Append(c);
        }
        throw new FormatException("The text group needs a closing brace.");
    }
}

