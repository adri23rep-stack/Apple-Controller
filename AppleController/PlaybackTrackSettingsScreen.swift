import SwiftUI

// Reads live tracks from XuperTV Desktop. These are not hard-coded languages.
struct PlaybackTrackSettingsScreen: View {
    @ObservedObject var remote: RemoteClient
    private let background = Color(red: 0.055, green: 0.067, blue: 0.098)
    private let panel = Color(red: 0.112, green: 0.137, blue: 0.188)
    private let accent = Color(red: 0.71, green: 0.65, blue: 1)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                if remote.playbackOptionsLoading {
                    ProgressView("Consultando pistas de Windows…")
                        .tint(accent)
                }
                Text(remote.playbackOptionsMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                if let playback = remote.playbackOptions, playback.active {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REPRODUCIENDO EN WINDOWS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(accent)
                        Text(playback.title.isEmpty ? "Video actual" : playback.title)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(panel, in: RoundedRectangle(cornerRadius: 14))

                    choiceSection("IDIOMA DEL AUDIO", icon: "speaker.wave.2",
                                  items: playback.audio, empty: "Este video no ofrece pistas de audio seleccionables.")
                    choiceSection("SUBTÍTULOS", icon: "captions.bubble",
                                  items: playback.subtitles, empty: "No hay subtítulos disponibles.")
                    choiceSection("CALIDAD / FUENTE", icon: "arrow.triangle.branch",
                                  items: playback.sources, empty: "El servicio no ofrece fuentes alternativas para este video.")

                    Text("Los idiomas dependen del contenido. La calidad / fuente cambia solo si el servicio ofrece más opciones. Cambiar de fuente puede reiniciar la reproducción.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                } else {
                    Label("Abre un video en XuperTV Desktop para ver idiomas, subtítulos y fuentes disponibles.",
                          systemImage: "tv")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(17)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Audio y subtítulos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { remote.loadPlaybackOptions() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Actualizar pistas del video")
            }
        }
        .task { remote.loadPlaybackOptions() }
    }

    @ViewBuilder
    private func choiceSection(_ title: String, icon: String,
                               items: [RemotePlaybackOption], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.66))
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panel, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.identity) { index, choice in
                        Button {
                            remote.selectPlaybackOption(choice)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: choice.selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(choice.selected ? accent : .white.opacity(0.35))
                                Text(choice.displayName)
                                    .font(.system(size: 14, weight: choice.selected ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if choice.selected {
                                    Text("ACTUAL")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(remote.playbackOptionsLoading || choice.selected)
                        if index + 1 < items.count {
                            Rectangle().fill(.white.opacity(0.07))
                                .frame(height: 1).padding(.leading, 15)
                        }
                    }
                }
                .background(panel, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
