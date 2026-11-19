import SwiftUI
import Foundation

// iOS diagnostic client. The catalog data is extracted exclusively from
// webos/fidelity/data/portal.js of the pinned Hydra LG repository.
struct HydraCatalogTitle: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let kind: String
    let synopsis: String
    let poster: String
    let year: String
    let row: String
    let score: String

    init?(_ source: [String: Any]) {
        func value(_ key: String) -> String {
            if let text = source[key] as? String { return text }
            if let number = source[key] as? NSNumber { return number.stringValue }
            return ""
        }
        let identifier = value("id")
        guard !identifier.isEmpty else { return nil }
        id = identifier
        title = value("title")
        category = value("category")
        kind = value("kind")
        synopsis = value("synopsis")
        poster = value("poster")
        year = value("year")
        row = value("row")
        score = value("score")
    }
}

@MainActor
final class HydraCatalogStore: ObservableObject {
    @Published private(set) var local: [HydraCatalogTitle] = []
    @Published private(set) var remote: [HydraCatalogTitle] = []
    @Published private(set) var snapshotDate = "desconocida"
    @Published private(set) var status = "Sin consultar el servidor"
    @Published private(set) var detail = "El catálogo guardado se carga directamente desde el código de Hydra LG."
    @Published private(set) var checking = false
    @Published var showRemote = false

    private let portal = HydraPortalClient()

    init() {
        guard let url = Bundle.main.url(forResource: "hydra-catalog", withExtension: "json", subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "hydra-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["items"] as? [[String: Any]] else {
            status = "No se encontró el catálogo original"
            detail = "El archivo hydra-catalog.json falta en el paquete. No se intentó ninguna conexión."
            return
        }
        local = raw.compactMap(HydraCatalogTitle.init)
        let timestamp = object["generatedAt"] as? String ?? "desconocida"
        snapshotDate = String(timestamp.prefix(10))
    }

    var active: [HydraCatalogTitle] {
        (showRemote && !remote.isEmpty) ? remote : local
    }

    func checkLive() {
        guard !checking else { return }
        checking = true
        status = "Solicitando sesión nueva a Hydra…"
        detail = "Prueba directa desde el iPhone. No necesita PC ni utiliza el catálogo de Nova."
        remote = []
        showRemote = false

        Task {
            do {
                _ = try await portal.execute("prewarm", parameters: [:])
                status = "Sesión aceptada. Consultando películas…"
                let response = try await portal.execute("home", parameters: [
                    "root": "movies", "pageNum": 1
                ])
                let movies = (response["items"] as? [[String: Any]] ?? [])
                    .compactMap(HydraCatalogTitle.init)

                status = "Consultando series…"
                var series: [HydraCatalogTitle] = []
                var seriesError: String?
                do {
                    let response2 = try await portal.execute("home", parameters: [
                        "root": "series", "pageNum": 1
                    ])
                    series = (response2["items"] as? [[String: Any]] ?? [])
                        .compactMap(HydraCatalogTitle.init)
                } catch {
                    seriesError = error.localizedDescription
                }
                var dedup = Set<String>()
                remote = (movies + series).filter { dedup.insert($0.id).inserted }

                if remote.isEmpty {
                    status = "Sesión aceptada, catálogo remoto vacío"
                    detail = "El portal respondió, pero el adaptador no obtuvo títulos. Películas: \(movies.count), series: \(series.count). \(seriesError ?? "")"
                } else {
                    status = "Catálogo EN VIVO recibido"
                    detail = "Hydra respondió desde este iPhone. Películas: \(movies.count), series: \(series.count). \(seriesError.map { "Series fallaron: " + $0 } ?? "Ambas consultas completadas.")"
                    showRemote = true
                }
            } catch {
                status = "Falló la conexión en vivo"
                detail = error.localizedDescription
                showRemote = false
            }
            checking = false
        }
    }
}

struct HydraRootView: View {
    @StateObject private var catalog = HydraCatalogStore()
    @State private var query = ""
    @State private var category = "Todo"
    @State private var limit = 40
    @State private var selected: HydraCatalogTitle?

    private let tabs = ["Todo", "Películas", "Series", "Anime", "Infantil"]

    private var filtered: [HydraCatalogTitle] {
        let source = catalog.active
        return source.filter { item in
            let name = item.kind.lowercased()
            let matchingCategory: Bool
            switch category {
            case "Películas": matchingCategory = name.contains("película") || name == "movie"
            case "Series": matchingCategory = name.contains("serie") || name == "series"
            case "Anime": matchingCategory = name.contains("anime") || item.category.lowercased().contains("anime")
            case "Infantil": matchingCategory = name.contains("infantil") || item.category.lowercased().contains("infantil")
            default: matchingCategory = true
            }
            let matchingQuery = query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
            return matchingCategory && matchingQuery
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    connectionPanel

                    TextField("Buscar en el catálogo Hydra", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _ in limit = 40 }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(tabs, id: \.self) { tab in
                                Button(tab) {
                                    category = tab
                                    limit = 40
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(category == tab ? Color.blue : Color.secondary.opacity(0.18))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    HStack {
                        Text(catalog.showRemote && !catalog.remote.isEmpty ? "Resultados EN VIVO" : "Catálogo guardado LG")
                            .font(.headline)
                        Spacer()
                        Text("\(filtered.count) títulos")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    ForEach(Array(filtered.prefix(limit))) { item in
                        Button { selected = item } label: {
                            HydraTitleRow(title: item)
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.count > limit {
                        Button("Mostrar más títulos") { limit += 40 }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                            .padding(.vertical, 8)
                    }
                    Text("Prueba de catálogo solamente: la reproducción no está integrada todavía.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Hydra · Prueba iOS")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { item in
                HydraTitleDetail(title: item)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Catálogo original Hydra LG").font(.title2.bold())
            Text("610 títulos en el archivo original · corte: \(catalog.snapshotDate)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Se ejecuta en el iPhone; no usa Windows, Nova ni Apple Controller.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: catalog.showRemote ? "checkmark.circle.fill" : "network")
                    .foregroundColor(catalog.showRemote ? .green : .secondary)
                Text("Prueba de conexión al servidor").font(.headline)
            }
            Text(catalog.status).font(.subheadline.bold())
            Text(catalog.detail).font(.footnote).textSelection(.enabled)
            if catalog.checking {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                catalog.checkLive()
                category = "Todo"
                limit = 40
            } label: {
                Label(catalog.checking ? "Probando portal…" : "Probar catálogo EN VIVO", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(catalog.checking)
            if !catalog.remote.isEmpty {
                Picker("Fuente de datos", selection: $catalog.showRemote) {
                    Text("Guardado").tag(false)
                    Text("En vivo").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HydraTitleRow: View {
    let title: HydraCatalogTitle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = URL(string: title.poster), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.18).overlay {
                            Image(systemName: "film").foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 74, height: 105)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "film")
                    .frame(width: 74, height: 105)
                    .background(Color.secondary.opacity(0.15))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title.title.isEmpty ? "(sin título)" : title.title)
                    .font(.subheadline.bold()).lineLimit(2)
                Text("\(title.kind.capitalized) · \(title.year)")
                    .font(.caption).foregroundStyle(.secondary)
                if !title.row.isEmpty {
                    Text(title.row).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if !title.synopsis.isEmpty {
                    Text(title.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct HydraTitleDetail: View {
    let title: HydraCatalogTitle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(title.title).font(.title2.bold())
                    Text("\(title.kind.capitalized) · \(title.year)")
                        .foregroundStyle(.secondary)
                    if !title.synopsis.isEmpty {
                        Text(title.synopsis)
                    }
                    Text("ID del catálogo Hydra: \(title.id)")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Solo estamos comprobando el origen del catálogo; todavía no hay reproducción en iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Detalle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
