import SwiftUI

/// «Calendario» (paridad iPad ↔ PC, docs/PARIDAD_IPAD_PC.md): entrenamientos por día en vista de mes o de año, filtro por
/// caballo y acumulados. Mismas reglas que windows/AVO.Windows/Views/CalendarView.xaml (Core/KeyData.swift ·
/// TrainingCalendar). Tocar un entrenamiento lo abre en «Datos clave».
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @State private var year: Int = TrainingCalendar.yearMonth(Date()).year
    @State private var month: Int = TrainingCalendar.yearMonth(Date()).month
    /// 0 = semana, 1 = mes, 2 = año (trainer's sketch 13/11/2026 added «Semana»).
    /// Vista semanal por defecto (boceto del entrenador 25/11/2026: el calendario es para la semana del planificador).
    @State private var mode: Int = 0
    @State private var weekStart: Date = TrainingCalendar.weekStart(Date())
    private var yearView: Bool { mode == 2 }
    @State private var hiddenHorses: Set<String> = []
    @State private var didJump: Bool = false
    /// Día abierto (AAAA-MM-DD): entrenamientos hechos y entrenamiento recomendado por el planificador.
    @State private var openDay: CalendarOpenDay? = nil
    /// Ficha de un caballo y un día: recomendado (rojo) o recomendado frente a realizado (verde).
    @State private var fichaReq: PlanFichaRequest? = nil

    var body: some View {
        let all: [CalendarEntry] = entries
        // trainer's sketch 13/11/2026: only the calendar, on the whole page (no horse filter, no totals row)
        VStack(alignment: .leading, spacing: 14) {
            header
            switch mode {
            case 0: weekGrid(all)
            case 2: yearGrid(all)
            default: monthGrid(all)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .sheet(item: $openDay) { (d: CalendarOpenDay) in
            CalendarDayDetail(day: d.id, close: { openDay = nil }, openSession: { (e: CalendarEntry) in openDay = nil; open(e) })
                .environment(app)
                .avoColorScheme()
        }
        .onAppear {
            // planificador semanal de cada caballo (semana en curso, motor ≥ 2.0.0-dev37)
            app.weekPlans.loadAll()
            // first visit: open the month of the most recent training
            if !didJump, let last = all.max(by: { $0.start < $1.start }) {
                // la vista semanal se queda en la semana en curso (la del planificador); el mes salta al último entrenamiento
                let ym = TrainingCalendar.yearMonth(last.start)
                year = ym.year
                month = ym.month
                didJump = true
            }
        }
        .accessibilityIdentifier("page.calendar")
    }

    private var entries: [CalendarEntry] { app.calendarEntries }

    // ------------------------------------------------------------------ header
    private var header: some View {
        headerRow
            .sheet(item: $fichaReq) { (r: PlanFichaRequest) in
                PlanFichaView(request: r, close: { fichaReq = nil }, openSession: { (id: String) in fichaReq = nil; openSessionId(id) })
                    .environment(app)
                    .avoColorScheme()
            }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.avoSecondary).accessibilityLabel(["Semana anterior", "Mes anterior", "Año anterior"][mode])
            Text(mode == 0 ? TrainingCalendar.weekTitle(weekStart)
                 : (yearView ? "\(year)" : "\(TrainingCalendar.monthNames[month - 1].capitalized) \(year)"))
                .font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
                .frame(minWidth: 220, alignment: .leading)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.avoSecondary).accessibilityLabel(["Semana siguiente", "Mes siguiente", "Año siguiente"][mode])
            Spacer()
            if app.weekPlans.loading {
                ProgressView().controlSize(.small)
                Text(app.weekPlans.progressText).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Picker("Vista", selection: $mode) {
                Text("Semana").tag(0)
                Text("Mes").tag(1)
                Text("Año").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }

    private func step(_ d: Int) {
        if mode == 0 {
            weekStart = TrainingCalendar.calendar.date(byAdding: .day, value: 7 * d, to: weekStart) ?? weekStart
            return
        }
        if yearView { year += d; return }
        month += d
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
    }

    // ------------------------------------------------------------------ month
    private func monthGrid(_ visible: [CalendarEntry]) -> some View {
        let days: [CalendarDay] = TrainingCalendar.monthGrid(year: year, month: month, entries: visible, today: Date())
        // 6 weeks × 7 days stretched to the whole height of the page
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(TrainingCalendar.weekdays, id: \.self) { (w: String) in
                    Text(w).font(.caption.weight(.semibold)).foregroundStyle(Avo.textDim).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { (r: Int) in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { (c: Int) in
                        if r * 7 + c < days.count { dayCell(days[r * 7 + c]) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func dayCell(_ d: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Text("\(d.day)").font(.footnote.weight(.semibold)).foregroundStyle(d.inMonth ? Avo.text : Avo.unknown.opacity(0.6))
            }
            let cs: [CalendarHorseChip] = horseChips(d.id, entries: d.entries)
            ForEach(Array(cs.prefix(3))) { (c: CalendarHorseChip) in
                horseChip(c, day: Self.isoDay(d.id), compact: true)
            }
            if cs.count > 3 {
                Text("+\(cs.count - 3) más").font(.caption2).foregroundStyle(Avo.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { openDay = CalendarOpenDay(id: Self.isoDay(d.id)) }
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity, alignment: .topLeading)
        .background(d.inMonth ? Avo.surface : Avo.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(d.isToday ? Avo.red : Avo.line, lineWidth: d.isToday ? 2 : 1))
    }

    // ------------------------------------------------------------------ week
    /// 7 columns (Monday first) over the whole page, each with the day's trainings: time, horse, distance.
    private func weekGrid(_ visible: [CalendarEntry]) -> some View {
        let days: [CalendarDay] = TrainingCalendar.weekGrid(start: weekStart, entries: visible, today: Date())
        return HStack(alignment: .top, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { (p: (offset: Int, element: CalendarDay)) in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(TrainingCalendar.weekdays[p.offset]).font(.caption.weight(.semibold)).foregroundStyle(Avo.textDim)
                        Spacer()
                        Text("\(p.element.day)").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                    }
                    ForEach(horseChips(p.element.id, entries: p.element.entries)) { (c: CalendarHorseChip) in
                        horseChip(c, day: Self.isoDay(p.element.id), compact: false)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .contentShape(Rectangle())
                .onTapGesture { openDay = CalendarOpenDay(id: Self.isoDay(p.element.id)) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Avo.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.element.isToday ? Avo.red : Avo.line, lineWidth: p.element.isToday ? 2 : 1))
            }
        }
        .frame(maxHeight: .infinity)
    }

    // ------------------------------------------------------------------ year
    private func yearGrid(_ visible: [CalendarEntry]) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(1...12, id: \.self) { (m: Int) in
                let s: CalendarSummary = TrainingCalendar.summary(TrainingCalendar.entries(in: year, m, visible))
                Button {
                    month = m
                    mode = 1
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TrainingCalendar.monthNames[m - 1].uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Avo.silver)
                        Text(s.count == 0 ? "—" : "\(s.count) sesiones").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                        Text(s.count == 0 ? " " : "\(s.distanceText) · \(s.durationText)").font(.caption).foregroundStyle(Avo.textDim)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ------------------------------------------------------------------ totals
    private func totals(_ s: CalendarSummary) -> some View {
        HStack(spacing: 10) {
            AvoMetric(label: yearView ? "Sesiones del año" : "Sesiones del mes", value: "\(s.count)")
            AvoMetric(label: "Tiempo acumulado", value: s.durationText)
            AvoMetric(label: "Duración media", value: s.meanText)
            AvoMetric(label: "Distancia acumulada", value: s.distanceText)
            AvoMetric(label: "Con RTK FIX", value: s.rtkText, caption: "≥ 50 % del tiempo en FIX (motor)",
                      accent: s.analysedCount > 0 && s.rtkCount < s.analysedCount ? Avo.warn : Avo.text)
        }
    }

    // ------------------------------------------------------------------ horses
    private func horseFilter(_ horses: [String]) -> some View {
        AvoCard(title: "Caballos") {
            if horses.isEmpty {
                AvoNoData(text: "Sin entrenamientos")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(horses, id: \.self) { (h: String) in
                        Toggle(isOn: Binding(get: { !hiddenHorses.contains(h) },
                                             set: { (on: Bool) in if on { hiddenHorses.remove(h) } else { hiddenHorses.insert(h) } })) {
                            Text(h).font(.callout).foregroundStyle(Avo.text)
                        }
                        .tint(Avo.red)
                    }
                    Text("Unifica en la Cuadra los nombres de un mismo caballo para ver juntas sus sesiones.")
                        .font(.caption2).foregroundStyle(Avo.textDim).padding(.top, 6)
                }
            }
        }
    }

    // ------------------------------------------------------------------ planificador
    /// "2026-11-5" (id de CalendarDay) → "2026-11-05".
    static func isoDay(_ id: String) -> String {
        let p: [String] = id.split(separator: "-").map(String.init)
        guard p.count == 3 else { return id }
        return p[0] + "-" + (p[1].count < 2 ? "0" + p[1] : p[1]) + "-" + (p[2].count < 2 ? "0" + p[2] : p[2])
    }

    /// Un recuadro por caballo y día: VERDE si ese día ya entrenó (abre recomendado frente a realizado) y ROJO con el
    /// entrenamiento recomendado por el planificador si aún no (abre la ficha del recomendado).
    private func horseChips(_ id: String, entries: [CalendarEntry]) -> [CalendarHorseChip] {
        let day: String = Self.isoDay(id)
        var order: [String] = []
        var byKey: [String: [CalendarEntry]] = [:]
        var nameOf: [String: String] = [:]
        for e in entries.sorted(by: { $0.start < $1.start }) {
            let key: String = app.sessions.first(where: { $0.id == e.id }).map { app.horseKey($0) } ?? e.horse
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(e)
            nameOf[key] = e.horse
        }
        var out: [CalendarHorseChip] = []
        var trained: Set<String> = []
        for k in order {
            let es: [CalendarEntry] = byKey[k] ?? []
            let km: Double = es.reduce(0) { $0 + $1.distanceKm }
            trained.insert(k.lowercased())
            let first: String = es.first.map { MadridTime.format($0.start, "HH:mm") } ?? ""
            out.append(CalendarHorseChip(id: "hecho|" + k, horseKey: k, horse: nameOf[k] ?? k, done: true,
                                         detail: first + " · " + DotNetFormat.custom(km, "0.00", spanish: true) + " km"))
        }
        for i in app.weekPlans.items(on: day) where !i.day.done && !trained.contains(i.key.lowercased()) {
            let extra: String = i.day.fastMaxM.map { " · hasta " + KbText.metres($0) } ?? ""
            out.append(CalendarHorseChip(id: "plan|" + i.key, horseKey: i.key, horse: i.name, done: false,
                                         detail: WeekPlan.typeTitle(i.day.type) + extra))
        }
        return out
    }

    private func horseChip(_ c: CalendarHorseChip, day: String, compact: Bool) -> some View {
        let color: Color = c.done ? Avo.ok : Avo.red
        return Button {
            fichaReq = PlanFichaRequest(horseKey: c.horseKey, horseName: c.horse, day: day)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(c.horse).font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold)).foregroundStyle(color).lineLimit(compact ? 1 : 2)
                if !compact {
                    Text(c.done ? "Hecho · " + c.detail : "Recomendado · " + c.detail).font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, compact ? 3 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.done ? "\(c.horse): entrenado, comparar con lo recomendado" : "\(c.horse): entrenamiento recomendado, \(c.detail)")
        .accessibilityIdentifier("calendar.chip.\(c.id)")
    }

    private func openSessionId(_ id: String) {
        if let s = app.sessions.first(where: { $0.id == id }) {
            app.select(s)
            app.page = .keyData
        }
    }

    private func open(_ e: CalendarEntry) {
        if let s = app.sessions.first(where: { $0.id == e.id }) {
            app.select(s)
            app.page = .keyData
        }
    }
}

/// Día abierto del calendario (AAAA-MM-DD).
struct CalendarOpenDay: Identifiable {
    let id: String
}

/// Recuadro de un caballo en un día del calendario.
struct CalendarHorseChip: Identifiable {
    let id: String
    let horseKey: String
    let horse: String
    /// true: ese día ya entrenó (verde); false: entrenamiento recomendado (rojo).
    let done: Bool
    let detail: String
}

/// Detalle de un día del calendario (boceto del entrenador 25/11/2026): los entrenamientos hechos ese día y, para los días
/// de la semana en curso que aún no han pasado, el entrenamiento recomendado por el planificador del motor para cada
/// caballo. Orientativo y sin calibrar: el entrenador decide.
struct CalendarDayDetail: View {
    @Environment(AppModel.self) private var app
    let day: String
    let close: () -> Void
    let openSession: (CalendarEntry) -> Void

    var body: some View {
        let sessions: [CalendarEntry] = app.calendarEntries.filter { AvoTime.formatter("yyyy-MM-dd").string(from: $0.start) == day }
            .sorted { $0.start < $1.start }
        let plans: [WeekPlanItem] = app.weekPlans.items(on: day)
        let pending: [WeekPlanItem] = plans.filter { !$0.day.done }
        let done: [WeekPlanItem] = plans.filter { $0.day.done }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AvoCard(title: "Entrenamientos hechos", subtitle: sessions.isEmpty ? "Ninguno registrado ese día" : "\(sessions.count) entrenamiento\(sessions.count == 1 ? "" : "s") · toca uno para abrirlo") {
                        if sessions.isEmpty {
                            AvoNoData(text: "Sin entrenamientos ese día")
                        } else {
                            ForEach(sessions) { (e: CalendarEntry) in
                                Button { openSession(e) } label: {
                                    HStack(spacing: 10) {
                                        Text(MadridTime.format(e.start, "HH:mm")).font(.callout.monospacedDigit()).foregroundStyle(Avo.textDim)
                                        Text(e.horse).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                                        Spacer()
                                        Text(DotNetFormat.custom(e.distanceKm, "0.00", spanish: true) + " km · " + TimeText.clock(e.durationS))
                                            .font(.caption.monospacedDigit()).foregroundStyle(Avo.silver)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Avo.textDim)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    AvoCard(title: "Entrenamiento recomendado (planificador)",
                            subtitle: "Propuesta orientativa del motor para cada caballo, sin calibrar · el entrenador decide") {
                        if app.weekPlans.loading && plans.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(app.weekPlans.progressText.isEmpty ? "Calculando…" : app.weekPlans.progressText)
                                    .font(.callout).foregroundStyle(Avo.textDim)
                            }
                        } else if pending.isEmpty {
                            AvoNoData(text: plans.isEmpty ? "El planificador propone la semana en curso (de lunes a domingo); para este día no hay propuesta."
                                                          : "Día ya pasado: abajo está lo realizado según los entrenamientos.")
                        } else {
                            ForEach(pending) { (p: WeekPlanItem) in
                                planRow(p.name, p.day)
                            }
                        }
                        if !done.isEmpty {
                            Divider().overlay(Avo.line)
                            Text("REALIZADO SEGÚN LOS ENTRENAMIENTOS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                            ForEach(done) { (p: WeekPlanItem) in
                                planRow(p.name, p.day).opacity(0.7)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Avo.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { close() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { app.weekPlans.loadAll(force: true) } label: { Label("Recalcular", systemImage: "arrow.clockwise") }
                        .disabled(app.weekPlans.loading)
                }
            }
        }
        .accessibilityIdentifier("calendar.day")
    }

    private var title: String {
        let f: DateFormatter = AvoTime.formatter("yyyy-MM-dd")
        guard let d = f.date(from: day) else { return day }
        return AvoTime.formatter("EEEE d 'de' MMMM").string(from: d).capitalized
    }

    private func planRow(_ horse: String, _ d: WeekPlanDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(horse).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).frame(width: 170, alignment: .leading)
            Text(d.typeText).fontWeight(.semibold).foregroundStyle(d.done ? Avo.textDim : Self.color(d.type)).frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(KbText.sentence(d.reason)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                if let m = d.fastMaxM, !d.done {
                    Text("Distancia rápida hasta \(KbText.metres(m))").font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
            Spacer(minLength: 4)
            Text(d.rules.map { WeekPlan.ruleTitle($0) }.joined(separator: " · ")).font(.caption2).foregroundStyle(Avo.textDim)
        }
        .padding(.vertical, 3)
    }

    static func color(_ t: String) -> Color {
        switch t {
        case "RAPIDO": return Avo.red
        case "CARRERA": return Avo.warn
        case "LIBRE": return Avo.ok
        default: return Avo.text
        }
    }
}
