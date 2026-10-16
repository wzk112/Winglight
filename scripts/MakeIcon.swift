import AppKit
import ImageIO
import UniformTypeIdentifiers
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:destination,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let c = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x:Double(size)/1024,y:Double(size)/1024)
    let rect = CGRect(x:60,y:60,width:904,height:904)
    c.addPath(CGPath(roundedRect:rect,cornerWidth:202,cornerHeight:202,transform:nil))
    c.clip()
    let colors = [CGColor(srgbRed:0.035,green:0.075,blue:0.12,alpha:1),CGColor(srgbRed:0.08,green:0.16,blue:0.22,alpha:1)] as CFArray
    let gradient = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors,locations:[0,1])!
    c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:1024,y:1024),options:[])
    c.setStrokeColor(CGColor(srgbRed:0.22,green:0.40,blue:0.5,alpha:0.24)); c.setLineWidth(2)
    for n in stride(from:120,through:960,by:110) { c.move(to:CGPoint(x:n,y:0)); c.addLine(to:CGPoint(x:n,y:1024)); c.move(to:CGPoint(x:0,y:n)); c.addLine(to:CGPoint(x:1024,y:n)) }; c.strokePath()
    let plane = CGMutablePath(); plane.move(to:CGPoint(x:512,y:850))
    plane.addCurve(to:CGPoint(x:546,y:650),control1:CGPoint(x:554,y:835),control2:CGPoint(x:546,y:734))
    for p in [(822,420),(822,380),(548,480),(538,290),(630,210),(630,183),(512,220),(394,183),(394,210),(486,290),(476,480),(202,380),(202,420),(478,650)] { plane.addLine(to:CGPoint(x:p.0,y:p.1)) }
    plane.addCurve(to:CGPoint(x:512,y:850),control1:CGPoint(x:478,y:734),control2:CGPoint(x:470,y:835)); plane.closeSubpath()
    c.addPath(plane); c.setFillColor(CGColor(srgbRed:0.14,green:0.27,blue:0.34,alpha:1)); c.setStrokeColor(CGColor(srgbRed:0.62,green:0.84,blue:0.91,alpha:1)); c.setLineWidth(13); c.setLineJoin(.round); c.drawPath(using:.fillStroke)
    for p in [(202.0,410.0),(822.0,410.0),(512.0,220.0)] {
        let col = CGColor(srgbRed:0.8,green:0.93,blue:1,alpha:1)
        c.setShadow(offset:.zero,blur:48,color:col); c.setFillColor(col); c.fillEllipse(in:CGRect(x:p.0-14,y:p.1-14,width:28,height:28)); c.setShadow(offset:.zero,blur:0,color:nil)
    }
    c.setFillColor(CGColor(srgbRed:1,green:0.12,blue:0.15,alpha:1)); c.fillEllipse(in:CGRect(x:502,y:529,width:20,height:20))
    let image = c.makeImage()!
    let names: [String]
    switch size {
    case 16:names=["icon_16x16.png"]
    case 32:names=["icon_16x16@2x.png","icon_32x32.png"]
    case 64:names=["icon_32x32@2x.png"]
    case 128:names=["icon_128x128.png"]
    case 256:names=["icon_128x128@2x.png","icon_256x256.png"]
    case 512:names=["icon_256x256@2x.png","icon_512x512.png"]
    default:names=["icon_512x512@2x.png"]
    }
    for name in names {
        let url = URL(fileURLWithPath:destination).appendingPathComponent(name)
        let out = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(out,image,nil); CGImageDestinationFinalize(out)
    }
}
