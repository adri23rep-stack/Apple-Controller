import Foundation
import Combine

// Standalone, opt-in media library. Never calls XuperTV Desktop or its LAN API.
// It plays only direct user-provided HTTPS video streams and M3U playlists.
struct StandaloneMediaEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var url: String
    var image: String
    var source: String

    var artworkURL: URL? {
        guard let url = URL(string: image), url.scheme == "https" else { return nil }
        return url
    }
    var playbackURL: URL? {
        guard let url = URL(string: self.url),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

@MainActor
final class StandaloneMediaLibrary: ObservableObject {
    @Published private(set) var items: [StandaloneMediaEntry] = []
    @Published private(set) var playlistURLs: [String] = []
    @Published private(set) var message = "Esta biblioteca funciona sin PC. Importa una lista M3U o agrega un video HTTPS."
    @Published private(set) var loading = false

    private struct SavedLibrary: Codable {
        var items: [StandaloneMediaEntry]
        var playlistURLs: [String]
    }

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("private-media-library.json")
    }

    init() {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        items = saved.items.filter { $0.playbackURL != nil }.prefix(5000).map { $0 }
        playlistURLs = Array(saved.playlistURLs.prefix(15))
    }

    private func save() {
        let directory = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let snapshot = SavedLibrary(items: items, playlistURLs: playlistURLs)
        if let data = try? JSONEncoder().encode(snapshot) {
            do {
                try data.write(to: file, options: [.atomic, .completeFileProtection])
            } catch {
                message = "No se pudieron guardar los cambios en este iPhone."
            }
        }
    }

    private static func secureURL(_ input: String, base: URL? = nil) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4000,
              !trimmed.contains("\r"), !trimmed.contains("\n"),
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func attribute(_ key: String, in text: String) -> String {
        let needle = key + "=\""
        guard let start = text.range(of: needle) else { return "" }
        let remainder = text[start.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return "" }
        return String(remainder[..<end]).prefix(500).description
    }

    private static func entries(from content: String, source: String,
                                base: URL? = nil) -> [StandaloneMediaEntry] {
        let content = String(content.prefix(4_000_000))
        let lines = content.components(separatedBy: .newlines)
        var items: [StandaloneMediaEntry] = []
        var title = "", category = "Videos", image = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-STREAM-INF") || line.hasPrefix("#EXT-X-TARGETDURATION") {
                // A real HLS manifest is a single video, not an IPTV directory.
                return []
            }
            if line.hasPrefix("#EXTINF:") {
                let separator = line.firstIndex(of: ",")
                title = separator.map { String(line[line.index(after: $0)...]) } ?? ""
                category = attribute("group-title", in: line)
                if category.isEmpty { category = "Videos" }
                image = attribute("tvg-logo", in: line)
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let link = secureURL(line, base: base) else { continue }
            let name = title.isEmpty ? (link.lastPathComponent.isEmpty ?
                             "Video \(items.count + 1)" : link.lastPathComponent) : title
            items.append(StandaloneMediaEntry(
                title: String(name.prefix(180)),
                category: String(category.prefix(90)),
                url: link.absoluteString,
                image: image, source: source))
            title = ""; category = "Videos"; image = ""
            if items.count >= 5000 { break }
        }
        return items
    }

    func addVideo(title: String, url input: String) -> Bool {
        guard let url = Self.secureURL(input) else {
            message = "Usa un enlace HTTPS directo a un video MP4 o emisión HLS (m3u8)."
            return false
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.insert(StandaloneMediaEntry(
            title: name.isEmpty ? "Video directo" : String(name.prefix(180)),
            category: "Videos directos", url: url.absoluteString,
            image: "", source: "Manual"), at: 0)
        if items.count > 5000 { items = Array(items.prefix(5000)) }
        save()
        message = "Video guardado. Se reproduce directamente en este iPhone."
        return true
    }

    @discardableResult
    func importPlaylist(data: Data, name: String) -> Int {
        guard data.count <= 4_000_000, let content = String(data: data, encoding: .utf8) else {
            message = "La lista debe ser M3U de texto UTF-8 y menor de 4 MB."
            return 0
        }
        let source = "Archivo: " + String(name.prefix(100))
        let parsed = Self.entries(from: content, source: source)
        guard !parsed.isEmpty else {
            message = "No encontré enlaces HTTPS compatibles en esa lista M3U."
            return 0
        }
        items.removeAll { $0.source == source }
        items = Array((items + parsed).prefix(5000))
        save()
        message = "\(parsed.count) títulos importados en el iPhone."
        return parsed.count
    }

    func addPlaylist(_ input: String) async -> Bool {
        guard let url = Self.secureURL(input) else {
            message = "La lista necesita un enlace HTTPS válido."
            return false
        }
        loading = true
        defer { loading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 18
            request.setValue("text/plain, application/vnd.apple.mpegurl, */*",
                             forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                message = "El servidor no devolvió una respuesta HTTP."
                return false
            }
            guard http.statusCode == 200 else {
                message = "La lista respondió HTTP \(http.statusCode). Revisa el enlace."
                return false
            }
            guard data.count <= 4_000_000, let text = String(data: data, encoding: .utf8) else {
                message = "La lista no es texto M3U válido o supera 4 MB."
                return false
            }
            let parsed = Self.entries(from: text, source: url.absoluteString, base: url)
            guard !parsed.isEmpty else {
                message = "No encontré videos HTTPS en esa lista. Un manifiesto HLS va en «Video directo»."
                return false
            }
            items.removeAll { $0.source == url.absoluteString }
            items = Array((items + parsed).prefix(5000))
            if !playlistURLs.contains(url.absoluteString) {
                playlistURLs.append(url.absoluteString)
            }
            save()
            message = "\(parsed.count) títulos cargados directamente desde Internet."
            return true
        } catch {
            message = "No pude descargar la lista. Revisa la conexión o el enlace."
            return false
        }
    }

    func refresh() async {
        for url in playlistURLs {
            if Task.isCancelled { return }
            _ = await addPlaylist(url)
        }
    }

    func delete(_ entry: StandaloneMediaEntry) {
        items.removeAll { $0.id == entry.id }
        save()
    }

    func removeAll() {
        items = []; playlistURLs = []
        save()
        message = "Biblioteca privada vacía."
    }
}
