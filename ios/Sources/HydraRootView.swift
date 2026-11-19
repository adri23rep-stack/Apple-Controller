import SwiftUI
import WebKit

struct HydraRootView: View {
    @AppStorage("hydra.test.mode") private var storedMode = ""
    @AppStorage("hydra.test.url") private var storedURL = "http://192.168.1.10:8910"
    @State private var editingURL = ""
    @State private var settingsOpen = false
    @State private var refreshID = UUID()

    private var lanURL: String? {
        guard let url = URL(string: storedURL), url.scheme == "http", url.port == 8910,
              let host = url.host, isPrivateAddress(host),
              url.user == nil, url.password == nil else { return nil }
        return "http://\(host):8910"
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if (storedMode == "offline" || (storedMode == "lan" && lanURL != nil)) && !settingsOpen {
                HydraWebView(serviceURL: storedMode == "lan" ? lanURL : nil)
                    .id("\(storedMode)-\(storedURL)-\(refreshID)")
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Button { editingURL = storedURL; settingsOpen = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .medium))
                                .padding(9)
                                .background(.black.opacity(0.6), in: Circle())
                        }
                        .accessibilityLabel("Configurar servicio")
                        Spacer()
                        Button { refreshID = UUID() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .padding(9)
                                .background(.black.opacity(0.6), in: Circle())
                        }
                        .accessibilityLabel("Recargar catálogo")
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            } else {
                setupView
            }
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Hydra para iOS · Prueba").font(.title2.bold())
                Text("Interfaz original de LG. El catálogo guardado funciona sin PC; los datos en vivo necesitan el servicio Node de prueba en tu misma red Wi-Fi.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Abrir catálogo guardado") {
                    storedMode = "offline"
                    settingsOpen = false
                }.buttonStyle(.borderedProminent)
                Divider()
                Text("Servicio en tu PC (red local)").font(.headline)
                TextField("http://192.168.1.10:8910", text: $editingURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                Button("Conectar al catálogo en vivo") {
                    storedURL = editingURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lanURL != nil { storedMode = "lan"; settingsOpen = false }
                }.buttonStyle(.borderedProminent)
                if !editingURL.isEmpty && !isValidURL(editingURL) {
                    Text("Usa la IPv4 privada de tu PC y el puerto 8910, ejemplo: http://192.168.1.10:8910")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Comprueba la conexión abriendo esa dirección seguida de /ping en Safari.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .onAppear { editingURL = storedURL }
    }

    private func isValidURL(_ address: String) -> Bool {
        guard let u = URL(string: address), u.scheme == "http", u.port == 8910,
              let host = u.host, u.user == nil, u.password == nil else { return false }
        return isPrivateAddress(host)
    }
    private func isPrivateAddress(_ host: String) -> Bool {
        let bytes = host.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            bytes[0] == 127
    }
}

private struct HydraWebView: UIViewRepresentable {
    let serviceURL: String?

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let configData: [String: Any] = ["offline": serviceURL == nil, "serviceUrl": serviceURL ?? ""]
        let data = try! JSONSerialization.data(withJSONObject: configData)
        let encoded = String(data: data, encoding: .utf8)!
        controller.addUserScript(WKUserScript(
            source: "window.__HYDRA_IOS__ = \(encoded);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Resources"),
           let folder = Bundle.main.url(forResource: "Resources", withExtension: nil) {
            webView.loadFileURL(index, allowingReadAccessTo: folder)
        } else {
            webView.loadHTMLString("<h2>Faltan los recursos del port.</h2>", baseURL: nil)
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
