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
    let provider: String?
    let description: String
    let image: String
    var id: Int { index }
    var imageURL: URL? {
        guard image.hasPrefix("https://") else { return nil }
        return URL(string: image)
    }
    var opensFolder: Bool {
        kind == "folder" || kind == "providers" ||
        kind == "platform" || kind == "movies" || kind == "series"
    }
    var kindLabel: String {
        switch kind {
        case "tv": return "EN VIVO"
        case "movies": return "PELÍCULA"
        case "series": return "SERIE"
        case "episode": return "EPISODIO"
        case "providers": return "PLATAFORMAS"
        case "platform": return "CATÁLOGO"
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
private struct PrivateVideoSource: Decodable { let ok: Bool; let url: String; let mode: String }
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
    @Published private(set) var privateItems: [RemoteBrowseItem] = []
    @Published private(set) var privateTitle = "Biblioteca privada"
    @Published private(set) var privateMessage = "Contenido disponible en la PC."
    @Published private(set) var privateLoading = false
    @Published private(set) var privateTotal = 0
    @Published private(set) var privateDepth = 0
    @Published private(set) var privatePlaybackURL: URL?
    @Published private(set) var privatePlaybackTitle = ""
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
    private var privateGeneration = 0
    private var privateWork: Task<Void, Never>?
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
            } catch {
                if case RemoteError.expired = error {
                    // Only an explicit server rejection means the saved
                    // credential is obsolete. A Wi-Fi outage never deletes it.
                    KeychainStore.delete(for: host)
                } else {
                    connected = false
                    message = "PC recordada. No responde por Wi-Fi; vuelve a intentarlo cuando esté encendida."
                    return
                }
            }
        }
        guard pin.count == 6, pin.allSatisfy({ $0.isNumber }) else {
            message = "Escribe el PIN de 6 dígitos que aparece en tu TV."
            return
        }
        do {
            let data = try await api("pair", payload: ["pin": pin])
            let result = try JSONDecoder().decode(PairResult.self, from: data)
            guard result.token.count == 64 else { throw RemoteError.unavailable }
            let saved = KeychainStore.store(result.token, for: host)
            authToken = result.token
            connected = true
            pin = ""
            message = saved ?
                "¡Vinculado y recordado! No necesitarás el PIN después de actualizar." :
                "Conectado, pero iOS no pudo guardar la vinculación. Revisa los permisos del teléfono."
            beginHeartbeat()
        } catch {
            connected = false
            message = Self.explanation(error)
        }
    }

    func pairFromQRCode(_ scanned: String) async {
        guard let code = URLComponents(string: scanned),
              code.scheme?.lowercased() == "xuperremote",
              code.host?.lowercased() == "pair",
              code.path.isEmpty,
              let fields = code.queryItems,
              fields.count == 2,
              let address = fields.first(where: { $0.name == "host" })?.value,
              let codePIN = fields.first(where: { $0.name == "pin" })?.value,
              validHost(address),
              codePIN.count == 6,
              codePIN.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            message = "Ese QR no pertenece a XuperTV o tiene datos inválidos."
            return
        }
        host = address
        pin = codePIN
        await connect()
    }

    func forgetThisPC() {
        // Local opt-out only: it does not revoke other devices on the PC.
        let current = host
        changePC()
        KeychainStore.delete(for: current)
        UserDefaults.standard.removeObject(forKey: "xuperHost")
        host = ""
        pin = ""
        message = "Se quitó la PC de este iPhone. Escanea el QR si quieres volver a vincular."
    }

    func restore() async {
        guard !host.isEmpty, KeychainStore.load(for: host) != nil else { return }
        await connect()
    }

    func changePC() {
        privateWork?.cancel()
        privateItems = []
        privatePlaybackURL = nil
        privateGeneration = 0
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
    func startFullCatalog(provider: String? = nil) {
        browseWork?.cancel()
        browseWork = Task {
            browseLoading = true
            browseItems = []
            browseTotal = 0
            browseDepth = 0
            browseMessage = provider == nil ?
                "Cargando categorías..." : "Buscando la sección de XuperTV..."
            do {
                let parameters: [String: Any] = provider.map { ["provider": $0] } ?? [:]
                let data = try await api("catalog/browse/start",
                                         payload: parameters, token: authToken)
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

    // MARK: Experimental private iPhone playback
    // This uses a separate PC catalogue so tapping a title NEVER launches
    // the TV output. The local hidden PIN gate is implemented in SwiftUI.
    func openPrivateLibrary() {
        privateWork?.cancel()
        privateWork = Task {
            privateLoading = true
            privatePlaybackURL = nil
            privateItems = []
            privateDepth = 0
            privateTotal = 0
            privateMessage = "Buscando videos compatibles con iPhone..."
            guard connected else {
                privateMessage = "Primero vincula este iPhone con XuperTV."
                privateLoading = false
                return
            }
            do {
                let data = try await api("mobile/catalog/start", payload: [:], token: authToken)
                let response = try JSONDecoder().decode(BrowseStep.self, from: data)
                privateGeneration = response.generation
                await loadPrivatePage(offset: 0)
            } catch is CancellationError {
                privateLoading = false
            } catch {
                privateMessage = Self.explanation(error)
                privateLoading = false
            }
        }
    }

    private func loadPrivatePage(offset: Int) async {
        let generation = privateGeneration
        privateLoading = true
        do {
            for _ in 0..<65 {
                try Task.checkCancellation()
                let data = try await api("mobile/catalog/results", payload: [
                    "generation": generation, "offset": offset, "limit": 48
                ], token: authToken)
                let page = try JSONDecoder().decode(BrowsePage.self, from: data)
                guard page.generation == generation else {
                    privateMessage = "El catálogo cambió. Vuelve a abrirlo."
                    privateLoading = false
                    return
                }
                if page.state == "loading" {
                    privateMessage = page.message
                    try await Task.sleep(nanoseconds: 550_000_000)
                    continue
                }
                guard page.state == "ready" else {
                    privateMessage = page.message
                    privateLoading = false
                    return
                }
                privateTitle = page.title
                privateTotal = page.total
                if offset == 0 { privateItems = page.items }
                else { privateItems.append(contentsOf: page.items) }
                privateMessage = page.message
                privateLoading = false
                return
            }
            privateMessage = "El catálogo tardó demasiado. Inténtalo nuevamente."
        } catch is CancellationError {
            privateLoading = false
            return
        } catch {
            privateMessage = Self.explanation(error)
        }
        privateLoading = false
    }

    func privateLoadMore() {
        guard !privateLoading, privateItems.count < privateTotal else { return }
        privateWork?.cancel()
        privateWork = Task { await loadPrivatePage(offset: privateItems.count) }
    }

    func privateSelect(_ item: RemoteBrowseItem) {
        guard !privateLoading else { return }
        privateWork?.cancel()
        privateWork = Task {
            privateLoading = true
            do {
                let data = try await api("mobile/catalog/select", payload: [
                    "generation": privateGeneration, "index": item.index
                ], token: authToken)
                let step = try JSONDecoder().decode(BrowseStep.self, from: data)
                if step.state == "playable" {
                    privateMessage = "Preparando video para iPhone..."
                    let resolved = try await api("mobile/source", payload: [
                        "generation": privateGeneration, "index": item.index
                    ], token: authToken)
                    let playback = try JSONDecoder().decode(PrivateVideoSource.self, from: resolved)
                    guard let url = URL(string: playback.url),
                          url.scheme?.lowercased() == "https",
                          url.host != nil else {
                        privateMessage = "El video no tiene un enlace compatible con iPhone."
                        privateLoading = false
                        return
                    }
                    privatePlaybackTitle = item.title
                    privatePlaybackURL = url
                    privateMessage = "Reproduciendo en este iPhone."
                    privateLoading = false
                } else {
                    privateGeneration = step.generation
                    privateDepth += 1
                    privateItems = []
                    privateTotal = 0
                    await loadPrivatePage(offset: 0)
                }
            } catch is CancellationError {
                privateLoading = false
            } catch {
                privateMessage = Self.explanation(error)
                privateLoading = false
            }
        }
    }

    func privateBack() {
        guard !privateLoading, privateDepth > 0 else { return }
        privateWork?.cancel()
        privateWork = Task {
            privateLoading = true
            do {
                let data = try await api("mobile/catalog/back", payload: [
                    "generation": privateGeneration
                ], token: authToken)
                let next = try JSONDecoder().decode(BrowseStep.self, from: data)
                privateGeneration = next.generation
                privateDepth -= 1
                await loadPrivatePage(offset: 0)
            } catch is CancellationError {
                privateLoading = false
            } catch {
                privateMessage = Self.explanation(error)
                privateLoading = false
            }
        }
    }

    func stopPrivatePlayback() {
        privatePlaybackURL = nil
        privatePlaybackTitle = ""
    }

    func closePrivateLibrary() {
        privateWork?.cancel()
        privatePlaybackURL = nil
        privateItems = []
        privateGeneration = 0
        privateLoading = false
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
