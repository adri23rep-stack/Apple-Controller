import Foundation
import Combine

@MainActor
final class RemoteClient: ObservableObject {
    @Published var host: String = UserDefaults.standard.string(forKey: "xuperHost") ?? ""
    @Published var pin: String = ""
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published var message = "Conecta tu iPhone a la misma red Wi-Fi que tu PC."
    @Published var volume = 100.0
    @Published var brightness = 50.0

    private let port = 47831
    private let session: URLSession
    private var authToken: String?
    private var queue: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

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
        pingTask?.cancel()
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
                self.message = Self.explanation(error)
                if case RemoteError.expired = error {
                    self.connected = false
                    self.pingTask?.cancel()
                }
            }
        }
    }

    func search(_ query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        send("search")
        // All three network requests are queued in order.
        send("text", text: String(cleaned.prefix(75)))
        send("ok")
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
        default: return "No responde la PC. Revisa Wi-Fi, IP y el firewall de Windows."
        }
    }

    private struct PairResult: Decodable { let token: String }
    private enum RemoteError: Error {
        case invalidAddress, unavailable, badPIN, expired, tooManyAttempts
    }
}
