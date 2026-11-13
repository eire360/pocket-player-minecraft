import Cocoa
import SceneKit
import ModelIO
func rgb(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->NSColor {NSColor(calibratedRed:r,green:g,blue:b,alpha:a)}
func rounded(_ r:NSRect,_ radius:CGFloat,_ color:NSColor){color.setFill();NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius).fill()}
func text(_ value:String,_ rect:NSRect,size:CGFloat,color:NSColor,weight:NSFont.Weight = .medium,align:NSTextAlignment = .left) {
 let p=NSMutableParagraphStyle();p.alignment=align
 (value as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:p])
}
let model=PodModel()
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let renderer = SCNRenderer(device:nil,options:nil)
renderer.scene=model.scene
renderer.pointOfView=model.camera
_ = renderer.snapshot(atTime:0,with:NSSize(width:500,height:810),antialiasingMode:.multisampling4X)
var groups:[[String:Any]]=[]
func values(_ s:SCNGeometrySource,_ i:Int,_ count:Int)->[Float] {
 (0..<count).map { j in
  let o=s.dataOffset+i*s.dataStride+j*s.bytesPerComponent
  return s.data.withUnsafeBytes { b in
   if s.bytesPerComponent==4 {return b.loadUnaligned(fromByteOffset:o,as:Float.self)}
   return Float(b.loadUnaligned(fromByteOffset:o,as:Double.self))
  }
 }
}
model.root.enumerateChildNodes {node,_ in
 guard let original=node.geometry, !["screen","screen-glass"].contains(node.name ?? "") else{return}
 var g=original
 var textImage:NSImage?=nil
 if let textGeometry=original as? SCNText,let value=textGeometry.string as? String {
    let bounds=textGeometry.boundingBox
    let w=bounds.max.x-bounds.min.x,h=bounds.max.y-bounds.min.y
    if w>0 && h>0 {
       let p=[SCNVector3(bounds.min.x,bounds.min.y,0),SCNVector3(bounds.max.x,bounds.min.y,0),SCNVector3(bounds.max.x,bounds.max.y,0),SCNVector3(bounds.min.x,bounds.max.y,0)]
       g=SCNGeometry(sources:[SCNGeometrySource(vertices:p),SCNGeometrySource(textureCoordinates:[CGPoint(x:0,y:1),CGPoint(x:1,y:1),CGPoint(x:1,y:0),CGPoint(x:0,y:0)])],elements:[SCNGeometryElement(indices:[Int32(0),1,2,0,2,3],primitiveType:.triangles)])
       let font=(textGeometry.font as? NSFont) ?? NSFont.systemFont(ofSize:1)
       let drawingFont=NSFont(descriptor:font.fontDescriptor,size:128) ?? NSFont.systemFont(ofSize:128)
       let attrs:[NSAttributedString.Key:Any]=[.font:drawingFont,.foregroundColor:NSColor.white]
       let size=(value as NSString).size(withAttributes:attrs)
       textImage=NSImage(size:size,flipped:true){r in
           (value as NSString).draw(in:r,withAttributes:attrs)
           return true
       }
    }
 }
 guard let positions=g.sources(for:.vertex).first else {return}
 let normals=g.sources(for:.normal).first
 let uvs=g.sources(for:.texcoord).first
 var primitiveScale:[Float]=[1,1,1]
 var desired:[Float]?=nil
 if let cylinder=original as? SCNCylinder {desired=[Float(cylinder.radius*2),Float(cylinder.height),Float(cylinder.radius*2)]}
 if let plane=original as? SCNPlane {desired=[Float(plane.width),Float(plane.height),0]}
 if let box=original as? SCNBox {desired=[Float(box.width),Float(box.height),Float(box.length)]}
 if let desired, positions.vectorCount>0 {
   let raw=(0..<positions.vectorCount).map {values(positions,$0,3)}
   for axis in 0..<3 {
      let span=raw.map{$0[axis]}.max()!-raw.map{$0[axis]}.min()!
      if span>0.000001 && desired[axis]>0 {primitiveScale[axis]=desired[axis]/span}
   }
 }
 var verts:[[Float]]=[]
 for i in 0..<positions.vectorCount {
  let scale=primitiveScale
  let p=zip(values(positions,i,3),scale).map(*)
  let adjusted=simd_inverse(node.simdPivot)*SIMD4<Float>(p[0],p[1],p[2],1)
  var v=node.convertPosition(SCNVector3(adjusted.x,adjusted.y,adjusted.z),to:model.root)
  if original is SCNText {
      let box=original.boundingBox
      let width=(box.max.x-box.min.x)*node.scale.x
      let ratio=(CGFloat(p[0])-box.min.x)/max(0.00001,box.max.x-box.min.x)
      v=SCNVector3(node.position.x-(ratio-0.5)*width,node.position.y+(CGFloat(p[1])-box.min.y)*node.scale.y,node.position.z)
  }
  let n=zip(normals.map {values($0,i,3)} ?? [0,0,1],scale).map { $0 / max(0.00001,$1) }
  let normal=node.convertVector(SCNVector3(n[0],n[1],n[2]),to:model.root)
  let uv=uvs.map {values($0,i,2)} ?? [0,0]
  verts.append([Float(v.x),Float(v.y),Float(v.z),Float(normal.x),Float(normal.y),Float(normal.z),uv[0],uv[1]])
 }
 for (idx,element) in g.elements.enumerated() {
  guard element.primitiveType == .triangles else {continue}
  let indices:[Int]=(0..<(element.primitiveCount*3)).map {i in
   element.data.withUnsafeBytes {b in
    switch element.bytesPerIndex {
    case 1:return Int(b.loadUnaligned(fromByteOffset:i,as:UInt8.self))
    case 2:return Int(b.loadUnaligned(fromByteOffset:i*2,as:UInt16.self))
    default:return Int(b.loadUnaligned(fromByteOffset:i*4,as:UInt32.self))
    }
   }
  }
  let material=original.materials[min(idx,max(0,original.materials.count-1))]
  var color:[Double]=[0.8,0.8,0.8,1]
  var texture=""
  if let c=material.diffuse.contents as? NSColor,let rgb=c.usingColorSpace(.sRGB) {color=[rgb.redComponent,rgb.greenComponent,rgb.blueComponent,rgb.alphaComponent].map(Double.init)}
  if let image=textImage ?? (material.diffuse.contents as? NSImage) {
   texture="model-decal-\(groups.count).png"
   var rect=NSRect(origin:.zero,size:image.size)
   if let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil),let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) {try? png.write(to:output.appendingPathComponent(texture))}
   if textImage == nil {color=[1,1,1,1]}
  }
  groups.append(["name":node.name ?? "mesh","vertices":verts,"indices":indices,"color":color,"texture":texture])
 }
}
let data=try JSONSerialization.data(withJSONObject:groups)
try data.write(to:output.appendingPathComponent("ipod-mesh.json"))
print("Exported \(groups.count) mesh groups")
