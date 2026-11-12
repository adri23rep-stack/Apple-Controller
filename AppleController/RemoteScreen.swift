import SwiftUI
import UIKit

// A single-colour, native SwiftUI remote. Everything sends commands to the
// paired Windows desktop; the fullscreen button never changes iPhone UI.
private enum ClassicTheme {
    static let background = Color(red: 0.055, green: 0.068, blue: 0.096)
    static let panel = Color(red: 0.112, green: 0.137, blue: 0.188)
    static let panelLight = Color(red: 0.148, green: 0.180, blue: 0.237)
    static let accent = Color(red: 0.71, green: 0.65, blue: 1.0)
    static let muted = Color(red: 0.65, green: 0.69, blue: 0.76)
}

// The circular cut-out on each tile is drawn in SwiftUI, not from an image.
private struct NotchedCard: Shape {
    enum Corner { case bottomRight, bottomLeft, topRight, topLeft }
    let corner: Corner

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 19)
        let center: CGPoint
        switch corner {
        case .bottomRight: center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: center = CGPoint(x: rect.minX, y: rect.maxY)
        case .topRight: center = CGPoint(x: rect.maxX, y: rect.minY)
        case .topLeft: center = CGPoint(x: rect.minX, y: rect.minY)
        }
        let radius: CGFloat = 55
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        return path
    }
}

struct RemoteScreen: View {
    @StateObject private var remote = RemoteClient()
    @State private var searchVisible = false
    @State private var settingsVisible = false
    @State private var youtubeVisible = false
    @State private var volumeWork: Task<Void, Never>?
    @State private var brightnessWork: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 9) {
            heading
            if !remote.connected {
                Spacer(minLength: 12)
                pairingCard
                Spacer(minLength: 12)
            } else {
                HStack(spacing: 7) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Conectado a \(remote.host)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ClassicTheme.muted)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 5)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        topActions
                        catalogSection
                        navigationSection
                        smallActionRow
                        VStack(alignment: .leading, spacing: 8) {
                            caption("TRACKPAD")
                            TrackpadView(remote: remote)
                                .frame(height: 172)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClassicTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await remote.restore() }
        .sheet(isPresented: $searchVisible) {
            RemoteCatalogSearchScreen(remote: remote)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $youtubeVisible) {
            YouTubeRemoteScreen(remote: remote)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $settingsVisible) { settingsSheet }
        .onChange(of: remote.volume) { value in
            volumeWork?.cancel()
            volumeWork = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                if !Task.isCancelled { remote.send("volume", value: Int(value)) }
            }
        }
        .onChange(of: remote.brightness) { value in
            brightnessWork?.cancel()
            brightnessWork = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                if !Task.isCancelled { remote.send("brightness", value: Int(value)) }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ClassicTheme.accent)
                .frame(width: 34, height: 34)
                .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("XuperTV").font(.system(size: 23, weight: .bold))
                Text("CONTROL CLÁSICO")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(ClassicTheme.muted)
            }
            Spacer()
            Text(remote.connected ? "CONECTADO" : "SIN CONEXIÓN")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ClassicTheme.muted)
        }
    }

    private var topActions: some View {
        HStack(spacing: 22) {
            topCircle("arrow.up.left.and.arrow.down.right", label: "Pantalla completa") {
                remote.send("fullscreen") // Windows SDL F11 or foreground browser fullscreen
            }
            topCircle("magnifyingglass", label: "Buscar") {
                searchVisible = true
            }
            topCircle("gearshape", label: "Ajustes") {
                settingsVisible = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func topCircle(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 47, height: 47)
                .background(ClassicTheme.panel, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            caption("CATÁLOGOS")
            GeometryReader { geo in
                let width = max(0, (geo.size.width - 12) / 2)
                ZStack {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            catalogTile("YouTube", symbol: "play.rectangle.fill",
                                        corner: .bottomRight, right: false,
                                        width: width) {
                                youtubeVisible = true
                            }
                            catalogTile("Netflix", symbol: "n.circle.fill",
                                        corner: .bottomLeft, right: true,
                                        width: width) {
                                remote.send("netflix_open")
                            }
                        }
                        HStack(spacing: 12) {
                            catalogTile("HBO Max", symbol: "play.tv",
                                        corner: .topRight, right: false,
                                        width: width) {
                                remote.send("hbo_max_open")
                            }
                            catalogTile("Apple TV", symbol: "apple.logo",
                                        corner: .topLeft, right: true,
                                        width: width) {
                                remote.send("apple_tv_open")
                            }
                        }
                    }
                    Button {
                        haptic(.medium)
                        remote.send("tv")
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "tv").font(.system(size: 23))
                            Text("TV").font(.system(size: 19, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 85, height: 85)
                        .background(ClassicTheme.panelLight, in: Circle())
                        .overlay(Circle().strokeBorder(ClassicTheme.accent, lineWidth: 2))
                        .shadow(color: ClassicTheme.background, radius: 0, x: 0, y: 0)
                        .padding(5)
                        .background(ClassicTheme.background, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("TV en vivo")
                }
            }
            .frame(height: 204)
        }
    }

    private func catalogTile(_ title: String, symbol: String,
                             corner: NotchedCard.Corner, right: Bool,
                             width: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            VStack(alignment: right ? .trailing : .leading, spacing: 7) {
                if title == "Netflix" {
                    Text("N")
                        .font(.system(size: 27, weight: .black, design: .serif))
                        .frame(height: 29)
                } else if title == "HBO Max" {
                    Text("max")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .frame(height: 29)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(height: 29)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: right ? .topTrailing : .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .background {
                NotchedCard(corner: corner)
                    .fill(ClassicTheme.panel, style: FillStyle(eoFill: true))
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: 96)
        .accessibilityLabel("Abrir \(title)")
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("NAVEGACIÓN")
            VStack(spacing: 5) {
                navButton("chevron.up", action: "up")
                HStack(spacing: 5) {
                    navButton("chevron.left", action: "left")
                    Button {
                        haptic(.medium)
                        remote.send("ok")
                    } label: {
                        Text("OK")
                            .font(.system(size: 15, weight: .heavy))
                            .frame(width: 57, height: 47)
                            .background(ClassicTheme.panelLight, in: Circle())
                            .overlay(Circle().strokeBorder(ClassicTheme.accent, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Seleccionar")
                    navButton("chevron.right", action: "right")
                }
                navButton("chevron.down", action: "down")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func navButton(_ symbol: String, action: String) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 62, height: 43)
                .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action)
    }

    private var smallActionRow: some View {
        HStack(spacing: 11) {
            miniButton("arrow.uturn.backward", label: "Regresar", action: "back")
            miniButton("house", label: "Inicio", action: "home")
            miniButton("playpause", label: "Reproducir/Pausar", action: "play_pause")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
    }

    private func miniButton(_ icon: String, label: String, action: String) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 39)
                .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Conexión") {
                    LabeledContent("PC vinculada", value: remote.host)
                    Button("Cambiar PC") {
                        remote.changePC()
                        settingsVisible = false
                    }
                }
                Section("Reproducción") {
                    VStack(alignment: .leading) {
                        Text("Volumen · \(Int(remote.volume))%")
                        Slider(value: $remote.volume, in: 0...100, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Brillo del video · \(Int(remote.brightness))%")
                        Slider(value: $remote.brightness, in: 0...100, step: 1)
                    }
                }
                Section {
                    Text("La pantalla completa cambia en Windows, no en el iPhone. El control funciona únicamente dentro de tu red local.")
                        .font(.footnote)
                        .foregroundStyle(ClassicTheme.muted)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { settingsVisible = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.system(size: 35))
                .foregroundStyle(ClassicTheme.accent)
            Text("Conecta tu PC").font(.title2.bold())
            Text("Abre XuperTV en Windows y escribe aquí la IP y el PIN que aparecen en pantalla.")
                .font(.subheadline)
                .foregroundStyle(ClassicTheme.muted)
            TextField("IP: 192.168.1.25", text: $remote.host)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(ClassicTheme.panelLight, in: RoundedRectangle(cornerRadius: 11))
            TextField("PIN de 6 dígitos", text: $remote.pin)
                .keyboardType(.numberPad)
                .padding(12)
                .background(ClassicTheme.panelLight, in: RoundedRectangle(cornerRadius: 11))
            Button {
                Task { await remote.connect() }
            } label: {
                HStack {
                    if remote.connecting { ProgressView().tint(.black) }
                    Text(remote.connecting ? "Conectando…" : "Conectar")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .foregroundStyle(ClassicTheme.background)
                .background(ClassicTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(remote.connecting)
            Text(remote.message)
                .font(.caption)
                .foregroundStyle(ClassicTheme.muted)
        }
        .padding(19)
        .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func caption(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.7)
            .foregroundStyle(ClassicTheme.muted)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
