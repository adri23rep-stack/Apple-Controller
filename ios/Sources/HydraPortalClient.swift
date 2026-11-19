import Foundation
import CommonCrypto
import CryptoKit

/// Consulta el portal que está descrito en el código original de Hydra LG.
 /// No importa sesiones de XuperTV, no usa servidores de Nova y no reutiliza semillas compartidas.
actor HydraPortalClient {
    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    // Los hosts y parámetros corresponden al port webOS suministrado.
    private let hosts = [
        "mptec.dhkrxuzcy.com", "ftmrmy.jdfey0cd.com",
        "fuxok.nguvmqhpk.com", "eajmnp.hcgv1dt8.com",
        "hinumz.a878kkoyc.com", "krdwvd.swcaw7qx.com",
        "osuhk.m3x8o50te.com", "oogoy.f30c96w8.com"
    ]
    private let portalCode = "masnew"
    private let appID = "com.android.msandroid"
    private let apkVersion = "49902"
    private let sysVersion = "2024-09-10 06:25:30_33_13_"
    private let fixedReserve = "583442714b345572434a4d5769637461545a735936413d3d"
    private let drmId = "0iSGEyv2EqiS/nqI/I3hqdu12irw5Q3/uqrWvRFx9bM="
    private let salt = "ntFT65w6itH!lHCPw7D=@qnsFC5adD28"
    private let keyHex = "e7af1ed7de1ffddd7bd3fe37ebdffde9ef3fe1ae39edfeb8"

    private var userID = ""
    private var userToken = ""
    private var serial = ""
    private var activationDate: Date?
    private var preferredHost: String?
    private var knownKinds: [String: String] = [:]

    private let roots: [String: String] = [
        "featured": "masnew_featured", "movies": "masnew_movies",
        "series": "masnew_series", "anime": "masnew_anime",
        "kids": "masnew_kids", "free": "masnew_free"
    ]
    private let categories: [String: String] = [
        "featured": "destacado", "movies": "pelicula", "series": "serie",
        "anime": "anime", "kids": "infantil", "free": "gratis"
    ]

    func execute(_ method: String, parameters p: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "prewarm":
            try await ensureSession()
            return ["returnValue": true]
        case "home":
            let root = str(p["root"]).isEmpty ? "movies" : str(p["root"])
            let raw = try await call("getNextColumns", [
                "columnCode": roots[root] ?? roots["movies"]!,
                "pageNum": Int(str(p["pageNum"])) ?? 1,
                "pageSize": 60,
                "version": ""
            ])
            var items: [[String: Any]] = []
            for group in dicts(raw["recommendList"]) {
                let row = str(group["name"])
                for asset in dicts(group["assetList"]) {
                    if let mapped = mapAsset(asset, category: categories[root] ?? "", row: row) {
                        items.append(mapped)
                    }
                }
            }
            return ["returnValue": true, "root": root, "items": items, "cached": false]
        case "search":
            let query = str(p["value"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty { return ["returnValue": true, "items": []] }
            let raw = try await call("v3/searchByName", [
                "value": query, "type": "1", "columnId": "", "filter": "",
                "pageNum": Int(str(p["pageNum"])) ?? 1, "pageSize": 50
            ])
            var items: [[String: Any]] = []
            var seen = Set<String>()
            for group in dicts(raw["searchItemList"]) {
                for asset in dicts(group["itemList"]) {
                    if let item = mapAsset(asset, category: "", row: ""),
                       let id = item["id"] as? String, seen.insert(id).inserted {
                        items.append(item)
                    }
                }
            }
            return ["returnValue": true, "items": items, "total": raw["totalSize"] ?? items.count]
        case "detail":
            let id = str(p["contentId"])
            guard !id.isEmpty else { throw Failure(reason: "Falta el ID del título") }
            let firstType = knownKinds[id] == "serie" ? "0" : "1"
            var raw: [String: Any] = [:]
            var found = false
            for type in [firstType, firstType == "0" ? "1" : "0"] {
                if let response = try? await call("v4/getItemData", [
                    "contentId": id, "type": type, "sortType": "0",
                    "language": "en", "macAddr": "02:00:00:00:00:00"
                ]), dict(response["assetData"]) != nil {
                    raw = response
                    found = true
                    break
                }
            }
            guard found, let asset = dict(raw["assetData"]) else {
                throw Failure(reason: "El portal no entregó los detalles de este título")
            }
            let item = mapAsset(asset, category: "", row: "") ?? ["id": id, "portal": true]
            let episodes: [[String: Any]] = dicts(asset["simpleProgramList"]).enumerated().map { index, ep in
                ["id": str(ep["contentId"]), "title": str(ep["name"]),
                 "name": str(ep["name"]), "number": ep["seriesNumber"] ?? index + 1,
                 "duration": str(ep["duration"]), "quality": str(ep["quality"]),
                 "picture": str(ep["picture"] ?? ep["posterUrl"])]
            }
            let seasons: [[String: Any]] = dicts(asset["sameSeasonSeriesList"]).map {
                ["id": str($0["contentId"]), "number": $0["seasonNumber"] ?? 1]
            }
            return ["returnValue": true, "item": item, "episodes": episodes, "seasons": seasons]
        case "liveCategories":
            let raw = try await call("getNextColumns", [
                "columnCode": "masnew_live", "pageNum": 1, "pageSize": 200, "version": ""
            ])
            let list: [[String: Any]] = dicts(raw["recommendList"]).compactMap {
                let id = str($0["columnId"])
                if id.isEmpty { return nil }
                return ["id": id, "name": str($0["name"] ?? $0["title"]), "code": str($0["code"])]
            }
            return ["returnValue": true, "categories": list]
        case "liveChannels":
            let raw = try await call("v6/getLiveData", [
                "columnId": str(p["columnId"]).isEmpty ? 76182 : p["columnId"]!,
                "dataVersion": "", "pageSize": 250,
                "pageNum": Int(str(p["pageNum"])) ?? 1,
                "expireTimeStr": ""
            ])
            let channels: [[String: Any]] = dicts(raw["channelList"]).enumerated().map { i, c in
                ["channelCode": str(c["channelCode"]), "index": c["channelNumber"] ?? i+1,
                 "name": str(c["name"] ?? c["alias"]),
                 "logo": str(c["posterUrl"] ?? dicts(c["posterList"]).first?["fileUrl"]),
                 "uhd": str(c["quality"]) == "3", "fav": false,
                 "now": "En vivo", "next": "", "time": "",
                 "liveAddressList": c["liveAddressList"] ?? []]
            }
            return ["returnValue": true, "channels": channels]
        case "liveLog", "abortMedia":
            return ["returnValue": true]
        case "resolve", "resolveSmooth", "resolveLive", "mediaInfo":
            throw Failure(reason: "Catálogo Hydra cargado. Esta versión aún no tiene el proxy/licencias de reproducción adaptados a iOS.")
        case "fetchM3u":
            throw Failure(reason: "Las listas M3U externas aún no están adaptadas a iOS")
        default:
            throw Failure(reason: "Función del port LG todavía no disponible en iOS: \(method)")
        }
    }

    private func ensureSession() async throws {
        if !userToken.isEmpty, let at = activationDate,
           Date().timeIntervalSince(at) < 60 * 60 * 6 { return }
        userID = ""
        userToken = ""
        serial = ""

        var fingerprint: [String: Any] = [
            "board": "goldfish_arm64", "brand": "google", "cpuAbi": "arm64-v8a",
            "device": "emu64a", "diskInfo": "8GB", "display": "sdk_gphone64_arm64",
            "fingerprint": "google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.036/11228894:user/release-keys",
            "hardware": "ranchu", "host": "abfarm", "manufacturer": "Google",
            "ramSize": "4GB", "romSize": "8GB", "tags": "release-keys", "verId": ""
        ]
        fingerprint["androidId"] = randomHex(8)
        fingerprint["cpuId"] = randomHex(8)
        fingerprint["serialNumber"] = randomHex(8)
        for k in ["etheMac", "gatewayMac", "wifiMac"] {
            let hex = randomHex(6)
            fingerprint[k] = stride(from: 0, to: hex.count, by: 2).map {
                let start = hex.index(hex.startIndex, offsetBy: $0)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }.joined(separator: ":")
        }
        let r1 = try await post("v3/snToken", fields: deviceFields().merging(fingerprint) { _, new in new })
        let snToken = str(r1["snToken"])
        guard !snToken.isEmpty else { throw Failure(reason: "El portal Hydra no entregó snToken") }
        let suppliedSN = str(r1["sn"])
        serial = suppliedSN.isEmpty ? md5(snToken + salt) : suppliedSN.lowercased()
        let r2 = try await post("v8/active", fields: deviceFields().merging([
            "snToken": snToken, "authVersion": "", "authCode": "", "preCode": "",
            "macAddr": "02:00:00:00:00:00", "reserve1": "", "openNum": 4,
            "channel": "default", "matadata": "", "signdata": ""
        ]) { _, new in new })
        let id = str(r2["userId"])
        let token = str(r2["userToken"])
        guard !id.isEmpty, !token.isEmpty else {
            throw Failure(reason: "El portal rechazó la activación de una sesión nueva en iPhone")
        }
        userID = id
        userToken = token
        activationDate = Date()
    }

    private func call(_ endpoint: String, _ params: [String: Any]) async throws -> [String: Any] {
        try await ensureSession()
        var fields = deviceFields()
        fields["portalCode"] = portalCode
        fields["userId"] = userID
        fields["userToken"] = userToken
        for (key, value) in params { fields[key] = value }
        return try await post(endpoint, fields: fields)
    }

    private func deviceFields() -> [String: Any] {
        ["loginType": "2", "appLanguage": "en",
         "hardwareInfo": "ranchu", "model": "sdk_gphone64_arm64",
         "product": "sdk_gphone64_arm64", "cpu": "arm64-v8a",
         "B29": "", "reserve1": fixedReserve,
         "deviceToken": "", "drmId": drmId, "sdkVer": 33,
         "apkVersion": apkVersion, "sysVersion": sysVersion,
         "appId": appID, "sn": serial]
    }

    private func post(_ path: String, fields: [String: Any]) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: fields, options: [.fragmentsAllowed])
        let cipher = try tripleDES(payload, encrypt: true)
        let body = Data(cipher.base64EncodedString().utf8)
            .map { String(format: "%02x", Int($0)) }.joined()
        var failures: [String] = []
        var order = hosts
        if let preferredHost { order.removeAll { $0 == preferredHost }; order.insert(preferredHost, at: 0) }

        // Se limita el número de intentos para no congelar la pantalla.
        for host in order.prefix(4) {
            guard let url = URL(string: "https://\(host)/api/portalCore/\(path)") else { continue }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
            req.httpMethod = "POST"
            req.setValue(appID, forHTTPHeaderField: "apk")
            req.setValue("43404", forHTTPHeaderField: "apkVer")
            req.setValue(sysVersion, forHTTPHeaderField: "spkgVer")
            req.setValue("okhttp/3.12.12", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw Failure(reason: "Respuesta no válida del portal")
                }
                let code = str(top["returnCode"])
                if !code.isEmpty, code != "0" {
                    throw Failure(reason: "El portal rechazó la petición (código \(code)).")
                }
                preferredHost = host
                if let wrapped = top["data"] as? String, !wrapped.isEmpty {
                    guard let ascii = Data(hexString: wrapped),
                          let b64 = String(data: ascii, encoding: .ascii),
                          let encrypted = Data(base64Encoded: b64) else {
                        throw Failure(reason: "Formato de respuesta del portal no válido")
                    }
                    let plaintext = try tripleDES(encrypted, encrypt: false)
                    guard let dict = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
                        throw Failure(reason: "El portal devolvió datos inesperados")
                    }
                    return dict
                }
                return (top["data"] as? [String: Any]) ?? top
            } catch {
                if let rejected = error as? Failure, rejected.reason.contains("rechazó") {
                    throw rejected // No esquivar rechazos ni controles de acceso.
                }
                failures.append(error.localizedDescription)
            }
        }
        throw Failure(reason: "El portal del port LG no respondió por HTTPS. \(failures.last ?? "Revisa tu conexión")")
    }

    private func tripleDES(_ input: Data, encrypt: Bool) throws -> Data {
        guard let key = Data(hexString: keyHex), key.count == kCCKeySize3DES else {
            throw Failure(reason: "Clave de protocolo incorrecta")
        }
        var output = Data(count: input.count + kCCBlockSize3DES)
        let capacity = output.count
        var outputLength: size_t = 0
        let status = output.withUnsafeMutableBytes { dest in
            key.withUnsafeBytes { keyBytes in
                input.withUnsafeBytes { source in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithm3DES),
                            CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySize3DES,
                            nil, source.baseAddress, input.count,
                            dest.baseAddress, capacity, &outputLength)
                }
            }
        }
        guard status == kCCSuccess else {
            throw Failure(reason: "No se pudo procesar el formato cifrado del portal")
        }
        output.count = outputLength
        return output
    }

    private func mapAsset(_ a: [String: Any], category: String, row: String) -> [String: Any]? {
        let id = str(a["contentId"])
        guard !id.isEmpty else { return nil }
        let isSeries = ["teleplay", "series"].contains(str(a["programType"])) ||
            (Int(str(a["volumnCount"])) ?? 0) > 1
        let kind = isSeries ? "serie" : "película"
        knownKinds[id] = kind
        func image(_ type: String) -> String {
            for entry in dicts(a["posterList"]) where str(entry["fileType"]) == type {
                let path = str(entry["fileUrl"])
                if !path.isEmpty { return path }
            }
            return str(a[type == "stage" ? "backdropUrl" : "posterUrl"] ??
                       a["coverUrl"] ?? a["iconUrl"])
        }
        let release = str(a["releaseTime"] ?? a["releaseDate"])
        return [
            "id": id, "title": str(a["name"] ?? a["title"]),
            "category": category, "kind": kind, "row": row,
            "year": release.isEmpty ? "—" : String(release.prefix(4)),
            "duration": str(a["duration"]), "score": str(a["score"]),
            "genres": str(a["tags"]).split(separator: ",").map(String.init),
            "director": str(a["director"]), "tagline": str(a["viewPoint"]),
            "volumeCount": Int(str(a["volumnCount"] ?? a["volumeCount"])) ?? 0,
            "updateCount": Int(str(a["updateCount"])) ?? 0,
            "poster": image("poster"), "landscape": image("stage"),
            "icon": image("icon"), "portal": true, "streamUrl": ""
        ]
    }

    private func str(_ x: Any?) -> String {
        if let s = x as? String { return s }
        if let n = x as? NSNumber { return n.stringValue }
        return ""
    }
    private func dict(_ x: Any?) -> [String: Any]? { x as? [String: Any] }
    private func dicts(_ x: Any?) -> [[String: Any]] { x as? [[String: Any]] ?? [] }
    private func md5(_ x: String) -> String {
        let hash = Insecure.MD5.hash(data: Data(x.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    private func randomHex(_ count: Int) -> String {
        (0..<count).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data()
        var start = hexString.startIndex
        while start < hexString.endIndex {
            let next = hexString.index(start, offsetBy: 2)
            guard let byte = UInt8(hexString[start..<next], radix: 16) else { return nil }
            data.append(byte)
            start = next
        }
        self = data
    }
}
