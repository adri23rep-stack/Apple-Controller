import SwiftUI

@main
struct HydraIOSApp: App {
    var body: some Scene {
        WindowGroup {
            HydraBootDiagnostic()
        }
    }
}

/// No data files, network, web views or portal objects are created
/// until the user taps the catalog button. The initial screen isolates
/// iOS installation/signing and SwiftUI startup from catalog failures.
private struct HydraBootDiagnostic: View {
    @State private var openCatalog = false

    var body: some View {
        Group {
            if openCatalog {
                HydraRootView()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Hydra LG · Diagnóstico")
                        .font(.title2.bold())
                    Text("Pantalla de arranque 0.4")
                        .font(.headline)
                    Text("Si puedes ver esta pantalla, iOS abrió la app. No se ha cargado ni consultado el catálogo todavía.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button {
                        openCatalog = true
                    } label: {
                        Label("Abrir catálogo Hydra LG", systemImage: "square.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("El catálogo usa el archivo original del port webOS. La PC no es necesaria.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(26)
                .frame(maxWidth: 550)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
