using System.Windows;

namespace KarimEldamatyWindows;

internal static class InkShapeRecognizer
{
    public const double HoldSeconds = .36;
    private const int FitSamples = 80;
    private const int MaxInputSamples = 4096;
    internal sealed record Fit(string Kind, Point[] Vertices, double Rotation = 0);

    public static Fit? Detect(IReadOnlyList<Point> input, double zoom, InkShapeMode mode)
    {
        if (mode == InkShapeMode.Off || input.Count < 4 || !double.IsFinite(zoom) || zoom <= 0)
            return null;

        var origin = input[0];
        var stride = Math.Max(1, (input.Count + MaxInputSamples - 1) / MaxInputSamples);
        var path = new List<Point>(Math.Min(MaxInputSamples + 1, input.Count)) { new() };
        var cumulative = new List<double>(path.Capacity) { 0 };
        var bounds = new Rect(new Point(), new Point());
        var length = 0d;
        for (var i = stride; ; i += stride)
        {
            var offset = (input[Math.Min(i, input.Count - 1)] - origin) * zoom;
            var point = new Point(offset.X, offset.Y);
            var distance = (point - path[^1]).Length;
            if (!double.IsFinite(distance)) return null;
            if (distance >= .08)
            {
                length += distance;
                path.Add(point);
                cumulative.Add(length);
                bounds.Union(point);
            }
            if (i >= input.Count - 1) break;
        }

        var automatic = mode == InkShapeMode.OnRelease;
        var diagonal = new Vector(bounds.Width, bounds.Height).Length;
        if (diagonal < (automatic ? 40 : 22) || path.Count < 4 || length > diagonal * 9)
            return null;

        var points = Resample(path, cumulative, length);
        var gap = (points[^1] - points[0]).Length;
        var fittedLength = PathLength(points);
        Fit? fit = null;
        if (gap >= (automatic ? 54 : 22) && gap > diagonal * .81)
        {
            fit = Line(points, gap, fittedLength, automatic);
        }
        else if (gap < diagonal * (automatic ? .11 : .18) && fittedLength > diagonal * 1.68 &&
                 Math.Min(bounds.Width, bounds.Height) > (automatic ? 20 : 13))
        {
            var ring = points[..^1];
            fit = Polygon(ring, diagonal, fittedLength + gap, automatic) ??
                  Ellipse(ring, fittedLength + gap, automatic);
        }

        if (fit is null) return null;
        return fit with { Vertices = fit.Vertices.Select(p => origin + new Vector(p.X / zoom, p.Y / zoom)).ToArray() };
    }

    private static Point[] Resample(List<Point> path, List<double> cumulative, double length)
    {
        var output = new Point[FitSamples];
        var segment = 1;
        for (var i = 0; i < output.Length; i++)
        {
            var target = length * i / (output.Length - 1);
            while (segment < path.Count - 1 && cumulative[segment] < target) segment++;
            var t = (target - cumulative[segment - 1]) / (cumulative[segment] - cumulative[segment - 1]);
            output[i] = path[segment - 1] + (path[segment] - path[segment - 1]) * t;
        }
        return output;
    }

    private static Fit? Line(Point[] points, double span, double length, bool automatic)
    {
        if (length > span * (automatic ? 1.065 : 1.16)) return null;
        var tangent = (points[^1] - points[0]) * (1 / span);
        var (previous, backwards, squares, worst) = (0d, 0d, 0d, 0d);
        foreach (var point in points)
        {
            var offset = point - points[0];
            var perpendicular = Math.Abs(Vector.CrossProduct(tangent, offset));
            var along = Vector.Multiply(tangent, offset);
            backwards += Math.Max(0, previous - along);
            previous = along;
            squares += perpendicular * perpendicular;
            worst = Math.Max(worst, perpendicular);
        }
        if (backwards > span * (automatic ? .03 : .08) ||
            worst > Math.Max(automatic ? 1.8 : 3.1, span * (automatic ? .025 : .05)) ||
            Math.Sqrt(squares / points.Length) > Math.Max(automatic ? .95 : 1.5, span * (automatic ? .012 : .026)))
            return null;

        return new("line", [points[0], points[^1]]);
    }

    private static Fit? Polygon(Point[] ring, double diagonal, double length, bool automatic)
    {
        var far = Farthest(ring, ring[0]);
        var opposite = Farthest(ring, ring[far]);
        var (start, end) = (Math.Min(far, opposite), Math.Max(far, opposite));
        if (start == end) return null;
        var tolerance = diagonal * (automatic ? .026 : .039);
        var a = Simplify(ring[start..(end + 1)], tolerance);
        var b = Simplify([..ring[end..], ..ring[..(start + 1)]], tolerance);
        var vertices = a.Take(a.Count - 1).Concat(b.Take(b.Count - 1)).ToList();

        // The two anchors can land on straight edges. Drop those extra vertices.
        for (var i = 0; vertices.Count > 3 && i < vertices.Count;)
        {
            var previous = vertices[(i + vertices.Count - 1) % vertices.Count];
            var next = vertices[(i + 1) % vertices.Count];
            if (DrawingMath.Distance(vertices[i], previous, next) < tolerance * .70)
            {
                vertices.RemoveAt(i);
                i = 0;
            }
            else i++;
        }
        if (vertices.Count is < 3 or > 4) return null;

        var edges = vertices.Select((p, i) => vertices[(i + 1) % vertices.Count] - p).ToArray();
        var perimeter = edges.Sum(v => v.Length);
        if (edges.Any(v => v.Length < diagonal * .14) || length / perimeter > (automatic ? 1.10 : 1.17))
            return null;

        var turns = edges.Select((edge, i) => Vector.CrossProduct(edge, edges[(i + 1) % edges.Length])).ToArray();
        if (turns.Any(t => Math.Abs(t) < diagonal * diagonal * .075 || Math.Sign(t) != Math.Sign(turns[0])))
            return null;
        if (vertices.Count == 3) return new("triangle", vertices.ToArray());

        var rightAngleTolerance = automatic ? .25 : .39;
        for (var i = 0; i < edges.Length; i++)
        {
            var u = edges[i];
            var v = edges[(i + 1) % edges.Length];
            if (Math.Abs(Vector.Multiply(u, v) / (u.Length * v.Length)) > rightAngleTolerance)
                return null;
        }
        if (Math.Abs(edges[0].Length - edges[2].Length) > diagonal * .16 ||
            Math.Abs(edges[1].Length - edges[3].Length) > diagonal * .16)
            return null;

        var angle = Math.Atan2(edges[0].Y - edges[2].Y, edges[0].X - edges[2].X) * (180 / Math.PI);
        return OrientedBounds("rectangle", vertices, angle);
    }

    private static Fit? Ellipse(Point[] ring, double length, bool automatic)
    {
        var center = new Point(ring.Average(p => p.X), ring.Average(p => p.Y));
        var offsets = ring.Select(p => p - center).ToArray();
        var xx = offsets.Sum(p => p.X * p.X);
        var yy = offsets.Sum(p => p.Y * p.Y);
        var xy = offsets.Sum(p => p.X * p.Y);
        var angle = .5 * Math.Atan2(2 * xy, xx - yy) * (180 / Math.PI);
        var fit = OrientedBounds("ellipse", ring, angle);
        var size = fit.Vertices[1] - fit.Vertices[0];
        var (a, b) = (size.X / 2, size.Y / 2);
        if (Math.Min(a, b) < (automatic ? 10 : 6.5) || Math.Min(a, b) / Math.Max(a, b) < .20)
            return null;

        var fittedCenter = fit.Vertices[0] + size * .5;
        var perimeter = Math.PI * (3 * (a + b) - Math.Sqrt((3 * a + b) * (a + 3 * b)));
        if (length < perimeter * .90 || length > perimeter * (automatic ? 1.10 : 1.17))
            return null;
        var errors = ring.Select(p => {
            var local = DrawingMath.Rotate(p, fittedCenter, -angle) - fittedCenter;
            return Math.Abs(Math.Sqrt(local.X * local.X / (a * a) + local.Y * local.Y / (b * b)) - 1);
        }).ToArray();
        if (errors.Average() > (automatic ? .056 : .09) || errors.Max() > (automatic ? .16 : .22))
            return null;
        return fit;
    }

    private static Fit OrientedBounds(string kind, IReadOnlyList<Point> points, double angle)
    {
        var origin = points[0];
        var rotated = points.Select(p => DrawingMath.Rotate(p, origin, -angle)).ToArray();
        var local = new Rect(rotated[0], rotated[0]);
        foreach (var p in rotated) local.Union(p);
        var halfSize = new Vector(local.Width / 2, local.Height / 2);
        var center = DrawingMath.Rotate(local.TopLeft + halfSize, origin, angle);
        return new(kind, [center - halfSize, center + halfSize], angle);
    }

    private static int Farthest(Point[] points, Point anchor)
    {
        var best = 0;
        var distance = -1d;
        for (var i = 0; i < points.Length; i++)
        {
            var candidate = (points[i] - anchor).LengthSquared;
            if (candidate > distance) (best, distance) = (i, candidate);
        }
        return best;
    }

    private static List<Point> Simplify(Point[] points, double tolerance)
    {
        var selected = new bool[points.Length];
        selected[0] = selected[^1] = true;
        var pending = new Stack<(int First, int Last)>();
        pending.Push((0, points.Length - 1));
        while (pending.TryPop(out var segment))
        {
            var best = -1;
            var distance = tolerance;
            for (var i = segment.First + 1; i < segment.Last; i++)
            {
                var candidate = DrawingMath.Distance(points[i], points[segment.First], points[segment.Last]);
                if (candidate > distance) (best, distance) = (i, candidate);
            }
            if (best < 0) continue;
            selected[best] = true;
            pending.Push((segment.First, best));
            pending.Push((best, segment.Last));
        }
        return points.Where((_, i) => selected[i]).ToList();
    }

    private static double PathLength(Point[] path)
    {
        var length = 0d;
        for (var i = 1; i < path.Length; i++) length += (path[i] - path[i - 1]).Length;
        return length;
    }
}
