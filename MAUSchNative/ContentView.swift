import SwiftUI
import WebKit
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let mauschURL = URL(string: "https://ppt0320.github.io/mausch/")!
private let mauschBackground = Color(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0)
private let mauschGreen = Color(red: 49.0 / 255.0, green: 211.0 / 255.0, blue: 154.0 / 255.0)

struct ContentView: View {
    @StateObject private var data = NativeCashData()
    @State private var selectedTab: NativeTab = .home
    @State private var showingMovement = false
    @State private var showingBox = false
    @State private var webView: WKWebView?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            WebAppView(
                webView: $webView,
                isLoading: $isLoading,
                loadFailed: $loadFailed,
                onPageLoaded: { page in data.connect(page) }
            )
            .opacity(selectedTab == .manage ? 1 : 0.001)
            .allowsHitTesting(selectedTab == .manage)
            .accessibilityHidden(selectedTab != .manage)

            if selectedTab == .manage {
                VStack {
                    HStack {
                        Button {
                            selectedTab = .home
                            data.refresh()
                        } label: {
                            Label("MAU$ch", systemImage: "chevron.left")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mauschGreen)
                        .foregroundStyle(mauschBackground)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    nativeHeader
                    Group {
                        switch selectedTab {
                        case .home:
                            HomeScreen(data: data, addMovement: { showingMovement = true }, addBox: { showingBox = true })
                        case .reports:
                            ReportsScreen(data: data)
                        case .manage:
                            EmptyView()
                        }
                    }
                    nativeTabBar
                }
                .background(mauschBackground.ignoresSafeArea())
            }

            if selectedTab == .manage && isLoading {
                ProgressView("Cargando MAU$ch…")
                    .tint(.white)
                    .padding(16)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }

            if selectedTab == .manage && loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 32))
                    Text("No se pudo conectar").font(.headline)
                    Text("Tus datos guardados en esta app no se borraron.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("Intentar de nuevo") {
                        loadFailed = false
                        isLoading = true
                        webView?.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(mauschBackground, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingMovement) {
            NativeMovementForm(boxes: data.activeBoxes) { record in
                data.save(store: "moves", record: record)
            }
        }
        .sheet(isPresented: $showingBox) {
            NativeBoxForm { record in
                data.save(store: "boxes", record: record)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                data.refresh()
            }
        }
        .onChange(of: selectedTab) { tab in
            if tab != .manage { data.refresh() }
        }
    }

    private var nativeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(red: 0.87, green: 0.72, blue: 0.43))
                .frame(width: 38, height: 38)
                .background(Color(red: 0.25, green: 0.20, blue: 0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("MAU$ch").font(.title3.bold())
                Text("CONTROL DE FONDOS")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            if data.isReady {
                Label("Actualizado", systemImage: "checkmark.icloud")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(mauschGreen)
                    .lineLimit(1)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var nativeTabBar: some View {
        HStack(spacing: 8) {
            tabButton(.home, title: "Inicio", symbol: "square.grid.2x2.fill")
            tabButton(.reports, title: "Reportes", symbol: "chart.bar.xaxis")
            tabButton(.manage, title: "Cajas y ajustes", symbol: "slider.horizontal.3")
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: NativeTab, title: String, symbol: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selectedTab == tab ? mauschGreen : .white.opacity(0.62))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private enum NativeTab {
    case home
    case reports
    case manage
}

@MainActor
private final class NativeCashData: ObservableObject {
    @Published private(set) var boxes: [CashBox] = []
    @Published private(set) var moves: [CashMove] = []
    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?

    private weak var webView: WKWebView?
    private var isRefreshing = false

    var activeBoxes: [CashBox] {
        boxes.filter { $0.deletedAt == nil }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var activeMoves: [CashMove] {
        let activeIDs = Set(activeBoxes.map(\.id))
        return moves.filter { $0.deletedAt == nil && activeIDs.contains($0.boxId) }
    }

    func connect(_ webView: WKWebView) {
        self.webView = webView
        refresh()
    }

    func refresh() {
        guard !isRefreshing, let webView else { return }
        isRefreshing = true
        let script = """
        for (let attempt = 0; attempt < 40; attempt++) {
          if (typeof all === 'function' && typeof db !== 'undefined' && db) break;
          await new Promise(resolve => setTimeout(resolve, 250));
        }
        if (typeof all !== 'function' || typeof db === 'undefined' || !db) {
          throw new Error('El almacenamiento todavía se está cargando.');
        }
        return JSON.stringify({boxes: await all('boxes'), moves: await all('moves')});
        """
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer { self.isRefreshing = false }
            do {
                let value = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
                guard let json = value as? String, let data = json.data(using: .utf8) else {
                    self.lastError = "No se pudieron leer las cajas."
                    return
                }
                let snapshot = try JSONDecoder().decode(CashSnapshot.self, from: data)
                self.boxes = snapshot.boxes
                self.moves = snapshot.moves
                self.isReady = true
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func balance(for box: CashBox) -> Double {
        let transactions = moves.filter { $0.boxId == box.id && $0.deletedAt == nil }
        return box.opening
            + transactions.filter { $0.kind == "entrada" }.reduce(0) { $0 + $1.amount }
            - transactions.filter { $0.kind == "salida" }.reduce(0) { $0 + $1.amount }
    }

    func total(for kind: String) -> Double {
        let activeIDs = Set(activeBoxes.map(\.id))
        let opening = kind == "entrada" ? activeBoxes.reduce(0) { $0 + $1.opening } : 0
        return opening + moves
            .filter { $0.deletedAt == nil && $0.kind == kind && activeIDs.contains($0.boxId) }
            .reduce(0) { $0 + $1.amount }
    }

    func save(store: String, record: [String: Any]) {
        guard let webView else {
            lastError = "Abre MAU$ch y espera a que carguen los datos."
            return
        }
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "await save(store, record); boxes = await all('boxes'); items = await all('moves'); renderHome(); return true;",
                    arguments: ["store": store, "record": record],
                    in: nil,
                    contentWorld: .page
                )
                self.refresh()
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}

private struct CashSnapshot: Decodable {
    var boxes: [CashBox]
    var moves: [CashMove]
}

private struct CashBox: Decodable, Identifiable {
    var id: String
    var name: String
    var note: String
    var opening: Double
    var date: String
    var closedAt: String?
    var deletedAt: Double?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Caja"
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        opening = try values.decodeIfPresent(Double.self, forKey: .opening) ?? 0
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? ""
        closedAt = try values.decodeIfPresent(String.self, forKey: .closedAt)
        deletedAt = try values.decodeIfPresent(Double.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, opening, date, closedAt, deletedAt
    }
}

private struct CashMove: Decodable, Identifiable {
    var id: String
    var boxId: String
    var kind: String
    var amount: Double
    var date: String
    var concept: String
    var note: String
    var deletedAt: Double?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        boxId = try values.decodeIfPresent(String.self, forKey: .boxId) ?? ""
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "salida"
        amount = try values.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? ""
        concept = try values.decodeIfPresent(String.self, forKey: .concept) ?? "Movimiento"
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        deletedAt = try values.decodeIfPresent(Double.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, boxId, kind, amount, date, concept, note, deletedAt
    }
}

private struct HomeScreen: View {
    @ObservedObject var data: NativeCashData
    var addMovement: () -> Void
    var addBox: () -> Void

    private var visibleMoves: [CashMove] {
        data.moves.filter { move in
            move.deletedAt == nil && data.activeBoxes.contains(where: { $0.id == move.boxId })
        }
    }

    private var totalBalance: Double {
        data.activeBoxes.reduce(0) { $0 + data.balance(for: $1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Disponible en tus cajas")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(totalBalance, format: .currency(code: "MXN"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(totalBalance < 0 ? .red : mauschGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.27), Color(red: 0.08, green: 0.13, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))

                HStack(spacing: 10) {
                    SummaryTile(title: "Entradas", amount: data.total(for: "entrada"), symbol: "arrow.down.left", color: mauschGreen)
                    SummaryTile(title: "Salidas", amount: data.total(for: "salida"), symbol: "arrow.up.right", color: .red)
                }

                HStack {
                    Text("Tus cajas").font(.title3.bold())
                    Spacer()
                    Button(action: addBox) {
                        Label("Nueva caja", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(mauschGreen)
                }

                if !data.isReady {
                    NativeEmptyState(title: "Cargando tus datos", symbol: "arrow.triangle.2.circlepath", message: "Estamos leyendo la información guardada en MAU$ch.")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if data.activeBoxes.isEmpty {
                    NativeEmptyState(title: "No hay cajas activas", symbol: "tray", message: "Crea una caja para empezar. Los reportes reflejan únicamente las cajas activas.")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(data.activeBoxes) { box in
                        NativeBoxCard(box: box, balance: data.balance(for: box), moveCount: visibleMoves.filter { $0.boxId == box.id }.count)
                    }
                }

                if !visibleMoves.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actividad reciente").font(.title3.bold())
                        ForEach(visibleMoves.sorted { $0.date > $1.date }.prefix(5)) { move in
                            NativeMoveRow(move: move, boxName: data.activeBoxes.first(where: { $0.id == move.boxId })?.name ?? "Caja")
                        }
                    }
                }

                Button(action: addMovement) {
                    Label("Registrar movimiento", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(mauschGreen)
                .foregroundStyle(mauschBackground)
                .disabled(data.activeBoxes.filter { $0.closedAt == nil }.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .refreshable { data.refresh() }
    }
}

private struct SummaryTile: View {
    let title: String
    let amount: Double
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(amount, format: .currency(code: "MXN"))
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct NativeEmptyState: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(mauschGreen)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NativeBoxCard: View {
    let box: CashBox
    let balance: Double
    let moveCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(box.name).font(.headline)
                    Text(box.note.isEmpty ? (box.closedAt == nil ? "Caja activa" : "Caja cerrada") : box.note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text(balance, format: .currency(code: "MXN"))
                    .font(.headline.bold())
                    .foregroundStyle(balance < 0 ? .red : mauschGreen)
            }
            HStack {
                Label("\(moveCount) movimientos", systemImage: "arrow.left.arrow.right")
                Spacer()
                Text("Fondo \(box.opening, format: .currency(code: "MXN"))")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(15)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

private struct NativeMoveRow: View {
    let move: CashMove
    let boxName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: move.kind == "entrada" ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(move.kind == "entrada" ? mauschGreen : .red)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(move.concept).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(boxName) · \(move.date)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 8)
            Text(move.amount, format: .currency(code: "MXN"))
                .font(.subheadline.bold())
                .foregroundStyle(move.kind == "entrada" ? mauschGreen : .red)
                .lineLimit(1)
        }
        .padding(11)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct ReportsScreen: View {
    @ObservedObject var data: NativeCashData

    private var generalReport: String {
        reportText(title: "REPORTE GENERAL", boxes: data.activeBoxes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Reportes").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reporte general").font(.headline)
                            Text("\(data.activeBoxes.count) cajas activas")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        ShareLink(item: generalReport) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .tint(mauschGreen)
                    }
                    HStack {
                        Text("Disponible")
                        Spacer()
                        Text(data.activeBoxes.reduce(0) { $0 + data.balance(for: $1) }, format: .currency(code: "MXN"))
                            .font(.title3.bold())
                            .foregroundStyle(mauschGreen)
                    }
                }
                .padding(16)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))

                Text("Reporte por caja").font(.title3.bold())
                if data.activeBoxes.isEmpty {
                    NativeEmptyState(title: "Sin cajas activas", symbol: "tray", message: "Cuando crees una caja, su reporte aparecerá aquí.")
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(data.activeBoxes) { box in
                        let boxReport = reportText(title: box.name, boxes: [box])
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(box.name).font(.headline)
                                    Text("Saldo: \(data.balance(for: box), format: .currency(code: "MXN"))")
                                        .font(.subheadline)
                                        .foregroundStyle(mauschGreen)
                                }
                                Spacer()
                                ShareLink(item: boxReport) {
                                    Label("Compartir", systemImage: "square.and.arrow.up")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                                .tint(mauschGreen)
                            }
                            let movements = data.moves.filter { $0.boxId == box.id && $0.deletedAt == nil }.sorted { $0.date > $1.date }
                            if movements.isEmpty {
                                Text("Sin movimientos activos.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.58))
                            } else {
                                ForEach(movements.prefix(8)) { move in
                                    NativeMoveRow(move: move, boxName: box.name)
                                }
                                if movements.count > 8 {
                                    Text("El reporte compartido incluye los \(movements.count) movimientos.")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.58))
                                }
                            }
                        }
                        .padding(15)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
                    }
                }
            }
            .padding(16)
        }
        .refreshable { data.refresh() }
    }

    private func reportText(title: String, boxes: [CashBox]) -> String {
        let ids = Set(boxes.map(\.id))
        let movements = data.moves.filter { $0.deletedAt == nil && ids.contains($0.boxId) }.sorted { $0.date > $1.date }
        let opening = boxes.reduce(0) { $0 + $1.opening }
        let incoming = opening + movements.filter { $0.kind == "entrada" }.reduce(0) { $0 + $1.amount }
        let outgoing = movements.filter { $0.kind == "salida" }.reduce(0) { $0 + $1.amount }
        let boxCount = boxes.count == 1 ? "1 caja activa" : "\(boxes.count) cajas activas"
        var lines = ["MAU$ch", title, boxCount, "", "Fondo inicial: \(opening.formatted(.currency(code: "MXN")))", "Entradas (incluye fondo): \(incoming.formatted(.currency(code: "MXN")))", "Salidas: \(outgoing.formatted(.currency(code: "MXN")))", "SALDO DISPONIBLE: \((incoming - outgoing).formatted(.currency(code: "MXN")))", "", "Movimientos"]
        lines += movements.map { "\($0.date) · \($0.kind == "entrada" ? "Entrada" : "Salida") · \($0.concept) · \($0.amount.formatted(.currency(code: "MXN")))" }
        return lines.joined(separator: "\n")
    }
}

private struct NativeMovementForm: View {
    @Environment(\.dismiss) private var dismiss
    let boxes: [CashBox]
    let onSave: ([String: Any]) -> Void

    @State private var boxID: String
    @State private var kind = "salida"
    @State private var amount = ""
    @State private var concept = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var message: String?

    init(boxes: [CashBox], onSave: @escaping ([String: Any]) -> Void) {
        self.boxes = boxes
        self.onSave = onSave
        _boxID = State(initialValue: boxes.first(where: { $0.closedAt == nil })?.id ?? boxes.first?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Movimiento") {
                    Picker("Tipo", selection: $kind) {
                        Text("Gasto").tag("salida")
                        Text("Ingreso").tag("entrada")
                    }
                    Picker("Caja", selection: $boxID) {
                        ForEach(boxes.filter { $0.closedAt == nil }) { box in
                            Text(box.name).tag(box.id)
                        }
                    }
                    TextField("Importe", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Concepto", text: $concept)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    TextField("Nota (opcional)", text: $note, axis: .vertical)
                }
                if let message {
                    Text(message).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(mauschBackground)
            .navigationTitle("Nuevo movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(boxID.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        let normalized = amount.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value > 0 else {
            message = "Escribe un importe mayor a cero."
            return
        }
        guard !concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Escribe el concepto del movimiento."
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        onSave([
            "id": UUID().uuidString.lowercased(),
            "boxId": boxID,
            "kind": kind,
            "amount": value,
            "date": Self.dateString(date),
            "concept": concept.trimmingCharacters(in: .whitespacesAndNewlines),
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "created": now,
            "updatedAt": now
        ])
        dismiss()
    }

    fileprivate static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct NativeBoxForm: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: ([String: Any]) -> Void

    @State private var name = ""
    @State private var note = ""
    @State private var opening = ""
    @State private var date = Date()
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva caja") {
                    TextField("Nombre", text: $name)
                    TextField("Descripción (opcional)", text: $note)
                    TextField("Fondo inicial", text: $opening)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                }
                if let message {
                    Text(message).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(mauschBackground)
            .navigationTitle("Crear caja")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        let normalized = opening.isEmpty ? "0" : opening.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value >= 0 else {
            message = "Escribe un fondo inicial válido."
            return
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            message = "Escribe un nombre para la caja."
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        onSave([
            "id": UUID().uuidString.lowercased(),
            "name": title,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "opening": value,
            "date": NativeMovementForm.dateString(date),
            "created": now,
            "updatedAt": now
        ])
        dismiss()
    }
}

#if os(iOS)
private struct WebAppView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    let onPageLoaded: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed, onPageLoaded: onPageLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = true
        webView = view
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool
        @Binding private var loadFailed: Bool
        private let onPageLoaded: (WKWebView) -> Void

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>, onPageLoaded: @escaping (WKWebView) -> Void) {
            _isLoading = isLoading
            _loadFailed = loadFailed
            self.onPageLoaded = onPageLoaded
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
            onPageLoaded(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: "MAU$ch", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: "MAU$ch", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Continuar", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let presenter = topViewController(for: webView) else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(title: "MAU$ch", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            presenter.present(alert, animated: true)
        }

        private func topViewController(for webView: WKWebView) -> UIViewController? {
            guard var presenter = webView.window?.rootViewController else { return nil }
            while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
                presenter = presented
            }
            return presenter
        }

        private func finish(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }
    }
}
#elseif os(macOS)
private struct WebAppView: NSViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    let onPageLoaded: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed, onPageLoaded: onPageLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool
        @Binding private var loadFailed: Bool
        private let onPageLoaded: (WKWebView) -> Void

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>, onPageLoaded: @escaping (WKWebView) -> Void) {
            _isLoading = isLoading
            _loadFailed = loadFailed
            self.onPageLoaded = onPageLoaded
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            loadFailed = false
            onPageLoaded(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let window = webView.window else {
                completionHandler()
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$ch"
            alert.informativeText = message
            alert.addButton(withTitle: "Aceptar")
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let window = webView.window else {
                completionHandler(false)
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$ch"
            alert.informativeText = message
            alert.addButton(withTitle: "Cancelar")
            alert.addButton(withTitle: "Continuar")
            alert.buttons.first?.keyEquivalent = "\u{1b}"
            alert.buttons.last?.keyEquivalent = "\r"
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertSecondButtonReturn)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let window = webView.window else {
                completionHandler(nil)
                return
            }
            let alert = NSAlert()
            alert.messageText = "MAU$ch"
            alert.informativeText = prompt
            let input = NSTextField(string: defaultText ?? "")
            input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = input
            alert.addButton(withTitle: "Cancelar")
            alert.addButton(withTitle: "Aceptar")
            alert.buttons.first?.keyEquivalent = "\u{1b}"
            alert.buttons.last?.keyEquivalent = "\r"
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertSecondButtonReturn ? input.stringValue : nil)
            }
        }

        private func finish(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading = false
            loadFailed = true
        }
    }
}
#endif

