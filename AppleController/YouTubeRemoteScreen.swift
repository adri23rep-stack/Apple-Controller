import SwiftUI
import UIKit

// A separate remote mode for the user's regular YouTube website in the Windows
// browser. No YouTube downloads, unofficial API, or account connection.
struct YouTubeRemoteScreen: View {
    @ObservedObject var remote: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var searching = false

    private let red = Color(red: 0.97, green: 0.13, blue: 0.19)
    private let panel = Color(red: 0.12, green: 0.13, blue: 0.17)
    private let background = Color(red: 0.035, green: 0.04, blue: 0.065)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                HStack(spacing: 11) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YouTube")
                            .font(.system(size: 23, weight: .heavy))
                        Text("CONTROL DESDE EL IPHONE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Circle()
                        .fill(remote.youtubeActive ? Color.green : red)
                        .frame(width: 9, height: 9)
                    Button {
                        remote.closeYouTube()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(panel, in: Circle())
                    }
                    .accessibilityLabel("Volver a Xuper TV")
                }
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(red)
                    TextField("Busca un video en YouTube", text: $query)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .onSubmit { search() }
                    Button(action: search) {
                        if searching { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.right") }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ||
                              searching || !remote.youtubeActive)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 35, height: 35)
                    .background(red, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))

                HStack(spacing: 9) {
                    Image(systemName: "tv")
                        .foregroundStyle(red)
                    Text(remote.youtubeMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        HStack(spacing: 11) {
                            mediaButton("gobackward.10", label: "Retroceder 10 s",
                                        action: "youtube_seek_back")
                            mediaButton("playpause.fill", label: "Reproducir / Pausar",
                                        action: "youtube_pause", emphasized: true)
                            mediaButton("goforward.10", label: "Adelantar 10 s",
                                        action: "youtube_seek_forward")
                        }
                        HStack(spacing: 9) {
                            smallButton("speaker.slash.fill", label: "Silenciar",
                                        action: "youtube_mute")
                            smallButton("arrow.up.left.and.arrow.down.right", label: "Pantalla completa",
                                        action: "youtube_fullscreen")
                            smallButton("forward.end.fill", label: "Siguiente video",
                                        action: "youtube_next")
                            smallButton("arrow.uturn.backward", label: "Volver",
                                        action: "youtube_back")
                        }
                        HStack(spacing: 10) {
                            smallButton("speaker.minus.fill", label: "Bajar volumen",
                                        action: "youtube_volume_down")
                            Text("Volumen de Windows")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                            smallButton("speaker.plus.fill", label: "Subir volumen",
                                        action: "youtube_volume_up")
                        }
                        navigation
                    }
                    .padding(.vertical, 4)
                }
                TrackpadView(remote: remote)
                    .frame(height: max(190, geometry.size.height * 0.27))

                Button {
                    remote.closeYouTube()
                    dismiss()
                } label: {
                    Label("Regresar a Xuper TV", systemImage: "tv")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(panel, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .task { await remote.startYouTube() }
        .onDisappear { remote.closeYouTube() }
    }

    private func search() {
        searchFocused = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, remote.youtubeActive else { return }
        searching = true
        Task {
            await remote.searchYouTube(text)
            searching = false
        }
    }

    private func mediaButton(_ symbol: String, label: String,
                             action: String, emphasized: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            remote.send(action)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: emphasized ? 25 : 22))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(emphasized ? red : panel,
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!remote.youtubeActive)
    }

    private func smallButton(_ symbol: String, label: String, action: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            remote.send(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(panel, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!remote.youtubeActive)
    }

    private var navigation: some View {
        VStack(spacing: 5) {
            HStack {
                Spacer()
                smallNav("chevron.up", "up")
                Spacer()
            }
            HStack(spacing: 11) {
                smallNav("chevron.left", "left")
                Button {
                    remote.send("ok")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("OK")
                        .font(.system(size: 19, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(red, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(!remote.youtubeActive)
                smallNav("chevron.right", "right")
            }
            HStack {
                Spacer()
                smallNav("chevron.down", "down")
                Spacer()
            }
        }
        .padding(.horizontal, 42)
    }

    private func smallNav(_ symbol: String, _ action: String) -> some View {
        Button {
            remote.send(action)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .frame(width: 75, height: 42)
                .background(panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!remote.youtubeActive)
    }
}
