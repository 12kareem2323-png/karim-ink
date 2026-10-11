// Test-only substitutes for portable document/math verification. These are NOT WPF renderer/runtime tests.
namespace System.Windows
{
    public struct Point(double x,double y){public double X=x,Y=y;public static Vector operator-(Point a,Point b)=>new(a.X-b.X,a.Y-b.Y);public static Point operator+(Point a,Vector b)=>new(a.X+b.X,a.Y+b.Y);public static Point operator-(Point a,Vector b)=>new(a.X-b.X,a.Y-b.Y);}
    public struct Vector(double x,double y){public double X=x,Y=y;public double LengthSquared=>X*X+Y*Y;public double Length=>Math.Sqrt(LengthSquared);public void Normalize(){var l=Length;X/=l;Y/=l;}public static Vector operator+(Vector a,Vector b)=>new(a.X+b.X,a.Y+b.Y);public static Vector operator-(Vector a,Vector b)=>new(a.X-b.X,a.Y-b.Y);public static Vector operator*(Vector a,double n)=>new(a.X*n,a.Y*n);public static Vector operator/(Vector a,double n)=>new(a.X/n,a.Y/n);public static double Multiply(Vector a,Vector b)=>a.X*b.X+a.Y*b.Y;public static double CrossProduct(Vector a,Vector b)=>a.X*b.Y-a.Y*b.X;}
    public struct Rect
    {
        public double X,Y,Width,Height;private bool empty;
        public Rect(double x,double y,double w,double h){X=x;Y=y;Width=w;Height=h;empty=false;}
        public Rect(Point a,Point b):this(Math.Min(a.X,b.X),Math.Min(a.Y,b.Y),Math.Abs(a.X-b.X),Math.Abs(a.Y-b.Y)){}
        public static Rect Empty=>new(){empty=true};public bool IsEmpty=>empty;public double Left=>X;public double Right=>X+Width;public double Top=>Y;public double Bottom=>Y+Height;public Point TopLeft=>new(Left,Top);public Point TopRight=>new(Right,Top);public Point BottomLeft=>new(Left,Bottom);public Point BottomRight=>new(Right,Bottom);
        public bool Contains(Point p)=>!empty&&p.X>=Left&&p.X<=Right&&p.Y>=Top&&p.Y<=Bottom;public bool Contains(Rect r)=>Contains(r.TopLeft)&&Contains(r.BottomRight);public bool IntersectsWith(Rect r)=>!empty&&!r.empty&&Left<=r.Right&&Right>=r.Left&&Top<=r.Bottom&&Bottom>=r.Top;
        public void Union(Point p){if(empty){this=new(p,p);return;}var right=Math.Max(Right,p.X);var bottom=Math.Max(Bottom,p.Y);X=Math.Min(X,p.X);Y=Math.Min(Y,p.Y);Width=right-X;Height=bottom-Y;}
        public void Union(Rect r){if(r.empty)return;Union(r.TopLeft);Union(r.BottomRight);}
        public void Inflate(double x,double y){if(empty)return;X-=x;Y-=y;Width+=2*x;Height+=2*y;}
    }
}
namespace System.Windows.Media
{
    public struct Color {public byte A,R,G,B;public static Color FromArgb(byte a,byte r,byte g,byte b)=>new(){A=a,R=r,G=g,B=b};}
    public sealed class SolidColorBrush(Color color){public Color Color=color;public void Freeze(){}}
    public struct Matrix{private double degrees,cx,cy;public void RotateAt(double d,double x,double y){degrees=d;cx=x;cy=y;}public System.Windows.Point Transform(System.Windows.Point p){var a=degrees*Math.PI/180;return new(cx+(p.X-cx)*Math.Cos(a)-(p.Y-cy)*Math.Sin(a),cy+(p.X-cx)*Math.Sin(a)+(p.Y-cy)*Math.Cos(a));}}
}
