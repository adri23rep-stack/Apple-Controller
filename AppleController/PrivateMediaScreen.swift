import SwiftUI
import AVKit
import UIKit
import UniformTypeIdentifiers

// Private media is completely standalone. The ordinary iPhone remote
// continues to use Windows, but this screen never makes a PC request.
struct PrivateMediaScreen: View {
    @ObservedObject var remote: RemoteClient
    @StateObject private var library = StandaloneMediaLibrary()
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var configured = PrivateAccessStore.isConfigured()
    @State private var code = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var wrongAttempts = 0
    @State private var blockedUntil = UserDefaults.standard.double(forKey: "privateAccessBlockedUntil")
    @State private var showAdd = false
    @State private var importing = false
    @State private var entryTitle = ""
    @State private var entryURL = ""
    @State private var addType = "playlist"
    @State private var search = ""
    @State private var group = "Todas"
    @State private var playing: StandaloneMediaEntry?
    @State private var confirmClear = false

    private let bg = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let tint = Color(red: 0.75, green: 0.63, blue: 1)
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var groups: [String] {
        ["Todas"] + Array(Set(library.items.map(\.category))).sorted()
    }
    private var filtered: [StandaloneMediaEntry] {
        library.items.filter { entry in
            (group == "Todas" || entry.category == group) &&
            (search.isEmpty || entry.title.localizedCaseInsensitiveContains(search) ||
             entry.category.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                if unlocked { content }
                else { lockScreen }
            }
            .navigationTitle(unlocked ? "Biblioteca privada" : "Acceso privado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                if unlocked {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { importing = true } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Importar archivo M3U")
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Agregar lista o video")
                    }
                }
            }
        }
        .tint(tint)
        .preferredColorScheme(.dark)
        .privacySensitive()
        .onDisappear {
            if playing == nil {
                code = ""
                confirm = ""
                unlocked = false
            }
        }
        .fullScreenCover(item: $playing) { entry in
            if let url = entry.playbackURL {
                PrivateVideoPlayer(url: url, title: entry.title) {
                    playing = nil
                }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, .data]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    _ = library.importPlaylist(data: data, name: url.lastPathComponent)
                } else {
                    error = "No se pudo leer el archivo M3U."
                }
            case .failure:
                error = "No se pudo importar el archivo."
            }
        }
        .confirmationDialog("¿Vaciar la biblioteca del iPhone?",
                            isPresented: $confirmClear) {
            Button("Eliminar todos los títulos", role: .destructive) {
                library.removeAll()
            }
            Button("Cancelar", role: .cancel) {}
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
            Text(configured ?
                 "Tu biblioteca se desbloquea solamente en este iPhone." :
                 "Elige de 6 a 12 números. El código nunca se manda a Windows.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            SecureField("Código privado", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            if !configured {
                SecureField("Confirma el código", text: $confirm)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(16)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Button { authorize() } label: {
                Text(configured ? "Desbloquear" : "Guardar y abrir")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 51)
                    .background(tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .disabled(code.isEmpty)
            Text("No requiere PC ni Wi-Fi local. Las listas y videos directos necesitan Internet.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 27)
    }

    private func authorize() {
        let now = Date().timeIntervalSince1970
        if blockedUntil > now {
            error = "Demasiados intentos. Inténtalo más tarde."
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
                error = "No se pudo guardar el código en el llavero."
                return
            }
            configured = true
        }
        code = "";confirm = "";error = ""
        wrongAttempts = 0;blockedUntil = 0
        UserDefaults.standard.removeObject(forKey: "privateAccessBlockedUntil")
        unlocked = true
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("REPRODUCTOR INDEPENDIENTE", systemImage: "iphone.gen3")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.3)
                        .foregroundStyle(tint)
                    Text("Tu biblioteca en el iPhone")
                        .font(.system(size: 22, weight: .bold))
                    Text("Sin conexión con Windows. Solo listas y videos HTTPS compatibles; no es todavía el catálogo automático de XuperTV.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

                Text(library.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                if !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if library.loading { ProgressView("Consultando lista…").tint(tint) }

                HStack(spacing: 10) {
                    actionButton("Agregar", icon: "plus") { showAdd = true }
                    actionButton("Importar M3U", icon: "square.and.arrow.down") {
                        importing = true
                    }
                }
                if !library.playlistURLs.isEmpty {
                    Button {
                        Task { await library.refresh() }
                    } label: {
                        Label("Actualizar listas de Internet", systemImage: "arrow.clockwise")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(library.loading)
                }
                if !library.items.isEmpty {
                    TextField("Buscar en mi biblioteca", text: $search)
                        .textInputAutocapitalization(.never)
                        .padding(13)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Picker("Categoría", selection: $group) {
                        ForEach(groups, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .tint(tint)
                    .pickerStyle(.menu)
                }

                LazyVGrid(columns: columns, spacing: 13) {
                    ForEach(filtered) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            playing = item
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(tint.opacity(0.12))
                                    if let image = item.artworkURL {
                                        AsyncImage(url: image) { phase in
                                            if let picture = phase.image {
                                                picture.resizable().scaledToFill()
                                            } else {
                                                Image(systemName: "play.rectangle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(tint)
                                            }
                                        }
                                    } else {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(tint)
                                    }
                                }
                                .frame(height: 148)
                                .clipped()
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                                    .frame(minHeight: 34, alignment: .topLeading)
                                Text(item.category)
                                    .font(.system(size: 10))
                                    .foregroundStyle(tint)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(.white.opacity(0.055),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Quitar de mi biblioteca", role: .destructive) {
                                library.delete(item)
                            }
                        }
                    }
                }
                if library.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.tv")
                            .font(.system(size: 42))
                            .foregroundStyle(tint.opacity(0.8))
                        Text("Aún no tienes videos")
                            .font(.headline)
                        Text("Agrega un enlace directo HTTPS o importa una lista M3U. Todo se reproduce aquí, sin encender la PC.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(.white.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 17))
                }
                if !library.items.isEmpty {
                    Button("Vaciar biblioteca", role: .destructive) {
                        confirmClear = true
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
            }
            .padding(17)
        }
        .foregroundStyle(.white)
    }

    private func actionButton(_ label: String, icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(13)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Picker("Agregar", selection: $addType) {
                    Text("Lista M3U de Internet").tag("playlist")
                    Text("Video directo MP4 / HLS").tag("video")
                }
                if addType == "video" {
                    TextField("Nombre del video", text: $entryTitle)
                }
                TextField("https://...", text: $entryURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(2...4)
                Text(addType == "video" ?
                     "El enlace debe apuntar al video, no a una página web." :
                     "Pega un enlace HTTPS a un archivo M3U con tus canales o películas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(library.loading ? "Importando…" : "Guardar en el iPhone") {
                    if addType == "video" {
                        if library.addVideo(title: entryTitle, url: entryURL) {
                            showAdd = false;entryTitle = "";entryURL = ""
                        }
                    } else {
                        Task {
                            let ok = await library.addPlaylist(entryURL)
                            if ok { showAdd = false;entryURL = "" }
                        }
                    }
                }
                .disabled(entryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          library.loading)
            }
            .navigationTitle("Agregar contenido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { showAdd = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
            VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
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
                    Text(title).font(.caption.bold()).lineLimit(1)
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
