import SwiftUI

/// Head of «Resumen» in the Equimetre style the trainer chose (14/11/2026): horse photo and name, big date and time,
/// discipline · rider, distance and duration, the place, the comment of the training and the weather of the session.
/// Nothing is invented: the weather is the model at the start and place of THIS session, loaded on entering.
struct SummaryHero: View {
    @Environment(AppModel.self) private var app
    @State private var notes: String = ""
    @State private var loadedFor: String = ""

    var body: some View {
        if let s = app.selected {
            AvoCard {
                HStack(alignment: .top, spacing: 20) {
                    horseColumn(s).frame(width: 170)
                    VStack(alignment: .center, spacing: 12) {
                        Text(Self.bigDate(s)).font(.system(size: 30, weight: .light)).foregroundStyle(Avo.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(s.discipline)  ·  Jinete: \(s.rider)").font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 34) {
                            figure("Distancia", s.distanceText)
                            figure("Duración", s.durationText)
                            if !place.isEmpty { figure("Lugar", place) }
                        }
                        notesBox(s)
                    }
                    .frame(maxWidth: .infinity)
                    weatherColumn(s).frame(width: 150)
                }
            }
            .onAppear { load() }
            .onChange(of: app.selected?.id ?? "") { _, _ in load() }
            // trainer's sketch 14/11/2026: the weather updates by itself on entering, with the exact data of the training
            // (its start time and first GNSS position; the model is cached for use without connection)
            .task(id: app.selected?.id ?? "") { await app.environment.load(force: false) }
            .onChange(of: notes) { _, v in
                guard let s = app.selected, s.id == loadedFor, v != s.notes else { return }
                app.saveSessionNotes(s, v)
            }
            .accessibilityIdentifier("summary.hero")
        }
    }

    private var place: String { app.environment.placeName.trimmed }

    private func horseColumn(_ s: SessionItem) -> some View {
        VStack(spacing: 10) {
            Group {
                if let code = s.horseCode, let img = IdentityPhotos.load(app.paths.root, code) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "figure.equestrian.sports").font(.system(size: 34)).foregroundStyle(Avo.silver)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Avo.surface2)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Avo.line, lineWidth: 1))
            Text(s.horse.uppercased()).font(.footnote.weight(.bold)).foregroundStyle(Avo.text).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7)
            if let code = s.horseCode {
                Button("VER FICHA") {
                    app.page = .stable
                    app.stable.page(.horse).select(code)
                }
                .font(.caption2.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Avo.textDim)
            }
            Button { app.stable.openAssign(s) } label: {
                Label("Editar", systemImage: "pencil").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.avoSecondary)
            Button { app.page = .reports } label: {
                Label("Informe PDF", systemImage: "doc.richtext").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.avoSecondary)
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Avo.textDim)
            Text(value).font(.title3).foregroundStyle(Avo.text).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func notesBox(_ s: SessionItem) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
            if notes.isEmpty {
                Text("Comentario del entrenamiento…").font(.callout).foregroundStyle(Avo.textDim)
                    .padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
            }
        }
        .frame(height: 100)
        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
        .accessibilityIdentifier("summary.notes")
    }

    @ViewBuilder
    private func weatherColumn(_ s: SessionItem) -> some View {
        let env: EnvironmentModel = app.environment
        let has: Bool = env.loadedFor == s.id && env.tempHeadline != "Sin datos"
        VStack(spacing: 8) {
            Image(systemName: has ? "cloud.sun" : "cloud").font(.system(size: 40, weight: .thin)).foregroundStyle(Avo.silver)
            if has {
                Text(env.tempHeadline).font(.title2.weight(.light)).foregroundStyle(Avo.text)
                Text("Viento \(env.windHeadline)").font(.caption).foregroundStyle(Avo.textDim).multilineTextAlignment(.center)
                if env.tideHeadline != "Sin datos" {
                    Text("Marea \(env.tideHeadline)").font(.caption).foregroundStyle(Avo.textDim)
                }
                Text("Modelo, no medición").font(.caption2).foregroundStyle(Avo.textDim)
            } else if env.loading {
                ProgressView().controlSize(.small)
                Text("Consultando el tiempo del entrenamiento…").font(.caption).foregroundStyle(Avo.textDim).multilineTextAlignment(.center)
            } else {
                Text("Sin datos del tiempo").font(.caption).foregroundStyle(Avo.textDim)
                Text(env.status).font(.caption2).foregroundStyle(Avo.textDim).multilineTextAlignment(.center).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func load() {
        loadedFor = app.selected?.id ?? ""
        notes = app.selected?.notes ?? ""
    }

    /// «SÁB 8 NOV 2026 · 11:38» (Europe/Madrid).
    static func bigDate(_ s: SessionItem) -> String {
        MadridTime.format(s.start, "EEE d MMM yyyy · HH:mm").uppercased().replacingOccurrences(of: ".", with: "")
    }
}

/// Folding section of «Resumen» (Ocultar / Desplegar), Equimetre «Key parameters».
struct SummaryFold<Content: View>: View {
    let title: String
    @State var open: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Avo.red)
                    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Spacer()
                    Text(open ? "Ocultar" : "Desplegar").font(.caption.weight(.semibold)).foregroundStyle(Avo.textDim)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
            if open { content() }
        }
    }
}
