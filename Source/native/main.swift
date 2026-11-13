import Cocoa
import SceneKit
import Darwin

// Set before any helper writes: new files are 0600, directories 0700.
umask(0o077)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let player = PlayerController()
let directory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory:true)
    : Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("live",isDirectory:true)
let commands = directory.appendingPathComponent("commands",isDirectory:true)
var session = ""
var lastClient = Date()
var lastFrame = Date.distantPast
func privateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let attr = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attr[.type] as? FileAttributeType == .typeDirectory,
          (attr[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
        throw NSError(domain: "PocketPlayerPrivacy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsafe local connection directory."])
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
}
try privateDirectory(directory)
try privateDirectory(commands)
// Tighten snapshots left by older versions; refuse links and files belonging to other accounts.
for folder in [directory, commands] {
    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
        let attr = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attr[.type] as? FileAttributeType == .typeRegular,
              (attr[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { continue }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
player.face = PodView(frame:NSRect(x:0,y:0,width:480,height:800))
player.face.controller = player
player.home()
var active = false
func frame() {
    let image = NSImage(size:NSSize(width:480,height:392),flipped:true) { rect in
        player.face.paintScreen(player,rect)
        return true
    }
    // Emit a fixed 8-bit sRGB image, independent of Retina scale and
    // extended-range AppKit backing stores.
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:480,pixelsHigh:392,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:480*4,bitsPerPixel:32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    image.draw(in:NSRect(x:0,y:0,width:480,height:392),from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
    NSGraphicsContext.restoreGraphicsState()
    if let png=bitmap.representation(using:.png,properties:[:]) {
        try? png.write(to:directory.appendingPathComponent("lcd.png"),options:.atomic)
    }
    let state:[String:Any] = ["session":session,"pid":ProcessInfo.processInfo.processIdentifier,"connected":player.connected,"busy":player.busy,"status":player.status,"title":player.playback.title,"artist":player.playback.artist,"page":player.page.title,"playing":player.playback.playing]
    if let data=try? JSONSerialization.data(withJSONObject:state) {
        try? data.write(to:directory.appendingPathComponent("state.json"),options:.atomic)
    }
}
func perform(_ line:String) {
    let parts=line.split(separator:" ",maxSplits:1).map(String.init)
    switch parts.first ?? "" {
    case "connect": active=true;player.connect()
    case "menu": player.back()
    case "select": player.select()
    case "next": player.skip(true)
    case "previous": player.skip(false)
    case "play": player.playPause()
    case "home": player.home()
    case "now": player.nowPlaying()
    case "step":
        if parts.count==2,let n=Int(parts[1]),abs(n)<=8 {player.step(n)}
    case "row":
        if parts.count==2,let n=Int(parts[1]),(0..<6).contains(n) {player.select(player.page.offset+n)}
    case "visible": active = parts.last=="1"
    case "quit": app.terminate(nil)
    default: break
    }
    frame()
}
func receive() {
    if let data=try? Data(contentsOf:directory.appendingPathComponent("client.json")),
       let client=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
       let current=client["session"] as? String,let heartbeat=client["heartbeat"] as? Double {
        session=current
        lastClient=Date(timeIntervalSince1970:heartbeat)
    }
    if Date().timeIntervalSince(lastClient)>40 {app.terminate(nil);return}
    let files=((try? FileManager.default.contentsOfDirectory(at:commands,includingPropertiesForKeys:nil)) ?? [])
        .filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
    for file in files.prefix(24) {
        defer{try? FileManager.default.removeItem(at:file)}
        guard let data=try? Data(contentsOf:file),
              let request=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              request["session"] as? String == session,
              let command=request["command"] as? String else{continue}
        perform(command)
    }
    if Date().timeIntervalSince(lastFrame)>=1 {
        lastFrame=Date()
        if active {player.poll()}
        frame()
    }
}
let controlTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){_ in receive()}
receive()
app.run()
