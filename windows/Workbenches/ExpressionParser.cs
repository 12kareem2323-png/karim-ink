using System.Globalization;

namespace KarimEldamatyWindows;

/// <summary>A bounded arithmetic grammar. It never invokes scripts, reflection or executable code.</summary>
public sealed class ExpressionParser
{
    private readonly string _source;
    private readonly double _x;
    private int _position;
    private int _depth;
    public ExpressionParser(string source, double x = 0)
    {
        if (source.Length > 2048) throw new FormatException("A calculation can contain at most 2,048 characters.");
        if (!double.IsFinite(x)) throw new FormatException("The x value must be finite.");
        _source = new string(source.ToLowerInvariant().Where(c => !char.IsWhiteSpace(c)).Select(c => c is '−' ? '-' : c is '×' ? '*' : c is '÷' ? '/' : c).ToArray()); _x = x;
    }
    private char Current => _position < _source.Length ? _source[_position] : '\0';
    private bool Consume(char c) { if (Current != c) return false; _position++; return true; }
    public double Evaluate()
    {
        if (_source.Length == 0) throw new FormatException("Enter a calculation.");
        var value = Sum();
        if (_position != _source.Length) throw new FormatException($"Unexpected symbol at position {_position + 1}.");
        if (!double.IsFinite(value)) throw new FormatException("This expression has no finite real result.");
        return value;
    }
    public static double Evaluate(string source, double x = 0) => new ExpressionParser(source, x).Evaluate();
    private double Sum()
    {
        var value = Product(); while (Current is '+' or '-') { var op = Current; _position++; var right = Product(); value = op == '+' ? value + right : value - right; } return value;
    }
    private double Product()
    {
        var value = Unary();
        while (Current is '*' or '/') { var op = Current; _position++; var right = Unary(); if (op == '/' && right == 0) throw new FormatException("Cannot divide by zero."); value = op == '*' ? value * right : value / right; } return value;
    }
    private double Unary()
    {
        if (++_depth > 64) throw new FormatException("The calculation is nested too deeply. Simplify it.");
        try { if (Consume('+')) return Unary(); if (Consume('-')) return -Unary(); return Power(); } finally { _depth--; }
    }
    private double Power() { var value = Atom(); return Consume('^') ? Math.Pow(value, Unary()) : value; }
    private double Atom()
    {
        if (Consume('(')) { var value = Sum(); if (!Consume(')')) throw new FormatException("Missing closing bracket."); return value; }
        if (Current == '\0') throw new FormatException("The expression is incomplete.");
        if (char.IsAsciiDigit(Current) || Current == '.')
        {
            var start = _position; while (char.IsAsciiDigit(Current) || Current == '.') _position++;
            if (Current == 'e') { _position++; if (Current is '+' or '-') _position++; var exponent = _position; while (char.IsAsciiDigit(Current)) _position++; if (_position == exponent) throw new FormatException("A scientific exponent needs digits."); }
            if (!double.TryParse(_source[start.._position], NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !double.IsFinite(value)) throw new FormatException("Invalid or oversized number."); return value;
        }
        if (char.IsLetter(Current) || Current == 'π')
        {
            var start = _position; while (char.IsLetter(Current) || Current == 'π') _position++; var name = _source[start.._position];
            if (name == "x") return _x; if (name is "pi" or "π") return Math.PI; if (name == "e") return Math.E;
            if (!Consume('(')) throw new FormatException("Use a function such as sqrt(16) or sin(pi/2).");
            var value = Sum(); if (!Consume(')')) throw new FormatException("Missing function closing bracket.");
            return name switch
            {
                "sin" => Math.Sin(value), "cos" => Math.Cos(value), "tan" => Math.Tan(value), "sqrt" => Math.Sqrt(value), "abs" => Math.Abs(value), "ln" => Math.Log(value), "log" => Math.Log10(value), "exp" => Math.Exp(value), "asin" => Math.Asin(value), "acos" => Math.Acos(value), "atan" => Math.Atan(value), "floor" => Math.Floor(value), "ceil" => Math.Ceiling(value), "round" => Math.Round(value), _ => throw new FormatException("Unknown function: " + name + ".")
            };
        }
        throw new FormatException("Use numbers, brackets, + − × ÷ ^ and the listed functions.");
    }
}

public sealed class EngineeringUnitFamily
{
    public string Name { get; }
    public IReadOnlyDictionary<string, double> Units { get; }
    public EngineeringUnitFamily(string name, Dictionary<string, double> units) { Name = name; Units = units; }
    public double Convert(double value, string from, string to)
    {
        if (!double.IsFinite(value) || !Units.TryGetValue(from, out var a) || !Units.TryGetValue(to, out var b)) throw new FormatException("Choose compatible units and a finite value.");
        var result = value * a / b; if (!double.IsFinite(result)) throw new FormatException("The converted value is too large."); return result;
    }
    public override string ToString() => Name;
    public static IReadOnlyList<EngineeringUnitFamily> All { get; } = new[]
    {
        new EngineeringUnitFamily("Length", new() { ["mm"] = .001, ["cm"] = .01, ["m"] = 1, ["km"] = 1000, ["in"] = .0254, ["ft"] = .3048 }),
        new EngineeringUnitFamily("Angle", new() { ["deg"] = Math.PI / 180, ["rad"] = 1 }),
        new EngineeringUnitFamily("Force", new() { ["N"] = 1, ["kN"] = 1000, ["lbf"] = 4.4482216152605 }),
        new EngineeringUnitFamily("Pressure", new() { ["Pa"] = 1, ["kPa"] = 1000, ["MPa"] = 1000000, ["bar"] = 100000, ["psi"] = 6894.757293168 }),
        new EngineeringUnitFamily("Mass", new() { ["g"] = .001, ["kg"] = 1, ["lb"] = .45359237 }),
        new EngineeringUnitFamily("Energy", new() { ["J"] = 1, ["kJ"] = 1000, ["Wh"] = 3600, ["kWh"] = 3600000 }),
        new EngineeringUnitFamily("Power", new() { ["W"] = 1, ["kW"] = 1000, ["hp (mechanical)"] = 745.6998715822702 }),
        new EngineeringUnitFamily("Time", new() { ["s"] = 1, ["min"] = 60, ["h"] = 3600 })
    };
}
