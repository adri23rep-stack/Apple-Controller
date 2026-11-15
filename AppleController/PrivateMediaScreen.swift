import SwiftUI
import AVKit
import UIKit

// Experimental, locally locked video library. Standard PC pairing remains
// mandatory. The private code is created by the user on first access.
struct PrivateMediaScreen: View {
    @ObservedObject var remote: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var configured = PrivateAccessStore.isConfigured()
    @State private var code = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var wrongAttempts = 0
    @State private var blockedUntil = UserDefaults.standard.double(forKey: "privateAccessBlockedUntil")
    private let bg = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let tint = Color(red: 0.75, green: 0.63, blue: 1)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                if unlocked { library }
                else { lockScreen }
            }
            .navigationTitle(unlocked ? "Para ver en iPhone" : "Acceso privado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if unlocked && remote.privateDepth > 0 {
                        Button {
                            remote.privateBack()
                        } label: {
                            Label("Atrás", systemImage: "chevron.left")
                        }
                        .disabled(remote.privateLoading)
                    } else {
                        Button("Cerrar") { dismiss() }
                    }
                }
                if unlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            remote.openPrivateLibrary()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Actualizar biblioteca privada")
                    }
                }
            }
        }
        .tint(tint)
        .preferredColorScheme(.dark)
        .privacySensitive()
        .onDisappear {
            // Presenting full-screen AVPlayer may hide this view temporarily.
            // Keep its catalogue alive until the video is dismissed.
            if remote.privatePlaybackURL == nil {
                remote.closePrivateLibrary()
                code = ""
                confirm = ""
                unlocked = false
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { remote.privatePlaybackURL != nil },
            set: { if !$0 { remote.stopPrivatePlayback() } }
        )) {
            if let url = remote.privatePlaybackURL {
                PrivateVideoPlayer(url: url, title: remote.privatePlaybackTitle) {
                    remote.stopPrivatePlayback()
                }
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 17) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 47, weight: .thin))
                .foregroundStyle(tint)
                .padding(20)
                .background(tint.opacity(0.08), in: Circle())
            Text(configured ? "Introduce tu código privado" : "Crea tu código secreto")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(configured ?
                "Esta biblioteca se desbloquea solo en este iPhone." :
                "Elige de 6 a 12 números. El código nunca se envía a Windows.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.67))
                .multilineTextAlignment(.center)
            SecureField("Código privado", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Código privado")
            if !configured {
                SecureField("Confirma el código", text: $confirm)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(16)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Button {
                authorize()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: configured ? "lock.open.fill" : "key.fill")
                    Text(configured ? "Desbloquear" : "Guardar y abrir")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 51)
                .background(tint, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
            }
            .disabled(code.isEmpty)
            Text("Requiere XuperTV abierto en tu PC y conexión a la misma Wi-Fi.\nLos videos protegidos no estarán disponibles por reproducción directa.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 27)
    }

    private func authorize() {
        let now = Date().timeIntervalSince1970
        if blockedUntil > now {
            error = "Demasiados intentos. Vuelve a intentarlo más tarde."
            code = ""
            return
        }
        guard PrivateAccessStore.valid(code) else {
            error = "Usa entre 6 y 12 números."
            return
        }
        if configured {
            if !PrivateAccessStore.verify(code) {
                wrongAttempts += 1
                if wrongAttempts >= 5 {
                    blockedUntil = now + 60
                    UserDefaults.standard.set(blockedUntil, forKey: "privateAccessBlockedUntil")
                    error = "Acceso bloqueado durante un minuto."
                    wrongAttempts = 0
                } else {
                    error = "Código incorrecto."
                }
                code = ""
                return
            }
        } else {
            guard code == confirm else {
                error = "Los códigos no coinciden."
                return
            }
            guard PrivateAccessStore.configure(code) else {
                error = "No se pudo proteger el código en el llavero."
                return
            }
            configured = true
        }
        code = ""
        confirm = ""
        error = ""
        wrongAttempts = 0
        blockedUntil = 0
        UserDefaults.standard.removeObject(forKey: "privateAccessBlockedUntil")
        unlocked = true
        remote.openPrivateLibrary()
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 27))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(remote.privateTitle)
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(2)
                        Text("Reproducir aquí, sin cambiar la TV")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
                Text(remote.privateMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                if remote.privateLoading {
                    HStack {
                        Spacer()
                        ProgressView("Cargando…").tint(tint)
                        Spacer()
                    }
                    .padding(.vertical, 18)
                }
                LazyVGrid(columns: columns, spacing: 13) {
                    ForEach(remote.privateItems) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            remote.privateSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(tint.opacity(0.12))
                                    if let url = item.imageURL {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Image(systemName: symbol(item))
                                                    .font(.system(size: 31))
                                                    .foregroundStyle(tint)
                                            }
                                        }
                                    } else {
                                        Image(systemName: symbol(item))
                                            .font(.system(size: 34))
                                            .foregroundStyle(tint)
                                    }
                                }
                                .frame(height: 158)
                                .clipped()
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(minHeight: 35, alignment: .topLeading)
                                Text(item.kind == "episode" || item.kind == "tv" ?
                                     "Ver en iPhone" : "Explorar")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.white.opacity(0.055),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(remote.privateLoading)
                    }
                }
                if remote.privateItems.count < remote.privateTotal {
                    Button("Cargar más títulos") {
                        remote.privateLoadMore()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .disabled(remote.privateLoading)
                }
                if remote.privateItems.isEmpty && !remote.privateLoading {
                    Text("No hay títulos en esta sección o no está disponible ahora.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(16)
                }
            }
            .padding(17)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
    }

    private func symbol(_ item: RemoteBrowseItem) -> String {
        switch item.kind {
        case "tv": return "tv.fill"
        case "episode": return "play.rectangle.fill"
        case "movies": return "film.fill"
        case "series": return "play.rectangle.on.rectangle"
        case "providers", "platform": return "square.grid.2x2.fill"
        default: return "folder.fill"
        }
    }
}

private struct PrivateVideoPlayer: View {
    let url: URL
    let title: String
    let close: () -> Void
    @State private var player: AVPlayer

    init(url: URL, title: String, close: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.close = close
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
            VStack {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .padding(12)
                            .background(.black.opacity(0.75), in: Circle())
                    }
                    .accessibilityLabel("Cerrar video privado")
                    Spacer()
                    Text(title)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .onAppear { player.play() }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .preferredColorScheme(.dark)
        .privacySensitive()
    }
}
