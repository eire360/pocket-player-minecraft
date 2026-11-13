import Cocoa
import SceneKit

final class PodAccessibleButton:NSAccessibilityElement {
    var invoke:()->Void = {}
    override func accessibilityPerformPress()->Bool {invoke();return true}
}
final class PodView:SCNView {
    weak var controller:PlayerController?
    let model=PodModel()
    var spinX:CGFloat=0,spinY:CGFloat=0
    var downPoint=NSPoint.zero,downSpin=NSPoint.zero,lastWheelAngle:CGFloat=0,wheelRemainder:CGFloat=0
    var rotating=false,wheeling=false,dragged=false,pressedName=""
    var scrollRemainder:CGFloat=0
    var lastScreenState="",lastAccessibilityState=""
    var cachedArt:NSImage?,lastArtID:ObjectIdentifier?
    var hasExported=false
    override var acceptsFirstResponder:Bool{true}
    override var mouseDownCanMoveWindow:Bool{false}
    override init(frame:NSRect,options:[String:Any]?=nil){
        super.init(frame:frame,options:options)
        scene=model.scene;pointOfView=model.camera;backgroundColor = .clear
        antialiasingMode = .multisampling4X;preferredFramesPerSecond=30;rendersContinuously=false;isPlaying=false;allowsCameraControl=false
        setAccessibilityElement(false);setAccessibilityLabel("3D iPod player")
    }
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();window?.makeFirstResponder(self);fitCamera()}
    override func layout(){super.layout();fitCamera()}
    func fitCamera(){
        guard bounds.width > 0,bounds.height > 0 else{return}
        var maxX:CGFloat=0,maxY:CGFloat=0
        // Fit all eight corners of the complete enclosure, including raised controls.
        for x:CGFloat in [-1.73,1.73] {for y:CGFloat in [-2.88,2.88] {for z:CGFloat in [-0.26,0.28] {
            let p=model.root.convertPosition(SCNVector3(x,y,z),to:nil)
            maxX=max(maxX,abs(p.x));maxY=max(maxY,abs(p.y))
        }}}
        let aspect=bounds.width/bounds.height
        model.camera.camera?.orthographicScale=Double(max(3.35,maxY*1.12,maxX/aspect*1.12))
        needsDisplay=true
    }
    func rebuildButtons(){updateAccessibility()}
    func updateScreen(){
        guard let c=controller else{return}
        let p=c.page
        if lastArtID != c.artwork.map({ObjectIdentifier($0)}) {lastArtID=c.artwork.map({ObjectIdentifier($0)});cachedArt=c.artwork}
        let state="\(p.id)|\(p.selection)|\(p.offset)|\(c.busy)|\(c.status)|\(c.playback.id)|\(Int(c.position))|\(c.playback.volume)|\(Date()<c.volumeUntil)|\(c.seekMode)|\(c.playback.playing)|\(c.held)|\(lastArtID.hashValue)"
        if state != lastScreenState {
            lastScreenState=state
            let image=NSImage(size:NSSize(width:480,height:392),flipped:true){[weak self] rect in
                guard let s=self else{return false};s.paintScreen(c,rect);return true
            }
            // Rasterize now so the renderer never executes AppKit drawing on its own thread.
            var rect=NSRect(x:0,y:0,width:480,height:392)
            model.lcdMaterial.diffuse.contents=image.cgImage(forProposedRect:&rect,context:nil,hints:[.interpolation:NSImageInterpolation.high])
            needsDisplay=true
        }
        updateAccessibility()
        
    }
    func lcdText(_ value:String,_ rect:NSRect,_ size:CGFloat,_ color:NSColor=rgb(0.22,0.25,0.29),center:Bool=false){
        let style=NSMutableParagraphStyle();style.lineBreakMode = .byTruncatingTail;style.alignment=center ? .center:.left
        let font=NSFont(name:"Krungthep",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:.medium)
        (value as NSString).draw(in:rect,withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:style])
    }
    func paintScreen(_ c:PlayerController,_ rect:NSRect){
        NSGradient(colors:[rgb(0.81,0.85,0.90),rgb(0.74,0.80,0.88),rgb(0.84,0.88,0.94)])!.draw(in:rect,angle:12)
        let ink=rgb(0.25,0.28,0.34),p=c.page
        lcdText(c.held ? "Locked":p.title,NSRect(x:50,y:9,width:380,height:47),35,ink,center:true)
        // A connection mark shaped like the source LCD's battery graphic; not a battery measurement.
        let battery=NSRect(x:414,y:20,width:47,height:24);ink.setStroke();let border=NSBezierPath(rect:battery);border.lineWidth=2;border.stroke()
        if c.connected{for i in 0..<5{rounded(NSRect(x:419+i*8,y:24,width:5,height:16),0,ink)}}
        stroke([NSPoint(x:0,y:64),NSPoint(x:480,y:64)],color:ink,width:3)
        if c.busy || !c.status.isEmpty {lcdText(c.status,NSRect(x:25,y:166,width:430,height:80),28,ink,center:true);return}
        if p.nowPlaying {
            let art=NSRect(x:20,y:91,width:146,height:146)
            if let image=cachedArt {image.draw(in:art,from:.zero,operation:.sourceOver,fraction:0.9,respectFlipped:true,hints:nil)}
            else{rounded(art,2,ink.withAlphaComponent(0.15));lcdText("♫",NSRect(x:20,y:110,width:146,height:100),75,ink,center:true)}
            lcdText(c.playback.title,NSRect(x:184,y:101,width:274,height:47),29,ink)
            lcdText(c.playback.artist,NSRect(x:184,y:157,width:274,height:41),25,ink)
            lcdText(c.playback.album,NSRect(x:184,y:202,width:274,height:38),23,ink.withAlphaComponent(0.8))
            let volume=Date()<c.volumeUntil
            lcdText(c.seekMode ? "Turn wheel to seek":c.playback.playing ? "Playing":"Paused",NSRect(x:20,y:263,width:440,height:32),23,ink,center:true)
            let bar=NSRect(x:23,y:310,width:434,height:19);let path=NSBezierPath(rect:bar);path.lineWidth=2;ink.setStroke();path.stroke()
            let fraction=volume ? Double(c.playback.volume)/100:c.position/max(1,c.playback.duration)
            rounded(NSRect(x:27,y:314,width:426*min(1,max(0,fraction)),height:11),0,ink)
            lcdText(volume ? "Volume":timeLabel(c.position),NSRect(x:22,y:344,width:200,height:36),25,ink)
            lcdText(volume ? "\(c.playback.volume)%":"−"+timeLabel(c.playback.duration-c.position),NSRect(x:294,y:344,width:170,height:36),25,ink)
            return
        }
        guard !p.rows.isEmpty else{lcdText("No items",NSRect(x:20,y:174,width:440,height:40),30,ink,center:true);return}
        for i in p.offset..<min(p.rows.count,p.offset+6){
            let y=74+CGFloat(i-p.offset)*48,selected=i==p.selection,row=p.rows[i]
            if selected{rounded(NSRect(x:0,y:y,width:480,height:48),0,ink)}
            let fg=selected ? rgb(0.90,0.92,0.95):ink
            lcdText(row.title,NSRect(x:16,y:y+3,width:422,height:44),32,fg)
            lcdText("›",NSRect(x:441,y:y-1,width:35,height:46),39,fg)
        }
    }
    func nodeName(_ hit:SCNHitTestResult?)->String {hit?.node.name ?? ""}
    func hit(_ event:NSEvent)->SCNHitTestResult? {
        let point=convert(event.locationInWindow,from:nil)
        return hitTest(point,options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.backFaceCulling:true]).first{ h in
            !["printed button legends","screen-glass"].contains(h.node.name ?? "")
        }
    }
    override func mouseDown(with event:NSEvent){
        window?.makeFirstResponder(self);downPoint=convert(event.locationInWindow,from:nil);downSpin=NSPoint(x:spinY,y:spinX);dragged=false
        if event.modifierFlags.contains(.option){rotating=true;return}
        let h=hit(event);pressedName=nodeName(h)
        if pressedName=="scroll"{
            wheeling=true;wheelRemainder=0;lastWheelAngle=wheelAngle(downPoint);return
        }
        if ["menu","previous","play","next","select","screen","hold"].contains(pressedName){return}
        if event.clickCount==2 {frontView();return}
        window?.performDrag(with:event)
    }
    func wheelAngle(_ point:NSPoint)->CGFloat {
        let world=model.root.convertPosition(SCNVector3(0,model.wheelY,0.24),to:nil),p=projectPoint(world)
        return atan2(point.y-p.y,point.x-p.x)
    }
    override func mouseDragged(with event:NSEvent){
        let p=convert(event.locationInWindow,from:nil);dragged=true
        if rotating {
            spinY=downSpin.x+(p.x-downPoint.x)*0.012;spinX=max(-1.3,min(1.3,downSpin.y-(p.y-downPoint.y)*0.009));applySpin();return
        }
        if wheeling {
            let a=wheelAngle(p);var d=a-lastWheelAngle;if d > .pi{d-=2 * .pi};if d < -.pi{d+=2 * .pi};lastWheelAngle=a;wheelRemainder-=d
            let ticks=Int(wheelRemainder/0.16);if ticks != 0{wheelRemainder-=CGFloat(ticks)*0.16;controller?.step(ticks)}
        }
    }
    override func mouseUp(with event:NSEvent){
        defer{rotating=false;wheeling=false;pressedName=""}
        guard !dragged,!wheeling,!rotating else{return}
        if pressedName=="screen",let h=hit(event),let c=controller,!c.page.nowPlaying{
            let local=model.root.convertPosition(h.worldCoordinates,from:nil)
            let y=(model.screenRect.maxY-local.y)/model.screenRect.height*392
            if y>=74 {let index=c.page.offset+Int((y-74)/48);if index<c.page.offset+6{c.select(index)}}
        }else{perform(pressedName)}
    }
    func perform(_ name:String){
        switch name{case "menu":controller?.back();case "previous":controller?.skip(false);case "next":controller?.skip(true);case "play":controller?.playPause();case "select":controller?.select();case "hold":toggleHold();default:break}
    }
    override func scrollWheel(with event:NSEvent){
        scrollRemainder += event.scrollingDeltaY*(event.hasPreciseScrollingDeltas ? 0.08:1)
        let ticks=Int(scrollRemainder);if ticks != 0{scrollRemainder-=CGFloat(ticks);controller?.step(-ticks)}
    }
    override func keyDown(with event:NSEvent){
        guard let c=controller else{return};let cmd=event.modifierFlags.contains(.command)
        switch event.keyCode{case 126:c.step(-1);case 125:c.step(1);case 36,76:c.select();case 53:c.back();case 123:cmd ? c.skip(false):c.back();case 124:cmd ? c.skip(true):c.select();case 49:c.playPause();default:super.keyDown(with:event)}
    }
    func applySpin(){
        SCNTransaction.begin();SCNTransaction.disableActions=true;model.root.eulerAngles=SCNVector3(spinX,spinY,0);SCNTransaction.commit();fitCamera();needsDisplay=true;lastAccessibilityState="";updateAccessibility()
    }
    @objc func frontView(){spinX=0;spinY=0;applySpin()}
    @objc func backView(){spinX=0;spinY = .pi;applySpin()}
    @objc func angleView(){spinX = -0.08;spinY = -0.42;applySpin()}
    @objc func sideView(){spinX=0;spinY = -.pi/2;applySpin()}
    @objc func toggleHold(){controller?.held.toggle();updateScreen()}
    override func menu(for event:NSEvent)->NSMenu?{makeMenu()}
    func makeMenu()->NSMenu {
        let menu=NSMenu()
        for (title,action,target) in [
            ("Front view",#selector(frontView),self as AnyObject),("Angled view",#selector(angleView),self as AnyObject),
            ("Back view",#selector(backView),self as AnyObject),("Side view",#selector(sideView),self as AnyObject),
            (controller?.held == true ? "Unlock controls":"Lock controls",#selector(toggleHold),self as AnyObject),
            ("Search Music Library…",#selector(PlayerController.search),controller as AnyObject),
            ("Keep on Top",#selector(PlayerController.toggleFloat),controller as AnyObject),
            ("Save Preview",#selector(PlayerController.savePreview),controller as AnyObject),
            ("Quit Pocket Player",#selector(PlayerController.quit),controller as AnyObject)] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=target;menu.addItem(item)
        };return menu
    }
    func updateAccessibility(){
        guard let c=controller,let w=window else{return}
        let p=c.page,key="\(p.id)|\(p.offset)|\(p.nowPlaying)|\(c.busy)|\(spinX)|\(spinY)"
        guard key != lastAccessibilityState else{return};lastAccessibilityState=key
        var buttons:[PodAccessibleButton]=[]
        func button(_ label:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ height:CGFloat,_ action:@escaping()->Void){
            let world=model.root.convertPosition(SCNVector3(x,y,0.25),to:nil),point=projectPoint(world)
            let rect=convert(NSRect(x:point.x-width/2,y:point.y-height/2,width:width,height:height),to:nil)
            let b=PodAccessibleButton();b.setAccessibilityRole(.button);b.setAccessibilityEnabled(true);b.setAccessibilityLabel(label);b.setAccessibilityParent(self);b.setAccessibilityFrame(w.convertToScreen(rect));b.invoke=action;buttons.append(b)
        }
        if cos(spinY)>0.15 {
            if !c.busy && !p.nowPlaying {
                for i in p.offset..<min(p.rows.count,p.offset+6){let y=model.screenRect.maxY-(98+CGFloat(i-p.offset)*48)/392*model.screenRect.height;button(p.rows[i].title,0,y,240,25){[weak c] in c?.select(i)}}
            }
            for (name,x,y,label) in [("menu",CGFloat(0),model.wheelY+1.29,"Menu"),("previous",-1.29,model.wheelY,"Previous track"),("next",1.29,model.wheelY,"Next track"),("play",0,model.wheelY-1.29,"Play or pause"),("select",0,model.wheelY,"Select")] {
                button(label,x,y,name=="select" ? 70:40,name=="select" ? 70:32){[weak self] in self?.perform(name)}
            }
        }
        setAccessibilityChildren(buttons)
    }
    func savePreview(){
        let image=snapshot();guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else{return}
        let directory=Bundle.main.bundleURL.deletingLastPathComponent();try? data.write(to:directory.appendingPathComponent("Preview.png"));model.export(to:directory)
    }
}
