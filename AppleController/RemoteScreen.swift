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
    @State private var catalogVisible = false
    @State private var settingsVisible = false
    @State private var youtubeVisible = false

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

                // One fixed screen: no ScrollView competing with the UIKit
                // trackpad. Action keys live BESIDE the D-pad so Back/Home/
                // Play-Pause remain visible without dragging the page.
                GeometryReader { area in
                    let compact = area.size.height < 635
                    let trackpadHeight: CGFloat = max(100, min(156,
                        area.size.height - (compact ? 447 : 476)))

                    VStack(spacing: compact ? 7 : 9) {
                        topActions
                        catalogSection(compact: compact)
                        navigationSection

                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                            caption("TRACKPAD")
                            TrackpadView(remote: remote)
                                .frame(height: trackpadHeight)
                                .accessibilityHint("Área fija: no desplaza el control")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .top)
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
        .sheet(isPresented: $catalogVisible) {
            RemoteFullCatalogScreen(remote: remote)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $youtubeVisible) {
            YouTubeRemoteScreen(remote: remote)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $settingsVisible) {
            DesktopSettingsScreen(remote: remote) {
                remote.changePC()
                settingsVisible = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        HStack(spacing: 14) {
            topCircle("arrow.up.left.and.arrow.down.right", label: "Pantalla completa") {
                remote.send("fullscreen") // Windows SDL F11 or foreground browser fullscreen
            }
            topCircle("square.grid.2x2.fill", label: "Catálogo completo") {
                catalogVisible = true
            }
            topCircle("magnifyingglass", label: "Buscar") {
                searchVisible = true
            }
            topCircle("gearshape", label: "Ajustes") {
                settingsVisible = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
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

    private func catalogSection(compact: Bool) -> some View {
        let tileHeight: CGFloat = compact ? 75 : 88
        let tileGap: CGFloat = compact ? 8 : 10
        let gridHeight = tileHeight * 2 + tileGap

        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            caption("CATÁLOGOS")
            GeometryReader { geo in
                let width = max(0, (geo.size.width - tileGap) / 2)
                ZStack {
                    VStack(spacing: tileGap) {
                        HStack(spacing: tileGap) {
                            catalogTile("YouTube", symbol: "play.rectangle.fill",
                                        corner: .bottomRight, right: false,
                                        width: width, height: tileHeight) {
                                youtubeVisible = true
                            }
                            catalogTile("Netflix", symbol: "n.circle.fill",
                                        corner: .bottomLeft, right: true,
                                        width: width, height: tileHeight) {
                                remote.send("netflix_open")
                            }
                        }
                        HStack(spacing: tileGap) {
                            catalogTile("HBO Max", symbol: "play.tv",
                                        corner: .topRight, right: false,
                                        width: width, height: tileHeight) {
                                remote.send("hbo_max_open")
                            }
                            catalogTile("Apple TV", symbol: "apple.logo",
                                        corner: .topLeft, right: true,
                                        width: width, height: tileHeight) {
                                remote.send("apple_tv_open")
                            }
                        }
                    }
                    Button {
                        haptic(.medium)
                        remote.send("tv")
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "tv")
                                .font(.system(size: compact ? 19 : 23))
                            Text("TV")
                                .font(.system(size: compact ? 16 : 19, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: compact ? 71 : 82,
                               height: compact ? 71 : 82)
                        .background(ClassicTheme.panelLight, in: Circle())
                        .overlay(Circle().strokeBorder(ClassicTheme.accent, lineWidth: 2))
                        .padding(5)
                        .background(ClassicTheme.background, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("TV en vivo")
                }
            }
            .frame(height: gridHeight)
        }
    }

    private func catalogTile(_ title: String, symbol: String,
                             corner: NotchedCard.Corner, right: Bool,
                             width: CGFloat, height: CGFloat,
                             action: @escaping () -> Void) -> some View {
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
        .frame(width: width, height: height)
        .accessibilityLabel("Abrir \(title)")
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            caption("NAVEGACIÓN")
            GeometryReader { geo in
                let tight = geo.size.width < 320

                HStack(alignment: .center, spacing: tight ? 5 : 9) {
                    // Left of the D-pad: Back and Home, always reachable.
                    VStack(spacing: 10) {
                        sideActionButton("arrow.uturn.backward",
                                         label: "Regresar", action: "back",
                                         tight: tight)
                        sideActionButton("house.fill",
                                         label: "Inicio", action: "home",
                                         tight: tight)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 5) {
                        navButton("chevron.up", action: "up", tight: tight)
                        HStack(spacing: 5) {
                            navButton("chevron.left", action: "left", tight: tight)
                            Button {
                                haptic(.medium)
                                remote.send("ok")
                            } label: {
                                Text("OK")
                                    .font(.system(size: 15, weight: .heavy))
                                    .frame(width: tight ? 47 : 57, height: tight ? 43 : 47)
                                    .background(ClassicTheme.panelLight, in: Circle())
                                    .overlay(Circle().strokeBorder(ClassicTheme.accent,
                                                                  lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Seleccionar")
                            navButton("chevron.right", action: "right", tight: tight)
                        }
                        navButton("chevron.down", action: "down", tight: tight)
                    }

                    Spacer(minLength: 0)

                    // To the right: Play/Pause. No scrolling to reach it.
                    sideActionButton("playpause.fill",
                                     label: "Reproducir/Pausar",
                                     action: "play_pause", tight: tight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .center)
            }
            .frame(height: 143)
        }
    }

    private func navButton(_ symbol: String, action: String,
                           tight: Bool) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: tight ? 48 : 62, height: 43)
                .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action)
    }

    private func sideActionButton(_ icon: String, label: String, action: String,
                                  tight: Bool) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: tight ? 44 : 48, height: 48)
                .background(ClassicTheme.panel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
