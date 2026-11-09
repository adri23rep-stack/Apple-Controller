import SwiftUI
import UIKit

private enum Palette {
    static let background = Color(red: 0.036, green: 0.044, blue: 0.072)
    static let panel = Color(red: 0.104, green: 0.117, blue: 0.160)
    static let panelLight = Color(red: 0.155, green: 0.166, blue: 0.215)
    static let accent = Color(red: 0.94, green: 0.18, blue: 0.29)
    static let secondary = Color(red: 0.65, green: 0.69, blue: 0.75)
}

struct RemoteScreen: View {
    @StateObject private var remote = RemoteClient()
    @State private var searchVisible = false
    @State private var searchText = ""
    @State private var volumeWork: Task<Void, Never>?
    @State private var brightnessWork: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                heading
                if !remote.connected {
                    Spacer(minLength: 12)
                    pairingCard
                    Spacer(minLength: 12)
                } else {
                    connectionHeader
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 17) {
                            sliders
                            quickAccess
                            transportButtons
                            directionPad
                        }
                        .padding(.vertical, 5)
                    }
                    TrackpadView(remote: remote)
                        .frame(height: max(205, geometry.size.height * 0.28))
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Palette.background,
                                        Color(red: 0.08, green: 0.052, blue: 0.09),
                                        Palette.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
        }
        .preferredColorScheme(.dark)
        .task { await remote.restore() }
        .sheet(isPresented: $searchVisible) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Buscar en Xuper TV")
                    .font(.title3.bold())
                TextField("Película, serie o canal", text: $searchText)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .padding(15)
                    .background(Palette.panelLight, in: RoundedRectangle(cornerRadius: 14))
                Button {
                    remote.search(searchText)
                    searchVisible = false
                    searchText = ""
                } label: {
                    Label("Buscar en la TV", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                }
                .buttonStyle(.plain)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(22)
            .presentationDetents([.height(270)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .onChange(of: remote.volume) { value in
            volumeWork?.cancel()
            volumeWork = Task {
                try? await Task.sleep(nanoseconds: 110_000_000)
                if !Task.isCancelled { remote.send("volume", value: Int(value)) }
            }
        }
        .onChange(of: remote.brightness) { value in
            brightnessWork?.cancel()
            brightnessWork = Task {
                try? await Task.sleep(nanoseconds: 110_000_000)
                if !Task.isCancelled { remote.send("brightness", value: Int(value)) }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            Text("X")
                .font(.system(size: 39, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Xuper TV").font(.system(size: 22, weight: .heavy))
                Text("APPLE CONTROLLER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            if remote.connected {
                Button {
                    searchVisible = true
                    haptic()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Palette.panel, in: Circle())
                }
                .accessibilityLabel("Buscar")
            }
            Circle().fill(remote.connected ? Color.green : Palette.accent)
                .frame(width: 8, height: 8)
        }
    }

    private var connectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi").foregroundStyle(.green)
            Text("Conectado a \(remote.host)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(Palette.secondary)
            Spacer()
            Button("Cambiar PC") {
                haptic()
                remote.changePC()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 4)
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.system(size: 42))
                .foregroundStyle(Palette.accent)
            Text("Conecta tu televisión")
                .font(.title2.bold())
            Text("Abre Xuper TV Desktop en Windows. En la parte inferior de la pantalla verás la IP y el PIN.")
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                Text("IP DE LA PC").font(.caption.bold()).foregroundStyle(Palette.secondary)
                TextField("192.168.1.25", text: $remote.host)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.headline, design: .monospaced))
                    .padding(14)
                    .background(Palette.panelLight, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("PIN DE 6 DÍGITOS").font(.caption.bold()).foregroundStyle(Palette.secondary)
                TextField("000000", text: $remote.pin)
                    .keyboardType(.numberPad)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .padding(14)
                    .background(Palette.panelLight, in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                haptic()
                Task { await remote.connect() }
            } label: {
                HStack {
                    if remote.connecting { ProgressView().tint(.white) }
                    else { Image(systemName: "link") }
                    Text(remote.connecting ? "Conectando…" : "Conectar al PC")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .disabled(remote.connecting)
            .buttonStyle(.plain)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
            Text(remote.message)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
    }

    private var sliders: some View {
        VStack(spacing: 16) {
            valueSlider(icon: "speaker.wave.2.fill", title: "Volumen",
                        value: $remote.volume, label: "\(Int(remote.volume))%")
            valueSlider(icon: "sun.max.fill", title: "Brillo del video",
                        value: $remote.brightness, label: "\(Int(remote.brightness))%")
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
        .tint(Palette.accent)
    }

    private func valueSlider(icon: String, title: String, value: Binding<Double>, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 21)
                    .foregroundStyle(Palette.accent)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(label).font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
                .accessibilityLabel(title)
        }
    }

    private var quickAccess: some View {
        HStack(spacing: 10) {
            quickButton("TV", symbol: "tv.fill", action: "tv")
            quickButton("Series", symbol: "rectangle.stack.fill", action: "series")
            quickButton("Películas", symbol: "film.fill", action: "movies")
        }
    }

    private func quickButton(_ title: String, symbol: String, action: String) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
        }
        .buttonStyle(.plain)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private var transportButtons: some View {
        HStack(spacing: 12) {
            utility("arrow.uturn.backward", label: "Volver", action: "back")
            utility("house.fill", label: "Inicio", action: "home")
            utility("playpause.fill", label: "Pausa", action: "play_pause")
            utility("line.3.horizontal", label: "Opciones", action: "menu")
        }
    }

    private func utility(_ symbol: String, label: String, action: String) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 47)
                .background(Palette.panelLight, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var directionPad: some View {
        VStack(spacing: 7) {
            HStack { Spacer(); navButton("chevron.up", action: "up"); Spacer() }
            HStack(spacing: 9) {
                navButton("chevron.left", action: "left")
                Button {
                    haptic(.medium)
                    remote.send("ok")
                } label: {
                    Text("OK").font(.system(size: 22, weight: .bold))
                        .frame(width: 81, height: 58)
                        .foregroundStyle(.white)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seleccionar")
                navButton("chevron.right", action: "right")
            }
            HStack { Spacer(); navButton("chevron.down", action: "down"); Spacer() }
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(_ symbol: String, action: String) -> some View {
        Button {
            haptic()
            remote.send(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .frame(width: 81, height: 51)
                .foregroundStyle(.white)
                .background(Palette.panelLight, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
