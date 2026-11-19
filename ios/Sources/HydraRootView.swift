import SwiftUI
import WebKit

/// Port experimental de la interfaz LG. Catálogo y peticiones exclusivas del código Hydra.
struct HydraRootView: View {
    @AppStorage("hydra.catalog.live") private var liveCatalog = true
    @State private var showSettings = false
    @State private var reload = UUID()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HydraWebView(liveCatalog: liveCatalog)
                .id("\(reload)-\(liveCatalog)")
                .ignoresSafeArea()
            VStack {
                HStack(spacing: 10) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .padding(11)
                            .background(.black.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel("Opciones del catálogo Hydra")
                    Spacer()
                    Button {
                        reload = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .padding(11)
                            .background(.black.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel("Recargar catálogo")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section("Fuente del catálogo") {
                        Toggle("Actualizar desde el portal Hydra", isOn: $liveCatalog)
                        Text(liveCatalog
                            ? "Se muestra el catálogo incluido en el port LG y se intenta actualizar directamente desde iPhone. No usa Nova ni tu PC."
                            : "Solo se muestra el catálogo incluido en el repositorio LG, sin conexión al portal.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Limitaciones de esta prueba") {
                        Text("El portal puede rechazar la activación o una petición. No se eluden verificaciones ni se usan sesiones compartidas. La reproducción de películas, series y TV en vivo sigue pendiente de adaptar a iOS.")
                            .font(.footnote)
                        Text("Catálogo base del proyecto Hydra LG: 27 de octubre de 2026.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Hydra iOS Test")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cerrar") {
                            showSettings = false
                            reload = UUID()
                        }
                    }
                }
            }
        }
    }
}

/// Puente WKWebView -> cliente Swift de Hydra. Ninguna llamada pasa por un equipo externo.
final class HydraMessageHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let client = HydraPortalClient()
    let liveCatalog: Bool

    init(liveCatalog: Bool) {
        self.liveCatalog = liveCatalog
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let method = body["method"] as? String else { return }
        let args = body["parameters"] as? [String: Any] ?? [:]
        Task {
            do {
                guard liveCatalog else {
                    throw HydraPortalClient.Failure(reason: "Modo catálogo guardado. Activa actualización en Ajustes.")
                }
                let result = try await client.execute(method, parameters: args)
                deliver(id: id, error: nil, payload: result)
            } catch {
                deliver(id: id, error: error.localizedDescription, payload: nil)
            }
        }
    }

    private func deliver(id: Int, error: String?, payload: [String: Any]?) {
        var script = ""
        if let payload,
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            script = "window.__hydraNativeResponse(\(id),null,\(json));"
        } else {
            let data = (try? JSONSerialization.data(withJSONObject: error ?? "Error desconocido",
                                                    options: .fragmentsAllowed)) ?? Data("\"Error\"".utf8)
            let json = String(data: data, encoding: .utf8) ?? "\"Error\""
            script = "window.__hydraNativeResponse(\(id),\(json),null);"
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

private struct HydraWebView: UIViewRepresentable {
    let liveCatalog: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        let script = """
        window.__hydraReq = 0;
        window.__hydraPending = {};
        window.__hydraNativeCall = function(method, parameters, callback) {
          var id = ++window.__hydraReq;
          window.__hydraPending[id] = callback;
          window.webkit.messageHandlers.hydra.postMessage({
            id:id, method:method, parameters:parameters||{}
          });
          return true;
        };
        window.__hydraNativeResponse = function(id,error,result) {
          var callback = window.__hydraPending[id];
          delete window.__hydraPending[id];
          if(callback) callback(error,result);
        };
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                             forMainFrameOnly: true))
        let handler = HydraMessageHandler(liveCatalog: liveCatalog)
        controller.add(handler, name: "hydra")
        config.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: config)
        handler.webView = view
        view.backgroundColor = .black
        view.isOpaque = false
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { view.isInspectable = true }
        #endif
        if let html = Bundle.main.url(forResource: "index", withExtension: "html",
                                      subdirectory: "Resources"),
           let folder = Bundle.main.url(forResource: "Resources", withExtension: nil) {
            view.loadFileURL(html, allowingReadAccessTo: folder)
        } else {
            view.loadHTMLString("<h2>Faltan archivos de Hydra LG.</h2>", baseURL: nil)
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
