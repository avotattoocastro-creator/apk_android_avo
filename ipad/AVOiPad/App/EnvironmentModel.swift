import SwiftUI
import Observation

/// One hour of the weather / sea model shown in the hourly table.
struct WeatherHourRow: Identifiable {
    let id: Int
    var hour: String
    var temperature: String
    var wind: String
    var gust: String
    var direction: String
    var pressure: String
    var humidity: String
    var wave: String
    var period: String
    var inTraining: Bool
}

/// Port of windows/AVO.Windows/ViewModels/MainViewModel.Environment.cs: official IHM tide prediction of a reference port and
/// Open-Meteo weather / sea-state model for the session. Prediction / model are always labelled, missing data = «Sin datos».
@Observable
final class EnvironmentModel {
    unowned let app: AppModel
    @ObservationIgnored private var serviceStore: EnvironmentService? = nil

    var tides: TidePrediction? = nil
    var weather: WeatherModel? = nil
    var ports: [TidePort] = []
    var selectedPortId: String? = nil
    var status: String = "Sin datos de entorno"
    var loading: Bool = false
    var tideSeries: [FeatureLineSeries] = []
    var tideMarker: Double = .nan
    var tideXMin: Double = 0
    var tideXMax: Double = 86_400
    /// Training interval on the tide chart (seconds since local midnight).
    var trainingBand: [FeatureBand] = []
    var tideRows: [FeatureKV] = []
    var weatherRows: [FeatureKV] = []
    var tideEvents: [FeatureKV] = []
    var weatherHours: [WeatherHourRow] = []
    var tideHeadline: String = "Sin datos"
    var tideTrend: String = "No disponible"
    var coefficientHeadline: String = "Sin datos"
    var windHeadline: String = "Sin datos"
    var tempHeadline: String = "Sin datos"
    var pressureHeadline: String = "Sin datos"
    var waveHeadline: String = "Sin datos"

    // place settings (Windows AppSettings.PlaceName / PlaceLatitude / PlaceLongitude) and online switch
    var placeName: String
    var placeLatitude: Double
    var placeLongitude: Double
    var onlineEnvironment: Bool {
        didSet {
            if oldValue == onlineEnvironment { return }
            app.settings.onlineEnvironment = onlineEnvironment
            saveSettings()
        }
    }

    /// Session id whose environment is shown (Windows _envLoadedFor); the report uses tides/weather only for that session.
    private(set) var loadedFor: String? = nil
    @ObservationIgnored private var requestNo: Int = 0

    init(app: AppModel) {
        self.app = app
        self.placeName = app.settings.placeName
        self.placeLatitude = app.settings.placeLatitude
        self.placeLongitude = app.settings.placeLongitude
        self.onlineEnvironment = app.settings.onlineEnvironment
        self.selectedPortId = app.settings.tidePortId
    }

    private var service: EnvironmentService {
        if let s = serviceStore { return s }
        let s = EnvironmentService(cacheDir: app.paths.environmentCache)
        serviceStore = s
        return s
    }

    var selectedPort: TidePort? {
        if let id = selectedPortId, let p = ports.first(where: { $0.id == id }) { return p }
        return nil
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        if app.page == .tides {
            Task { @MainActor in await self.load(force: false) }
        }
    }

    func pageShown() {
        Task { @MainActor in await self.load(force: false) }
    }

    // ------------------------------------------------------------------ actions
    /// ComboBox «Puerto de referencia (IHM)»: stored in the settings and reloaded.
    func choosePort(_ id: String) {
        if id == selectedPortId { return }
        selectedPortId = id
        app.settings.tidePortId = id
        saveSettings()
        Task { @MainActor in await self.load(force: true) }
    }

    /// Saves the training place; the ports are ordered again by distance to it.
    func savePlace() {
        let name: String = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !placeLatitude.isFinite || abs(placeLatitude) > 90 || !placeLongitude.isFinite || abs(placeLongitude) > 180 {
            app.show("Zona de entrenamiento", "Coordenadas no válidas (latitud −90…90, longitud −180…180).", error: true)
            return
        }
        app.settings.placeName = name.isEmpty ? TrainingPlace.regaton.name : name
        app.settings.placeLatitude = placeLatitude
        app.settings.placeLongitude = placeLongitude
        placeName = app.settings.placeName
        saveSettings()
        ports = []
        Task { @MainActor in await self.load(force: true) }
    }

    func resetPlace() {
        placeName = TrainingPlace.regaton.name
        placeLatitude = TrainingPlace.regaton.latitude
        placeLongitude = TrainingPlace.regaton.longitude
        savePlace()
    }

    private func saveSettings() {
        do { try app.settings.save(app.paths.settingsFile) } catch { app.log.warn("ajustes", error.localizedDescription, error) }
    }

    // ------------------------------------------------------------------ LoadEnvironmentAsync
    @MainActor
    func load(force: Bool) async {
        guard let s = app.selected, let start = s.start else {
            status = "La sesión no tiene fecha: no se pueden asociar mareas ni meteorología."
            loadedFor = nil
            clear()
            return
        }
        if !force && loadedFor == s.id { return }
        loadedFor = s.id
        requestNo += 1
        let request: Int = requestNo
        clear()
        if !onlineEnvironment {
            status = "Consulta en línea desactivada: sin datos de entorno."
            return
        }
        status = "Consultando predicción de mareas (IHM) y modelo meteorológico (Open-Meteo)…"
        loading = true
        var errors: [String] = []
        var lat: Double = app.settings.placeLatitude
        var lon: Double = app.settings.placeLongitude
        if s.timeline.count > 0 && s.timeline.lat[0].isFinite && s.timeline.lon[0].isFinite {
            lat = s.timeline.lat[0]
            lon = s.timeline.lon[0]
        }
        let svc: EnvironmentService = service
        var newTides: TidePrediction? = nil
        var newWeather: WeatherModel? = nil
        do {
            if ports.isEmpty {
                let all: [TidePort] = try await svc.ports()
                // nearest 12 ports to the training place (stable for equal distances)
                let indexed: [(i: Int, p: TidePort, d: Double)] = all.enumerated().map { (i: $0.offset, p: $0.element, d: $0.element.distanceKmTo(lat, lon)) }
                let sorted = indexed.sorted { (a: (i: Int, p: TidePort, d: Double), b: (i: Int, p: TidePort, d: Double)) -> Bool in
                    a.d != b.d ? a.d < b.d : a.i < b.i
                }
                ports = Array(sorted.prefix(12)).map { $0.p }
            }
            let port: TidePort? = ports.first(where: { $0.id == app.settings.tidePortId }) ?? ports.first
            if let port = port {
                selectedPortId = port.id
                newTides = try await svc.tides(port, aroundUtc: start, placeLat: lat, placeLon: lon)
            } else {
                errors.append("sin puertos de referencia")
            }
        } catch {
            errors.append("mareas: " + EnvironmentModel.message(error))
            app.log.warn("entorno", "IHM no disponible", error)
        }
        do {
            newWeather = try await svc.weather(lat, lon, utc: start)
        } catch {
            errors.append("meteorología: " + EnvironmentModel.message(error))
            app.log.warn("entorno", "Open-Meteo no disponible", error)
        }
        if app.selected !== s || request != requestNo { return }   // a newer request owns the panels
        loading = false
        tides = newTides
        weather = newWeather
        fill(s, start)
        status = errors.isEmpty ? "Datos de entorno cargados (con copia local para uso sin conexión)." : "Parcial — " + errors.joined(separator: " · ")
    }

    private static func message(_ e: Error) -> String {
        if let l = e as? LocalizedError, let d = l.errorDescription { return d }
        return e.localizedDescription
    }

    private func clear() {
        loading = false
        tides = nil
        weather = nil
        tideRows = []; weatherRows = []; tideEvents = []; weatherHours = []
        tideSeries = []; tideMarker = .nan; trainingBand = []
        tideHeadline = "Sin datos"; windHeadline = "Sin datos"; tempHeadline = "Sin datos"; pressureHeadline = "Sin datos"
        waveHeadline = "Sin datos"; coefficientHeadline = "Sin datos"
        tideTrend = "No disponible"
    }

    // ------------------------------------------------------------------ FillEnvironment
    private func fill(_ s: SessionItem, _ start: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = MadridTime.timeZone
        let day0: Date = cal.startOfDay(for: start)
        let day1: Date = cal.date(byAdding: .day, value: 1, to: day0) ?? day0.addingTimeInterval(86_400)
        func toX(_ u: Date) -> Double { u.timeIntervalSince(day0) }
        let duration: Double = s.timeline.durationS
        let end: Date = start.addingTimeInterval(duration)
        var tRows: [FeatureKV] = []
        var events: [FeatureKV] = []
        if let tp = tides {
            let curve: [TideCurvePoint] = tp.curve(from: day0, to: day1, step: 600)
            tideSeries = curve.count > 1
                ? [FeatureLineSeries(id: "marea", name: "Marea (predicción)", color: Avo.blue, x: curve.map { toX($0.t) }, y: curve.map { $0.h },
                                     unit: "m", format: "0.00", width: 2)]
                : []
            tideMarker = toX(start)
            tideXMin = 0
            tideXMax = 86_400
            trainingBand = duration > 0 ? [FeatureBand(id: 0, x0: toX(start), x1: toX(end), color: Avo.red)] : []
            let h: Double? = tp.heightAt(start)
            tideHeadline = TimeText.num(h, "0.00", " m")
            if let tr = tp.trendAt(start) { tideTrend = tr == "subiendo" ? "Subiendo" : "Bajando" } else { tideTrend = "No disponible" }
            coefficientHeadline = TimeText.num(tp.coefficientAt(start), "0")
            tRows.add("Fuente", tp.source)
            tRows.add("Tipo de dato", "Predicción (no es una medición)")
            tRows.add("Puerto de referencia", "\(tp.port.name) · \(TimeText.num(tp.portDistanceKm, "0.0", " km"))")
            tRows.add("Altura al inicio", TimeText.num(h, "0.00", " m (cero hidrográfico)"))
            tRows.add("Altura al final", TimeText.num(tp.heightAt(end), "0.00", " m"))
            tRows.add("Amplitud del semiciclo", TimeText.num(tp.rangeAt(start), "0.00", " m"))
            tRows.add("Coeficiente aproximado", TimeText.num(tp.coefficientAt(start), "0"))
            for x in tp.extremes where x.utc >= day0 && x.utc < day1 {
                events.add(x.high ? "Pleamar" : "Bajamar", "\(MadridTime.format(x.utc, "HH:mm")) · \(DotNetFormat.custom(x.heightM, "0.00", spanish: true)) m")
            }
        }
        tideRows = tRows
        tideEvents = events

        var wRows: [FeatureKV] = []
        var hours: [WeatherHourRow] = []
        if let wm = weather {
            if let w = wm.at(start) {
                var wind: String = TimeText.num(w.windKmh, "0", " km/h")
                if let d = w.windDirDeg { wind += " " + EnvironmentModel.compass(d) }
                windHeadline = wind
                tempHeadline = TimeText.num(w.temperatureC, "0.0", " °C")
                pressureHeadline = TimeText.num(w.pressureHpa, "0", " hPa")
                waveHeadline = TimeText.num(w.waveHeightM, "0.0", " m")
                wRows.add("Fuente", wm.source)
                wRows.add("Tipo de dato", "Modelo numérico (no es una medición en la playa)")
                wRows.add("Hora del modelo", MadridTime.format(w.utc, "dd/MM HH:mm"))
                wRows.add("Viento / rachas", "\(TimeText.num(w.windKmh, "0", " km/h")) / \(TimeText.num(w.windGustKmh, "0", " km/h"))")
                wRows.add("Humedad relativa", TimeText.num(w.humidityPct, "0", " %"))
                wRows.add("Oleaje (altura / periodo)", "\(TimeText.num(w.waveHeightM, "0.0", " m")) / \(TimeText.num(w.wavePeriodS, "0", " s"))")
            }
            // hourly table of the training day (model hours, Europe/Madrid)
            for h in wm.hours where h.utc >= day0 && h.utc < day1 {
                let inTraining: Bool = h.utc.addingTimeInterval(3600) > start && h.utc <= end
                var dir: String = "Sin datos"
                if let d = h.windDirDeg { dir = EnvironmentModel.compass(d) + " (" + DotNetFormat.custom(d, "0", spanish: true) + "°)" }
                hours.append(WeatherHourRow(id: hours.count, hour: MadridTime.format(h.utc, "HH:mm"),
                                            temperature: TimeText.num(h.temperatureC, "0.0", " °C"),
                                            wind: TimeText.num(h.windKmh, "0", " km/h"), gust: TimeText.num(h.windGustKmh, "0", " km/h"),
                                            direction: dir, pressure: TimeText.num(h.pressureHpa, "0", " hPa"),
                                            humidity: TimeText.num(h.humidityPct, "0", " %"), wave: TimeText.num(h.waveHeightM, "0.0", " m"),
                                            period: TimeText.num(h.wavePeriodS, "0", " s"), inTraining: inTraining))
            }
        }
        weatherRows = wRows
        weatherHours = hours
    }

    static func compass(_ deg: Double) -> String {
        let n: [String] = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let a: Double = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45
        let k: Int = Int(a.rounded(.toNearestOrEven)) % 8
        return n[k]
    }
}
