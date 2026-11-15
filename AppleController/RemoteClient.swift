import Foundation
import Combine

struct RemoteSearchItem: Identifiable, Decodable {
    let index: Int
    let title: String
    let kind: String
    let description: String
    let image: String
    var id: Int { index }
    var imageURL: URL? {
        guard image.hasPrefix("https://") else { return nil }
        return URL(string: image)
    }
    var kindLabel: String {
        switch kind { case "tv": return "TV EN VIVO"
            case "movies": return "PELÍCULA"
            case "series": return "SERIE"
            default: return "CONTENIDO" }
    }
}

struct RemoteBrowseItem: Identifiable, Decodable {
    let index: Int
    let title: String
    let kind: String
    let description: String
    let image: String
    var id: Int { index }
    var imageURL: URL? {
        guard image.hasPrefix("https://") else { return nil }
        return URL(string: image)
    }
    var opensFolder: Bool { kind == "folder" || kind == "movies" || kind == "series" }
    var kindLabel: String {
        switch kind {
        case "tv": return "EN VIVO"
        case "movies": return "PELÍCULA"
        case "series": return "SERIE"
        case "episode": return "EPISODIO"
        default: return "CATEGORÍA"
        }
    }
}

struct RemotePCSetting: Identifiable, Decodable {
    let key: String
    let label: String
    let category: String
    let min: Int
    let max: Int
    let step: Int
    var value: Int
    var id: String { key }
}

private struct BrowseStep: Decodable {
    let generation: Int
    let state: String
}
private struct BrowsePage: Decodable {
    let generation: Int
    let state: String
    let message: String
    let title: String
    let description: String
    let image: String
    let total: Int
    let offset: Int
    let auto_played: Bool
    let items: [RemoteBrowseItem]
}
private struct DesktopSettingsResponse: Decodable {
    let settings: [RemotePCSetting]
}

private struct SearchStart: Decodable { let generation: Int; let state: String }
private struct SearchSnapshot: Decodable { let generation: Int; let state: String; let message: String; let items: [RemoteSearchItem] }

@MainActor
final class RemoteClient: ObservableObject {
    @Published var host: String = UserDefaults.standard.string(forKey: "xuperHost") ?? ""
    @Published var pin: String = ""
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published var message = "Conecta tu iPhone a la misma red Wi-Fi que tu PC."
    @Published var volume = 100.0
    @Published var brightness = 50.0
    @Published private(set) var youtubeActive = false
    @Published var youtubeMessage = "YouTube se abrirá en el navegador de tu PC."
    @Published private(set) var searchItems: [RemoteSearchItem] = []
    @Published private(set) var searching = false
    @Published private(set) var searchMessage = "Busca canales, películas o series."
    @Published private(set) var browseItems: [RemoteBrowseItem] = []
    @Published private(set) var browseTitle = "Explorar XuperTV"
    @Published private(set) var browseDescription = ""
    @Published private(set) var browseMessage = ""
    @Published private(set) var browseLoading = false
    @Published private(set) var browseTotal = 0
    @Published private(set) var browseDepth = 0
    @Published private(set) var pcSettings: [RemotePCSetting] = []
    @Published private(set) var pcSettingsLoading = false
    @Published private(set) var pcSettingsMessage = ""

    private let port = 47831
    private let session: URLSession
    private var authToken: String?
    private var queue: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var browseGeneration = 0
    private var browseWork: Task<Void, Never>?
    private var settingsWork: [String: Task<Void, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    private func validHost(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { component in
            guard let number = Int(component) else { return false }
            return number >= 0 && number <= 255 && component.count <= 3
        }
    }

    private func api(_ endpoint: String,
                     payload: [String: Any],
                     token: String? = nil) async throws -> Data {
        guard validHost(host), let url = URL(string: "http://\(host):\(port)/\(endpoint)") else {
            throw RemoteError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RemoteError.unavailable
        }
        guard response.statusCode == 200 else {
            if response.statusCode == 400,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reason = json["error"] as? String {
                throw RemoteError.serverMessage(reason)
            }
            if response.statusCode == 401 { throw RemoteError.expired }
            if response.statusCode == 403 { throw RemoteError.badPIN }
            if response.statusCode == 429 { throw RemoteError.tooManyAttempts }
            throw RemoteError.unavailable
        }
        return data
    }

    func connect() async {
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHost(host) else {
            message = "Escribe la IP local de tu PC. Ejemplo: 192.168.1.25"
            return
        }
        UserDefaults.standard.set(host, forKey: "xuperHost")
        connecting = true
        defer { connecting = false }
        if let stored = KeychainStore.load(for: host) {
            do {
                _ = try await api("input", payload: ["action": "ping"], token: stored)
                authToken = stored
                connected = true
                message = "Conectado a Xuper TV."
                beginHeartbeat()
                return
            } catch { /* Token may have been rotated on Windows. Pair again. */ }
        }
        guard pin.count == 6, pin.allSatisfy({ $0.isNumber }) else {
            message = "Escribe el PIN de 6 dígitos que aparece en tu TV."
            return
        }
        do {
            let data = try await api("pair", payload: ["pin": pin])
            let result = try JSONDecoder().decode(PairResult.self, from: data)
            guard result.token.count == 64 else { throw RemoteError.unavailable }
            KeychainStore.store(result.token, for: host)
            authToken = result.token
            connected = true
            pin = ""
            message = "¡Conectado! Ya puedes controlar Xuper TV."
            beginHeartbeat()
        } catch {
            connected = false
            message = Self.explanation(error)
        }
    }

    func restore() async {
        guard !host.isEmpty, KeychainStore.load(for: host) != nil else { return }
        await connect()
    }

    func changePC() {
        browseWork?.cancel()
        for (_, work) in settingsWork { work.cancel() }
        browseItems = []
        pcSettings = []
        browseGeneration = 0
        pingTask?.cancel()
        searchTask?.cancel()
        searchItems = []
        searching = false
        youtubeActive = false
        authToken = nil
        connected = false
        message = "Escribe la IP y el PIN de la PC que quieres controlar."
    }

    func send(_ action: String,
              dx: Int? = nil,
              dy: Int? = nil,
              value: Int? = nil,
              text: String? = nil) {
        guard connected, let authToken else { return }
        var data: [String: Any] = ["action": action]
        if let dx { data["dx"] = dx }
        if let dy { data["dy"] = dy }
        if let value { data["value"] = value }
        if let text { data["text"] = text }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                _ = try await self.api("input", payload: data, token: authToken)
            } catch {
                let explanation = Self.explanation(error)
                if self.youtubeActive { self.youtubeMessage = explanation }
                else { self.message = explanation }
                if case RemoteError.expired = error {
                    self.connected = false
                    self.pingTask?.cancel()
                }
            }
        }
    }

    func search(_ query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, connected, let authToken else { return }
        send("search")
        let previous = queue
        // The PC handles the search shortcut, then opens its text-entry loop.
        // Wait briefly before delivering the text and Enter, so none of the
        // keystrokes get swallowed by the main screen's event queue.
        queue = Task { [weak self] in
            await previous?.value
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                _ = try await self.api("input", payload: [
                    "action": "text", "text": String(cleaned.prefix(70))
                ], token: authToken)
                _ = try await self.api("input", payload: [
                    "action": "ok"
                ], token: authToken)
            } catch {
                self.message = Self.explanation(error)
            }
        }
    }

    // MARK: Full desktop catalogue
    func startFullCatalog() {
        browseWork?.cancel()
        browseWork = Task {
            browseLoading = true
            browseItems = []
            browseTotal = 0
            browseDepth = 0
            browseMessage = "Cargando categorías..."
            do {
                let data = try await api("catalog/browse/start", payload: [:], token: authToken)
                let step = try JSONDecoder().decode(BrowseStep.self, from: data)
                browseGeneration = step.generation
                await loadBrowsePage(offset: 0)
            } catch {
                browseMessage = Self.explanation(error)
                browseLoading = false
            }
        }
    }

    private func loadBrowsePage(offset: Int) async {
        let generation = browseGeneration
        browseLoading = true
        do {
            for _ in 0..<65 {
                try Task.checkCancellation()
                let data = try await api("catalog/browse/results", payload: [
                    "generation": generation,
                    "offset": offset,
                    "limit": 48
                ], token: authToken)
                let page = try JSONDecoder().decode(BrowsePage.self, from: data)
                guard page.generation == generation else {
                    browseMessage = "El catálogo cambió. Ábrelo de nuevo."
                    browseLoading = false
                    return
                }
                if page.state == "loading" {
                    browseMessage = page.message
                    try await Task.sleep(nanoseconds: 650_000_000)
                    continue
                }
                if page.state != "ready" {
                    browseMessage = page.message
                    browseLoading = false
                    return
                }
                browseTitle = page.title
                browseDescription = page.description
                browseTotal = page.total
                if offset == 0 { browseItems = page.items }
                else { browseItems.append(contentsOf: page.items) }
                browseMessage = page.auto_played ?
                    "Reproduciendo película en tu PC." : page.message
                browseLoading = false
                return
            }
            browseMessage = "El catálogo tardó demasiado en responder."
        } catch is CancellationError {
            return
        } catch {
            browseMessage = Self.explanation(error)
        }
        browseLoading = false
    }

    func loadMoreBrowse() {
        guard !browseLoading, browseItems.count < browseTotal else { return }
        browseWork?.cancel()
        browseWork = Task { await loadBrowsePage(offset: browseItems.count) }
    }

    func browseSelect(_ item: RemoteBrowseItem) {
        guard !browseLoading else { return }
        browseWork?.cancel()
        browseWork = Task {
            browseLoading = true
            do {
                let data = try await api("catalog/browse/select", payload: [
                    "generation": browseGeneration, "index": item.index
                ], token: authToken)
                let step = try JSONDecoder().decode(BrowseStep.self, from: data)
                if step.state == "playing" {
                    browseMessage = "Reproduciendo \(item.title) en la PC."
                    browseLoading = false
                } else {
                    browseGeneration = step.generation
                    browseDepth += 1
                    browseItems = []
                    browseTotal = 0
                    await loadBrowsePage(offset: 0)
                }
            } catch {
                browseMessage = Self.explanation(error)
                browseLoading = false
            }
        }
    }

    func browseBack() {
        guard browseDepth > 0, !browseLoading else { return }
        browseWork?.cancel()
        browseWork = Task {
            browseLoading = true
            do {
                let data = try await api("catalog/browse/back", payload: [
                    "generation": browseGeneration
                ], token: authToken)
                let step = try JSONDecoder().decode(BrowseStep.self, from: data)
                browseGeneration = step.generation
                browseDepth -= 1
                await loadBrowsePage(offset: 0)
            } catch {
                browseMessage = Self.explanation(error)
                browseLoading = false
            }
        }
    }

    func cancelBrowse() {
        browseWork?.cancel()
    }

    // MARK: Real Windows playback preferences
    func loadPCSettings() {
        pcSettingsLoading = true
        Task {
            do {
                let data = try await api("settings/get", payload: [:], token: authToken)
                let received = try JSONDecoder().decode(DesktopSettingsResponse.self, from: data)
                pcSettings = received.settings
                pcSettingsMessage = "Los cambios se envían a XuperTV en Windows."
            } catch {
                pcSettingsMessage = Self.explanation(error)
            }
            pcSettingsLoading = false
        }
    }

    func updatePCSetting(_ key: String, value: Int) {
        guard let index = pcSettings.firstIndex(where: { $0.key == key }) else { return }
        let setting = pcSettings[index]
        guard value >= setting.min, value <= setting.max,
              (value - setting.min) % max(1, setting.step) == 0 else { return }
        pcSettings[index].value = value
        settingsWork[key]?.cancel()
        settingsWork[key] = Task {
            try? await Task.sleep(nanoseconds: 170_000_000)
            if Task.isCancelled { return }
            do {
                _ = try await api("settings/set", payload: [
                    "key": key, "value": value
                ], token: authToken)
                pcSettingsMessage = key == "video_preset" ?
                    "La calidad nueva se aplica al siguiente video." :
                    "Ajuste enviado a la PC."
            } catch {
                pcSettingsMessage = Self.explanation(error)
                loadPCSettings() // revert if the PC rejected the setting
            }
        }
    }

    func startYouTube() async {
        guard connected, let authToken else {
            youtubeMessage = "Primero conecta Apple Controller con la PC."
            return
        }
        do {
            _ = try await api("input", payload: ["action": "youtube_open"], token: authToken)
            youtubeActive = true
            youtubeMessage = "YouTube abierto. Usa el trackpad para elegir un video."
        } catch {
            youtubeActive = false
            youtubeMessage = Self.explanation(error)
        }
    }

    func searchYouTube(_ query: String) async {
        guard connected, youtubeActive, let authToken else {
            youtubeMessage = "Abre YouTube en la PC primero."
            return
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 120 else {
            youtubeMessage = "Escribe dos letras o más."
            return
        }
        do {
            _ = try await api("input", payload: [
                "action": "youtube_search", "text": query
            ], token: authToken)
            youtubeMessage = "Resultados abiertos en YouTube de Windows."
        } catch {
            youtubeMessage = Self.explanation(error)
        }
    }

    func closeYouTube() {
        guard youtubeActive else { return }
        youtubeActive = false
        send("youtube_close")
    }

    func searchCatalog(_ value: String) {
        searchTask?.cancel()
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        searchItems = []
        searchMessage = "Buscando en Xuper TV..."
        guard connected, let authToken else {
            searchMessage = "Conecta el iPhone a Xuper TV primero."
            searching = false
            return
        }
        guard query.count >= 2, query.count <= 120 else {
            searchMessage = "Escribe al menos dos letras."
            searching = false
            return
        }
        searching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.api("catalog/search",
                                               payload: ["query": query], token: authToken)
                let start = try JSONDecoder().decode(SearchStart.self, from: data)
                self.searchGeneration = start.generation
                for _ in 0..<165 {
                    try Task.checkCancellation()
                    let response = try await self.api("catalog/results",
                        payload: ["generation": start.generation], token: authToken)
                    let result = try JSONDecoder().decode(SearchSnapshot.self, from: response)
                    guard result.generation == start.generation else { throw RemoteError.expired }
                    if result.state == "ready" {
                        self.searchItems = result.items
                        self.searchMessage = result.items.isEmpty ? "No encontramos resultados." :
                            "\(result.items.count) resultados encontrados."
                        self.searching = false
                        return
                    }
                    if result.state == "error" || result.state == "expired" {
                        self.searchMessage = result.message
                        self.searching = false
                        return
                    }
                    try await Task.sleep(nanoseconds: 800_000_000)
                }
                self.searchMessage = "El servidor tardó demasiado en buscar."
            } catch is CancellationError {
                return
            } catch {
                self.searchMessage = Self.explanation(error)
            }
            self.searching = false
        }
    }

    func openSearchItem(_ item: RemoteSearchItem) async -> Bool {
        guard connected, let authToken, searchGeneration > 0 else { return false }
        do {
            _ = try await api("catalog/open",
                payload: ["generation": searchGeneration, "index": item.index],
                token: authToken)
            message = "Abriendo \(item.title) en la televisión."
            return true
        } catch {
            searchMessage = Self.explanation(error)
            return false
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searching = false
    }

    private func beginHeartbeat() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled, let self, self.connected else { return }
                self.send("ping")
            }
        }
    }

    private static func explanation(_ error: Error) -> String {
        switch error {
        case RemoteError.invalidAddress: return "IP inválida. Revisa la dirección de Windows."
        case RemoteError.badPIN: return "PIN incorrecto. Revísalo en la TV."
        case RemoteError.expired: return "La conexión caducó. Vuelve a emparejar el iPhone."
        case RemoteError.tooManyAttempts: return "Demasiados intentos. Prueba en un minuto."
        case RemoteError.serverMessage(let text): return text
        default: return "No responde la PC. Revisa Wi-Fi, IP y el firewall de Windows."
        }
    }

    private struct PairResult: Decodable { let token: String }
    private enum RemoteError: Error {
        case invalidAddress, unavailable, badPIN, expired, tooManyAttempts
        case serverMessage(String)
    }
}
