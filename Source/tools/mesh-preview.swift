import Cocoa
import SceneKit
var bytes=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
var cursor=0
func int()->Int{defer{cursor+=4};return Int(bytes.withUnsafeBytes{UInt32(bigEndian:$0.loadUnaligned(fromByteOffset:cursor,as:UInt32.self))})}
func float()->Float{Float(bitPattern:UInt32(int()))}
func string()->String{let n=Int(bytes[cursor])*256+Int(bytes[cursor+1]);cursor+=2;defer{cursor+=n};return String(data:bytes.subdata(in:cursor..<cursor+n),encoding:.utf8)!}
let scene=SCNScene()
let model=SCNNode();scene.rootNode.addChildNode(model)
let count=int()
let assets=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
var triangles=0
for _ in 0..<count{
 let path=string()
 let n=int()
 var p:[SCNVector3]=[],uv:[CGPoint]=[],color:[Float]=[]
 for _ in 0..<n{
  p.append(SCNVector3(float(),float(),float()))
  uv.append(CGPoint(x:Double(float()),y:Double(1-float())))
  let c=UInt32(int())
  color += [Float((c>>16)&255)/255,Float((c>>8)&255)/255,Float(c&255)/255,Float((c>>24)&255)/255]
 }
 let number=int();triangles+=number/3
 let indices:[Int32]=(0..<number).map{_ in Int32(int())}
 let colorData=color.withUnsafeBytes{Data($0)}
 let cs=SCNGeometrySource(data:colorData,semantic:.color,vectorCount:n,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
 let g=SCNGeometry(sources:[SCNGeometrySource(vertices:p),SCNGeometrySource(textureCoordinates:uv),cs],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
 let material=SCNMaterial();material.lightingModel = .constant;material.isDoubleSided=true
 let texture=path.replacingOccurrences(of:"pocketplayer:",with:"")
 material.diffuse.contents=NSImage(contentsOf:assets.appendingPathComponent(texture))
 material.blendMode = .alpha
 g.materials=[material];model.addChildNode(SCNNode(geometry:g))
}
let screen=SCNPlane(width:0.352,height:0.288)
let sm=SCNMaterial();sm.lightingModel = .constant;sm.diffuse.contents=NSImage(contentsOf:assets.appendingPathComponent("textures/lcd_off.png"))
screen.materials=[sm]
let lcd=SCNNode(geometry:screen);lcd.position=SCNVector3(0,0.2568,0.0205);model.addChildNode(lcd)
let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=0.56;camera.position=SCNVector3(0,0,2)
scene.rootNode.addChildNode(camera)
scene.background.contents=NSColor(calibratedWhite:0.12,alpha:1)
let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=scene;renderer.pointOfView=camera
let output=URL(fileURLWithPath:CommandLine.arguments[3],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for (name,angle) in [("front",Float(0)),("angle",Float(-0.5)),("back",Float.pi)] {
 model.eulerAngles=SCNVector3(0,angle,0)
 let image=renderer.snapshot(atTime:0,with:NSSize(width:550,height:800),antialiasingMode:.multisampling4X)
 var r=NSRect(origin:.zero,size:image.size)
 let cg=image.cgImage(forProposedRect:&r,context:nil,hints:nil)!
 try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
}
print("Verified",count,"groups and",triangles,"triangles; front/angle/back previews rendered.")
