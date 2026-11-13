import Cocoa
import SceneKit

// All Music requests are serialized off the UI thread. No web account or API token is used.
struct Song {
    let id: String, title: String, artist: String, album: String
    let duration: Double
}
struct Playlist { let id: String, name: String }
struct Playback {
    var id = "", title = "Nothing playing", artist = "", album = ""
    var duration = 0.0, position = 0.0, volume = 50
    var playing = false, shuffle = false, repeatMode = "off"
}
struct MusicFailure: Error { let message: String }
func quoted(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
final class MusicBridge {
    let queue = DispatchQueue(label: "local.pocketplayer.music", qos: .userInitiated)
    func execute(_ body: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let source = "with timeout of 25 seconds\ntell application id \"com.apple.Music\"\n\(body)\nend tell\nend timeout"
        guard let script = NSAppleScript(source: source) else { throw MusicFailure(message: "Couldn’t prepare the Music request.") }
        let result = script.executeAndReturnError(&error)
        if let error = error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw MusicFailure(message: "Allow Pocket Player Bridge (or Minecraft) in System Settings → Privacy & Security → Automation → Music, then connect again.") }
            let raw = error[NSAppleScript.errorMessage] as? String ?? ""
            let message: String
            if code == -1712 { message = "Music took too long to respond. Open Music, wait for your library to load, then try again." }
            else if raw.count > 240 { message = "Music couldn’t read that library item (error \(code)). Refresh your library and try again." }
            else { message = raw.isEmpty ? "Music couldn’t complete that request (error \(code))." : raw }
            throw MusicFailure(message: message)
        }
        return result
    }
    func request<T>(_ work: @escaping (MusicBridge) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            let result = Result { try work(self) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func playlists() throws -> [Playlist] {
        let data = try execute("set playlistIDs to get persistent ID of (every user playlist whose special kind is not folder)\nset playlistNames to get name of (every user playlist whose special kind is not folder)\nreturn {playlistIDs, playlistNames}")
        guard data.numberOfItems == 2 else { return [] }
        let ids = data.atIndex(1)!, names = data.atIndex(2)!
        return (1...max(1, ids.numberOfItems)).compactMap { i in
            guard let id = ids.atIndex(i)?.stringValue, let name = names.atIndex(i)?.stringValue else { return nil }
            return Playlist(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func songs(in playlist: String? = nil) throws -> [Song] {
        let target = playlist.map { "user playlist (first index of every user playlist whose persistent ID is \(quoted($0)))" } ?? "library playlist 1"
        // Resolve the playlist by persistent ID; user-visible names never become identifiers.
        let reference = playlist.map { "first user playlist whose persistent ID is \(quoted($0))" } ?? target
        let data = try execute("set p to \(reference)\nreturn {persistent ID of every track of p, name of every track of p, artist of every track of p, album of every track of p, duration of every track of p}")
        guard data.numberOfItems == 5 else { return [] }
        let columns = (1...5).map { data.atIndex($0)! }
        guard columns[0].numberOfItems > 0 else { return [] }
        return (1...columns[0].numberOfItems).compactMap { i in
            guard let id = columns[0].atIndex(i)?.stringValue else { return nil }
            return Song(id: id, title: columns[1].atIndex(i)?.stringValue ?? "Untitled", artist: columns[2].atIndex(i)?.stringValue ?? "", album: columns[3].atIndex(i)?.stringValue ?? "", duration: columns[4].atIndex(i)?.doubleValue ?? 0)
        }
    }
    func status() throws -> Playback {
        let d = try execute("""
        set details to {"", "Nothing playing", "", "", 0, 0}
        try
            set t to current track
            set details to {persistent ID of t, name of t, artist of t, album of t, duration of t, player position}
        end try
        return details & {(player state is playing), sound volume, shuffle enabled, (song repeat as text)}
        """)
        var p = Playback()
        p.id = d.atIndex(1)?.stringValue ?? ""; p.title = d.atIndex(2)?.stringValue ?? "Nothing playing"
        p.artist = d.atIndex(3)?.stringValue ?? ""; p.album = d.atIndex(4)?.stringValue ?? ""
        p.duration = d.atIndex(5)?.doubleValue ?? 0; p.position = d.atIndex(6)?.doubleValue ?? 0
        p.playing = d.atIndex(7)?.booleanValue ?? false; p.volume = Int(d.atIndex(8)?.int32Value ?? 50)
        p.shuffle = d.atIndex(9)?.booleanValue ?? false; p.repeatMode = d.atIndex(10)?.stringValue ?? "off"
        return p
    }
}

struct MenuRow { let title: String; let detail: String; let action: () -> Void; init(_ title: String, _ detail: String = "", _ action: @escaping () -> Void) { self.title = title; self.detail = detail; self.action = action } }
struct Page { var id = UUID(); var title: String; var rows: [MenuRow]; var selection = 0; var offset = 0; var nowPlaying = false }

final class PlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PlayerController: NSObject, NSWindowDelegate {
    let music = MusicBridge()
    var window: NSWindow!, face: PodView!
    var pages: [Page] = []
    var playlists: [Playlist] = [], library: [Song] = []
    var playback = Playback(), artwork: NSImage?
    var connected = false, busy = false, polling = false, held = false
    var status = "", notice = "", noticeUntil = Date.distantPast
    var pollTimer: Timer?, paintTimer: Timer?
    var observedAt = Date(), volumeUntil = Date.distantPast, seekMode = false
    var libraryLoaded = false, requestGeneration = 0
    var commandBusy = false
    var searchWindow: NSWindow?, searchField: NSSearchField?
    var floating = UserDefaults.standard.bool(forKey: "floating")
    var page: Page { pages.last ?? Page(title: "iPod", rows: []) }
    func start() {
        window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 810), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Pocket Player"; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = true; window.isMovableByWindowBackground = true; window.delegate = self
        window.level = floating ? .floating : .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setFrameAutosaveName("PocketPlayerMeshWindow")
        if !window.setFrameUsingName("PocketPlayerMeshWindow") { window.center() }
        if let available = (window.screen ?? NSScreen.main)?.visibleFrame {
            let height = min(window.frame.height, available.height - 32)
            let width = min(window.frame.width, available.width - 32, height * 500 / 810)
            window.setContentSize(NSSize(width: width, height: height))
            let x = max(available.minX + 12, min(window.frame.origin.x, available.maxX - width - 12))
            let y = max(available.minY + 12, min(window.frame.origin.y, available.maxY - height - 12))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        face = PodView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size)); face.autoresizingMask = [.width, .height]; face.controller = self
        window.contentView = face; window.makeFirstResponder(face)
        home(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        paintTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let s = self, s.window.isVisible, !s.window.isMiniaturized, s.page.nowPlaying else { return }
            s.face.needsDisplay = true; s.face.updateScreen()
        }
        if UserDefaults.standard.bool(forKey: "connected") { connect() }
    }
    func redraw() { face?.needsDisplay = true; face?.updateScreen(); face?.rebuildButtons() }
    func home() {
        pages = [Page(title: "iPod", rows: connected ? [
            MenuRow("Playlists") { [weak self] in self?.showPlaylists() },
            MenuRow("Artists") { [weak self] in self?.showArtists() },
            MenuRow("Albums") { [weak self] in self?.showAlbums() },
            MenuRow("Songs") { [weak self] in self?.withLibrary { self?.showSongs($0, title: "Songs") } },
            MenuRow("Shuffle Songs") { [weak self] in self?.shuffleSongs() },
            MenuRow("Now Playing") { [weak self] in self?.nowPlaying() },
            MenuRow("Settings") { [weak self] in self?.settings() }
        ] : [
            MenuRow("Connect Apple Music") { [weak self] in self?.connect() },
            MenuRow("How to use") { [weak self] in self?.help() },
            MenuRow("Settings") { [weak self] in self?.settings() }
        ])]; redraw()
    }
    func push(_ title: String, rows: [MenuRow], nowPlaying: Bool = false) { pages.append(Page(title: title, rows: rows, nowPlaying: nowPlaying)); seekMode = false; redraw() }
    func back() { guard !held else { return }; if pages.count > 1 { pages.removeLast(); seekMode = false; redraw() } else { home() } }
    func step(_ delta: Int) {
        guard !held, !busy else { return }
        if page.nowPlaying {
            guard connected else { return }
            if seekMode { seek(by: Double(delta * 5)) } else { setVolume(playback.volume + delta * 3) }; return
        }
        guard !page.rows.isEmpty else { return }
        let i = pages.count - 1
        pages[i].selection = max(0, min(page.rows.count - 1, page.selection + delta))
        if pages[i].selection < pages[i].offset { pages[i].offset = pages[i].selection }
        if pages[i].selection >= pages[i].offset + 6 { pages[i].offset = pages[i].selection - 5 }
        redraw()
    }
    func select(_ index: Int? = nil) {
        guard !held, !busy else { return }
        if page.nowPlaying { seekMode.toggle(); volumeUntil = .distantPast; redraw(); return }
        let i = index ?? page.selection
        guard page.rows.indices.contains(i) else { return }
        pages[pages.count - 1].selection = i; page.rows[i].action()
    }
    func flash(_ text: String) { notice = text; noticeUntil = Date().addingTimeInterval(2); redraw(); DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [weak self] in self?.redraw() } }
    func failure(_ error: Error) {
        busy = false
        status = String(((error as? MusicFailure)?.message ?? error.localizedDescription).prefix(280))
        redraw()
    }
    func connect() {
        guard !busy else { return }; busy = true; status = "Connecting to Music…"; redraw()
        music.request({ bridge -> ([Playlist], Playback) in (try bridge.playlists(), try bridge.status()) }) { [weak self] result in
            guard let s = self else { return }; s.busy = false
            switch result {
            case .success(let value): s.playlists = value.0; s.playback = value.1; s.connected = true; UserDefaults.standard.set(true, forKey: "connected"); s.status = ""; s.home(); s.poll()
            case .failure(let error): s.failure(error)
            }
        }
    }
    func poll() {
        guard connected, !polling, !busy, !commandBusy else { return }; polling = true
        music.request({ try $0.status() }) { [weak self] result in
            guard let s = self else { return }; s.polling = false
            switch result {
            case .success(let p):
                let changed = p.id != s.playback.id || p.album != s.playback.album
                s.playback = p; s.observedAt = Date(); s.status = ""; s.redraw()
                if changed || (s.artwork == nil && !p.id.isEmpty) { s.loadArtwork(id: p.id) }
            case .failure(let error): s.status = (error as? MusicFailure)?.message ?? error.localizedDescription; s.redraw()
            }
        }
    }
    func loadArtwork(id: String) {
        music.request({ try $0.execute("get raw data of artwork 1 of current track").data }) { [weak self] result in
            guard let s = self, s.playback.id == id else { return }
            s.artwork = (try? result.get()).flatMap { NSImage(data: $0) }; s.redraw()
        }
    }
    func command(_ body: String, done: (() -> Void)? = nil) {
        guard connected else { connect(); return }
        guard !commandBusy, !busy else { return }
        commandBusy = true
        music.request({ _ = try $0.execute(body) }) { [weak self] result in
            self?.commandBusy = false
            switch result { case .success: done?(); self?.poll(); case .failure(let error): self?.failure(error) }
        }
    }
    func playPause() { guard !held else { return }; command("playpause") }
    func skip(_ next: Bool) { guard !held else { return }; command(next ? "next track" : "back track") }
    func setVolume(_ value: Int) {
        let volume = max(0, min(100, value)); playback.volume = volume; volumeUntil = Date().addingTimeInterval(1.6); redraw()
        // Coalesce wheel movement so Music never accumulates a queue of old volume values.
        volumeWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.command("set sound volume to \(volume)") }; volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    var volumeWork: DispatchWorkItem?, seekWork: DispatchWorkItem?
    var position: Double { min(playback.duration, max(0, playback.position + (playback.playing ? Date().timeIntervalSince(observedAt) : 0))) }
    func seek(by amount: Double) {
        let value = min(max(0, playback.duration - 0.1), max(0, position + amount))
        playback.position = value; observedAt = Date(); redraw(); seekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.command("set player position to \(value)") }; seekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func nowPlaying() { if page.nowPlaying { redraw() } else { push("Now Playing", rows: [], nowPlaying: true) } }
    func showPlaylists() {
        push("Playlists", rows: playlists.map { p in MenuRow(p.name) { [weak self] in self?.loadPlaylist(p) } })
    }
    func loadPlaylist(_ p: Playlist) {
        busy = true; status = "Loading playlist…"; redraw(); requestGeneration += 1; let generation = requestGeneration
        music.request({ try $0.songs(in: p.id) }) { [weak self] result in
            guard let s = self, s.requestGeneration == generation else { return }; s.busy = false; s.status = ""
            switch result {
            case .success(let songs):
                s.showSongs(songs, title: p.name, playlist: p.id, playAll: { [weak s] in s?.playPlaylist(p.id) })
            case .failure(let e): s.failure(e)
            }
        }
    }
    func playPlaylist(_ id: String) { command("play (first user playlist whose persistent ID is \(quoted(id)))") { [weak self] in self?.nowPlaying() } }
    func withLibrary(_ action: @escaping ([Song]) -> Void) {
        if libraryLoaded { action(library); return }
        guard !busy else { return }; busy = true; status = "Loading your library…"; redraw()
        music.request({ try $0.songs() }) { [weak self] result in
            guard let s = self else { return }; s.busy = false; s.status = ""
            switch result { case .success(let tracks): s.library = tracks; s.libraryLoaded = true; action(tracks); case .failure(let e): s.failure(e) }
        }
    }
    func showSongs(_ songs: [Song], title: String, playlist: String? = nil, playAll: (() -> Void)? = nil) {
        var rows: [MenuRow] = []
        if let playAll = playAll, !songs.isEmpty { rows.append(MenuRow("Play all", "\(songs.count) songs", playAll)) }
        rows += songs.map { song in MenuRow(song.title, song.artist) { [weak self] in
            let target = playlist.map { "first user playlist whose persistent ID is \(quoted($0))" } ?? "library playlist 1"
            self?.command("set p to \(target)\nplay (first track of p whose persistent ID is \(quoted(song.id)))") { [weak self] in self?.nowPlaying() }
        } }
        push(title, rows: rows)
    }
    func showArtists() { withLibrary { [weak self] tracks in
        let names = Set(tracks.map { $0.artist.isEmpty ? "Unknown Artist" : $0.artist }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        self?.push("Artists", rows: names.map { name in MenuRow(name) { [weak self] in self?.showSongs(tracks.filter { ($0.artist.isEmpty ? "Unknown Artist" : $0.artist) == name }, title: name) } })
    } }
    func showAlbums() { withLibrary { [weak self] tracks in
        let groups = Dictionary(grouping: tracks, by: { $0.album + "\u{1F}" + $0.artist })
        let keys = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        self?.push("Albums", rows: keys.compactMap { key in
            guard let songs = groups[key], let first = songs.first else { return nil }
            return MenuRow(first.album.isEmpty ? "Unknown Album" : first.album, first.artist) { [weak self] in self?.showSongs(songs, title: first.album.isEmpty ? "Unknown Album" : first.album) }
        })
    } }
    func shuffleSongs() { command("set shuffle enabled to true\nset shuffle mode to songs\nplay library playlist 1") { [weak self] in self?.nowPlaying() } }
    func settings() {
        push("Settings", rows: [
            MenuRow("Refresh playlists") { [weak self] in self?.connect() },
            MenuRow("Now Playing") { [weak self] in self?.nowPlaying() },
            MenuRow("Main Menu") { [weak self] in self?.home() }
        ])
    }
    func help() {
        push("How to use", rows: [
            MenuRow("Scroll / drag wheel") {},
            MenuRow("Center / Enter: select") {},
            MenuRow("Menu / Backspace: back") {},
            MenuRow("Space: play / pause") {},
            MenuRow("Now Playing: volume") {},
            MenuRow("Select: switch to seek") {}
        ])
    }
    @objc func search() {
        guard connected, !held else { return }
        withLibrary { [weak self] _ in
            guard let s = self else { return }
            if s.searchWindow == nil {
                let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                panel.title = "Search your Music library"; panel.isReleasedWhenClosed = false
                let field = NSSearchField(frame: NSRect(x: 18, y: 30, width: 304, height: 28)); field.placeholderString = "Song, artist, or album"; field.target = s; field.action = #selector(s.submitSearch)
                field.sendsSearchStringImmediately = false; field.sendsWholeSearchString = true
                panel.contentView?.addSubview(field); s.searchWindow = panel; s.searchField = field
            }
            s.searchWindow?.center(); s.searchWindow?.makeKeyAndOrderFront(nil); s.searchWindow?.makeFirstResponder(s.searchField)
        }
    }
    @objc func submitSearch() {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return }; searchWindow?.orderOut(nil)
        let matches = library.filter { [$0.title, $0.artist, $0.album].contains { $0.localizedCaseInsensitiveContains(query) } }
        showSongs(matches, title: "Search: \(query)"); window.makeKeyAndOrderFront(nil)
    }
    @objc func savePreview() { face.savePreview() }
    @objc func toggleFloat() { floating.toggle(); window.level = floating ? .floating : .normal; UserDefaults.standard.set(floating, forKey: "floating") }
    @objc func minimize() { window.miniaturize(nil) }
    @objc func quit() { NSApp.terminate(nil) }
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }
func rounded(_ r: NSRect, _ radius: CGFloat, _ color: NSColor) { color.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .medium, align: NSTextAlignment = .left) {
    let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail; p.alignment = align
    (value as NSString).draw(in: rect, withAttributes: [.font: (NSFont(name: weight == .bold ? "LucidaGrande-Bold" : "LucidaGrande", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)), .foregroundColor: color, .paragraphStyle: p])
}
func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat = 1) {
    guard let start = points.first else { return }; let p = NSBezierPath(); p.move(to: start); points.dropFirst().forEach { p.line(to: $0) }; p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; color.setStroke(); p.stroke()
}
func timeLabel(_ t: Double) -> String { let n = Int(max(0, t)); return "\(n / 60):\(String(format: "%02d", n % 60))" }
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    init(_ frame: NSRect, label: String, action: @escaping () -> Void) {
        super.init(frame: frame); title = ""; isBordered = false; isTransparent = true
        setAccessibilityLabel(label); actionBlock = action; target = self; self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func invoke() { actionBlock?() }
}
