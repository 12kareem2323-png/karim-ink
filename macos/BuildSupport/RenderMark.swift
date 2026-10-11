import AppKit
import Foundation
let target=CommandLine.arguments[1]
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let rect=NSBezierPath(roundedRect:NSRect(x:24,y:24,width:976,height:976),xRadius:220,yRadius:220)
NSGradient(starting:NSColor(srgbRed:0.11,green:0.52,blue:0.48,alpha:1),ending:NSColor(srgbRed:0.06,green:0.37,blue:0.35,alpha:1))!.draw(in:rect,angle:-50)
let p=NSBezierPath();p.move(to:NSPoint(x:706,y:751));p.curve(to:NSPoint(x:404,y:770),controlPoint1:NSPoint(x:634,y:814),controlPoint2:NSPoint(x:506,y:818));p.curve(to:NSPoint(x:370,y:592),controlPoint1:NSPoint(x:308,y:724),controlPoint2:NSPoint(x:302,y:637));p.curve(to:NSPoint(x:627,y:499),controlPoint1:NSPoint(x:425,y:556),controlPoint2:NSPoint(x:571,y:545));p.curve(to:NSPoint(x:585,y:287),controlPoint1:NSPoint(x:708,y:433),controlPoint2:NSPoint(x:674,y:331));p.curve(to:NSPoint(x:284,y:319),controlPoint1:NSPoint(x:488,y:239),controlPoint2:NSPoint(x:361,y:254));p.lineWidth=84;p.lineCapStyle = .round;NSColor(srgbRed:0.973,green:0.961,blue:0.925,alpha:1).setStroke();p.stroke()
let gold=NSColor(srgbRed:0.863,green:0.769,blue:0.573,alpha:1);gold.setFill();let nib=NSBezierPath();nib.move(to:.init(x:700,y:333));nib.line(to:.init(x:771,y:362));nib.line(to:.init(x:747,y:287));nib.line(to:.init(x:722,y:291));nib.close();nib.fill();NSBezierPath(ovalIn:.init(x:750,y:752,width:40,height:40)).fill()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;let data=rep.representation(using:.png,properties:[:])!;try data.write(to:URL(fileURLWithPath:target));print("Rendered SketchGlide vector mark.")
