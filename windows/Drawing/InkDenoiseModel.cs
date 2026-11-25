using System.Windows;

namespace KarimEldamatyWindows;

// Port of Velin Mac build 116's seven-weight regression model.
// Position-only refinement runs once per completed stroke, with sharp-turn guards.
internal static class InkDenoiseModel
{
    public const int MaximumSamples = 8192;

    public static Point[] Refine(IReadOnlyList<Point> points, double strength, double zoom)
    {
        var result = points.ToArray();
        if (points.Count is < 5 or > MaximumSamples || !double.IsFinite(strength) || strength <= 0 ||
            !double.IsFinite(zoom) || zoom <= 0)
            return result;

        var blend = Math.Min(1, strength / .85);
        for (var i = 2; i < points.Count - 2; i++)
        {
            var (a, b, p, c, d) = (points[i - 2], points[i - 1], points[i], points[i + 1], points[i + 2]);
            var chord = (c - b) * zoom;
            var left = (b - a) * zoom;
            var right = (d - c) * zoom;
            var (span, l, r) = (chord.Length, left.Length, right.Length);
            if (!double.IsFinite(span + l + r) || Math.Min(span, Math.Min(l, r)) <= .2)
                continue;

            var tangent = chord * (1 / span);
            var normal = new Vector(-tangent.Y, tangent.X);
            var alignment = Vector.Multiply(left, right) / (l * r);
            var leftStep = Vector.Multiply(left, tangent);
            var rightStep = Vector.Multiply(right, tangent);
            if (alignment < .52 || leftStep < l * .4 || rightStep < r * .4)
                continue;

            var offset = (p - b) * zoom;
            var along = Vector.Multiply(offset, tangent) / span;
            var residual = Vector.Multiply(offset, normal);
            if (along <= .04 || along >= .96 || !double.IsFinite(residual) || Math.Abs(residual) <= .02)
                continue;

            var curvature = Vector.Multiply(right, normal) / rightStep - Vector.Multiply(left, normal) / leftStep;
            var limit = 1.5 * Math.Abs(residual);
            var sag = Math.Clamp(-.5 * curvature * along * (1 - along) * span, -limit, limit);
            var ratio = Math.Min(1, Math.Abs(residual) / (span * .28));
            var spanScale = Math.Min(1, span / 20);
            var balance = Math.Min(l, r) / Math.Max(l, r);
            var turn = 1 - alignment;
            var predicted = -residual * (.67982043 + .14391941 * ratio - .2926251 * spanScale +
                .0724634 * balance - .54321462 * turn) + sag * (-.12790456 + .20133192 * turn);
            var gain = Math.Clamp(-predicted / residual, 0, .92);
            result[i] = p + normal * (Math.Clamp(-residual * gain * blend, -2.4, 2.4) / zoom);
        }
        return result;
    }
}
