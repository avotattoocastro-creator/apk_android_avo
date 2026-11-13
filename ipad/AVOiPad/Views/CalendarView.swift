import SwiftUI

/// «Calendario» (paridad iPad ↔ PC, docs/PARIDAD_IPAD_PC.md): entrenamientos por día en vista de mes o de año, filtro por
/// caballo y acumulados. Mismas reglas que windows/AVO.Windows/Views/CalendarView.xaml (Core/KeyData.swift ·
/// TrainingCalendar). Tocar un entrenamiento lo abre en «Datos clave».
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @State private var year: Int = TrainingCalendar.yearMonth(Date()).year
    @State private var month: Int = TrainingCalendar.yearMonth(Date()).month
    @State private var yearView: Bool = false
    @State private var hiddenHorses: Set<String> = []
    @State private var didJump: Bool = false

    var body: some View {
        let all: [CalendarEntry] = entries
        // trainer's sketch 13/11/2026: only the calendar, on the whole page (no horse filter, no totals row)
        VStack(alignment: .leading, spacing: 14) {
            header
            if yearView { yearGrid(all) } else { monthGrid(all) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear {
            // first visit: open the month of the most recent training
            if !didJump, let last = all.max(by: { $0.start < $1.start }) {
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
        HStack(spacing: 10) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.avoSecondary).accessibilityLabel(yearView ? "Año anterior" : "Mes anterior")
            Text(yearView ? "\(year)" : "\(TrainingCalendar.monthNames[month - 1].capitalized) \(year)")
                .font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
                .frame(minWidth: 220, alignment: .leading)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.avoSecondary).accessibilityLabel(yearView ? "Año siguiente" : "Mes siguiente")
            Spacer()
            Picker("Vista", selection: $yearView) {
                Text("Mes").tag(false)
                Text("Año").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    private func step(_ d: Int) {
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
            ForEach(d.entries.prefix(3)) { (e: CalendarEntry) in
                Button { open(e) } label: {
                    Text("\(e.horse) · \(MadridTime.format(e.start, "HH:mm"))")
                        .font(.caption2).foregroundStyle(Avo.text).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Avo.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .leading) { Rectangle().fill(Avo.blue).frame(width: 3) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar.entry.\(e.id)")
            }
            if d.entries.count > 3 {
                Text("+\(d.entries.count - 3) más").font(.caption2).foregroundStyle(Avo.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity, alignment: .topLeading)
        .background(d.inMonth ? Avo.surface : Avo.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(d.isToday ? Avo.red : Avo.line, lineWidth: d.isToday ? 2 : 1))
    }

    // ------------------------------------------------------------------ year
    private func yearGrid(_ visible: [CalendarEntry]) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(1...12, id: \.self) { (m: Int) in
                let s: CalendarSummary = TrainingCalendar.summary(TrainingCalendar.entries(in: year, m, visible))
                Button {
                    month = m
                    yearView = false
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

    private func open(_ e: CalendarEntry) {
        if let s = app.sessions.first(where: { $0.id == e.id }) {
            app.select(s)
            app.page = .keyData
        }
    }
}
