using System.Windows.Media;
using System.Windows.Media.Media3D;

namespace KarimEldamatyWindows;

internal static class Sketch3DGeometry
{
    public static GeometryModel3D Model(MeshGeometry3D mesh, InkColor color, bool selected = false)
    {
        var material = new MaterialGroup();
        material.Children.Add(new DiffuseMaterial(color.Brush()));
        material.Children.Add(new SpecularMaterial(new SolidColorBrush(Color.FromArgb(70, 255, 255, 255)), 24));
        if (selected) material.Children.Add(new EmissiveMaterial(color.Brush(.25)));
        return new GeometryModel3D(mesh, material) { BackMaterial = material };
    }
    public static MeshGeometry3D Tube(IReadOnlyList<Sketch3DPoint> points, double width)
    {
        if (points.Count == 1) return Sphere(points[0].Point, width * Math.Max(.15, points[0].Pressure) / 2, 8, 6);
        var mesh = new MeshGeometry3D(); const int sides = 8;
        for (var i = 0; i < points.Count; i++)
        {
            var tangent = points[Math.Min(points.Count - 1, i + 1)].Point - points[Math.Max(0, i - 1)].Point;
            if (tangent.Length < .000001) tangent = new Vector3D(0, 1, 0); tangent.Normalize();
            var reference = Math.Abs(tangent.Y) < .9 ? new Vector3D(0, 1, 0) : new Vector3D(1, 0, 0);
            var u = Vector3D.CrossProduct(tangent, reference); u.Normalize();
            var v = Vector3D.CrossProduct(tangent, u); v.Normalize();
            var radius = width / 2 * (.15 + .85 * points[i].Pressure);
            for (var side = 0; side < sides; side++)
            {
                var angle = side * 2 * Math.PI / sides;
                var normal = u * Math.Cos(angle) + v * Math.Sin(angle);
                mesh.Positions.Add(points[i].Point + normal * radius); mesh.Normals.Add(normal);
                if (i > 0)
                {
                    var a = (i - 1) * sides + side; var b = (i - 1) * sides + (side + 1) % sides;
                    var c = i * sides + side; var d = i * sides + (side + 1) % sides;
                    Triangle(mesh, a, c, b); Triangle(mesh, b, c, d);
                }
            }
        }
        mesh.Freeze(); return mesh;
    }
    public static MeshGeometry3D Primitive(Sketch3DPrimitive primitive) => primitive.Kind switch
    {
        "Sphere" => Sphere(primitive.Center.Point, primitive.Size.X / 2),
        "Cylinder" => Cylinder(primitive.Center.Point, primitive.Size.X / 2, primitive.Size.Y),
        _ => Box(primitive.Center.Point, primitive.Size.X, primitive.Size.Y, primitive.Size.Z)
    };
    public static MeshGeometry3D Box(Point3D center, double width, double height, double depth)
    {
        var mesh = new MeshGeometry3D();
        var x = width / 2; var y = height / 2; var z = depth / 2;
        var corners = new[] { new Point3D(-x,-y,-z), new Point3D(x,-y,-z), new Point3D(x,y,-z), new Point3D(-x,y,-z), new Point3D(-x,-y,z), new Point3D(x,-y,z), new Point3D(x,y,z), new Point3D(-x,y,z) };
        foreach (var p in corners) mesh.Positions.Add(center + (Vector3D)p);
        foreach (var i in new[] { 0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5 }) mesh.TriangleIndices.Add(i);
        mesh.Freeze(); return mesh;
    }
    public static MeshGeometry3D Sphere(Point3D center, double radius, int longitude = 24, int latitude = 16)
    {
        var mesh = new MeshGeometry3D();
        for (var row = 0; row <= latitude; row++)
        {
            var theta = row * Math.PI / latitude;
            for (var col = 0; col <= longitude; col++)
            {
                var phi = col * 2 * Math.PI / longitude;
                var normal = new Vector3D(Math.Sin(theta) * Math.Cos(phi), Math.Cos(theta), Math.Sin(theta) * Math.Sin(phi));
                mesh.Positions.Add(center + normal * radius); mesh.Normals.Add(normal);
                if (row > 0 && col > 0)
                {
                    var a = (row - 1) * (longitude + 1) + col - 1; var b = a + 1; var c = row * (longitude + 1) + col - 1; var d = c + 1;
                    Triangle(mesh, a, b, c); Triangle(mesh, b, d, c);
                }
            }
        }
        mesh.Freeze(); return mesh;
    }
    public static MeshGeometry3D Cylinder(Point3D center, double radius, double height)
    {
        var mesh = new MeshGeometry3D(); const int sides = 32;
        mesh.Positions.Add(center + new Vector3D(0, -height / 2, 0)); mesh.Positions.Add(center + new Vector3D(0, height / 2, 0));
        for (var i = 0; i < sides; i++)
        {
            var angle = i * 2 * Math.PI / sides; var offset = new Vector3D(Math.Cos(angle) * radius, 0, Math.Sin(angle) * radius);
            mesh.Positions.Add(center + offset + new Vector3D(0, -height / 2, 0));
            mesh.Positions.Add(center + offset + new Vector3D(0, height / 2, 0));
        }
        for (var i = 0; i < sides; i++)
        {
            var a = 2 + i * 2; var b = 2 + (i + 1) % sides * 2;
            Triangle(mesh, a, b, a + 1); Triangle(mesh, b, b + 1, a + 1);
            Triangle(mesh, 0, b, a); Triangle(mesh, 1, a + 1, b + 1);
        }
        mesh.Freeze(); return mesh;
    }
    private static void Triangle(MeshGeometry3D mesh, int a, int b, int c) { mesh.TriangleIndices.Add(a); mesh.TriangleIndices.Add(b); mesh.TriangleIndices.Add(c); }
}
