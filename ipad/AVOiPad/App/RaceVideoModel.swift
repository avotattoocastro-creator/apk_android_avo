import Foundation
import Observation
import AVFoundation
import CoreGraphics
import QuartzCore
import UIKit

/// Runner read on the France Galop race page (place, name, saddle-cloth number, silk colours).
struct RaceVideoRunner: Identifiable, Equatable {
    var place: Int?
    var name: String
    var number: Int?
    var colors: [(hex: String, w: Double)]
    var imageURL: String
    var id: String { name }

    static func == (a: RaceVideoRunner, b: RaceVideoRunner) -> Bool {
        a.place == b.place && a.name == b.name && a.number == b.number && a.imageURL == b.imageURL
            && a.colors.map { $0.hex } == b.colors.map { $0.hex }
    }
}

/// What was read on the France Galop page of the race.
struct RaceVideoPage {
    var url: String = ""
    var title: String = ""
    var text: String = ""
    var videos: [String] = []
    var runners: [RaceVideoRunner] = []
}

/// «Análisis automático del vídeo de la carrera» (full screen). Plays the race video (France Galop page or a file /
/// screen recording), follows our jockey frame by frame (App/RaceVideoTracker.swift) and builds an estimated race
/// (Core/RaceVideoAnalysis.swift) that is saved in «Carreras» and compared with the trainings like a tracked race.
@Observable
final class RaceVideoModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private let tracker = RaceVideoTracker()
    @ObservationIgnored private let queue = DispatchQueue(label: "avo.racevideo", qos: .userInitiated)
    @ObservationIgnored private(set) var player: AVPlayer? = nil
    @ObservationIgnored private var output: AVPlayerItemVideoOutput? = nil
    @ObservationIgnored private var timer: Timer? = nil
    @ObservationIgnored private var processing: Bool = false
    @ObservationIgnored private var samples: [RaceVideoSample] = []
    @ObservationIgnored private var lastTime: Double = -1

    var visible: Bool = false
    var playerVersion: Int = 0
    var sourceLabel: String = ""
    var pageURL: String = ""
    var videoCandidates: [String] = []
    var running: Bool = false
    var analysed: Bool = false
    var slow: Bool = false
    var status: String = ""
    var trackStatus: String = ""
    var progress: Double = 0
    var duration: Double = 0
    var sampleCount: Int = 0
    var foundCount: Int = 0
    /// Overlay (pixels of the video frame).
    var frameSize: CGSize = .zero
    var targetBox: CGRect? = nil
    var otherBoxes: [CGRect] = []
    /// Video paused by the trainer or by the app (camera change without our horse).
    var paused: Bool = false
    /// Paused waiting for the trainer to mark the horse (circle it with the Pencil or a finger).
    var waitingSelection: Bool = false
    /// Pause on its own when the horse is lost after a camera change (trainer's request 09/11/2026).
    var autoPause: Bool = true
    @ObservationIgnored private var lostFrames: Int = 0
    @ObservationIgnored private var suppressUntilCut: Bool = false

    // data of the race (prefilled from the page, editable)
    var runners: [RaceVideoRunner] = []
    var raceName: String = ""
    var hippodrome: String = ""
    var date: Date? = nil
    var distanceText: String = "" { didSet { recompute() } }
    var winnerTimeText: String = "" { didSet { recompute() } }
    var lengthsText: String = "" { didSet { recompute() } }
    var horseCode: String = ""
    var runnerName: String = "" { didSet { runnerChanged() } }
    var startT: Double = 0 { didSet { if !settingStart { recompute() } } }
    @ObservationIgnored private var settingStart: Bool = false
    var result: RaceVideoResult? = nil

    init(app: AppModel) {
        self.app = app
    }

    // ---------------------------------------------------------------- open / close
    /// From the France Galop browser: reads the race page (video, runners and silks, distance, time) and opens the page.
    @MainActor
    func openFromFranceGalop() async {
        guard let w = app.franceGalop.webView else { return }
        do {
            let r: Any? = try await w.evaluateJavaScript(RaceVideoModel.pageJS)
            guard let json = r as? String, let p = RaceVideoModel.parsePage(json) else {
                app.franceGalop.status = "No se pudo leer la página de la carrera."
                return
            }
            prepare(p)
            visible = true
            if let u = videoCandidates.first {
                openURL(u)
            } else {
                status = "No he encontrado el archivo del vídeo en la página (el reproductor no lo deja ver). Reproduce el vídeo en France Galop, "
                    + "grábalo con la grabación de pantalla del iPad y elígelo con «Elegir vídeo»."
            }
            await fillMissingColors()
        } catch {
            app.franceGalop.status = "No se pudo leer la página: " + error.localizedDescription
        }
    }

    /// From «Carreras»: empty page; the trainer picks a file / screen recording and types the official data.
    func openEmpty() {
        prepare(RaceVideoPage())
        status = "Elige el vídeo de la carrera (Fotos o Archivos: también vale una grabación de pantalla) y rellena distancia y tiempo."
        visible = true
    }

    func close() {
        stop()
        player?.pause()
        player = nil
        output = nil
        visible = false
    }

    private func prepare(_ p: RaceVideoPage) {
        stop()
        player = nil
        output = nil
        samples = []
        tracker.reset()
        result = nil
        analysed = false
        progress = 0
        sampleCount = 0
        foundCount = 0
        targetBox = nil
        otherBoxes = []
        trackStatus = ""
        pageURL = p.url
        videoCandidates = p.videos
        runners = p.runners
        raceName = RaceVideoModel.pageRaceName(p)
        let meeting: (date: Date?, place: String) = RaceVideoModel.meeting(p.text)
        date = meeting.date
        hippodrome = meeting.place
        distanceText = RaceVideoAnalysis.parseDistance(p.text).map { String(Int($0)) } ?? ""
        winnerTimeText = RaceVideoModel.winnerTime(p.text).map { RaceFormat.official($0) } ?? ""
        lengthsText = ""
        // our horse: a Cuadra horse among the runners
        horseCode = ""
        var name: String = ""
        for h in app.stable.horses.allRows where !h.record.demo {
            if let r = p.runners.first(where: { RaceNames.matches(h.name, $0.name) }) {
                horseCode = h.code
                name = r.name
                break
            }
        }
        runnerName = name
        sourceLabel = p.url.isEmpty ? "" : "France Galop"
    }

    // ---------------------------------------------------------------- video source
    func openURL(_ s: String) {
        guard let u = URL(string: s) else { return }
        var headers: [String: String] = ["User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"]
        if !pageURL.isEmpty { headers["Referer"] = pageURL }
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        load(asset, label: u.lastPathComponent.isEmpty ? "Vídeo de France Galop" : "France Galop · " + u.lastPathComponent)
    }

    func openFile(_ url: URL) {
        let access: Bool = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dir: String = AvoFiles.join(app.paths.root, "carreras_video")
        AvoFiles.ensureDir(dir)
        let target: String = AvoFiles.join(dir, AvoTime.formatter("yyyyMMdd-HHmmss").string(from: Date()) + "_" + url.lastPathComponent)
        do {
            if url.path != target { try FileManager.default.copyItem(atPath: url.path, toPath: target) }
            load(AVURLAsset(url: URL(fileURLWithPath: target)), label: url.lastPathComponent)
        } catch {
            status = "No se pudo abrir el vídeo: " + error.localizedDescription
        }
    }

    private func load(_ asset: AVURLAsset, label: String) {
        stop()
        samples = []
        tracker.reset()
        result = nil
        analysed = false
        progress = 0
        sampleCount = 0
        foundCount = 0
        targetBox = nil
        otherBoxes = []
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        player = p
        output = nil
        paused = false
        waitingSelection = false
        // frames analysed at ≤ 960 px wide (a full-resolution iPad screen recording was far too slow for Vision)
        Task { @MainActor [weak self] in
            for _ in 0..<100 {
                if item.status == .readyToPlay && item.presentationSize.width > 0 { break }
                if item.status == .failed { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let self = self, self.player?.currentItem === item, self.output == nil else { return }
            self.attachOutput(item)
        }
        playerVersion += 1
        sourceLabel = label
        status = "Vídeo cargado. Pulsa «Analizar automáticamente»."
        applySilks()
    }

    var hasVideo: Bool { player != nil }

    private func attachOutput(_ item: AVPlayerItem) {
        var attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        let s: CGSize = item.presentationSize
        if s.width > 960 && s.height > 0 {
            let w: Int = 960
            let h: Int = Int((Double(s.height) * 960 / Double(s.width) / 2).rounded()) * 2
            attrs[kCVPixelBufferWidthKey as String] = w
            attrs[kCVPixelBufferHeightKey as String] = h
        }
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        item.add(out)
        output = out
    }

    // ---------------------------------------------------------------- pause / mark the horse
    func pause(waiting: Bool) {
        guard running else { return }
        player?.pause()
        paused = true
        if waiting { waitingSelection = true }
    }

    func resume() {
        guard running else { return }
        paused = false
        waitingSelection = false
        lostFrames = 0
        player?.playImmediately(atRate: slow ? 0.5 : 1.0)
    }

    /// «No se ve: seguir»: continue without the horse until the next camera change.
    func skipUntilCut() {
        suppressUntilCut = true
        trackStatus = "Sigo sin tu caballo hasta el próximo cambio de cámara."
        resume()
    }

    /// Box drawn around the horse (normalised 0…1, top-left origin) on the paused frame.
    func selectBox(_ n: CGRect) {
        if running && !paused { pause(waiting: true) }
        let tr: RaceVideoTracker = tracker
        queue.async { [weak self] in
            let r: CGRect? = tr.select(n)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let b = r {
                    self.targetBox = b
                    self.lostFrames = 0
                    self.suppressUntilCut = false
                    self.trackStatus = self.running ? "Caballo marcado. Pulsa «Continuar»." : "Caballo marcado. Pulsa «Analizar automáticamente»."
                } else {
                    self.trackStatus = "No hay imagen para marcar todavía: pulsa «Analizar automáticamente» y pausa el vídeo."
                }
            }
        }
    }

    // ---------------------------------------------------------------- analysis run
    func start() {
        guard let p = player, let item = p.currentItem else { return }
        stop()
        samples = []
        tracker.reset()
        applySilks()
        result = nil
        analysed = false
        sampleCount = 0
        foundCount = 0
        lastTime = -1
        lostFrames = 0
        suppressUntilCut = false
        paused = false
        waitingSelection = false
        if output == nil { attachOutput(item) }
        p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        running = true
        status = "Analizando el vídeo…"
        p.playImmediately(atRate: slow ? 0.5 : 1.0)
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick(item) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        paused = false
        waitingSelection = false
        if running {
            running = false
            player?.pause()
        }
    }

    /// Stops and analyses what has been seen so far.
    func finishNow() {
        stop()
        finish()
    }

    private func tick(_ item: AVPlayerItem) {
        if item.status == .failed {
            stop()
            let e: String = item.error?.localizedDescription ?? "error desconocido"
            status = "No se pudo reproducir el vídeo (\(e)). Grábalo con la grabación de pantalla del iPad y elígelo con «Elegir vídeo»."
            return
        }
        let d: Double = CMTimeGetSeconds(item.duration)
        if d.isFinite && d > 0 { duration = d }
        guard let out = output else { return }
        let now: CMTime = out.itemTime(forHostTime: CACurrentMediaTime())
        let sec: Double = CMTimeGetSeconds(now)
        if duration > 0 { progress = max(0, min(1, sec / duration)) }
        if duration > 0 && sec >= duration - 0.08 && !processing {
            stop()
            finish()
            return
        }
        if processing || !out.hasNewPixelBuffer(forItemTime: now) { return }
        guard let pb = out.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) else { return }
        if sec <= lastTime { return }
        lastTime = sec
        processing = true
        let tr: RaceVideoTracker = tracker
        queue.async { [weak self] in
            let r: RaceVideoFrameResult = tr.process(pb, t: sec)
            DispatchQueue.main.async { self?.consume(r) }
        }
    }

    private func consume(_ r: RaceVideoFrameResult) {
        processing = false
        samples.append(r.sample)
        sampleCount = samples.count
        if r.sample.x != nil { foundCount += 1 }
        frameSize = r.frameSize
        targetBox = r.target
        otherBoxes = r.others
        if !r.status.isEmpty { trackStatus = r.status }
        // automatic pause: horse not found for ~0,4 s (start of the video or after a camera change)
        if r.sample.cut { suppressUntilCut = false }
        if r.target != nil {
            lostFrames = 0
        } else {
            lostFrames += 1
            if running && !paused && autoPause && !suppressUntilCut && lostFrames >= 6 {
                pause(waiting: true)
                trackStatus = foundCount == 0
                    ? "Vídeo en pausa: rodea a tu caballo con el Pencil (o el dedo) y pulsa «Continuar»."
                    : "Cambio de cámara: no encuentro a tu caballo. Rodéalo con el Pencil y pulsa «Continuar», o «No se ve» si no aparece."
            }
        }
    }

    /// Trainer taps the video (normalised point, top-left origin): choose / correct our jockey.
    func tapVideo(_ p: CGPoint) {
        if running && paused { return }      // paused: the horse is marked by circling it (buttons of the banner are taps too)
        let tr: RaceVideoTracker = tracker
        queue.async { tr.tap = p }
        trackStatus = "Buscando el jinete que has tocado…"
        if !running, hasVideo { trackStatus += " (pulsa «Analizar automáticamente»)" }
    }

    private func finish() {
        analysed = true
        let found: Double = sampleCount > 0 ? Double(foundCount) / Double(sampleCount) : 0
        status = "Vídeo analizado: \(sampleCount) fotogramas, caballo seguido en el \(Int((found * 100).rounded())) %."
        settingStart = true
        startT = RaceVideoAnalysis.autoStart(samples)
        settingStart = false
        recompute()
    }

    // ---------------------------------------------------------------- official data → result
    var distanceM: Double? {
        let v: Double? = Double(distanceText.filter { $0.isNumber })
        return (v ?? 0) >= 100 ? v : nil
    }
    var winnerTimeS: Double? { RaceVideoAnalysis.parseTime(winnerTimeText) }
    var lengths: Double? { Double(lengthsText.replacingOccurrences(of: ",", with: ".")) }
    var ourPlace: Int? { runners.first { $0.name == runnerName }?.place }
    var ourTimeS: Double? {
        guard let w = winnerTimeS else { return nil }
        if ourPlace == 1 { return w }
        return w + (lengths ?? 0) * RaceFormat.secondsPerLength
    }
    var needsLengths: Bool { (ourPlace ?? 1) != 1 && lengths == nil }

    func recompute() {
        guard analysed, let d = distanceM, let t = ourTimeS else { result = nil; return }
        result = RaceVideoAnalysis.analyze(samples, start: startT, timeS: t, distanceM: d)
    }

    // ---------------------------------------------------------------- silks
    private func runnerChanged() {
        applySilks()
        recompute()
    }

    private func applySilks() {
        let sig: SilkSignature = SilkSignature.from(colors: runners.first { $0.name == runnerName }?.colors ?? [])
        let tr: RaceVideoTracker = tracker
        queue.async { tr.silk = sig }
    }

    var ourColors: [String] { runners.first { $0.name == runnerName }?.colors.map { $0.hex } ?? [] }

    /// Silk images the page could not read (other domain): downloaded and read here.
    @MainActor
    private func fillMissingColors() async {
        for i in runners.indices where runners[i].colors.isEmpty && !runners[i].imageURL.isEmpty {
            guard let u = URL(string: runners[i].imageURL) else { continue }
            let got: (Data, URLResponse)? = try? await URLSession.shared.data(from: u)
            guard let data = got?.0, let img = UIImage(data: data) else { continue }
            runners[i].colors = RaceVideoModel.palette(img)
        }
        applySilks()
    }

    static func palette(_ img: UIImage) -> [(hex: String, w: Double)] {
        guard let cg = img.cgImage else { return [] }
        let n: Int = 32
        var px: [UInt8] = Array(repeating: 0, count: n * n * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        if !drawn { return [] }
        var count: [Int: Double] = [:]
        var i: Int = 0
        while i < px.count {
            if px[i + 3] >= 128 {
                let k: Int = (Int(px[i]) >> 4) << 8 | (Int(px[i + 1]) >> 4) << 4 | (Int(px[i + 2]) >> 4)
                count[k, default: 0] += 1
            }
            i += 4
        }
        let top: [(key: Int, value: Double)] = count.sorted { $0.value > $1.value }.prefix(6).map { $0 }
        return top.map { (e: (key: Int, value: Double)) -> (hex: String, w: Double) in
            let r: Int = ((e.key >> 8) & 15) * 17
            let g: Int = ((e.key >> 4) & 15) * 17
            let b: Int = (e.key & 15) * 17
            return (hex: String(format: "#%02X%02X%02X", r, g, b), w: e.value)
        }
    }

    // ---------------------------------------------------------------- save
    var canSave: Bool { result.map { !$0.sectors.isEmpty } ?? false && (!runnerName.isEmpty || !horseCode.isEmpty) }

    /// What is missing to show the result (after the video has been analysed).
    var missing: [String] {
        var m: [String] = []
        if distanceM == nil { m.append("la distancia de la carrera (m)") }
        if winnerTimeS == nil { m.append("el tiempo del ganador (por ejemplo 2'25\"30)") }
        if runnerName.isEmpty && horseCode.isEmpty { m.append("tu caballo (Cuadra o «En la carrera»)") }
        if !runners.isEmpty && runnerName.isEmpty { m.append("tu caballo en la lista «En la carrera» (para su puesto y sus colores)") }
        return m
    }

    func save() {
        guard let r = result, !r.sectors.isEmpty else { return }
        var info = RaceVideoInfo()
        info.raceName = raceName.isEmpty ? "Carrera (vídeo)" : raceName
        info.hippodrome = hippodrome
        info.date = date
        info.horseCode = horseCode.isEmpty ? nil : horseCode
        info.horseName = horseCode.isEmpty ? nil : app.races.horseName(horseCode)
        info.runnerName = runnerName.isEmpty ? (info.horseName ?? "Mi caballo") : runnerName
        info.number = runners.first { $0.name == runnerName }?.number
        info.place = ourPlace
        info.winnerTimeS = winnerTimeS
        var others: [RaceRunner] = []
        for o in runners where o.name != runnerName {
            others.append(RaceRunner(number: o.number, draw: nil, name: o.name, jockey: "", finish: o.place,
                                     officialTimeS: o.place == 1 ? winnerTimeS : nil, maxSpeedKmh: nil, maxSpeedSector: "",
                                     fastest200S: nil, fastestSector: "", last600S: nil, distanceVsWinnerM: nil,
                                     meanSpeedKmh: nil, redk: nil, sectors: []))
        }
        let race: Race = RaceVideoAnalysis.makeRace(r, info: info, others: others)
        close()
        app.franceGalop.close()
        app.races.addVideoRace(race)
    }

    // ---------------------------------------------------------------- page parsing
    /// Video files of the player (also the HLS/MP4 requests of the page), runners with place, number and silk colours.
    static let pageJS: String = """
    (function(){
      function t(e){return ((e && (e.innerText || e.textContent)) || '').replace(/\\s+/g,' ').trim();}
      var vids=[];
      function addV(u){ if(u && u.indexOf('blob:')!==0 && vids.indexOf(u)<0){ vids.push(u); } }
      document.querySelectorAll('video').forEach(function(v){ addV(v.currentSrc); addV(v.getAttribute('src') ? v.src : ''); v.querySelectorAll('source').forEach(function(s){ addV(s.src); }); });
      try { performance.getEntriesByType('resource').forEach(function(r){ var n=r.name||''; if(/\\.m3u8(\\?|$)/i.test(n)){ addV(n); } }); } catch(e) {}
      try { performance.getEntriesByType('resource').forEach(function(r){ var n=r.name||''; if(/\\.mp4(\\?|$)/i.test(n)){ addV(n); } }); } catch(e) {}
      var runners=[]; var rows=[];
      var all=document.querySelectorAll('body *');
      for(var i=0;i<all.length && runners.length<30;i++){
        var el=all[i]; if(el.children.length>0){ continue; }
        var x=t(el); if(!/^N°\\s?\\d{1,2}$/.test(x)){ continue; }
        var row=el;
        for(var k=0;k<6 && row.parentElement;k++){ row=row.parentElement; if(row.querySelector('img') && /[A-Z]{3,}/.test(t(row))){ break; } }
        if(rows.indexOf(row)>=0){ continue; } rows.push(row);
        var img=row.querySelector('img'); var colors=[];
        if(img){
          try {
            var c=document.createElement('canvas'); c.width=32; c.height=32; var g=c.getContext('2d');
            g.drawImage(img,0,0,32,32); var d=g.getImageData(0,0,32,32).data; var cnt={};
            for(var p=0;p<d.length;p+=4){ if(d[p+3]<128){ continue; } var key=((d[p]>>4)<<8)|((d[p+1]>>4)<<4)|(d[p+2]>>4); cnt[key]=(cnt[key]||0)+1; }
            Object.keys(cnt).map(function(q){ return [parseInt(q),cnt[q]]; }).sort(function(a,b){ return b[1]-a[1]; }).slice(0,6).forEach(function(a){
              var r=((a[0]>>8)&15)*17, gg=((a[0]>>4)&15)*17, b=(a[0]&15)*17;
              colors.push({hex:'#'+[r,gg,b].map(function(v){ return ('0'+v.toString(16)).slice(-2); }).join(''), w:a[1]});
            });
          } catch(e) {}
        }
        runners.push({text:t(row), num:x, img: img ? (img.currentSrc || img.src || '') : '', colors:colors});
      }
      var h=document.querySelector('h1');
      return JSON.stringify({url:location.href, title:h ? t(h) : document.title, text:(document.body.innerText||'').slice(0,40000), videos:vids, runners:runners});
    })()
    """

    static func parsePage(_ json: String) -> RaceVideoPage? {
        guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        var p = RaceVideoPage()
        p.url = o["url"] as? String ?? ""
        p.title = (o["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        p.text = o["text"] as? String ?? ""
        p.videos = (o["videos"] as? [String] ?? []).sorted { (a: String, b: String) -> Bool in
            // HLS / MP4 files first, the rest after
            let ka: Int = a.lowercased().contains(".m3u8") ? 0 : (a.lowercased().contains(".mp4") ? 1 : 2)
            let kb: Int = b.lowercased().contains(".m3u8") ? 0 : (b.lowercased().contains(".mp4") ? 1 : 2)
            return ka < kb
        }
        for case let r as [String: Any] in (o["runners"] as? [Any] ?? []) {
            let text: String = r["text"] as? String ?? ""
            let num: Int? = Int((r["num"] as? String ?? "").filter { $0.isNumber })
            var colors: [(hex: String, w: Double)] = []
            for case let c as [String: Any] in (r["colors"] as? [Any] ?? []) {
                if let hx = c["hex"] as? String { colors.append((hex: hx, w: (c["w"] as? NSNumber)?.doubleValue ?? 1)) }
            }
            let parsed: (place: Int?, name: String) = parseRunner(text)
            if parsed.name.isEmpty { continue }
            p.runners.append(RaceVideoRunner(place: parsed.place, name: parsed.name, number: num, colors: colors,
                                             imageURL: r["img"] as? String ?? ""))
        }
        return p
    }

    /// «1 LIGHTNING GIRL IRE F.PS. 3 a. N°9» → (1, «LIGHTNING GIRL IRE»).
    static func parseRunner(_ text: String) -> (place: Int?, name: String) {
        var s: String = text
        if let re = try? NSRegularExpression(pattern: #"N°\s?\d{1,2}"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        s = s.trimmingCharacters(in: .whitespaces)
        var place: Int? = nil
        if let re = try? NSRegularExpression(pattern: #"^(\d{1,2})\s+"#),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) {
            place = Int(s[r])
            if let all = Range(m.range, in: s) { s = String(s[all.upperBound...]) }
        }
        if let re = try? NSRegularExpression(pattern: #"\s+[FHM]\.\s?[A-Z]{1,4}\.?\s+\d{1,2}\s*a\.?.*$"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return (place: place, name: s.trimmingCharacters(in: .whitespaces))
    }

    static func pageRaceName(_ p: RaceVideoPage) -> String {
        for line in p.text.components(separatedBy: .newlines) {
            let l: String = line.trimmingCharacters(in: .whitespaces)
            if l.uppercased().hasPrefix("PRIX ") || l.uppercased().hasPrefix("GRAND PRIX") || l.uppercased().hasPrefix("HANDICAP") {
                return l.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespaces) ?? l
            }
        }
        return p.title
    }

    /// «Réunion du 17/10/2026 à DAX».
    static func meeting(_ text: String) -> (date: Date?, place: String) {
        guard let re = try? NSRegularExpression(pattern: #"Réunion du (\d{2}/\d{2}/\d{4}) à ([^\n—\-]+)"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let rd = Range(m.range(at: 1), in: text), let rp = Range(m.range(at: 2), in: text) else { return (date: nil, place: "") }
        let f: DateFormatter = AvoTime.formatter("dd/MM/yyyy")
        return (date: f.date(from: String(text[rd])), place: String(text[rp]).trimmingCharacters(in: .whitespaces))
    }

    /// Winner time on the page: after «Temps», otherwise the first time like 1'36"57.
    static func winnerTime(_ text: String) -> Double? {
        if let r = text.range(of: "Temps", options: .caseInsensitive) {
            let tail: String = String(text[r.upperBound...].prefix(40))
            if let v = RaceVideoAnalysis.parseTime(tail) { return v }
        }
        guard let re = try? NSRegularExpression(pattern: #"\d'\s?\d{2}\s?(?:"|'')\s?\d{1,2}"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return RaceVideoAnalysis.parseTime(String(text[r]))
    }
}
