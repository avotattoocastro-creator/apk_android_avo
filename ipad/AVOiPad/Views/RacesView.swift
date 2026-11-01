import SwiftUI

/// «Carreras»: races imported from the tracking PDF (France Galop / McLloyd «Statistiques Tracking»), filterable by horse
/// and date, with «Añadir carrera». Tapping a race opens its card (RaceDetailView). App/RacesModel.swift.
struct RacesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        RacesContent(model: app.races)
    }
}

private struct RacesContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: RacesModel

    var body: some View {
        Group {
            if let r = model.selectedRace {
                RaceDetailView(model: model, race: r)
            } else {
                list
            }
        }
        .background(Avo.bg)
        .onAppear { model.pageShown() }
        .raceImport(model) { (e: Error) in app.fail(e) }
    }

    // ------------------------------------------------------------------ list
    private var list: some View {
        let rows: [Race] = model.filtered
        return VStack(alignment: .leading, spacing: 0) {
            header(rows)
            if !model.races.isEmpty { filters }
            Rectangle().fill(Avo.line).frame(height: 1)
            if model.races.isEmpty {
                empty
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    AvoNoData(text: "Ninguna carrera cumple los filtros")
                    Button("Limpiar filtros") { model.clearFilters() }.buttonStyle(.avoSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { (r: Race) in
                            RaceRowView(race: r)
                                .contentShape(Rectangle())
                                .onTapGesture { model.open(r) }
                                .accessibilityIdentifier("races.row.\(r.id)")
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func header(_ rows: [Race]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock(rows)
                Spacer(minLength: 8)
                addButton
            }
            VStack(alignment: .leading, spacing: 10) {
                titleBlock(rows)
                addButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func titleBlock(_ rows: [Race]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Carreras").font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
            HStack(spacing: 8) {
                Text(rows.count == 1 ? "1 carrera" : "\(rows.count) carreras").font(.footnote.monospacedDigit()).foregroundStyle(Avo.silver)
                if rows.count != model.races.count {
                    Text("de \(model.races.count)").font(.footnote).foregroundStyle(Avo.textDim)
                }
                if model.busy {
                    ProgressView().controlSize(.mini)
                }
                if !model.message.isEmpty {
                    Text(model.message).font(.caption).foregroundStyle(model.messageIsError ? Avo.warn : Avo.cyan).lineLimit(2)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var addButton: some View {
        Button {
            model.startImport(horseCode: nil)
        } label: {
            Label("Añadir carrera", systemImage: "plus")
        }
        .buttonStyle(.avoPrimary)
        .disabled(model.busy)
        .accessibilityIdentifier("races.add")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Button("Todos los caballos") { model.filterHorse = "" }
                    ForEach(horsesWithRaces) { (item: RaceHorseOption) in
                        Button(item.name) { model.filterHorse = item.code }
                    }
                } label: {
                    Label(model.filterHorse.isEmpty ? "Todos los caballos" : model.horseName(model.filterHorse), systemImage: "figure.equestrian.sports")
                        .font(.callout).foregroundStyle(Avo.text)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                }
                HStack(spacing: 6) {
                    Toggle("Desde", isOn: $model.useDateFrom).labelsHidden().tint(Avo.red)
                    Text("Desde").font(.footnote).foregroundStyle(Avo.textDim)
                    DatePicker("", selection: $model.dateFrom, displayedComponents: .date).labelsHidden().disabled(!model.useDateFrom)
                }
                HStack(spacing: 6) {
                    Toggle("Hasta", isOn: $model.useDateTo).labelsHidden().tint(Avo.red)
                    Text("Hasta").font(.footnote).foregroundStyle(Avo.textDim)
                    DatePicker("", selection: $model.dateTo, displayedComponents: .date).labelsHidden().disabled(!model.useDateTo)
                }
                if model.hasFilters {
                    Button("Limpiar filtros") { model.clearFilters() }.buttonStyle(.avoSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    /// Horses that have races (filter menu).
    private var horsesWithRaces: [RaceHorseOption] {
        var seen: Set<String> = []
        var out: [RaceHorseOption] = []
        for r in model.races {
            guard let c = r.horseRecordCode, !seen.contains(c.uppercased()) else { continue }
            seen.insert(c.uppercased())
            out.append(RaceHorseOption(code: c, name: model.horseName(c)))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "flag.checkered").font(.system(size: 34)).foregroundStyle(Avo.red)
            Text("Todavía no hay carreras").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
            Text("Pulsa «Añadir carrera» y elige el PDF «Statistiques Tracking» de la carrera (France Galop / McLloyd). La app busca el caballo de la Cuadra entre los participantes, transcribe la carrera completa y la analiza con los entrenamientos del caballo. También puedes añadirla desde la ficha del caballo en Cuadra.")
                .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            addButton.padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct RaceHorseOption: Identifiable {
    var code: String
    var name: String
    var id: String { code }
}

/// One race of the list: date, hippodrome, race, distance, our horse, finish/field, time and gap to the winner.
struct RaceRowView: View {
    let race: Race

    var body: some View {
        let us: RaceRunner? = race.ourRunner
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(race.dateText).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text)
                Text(race.hippodrome).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(race.title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                    if race.isDemo { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) }
                }
                Text("\(race.category.isEmpty ? "" : race.category + " · ")\(race.distanceText) · \(race.horseName ?? "—") (\(us?.name ?? "—"))")
                    .font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(race.finishText).font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(us?.finish == 1 ? Avo.ok : Avo.text)
                Text("Puesto").font(.caption2).foregroundStyle(Avo.textDim)
            }
            .frame(width: 70, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceFormat.official(us?.officialTimeS)).font(.callout.monospacedDigit()).foregroundStyle(Avo.text)
                Text(us?.finish == 1 ? "Ganador" : RaceFormat.signedSeconds(race.ourGapToWinnerS) + " al 1.º")
                    .font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
            }
            .frame(width: 110, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Avo.textDim)
        }
        .padding(12)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}
