import Cocoa
import SceneKit
import simd

// A single indexed, welded mesh sweeps rounded rectangle outlines through a curved depth profile.
// Every front, side, bevel and back is real geometry; no stacked view layers are used.
struct EnclosureMesh {
    static func make(width: CGFloat, height: CGFloat, radius: CGFloat, profile: [(CGFloat, CGFloat)], backCrown: CGFloat = 0) -> SCNGeometry {
        let cornerSteps = 32
        let count = cornerSteps * 4
        var vertices: [SCNVector3] = []
        for (z, inset) in profile {
            let w = width / 2 - inset, h = height / 2 - inset, r = max(0.005, radius - inset)
            for corner in 0..<4 {
                let cx: CGFloat = (corner == 0 || corner == 3) ? w-r : -w+r
                let cy: CGFloat = corner < 2 ? h-r : -h+r
                for step in 0..<cornerSteps {
                    let a = CGFloat(corner) * .pi/2 + CGFloat(step) / CGFloat(cornerSteps-1) * .pi/2
                    vertices.append(SCNVector3(cx+r*cos(a),cy+r*sin(a),z))
                }
            }
        }
        var indices: [Int32] = []
        for ring in 0..<profile.count-1 {
            for i in 0..<count {
                let j = (i+1)%count
                let a=Int32(ring*count+i),b=Int32(ring*count+j),c=Int32((ring+1)*count+j),d=Int32((ring+1)*count+i)
                indices += [a,b,c,a,c,d]
            }
        }
        // Real gently crowned rear surface: changing normals bend studio reflections across the steel.
        for end in [0,profile.count-1] {
            let base=vertices.count, rings = end == 0 && backCrown > 0 ? 20:1
            for ring in 0..<rings {
                let scale=1-CGFloat(ring)/CGFloat(rings)
                for i in 0..<count {
                    let v=vertices[end*count+i]
                    let z=profile[end].0-(end == 0 ? backCrown*(1-scale*scale):0)
                    vertices.append(SCNVector3(v.x*scale,v.y*scale,z))
                }
            }
            for ring in 0..<rings-1 {for i in 0..<count {
                let j=(i+1)%count
                let a=Int32(base+ring*count+i),b=Int32(base+ring*count+j),c=Int32(base+(ring+1)*count+j),d=Int32(base+(ring+1)*count+i)
                indices += end == 0 ? [a,c,b,a,d,c]:[a,b,c,a,c,d]
            }}
            let center=vertices.count
            vertices.append(SCNVector3(0,0,profile[end].0-(end == 0 ? backCrown:0)))
            for i in 0..<count {
                let a=Int32(base+(rings-1)*count+i),b=Int32(base+(rings-1)*count+(i+1)%count),c=Int32(center)
                indices += end == 0 ? [c,b,a]:[c,a,b]
            }
        }
        // Average shared triangle normals on curved surfaces, keeping the caps separate.
        var normals=Array(repeating:SIMD3<Float>(0,0,0),count:vertices.count)
        func v(_ i:Int)->SIMD3<Float>{let p=vertices[i];return SIMD3(Float(p.x),Float(p.y),Float(p.z))}
        for t in stride(from:0,to:indices.count,by:3) {
            let a=Int(indices[t]),b=Int(indices[t+1]),c=Int(indices[t+2])
            let n=simd_cross(v(b)-v(a),v(c)-v(a))
            normals[a]+=n;normals[b]+=n;normals[c]+=n
        }
        let normalVectors=normals.map{n->SCNVector3 in let q=simd_length(n)>0 ? simd_normalize(n):SIMD3<Float>(0,0,1);return SCNVector3(CGFloat(q.x),CGFloat(q.y),CGFloat(q.z))}
        return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normalVectors)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
    // A revolved radial profile creates a rounded scroll wheel or a beveled annular button.
    static func lathe(profile:[(CGFloat,CGFloat)],from:CGFloat=0,to:CGFloat=2 * .pi,segments:Int=192)->SCNGeometry {
        var points:[SCNVector3]=[],normals:[SCNVector3]=[],indices:[Int32]=[]
        for i in 0...segments {
            let a=from+(to-from)*CGFloat(i)/CGFloat(segments)
            for j in profile.indices {
                let p=profile[j],prev=profile[(j+profile.count-1)%profile.count],next=profile[(j+1)%profile.count]
                let dr=next.0-prev.0,dz=next.1-prev.1,l=max(0.000001,hypot(dr,dz))
                points.append(SCNVector3(p.0*cos(a),p.0*sin(a),p.1))
                normals.append(SCNVector3(-dz/l*cos(a),-dz/l*sin(a),dr/l))
            }
        }
        let n=profile.count
        for i in 0..<segments {for j in 0..<n {
            let a=Int32(i*n+j),b=Int32((i+1)*n+j),c=Int32((i+1)*n+(j+1)%n),d=Int32(i*n+(j+1)%n)
            indices += [a,c,b,a,d,c]
        }}
        if to-from < 2 * .pi-0.001 {
            for end in [0,segments] {
                let center=points.count
                let a=from+(to-from)*CGFloat(end)/CGFloat(segments)
                let r=profile.map{$0.0}.reduce(0,+)/CGFloat(n),z=profile.map{$0.1}.reduce(0,+)/CGFloat(n)
                points.append(SCNVector3(r*cos(a),r*sin(a),z));normals.append(SCNVector3(end==0 ? sin(a):(-sin(a)),end==0 ? -cos(a):cos(a),0))
                for j in 0..<n {indices += end==0 ? [Int32(center),Int32(end*n+(j+1)%n),Int32(end*n+j)] : [Int32(center),Int32(end*n+j),Int32(end*n+(j+1)%n)]}
            }
        }
        return SCNGeometry(sources:[SCNGeometrySource(vertices:points),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
}

final class PodModel {
    let scene=SCNScene(),root=SCNNode(),lcdMaterial=SCNMaterial(),camera=SCNNode()
    let wheelY:CGFloat = -1.055
    let screenRect=NSRect(x:-1.10,y:0.705,width:2.20,height:1.80)
    var meshCount=0,triangleCount=0
    init(){build()}
    func material(_ color:NSColor,metal:CGFloat=0,rough:CGFloat=0.35,coat:CGFloat=0)->SCNMaterial {
        let m=SCNMaterial();m.lightingModel = .physicallyBased;m.diffuse.contents=color
        m.metalness.contents=metal;m.roughness.contents=rough;m.clearCoat.contents=coat;m.clearCoatRoughness.contents=0.12
        return m
    }
    @discardableResult func add(_ g:SCNGeometry,_ name:String,_ mat:SCNMaterial,_ pos:SCNVector3=SCNVector3Zero,parent:SCNNode?=nil)->SCNNode {
        g.materials=[mat];let n=SCNNode(geometry:g);n.name=name;n.position=pos;(parent ?? root).addChildNode(n)
        meshCount+=1;triangleCount+=g.elements.reduce(0){$0+$1.primitiveCount};return n
    }
    func bevelCurve()->NSBezierPath {
        let p=NSBezierPath();p.move(to:NSPoint(x:0,y:1));p.curve(to:NSPoint(x:1,y:0),controlPoint1:NSPoint(x:0.5523,y:1),controlPoint2:NSPoint(x:1,y:0.5523));p.flatness=0.001;return p
    }
    func slab(_ rect:NSRect,radius:CGFloat,depth:CGFloat,z:CGFloat,name:String,mat:SCNMaterial)->SCNNode {
        let path=NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius);path.flatness=0.0008
        let g=SCNShape(path:path,extrusionDepth:depth);g.chamferRadius=min(0.008,depth/3);g.chamferProfile=bevelCurve()
        return add(g,name,mat,SCNVector3(0,0,z))
    }
    @discardableResult func lettering(_ string:String,height:CGFloat,position:SCNVector3,back:Bool=false,ink:NSColor=NSColor(white:0.36,alpha:1),weight:NSFont.Weight = .medium)->SCNNode {
        let g=SCNText(string:string,extrusionDepth:0.0005);g.font=NSFont.systemFont(ofSize:1,weight:weight);g.flatness=0.0005;g.chamferRadius=0
        let mat=material(ink,metal:back ? 0.8:0,rough:back ? 0.43:0.65)
        let n=add(g,"mark-"+string,mat,position)
        let b=g.boundingBox;let h=max(0.001,b.max.y-b.min.y);let scale=height/h
        n.scale=SCNVector3(scale,scale,scale)
        n.pivot=SCNMatrix4MakeTranslation((b.min.x+b.max.x)/2,b.min.y,0)
        if back{n.eulerAngles.y = .pi}
        return n
    }
    func build() {
        scene.rootNode.addChildNode(root);root.name="iPod — solid mesh assembly"
        camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=3.35
        camera.camera!.zNear=0.1;camera.camera!.zFar=50;camera.camera!.wantsHDR=false;camera.position=SCNVector3(0,0,12);scene.rootNode.addChildNode(camera)
        let environment=NSImage(size:NSSize(width:2048,height:1024),flipped:false){r in
            rgb(0.075,0.085,0.105).setFill();r.fill()
            let left=NSBezierPath(roundedRect:NSRect(x:120,y:100,width:420,height:820),xRadius:90,yRadius:90)
            NSGradient(colors:[rgb(0.55,0.59,0.65),.white,rgb(0.76,0.79,0.84)])!.draw(in:left,angle:0)
            let right=NSBezierPath(roundedRect:NSRect(x:1330,y:40,width:210,height:920),xRadius:65,yRadius:65)
            NSGradient(colors:[rgb(0.45,0.50,0.58),.white,rgb(0.72,0.75,0.79)])!.draw(in:right,angle:0)
            rounded(NSRect(x:690,y:735,width:500,height:190),65,rgb(0.73,0.77,0.82))
            return true
        }
        scene.lightingEnvironment.contents=environment;scene.lightingEnvironment.intensity=0.85
        func light(_ pos:SCNVector3,_ intensity:CGFloat){let n=SCNNode();n.light=SCNLight();n.light!.type = .omni;n.light!.intensity=intensity;n.light!.attenuationFalloffExponent=0;n.position=pos;scene.rootNode.addChildNode(n)}
        light(SCNVector3(-4,6,8),180);light(SCNVector3(5,-1,6),60)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=90;scene.rootNode.addChildNode(ambient)
        let steel=material(rgb(0.79,0.81,0.84),metal:1,rough:0.17)
        let shellProfile:[(CGFloat,CGFloat)]=[(-0.225,0.085),(-0.222,0.061),(-0.212,0.038),(-0.197,0.020),(-0.176,0.007),(-0.151,0),(-0.06,0),(-0.025,0.002),(0.004,0.010),(0.024,0.025),(0.034,0.044)]
        add(EnclosureMesh.make(width:3.4,height:5.67,radius:0.29,profile:shellProfile,backCrown:0.018),"polished stainless back and curved sidewalls",steel)
        let seam=material(rgb(0.28,0.29,0.30),metal:0.6,rough:0.35)
        add(EnclosureMesh.make(width:3.365,height:5.635,radius:0.274,profile:[(0.032,0),(0.041,0)]),"precision case seam",seam)
        // The plastic face has a real opening for the recessed LCD.
        let outer=NSBezierPath(roundedRect:NSRect(x:-1.674,y:-2.809,width:3.348,height:5.618),xRadius:0.27,yRadius:0.27)
        outer.windingRule = .evenOdd
        let hole=NSBezierPath(roundedRect:NSRect(x:-1.201,y:0.608,width:2.402,height:1.996),xRadius:0.068,yRadius:0.068)
        outer.append(hole);outer.flatness=0.0008
        let face=SCNShape(path:outer,extrusionDepth:0.098);face.chamferRadius=0.027;face.chamferProfile=bevelCurve();face.chamferMode = .both
        add(face,"curved polycarbonate faceplate with LCD aperture",material(rgb(0.79,0.785,0.771),rough:0.32,coat:0.6),SCNVector3(0,0,0.054))
        let gasket=slab(NSRect(x:-1.204,y:0.605,width:2.408,height:2.002),radius:0.066,depth:0.012,z:0.112,name:"recessed screen gasket",mat:material(rgb(0.065,0.07,0.075),rough:0.55))
        gasket.name="screen-frame"
        let screen=SCNPlane(width:2.20,height:1.80);screen.cornerRadius=0.008;screen.cornerSegmentCount=12
        lcdMaterial.lightingModel = .constant;lcdMaterial.diffuse.magnificationFilter = .linear;lcdMaterial.diffuse.minificationFilter = .linear
        add(screen,"screen",lcdMaterial,SCNVector3(0,1.605,0.127))
        let glass=SCNPlane(width:2.22,height:1.82);glass.cornerRadius=0.012
        let gm=material(NSColor(white:0.98,alpha:0.025),rough:0.07,coat:0.6);gm.transparency=0.18;gm.writesToDepthBuffer=false;gm.blendMode = .alpha
        add(glass,"screen-glass",gm,SCNVector3(0,1.605,0.131)).renderingOrder=2
        // Four independent, softly beveled buttons surround a sculpted mechanical wheel.
        let recess=SCNCylinder(radius:1.452,height:0.014);recess.radialSegmentCount=256
        let rec=add(recess,"wheel cavity",material(rgb(0.45,0.46,0.46),rough:0.65),SCNVector3(0,wheelY,0.145));rec.eulerAngles.x = .pi/2
        let buttonMaterial=material(rgb(0.74,0.737,0.724),rough:0.35,coat:0.25)
        let profile:[(CGFloat,CGFloat)]=[(1.142,0.160),(1.142,0.187),(1.153,0.208),(1.184,0.219),(1.395,0.219),(1.425,0.204),(1.441,0.181),(1.441,0.160)]
        for (name,center) in [("menu",CGFloat.pi/2),("previous",CGFloat.pi),("play",CGFloat.pi*1.5),("next",CGFloat(0))] {
            add(EnclosureMesh.lathe(profile:profile,from:center - .pi/4+0.008,to:center + .pi/4-0.008,segments:64),name,buttonMaterial,SCNVector3(0,wheelY,0))
        }
        let wheelProfile:[(CGFloat,CGFloat)]=[(0,0.181),(0,0.235),(1.065,0.235),(1.103,0.229),(1.125,0.213),(1.129,0.190),(1.12,0.179)]
        add(EnclosureMesh.lathe(profile:wheelProfile),"scroll",material(rgb(0.73,0.732,0.72),rough:0.56,coat:0.08),SCNVector3(0,wheelY,0))
        let centerProfile:[(CGFloat,CGFloat)]=[(0,0.231),(0,0.250),(0.361,0.250),(0.385,0.244),(0.397,0.230),(0.392,0.219)]
        add(EnclosureMesh.lathe(profile:centerProfile),"select",material(rgb(0.77,0.768,0.755),rough:0.32,coat:0.4),SCNVector3(0,wheelY,0))
        // Printed symbols are texture decals on the actual button surfaces.
        let marks=NSImage(size:NSSize(width:900,height:900),flipped:true){r in
            let ink=rgb(0.43,0.44,0.43)
            text("menu",NSRect(x:290,y:27,width:320,height:80),size:50,color:ink,weight:.bold,align:.center)
            func tri(_ x:CGFloat,_ y:CGFloat,_ backwards:Bool){let p=NSBezierPath();p.move(to:NSPoint(x:x,y:y));p.line(to:NSPoint(x:x+(backwards ? 25:-25),y:y-16));p.line(to:NSPoint(x:x+(backwards ? 25:-25),y:y+16));p.close();ink.setFill();p.fill()}
            for x:CGFloat in [30,55]{tri(x,450,true)};rounded(NSRect(x:24,y:434,width:5,height:32),0.5,ink)
            for x:CGFloat in [842,867]{tri(x,450,false)};rounded(NSRect(x:871,y:434,width:5,height:32),0.5,ink)
            tri(443,847,false);rounded(NSRect(x:459,y:831,width:7,height:32),0.5,ink);rounded(NSRect(x:472,y:831,width:7,height:32),0.5,ink)
            return true
        }
        let markMat=SCNMaterial();markMat.lightingModel = .constant;markMat.diffuse.contents=marks;markMat.writesToDepthBuffer=false
        let markPlane=SCNPlane(width:2.87,height:2.87);markPlane.materials=[markMat]
        add(markPlane,"printed button legends",markMat,SCNVector3(0,wheelY,0.221)).renderingOrder=3
        // Rear lettering is actual shallow text geometry, attached to the metal surface.
        lettering("\u{f8ff}",height:0.55,position:SCNVector3(0,1.35,-0.244),back:true,weight:.regular)
        lettering("iPod",height:0.37,position:SCNVector3(0,0.78,-0.245),back:true,weight:.medium)
        lettering("5GB",height:0.10,position:SCNVector3(0,-1.75,-0.240),back:true)
        lettering("Designed by Apple in California. Assembled in Taiwan.",height:0.047,position:SCNVector3(0,-2.03,-0.236),back:true,weight:.regular)
        lettering("Model No. M8541    EMC No. 1910",height:0.047,position:SCNVector3(0,-2.13,-0.235),back:true,weight:.regular)
        lettering("© 2001 Apple Computer, Inc.",height:0.047,position:SCNVector3(0,-2.23,-0.234),back:true,weight:.regular)
        lettering("FCC  CE",height:0.105,position:SCNVector3(0,-2.43,-0.231),back:true,weight:.regular)
        // Solid top-edge hardware, so edge-on inspection has ports rather than an empty box.
        let black=material(rgb(0.025,0.03,0.035),rough:0.9)
        let socket=SCNCylinder(radius:0.062,height:0.014);socket.radialSegmentCount=64
        add(socket,"headphone jack",black,SCNVector3(-1.07,2.835,-0.074))
        let port=SCNBox(width:0.35,height:0.011,length:0.15,chamferRadius:0.022);port.chamferSegmentCount=8
        add(port,"FireWire port",black,SCNVector3(0,2.835,-0.07))
        let hold=SCNBox(width:0.39,height:0.025,length:0.12,chamferRadius:0.025);hold.chamferSegmentCount=8
        add(hold,"hold",material(rgb(0.78,0.79,0.78),rough:0.4),SCNVector3(1.0,2.838,-0.075))
    }
    func export(to directory:URL) {
        scene.write(to:directory.appendingPathComponent("iPod Model.scn"),options:nil,delegate:nil,progressHandler:nil)
        let report="Native SceneKit model\nMesh objects: \(meshCount)\nExplicit mesh triangles: \(triangleCount)\nEnclosure width: 3.40; height: 5.67; maximum depth: 0.493 model units\nCurved case: indexed meshes with shared surface vertices and computed vertex normals\nWheel: revolved cross-section meshes and four separate annular button meshes\nMaterials: physically based steel and coated plastic, lit by a studio environment\nLCD: live texture driven by the existing Music controller\n"
        try? report.write(to:directory.appendingPathComponent("Model Details.txt"),atomically:true,encoding:.utf8)
    }
}
