import SwiftUI

// Complete browser for the XuperTV service already authenticated on Windows.
// Artwork and labels come from catalogue metadata, NEVER from private stream URLs.
struct RemoteFullCatalogScreen: View {
    @ObservedObject var remote: RemoteClient
    let initialProvider: String?
    @Environment(\.dismiss) private var dismiss
    @State private var showingSearch = false
    private let background = Color(red: 0.055, green: 0.067, blue: 0.098)
    private let panel = Color(red: 0.105, green: 0.129, blue: 0.184)
    private let accent = Color(red: 0.71, green: 0.65, blue: 1)
    private let grid = [GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        heading
                        statusLine
                        if remote.browseItems.isEmpty && !remote.browseLoading {
                            ContentUnavailableView("Sin títulos disponibles",
                                systemImage: "sparkles.tv",
                                description: Text(remote.browseMessage))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.vertical, 36)
                        }

                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(remote.browseItems) { item in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    remote.browseSelect(item)
                                } label: {
                                    RemoteBrowseCard(item: item, panel: panel, accent: accent)
                                }
                                .buttonStyle(.plain)
                                .disabled(remote.browseLoading)
                                .accessibilityLabel("\(item.kindLabel): \(item.title)")
                            }
                        }

                        if remote.browseItems.count < remote.browseTotal {
                            Button {
                                remote.loadMoreBrowse()
                            } label: {
                                HStack {
                                    Image(systemName: "square.stack.3d.up")
                                    Text("Mostrar más")
                                    if remote.browseLoading { ProgressView().tint(.white) }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(panel, in: RoundedRectangle(cornerRadius: 13))
                            }
                            .disabled(remote.browseLoading)
                        }
                        if remote.browseLoading {
                            HStack {
                                Spacer()
                                ProgressView("Cargando catálogo…").tint(accent)
                                Spacer()
                            }
                            .padding(.vertical, 18)
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .toolbarBackground(background, for: .navigationBar)
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if remote.browseDepth > 0 {
                            remote.browseBack()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label(remote.browseDepth > 0 ? "Atrás" : "Cerrar",
                              systemImage: "chevron.left")
                    }
                    .disabled(remote.browseLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Buscar películas, series o canales")
                }
            }
            .sheet(isPresented: $showingSearch) {
                RemoteCatalogSearchScreen(remote: remote)
                    .presentationDetents([.large])
            }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
        .task { remote.startFullCatalog(provider: initialProvider) }
        .onDisappear { remote.cancelBrowse() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent)
                Text("XuperTV")
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(1)
                Spacer()
                Label("PC conectada", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.85))
            }
            Text(remote.browseTitle)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .lineLimit(2)
            if !remote.browseDescription.isEmpty {
                Text(remote.browseDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(3)
            }
            HStack(spacing: 7) {
                Image(systemName: "rectangle.stack.fill").foregroundStyle(accent)
                Text(remote.browseTotal == 0 ? "Explora canales, películas y series" :
                     "\(remote.browseTotal) elementos en esta sección")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [panel, accent.opacity(0.2), panel],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 20)
                 .strokeBorder(.white.opacity(0.1)))
    }

    private var statusLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: remote.browseMessage.contains("Reproduciendo") ?
                  "play.circle.fill" : "info.circle")
                .foregroundStyle(accent)
            Text(remote.browseMessage.isEmpty ?
                 "Toca un título para verlo en la PC." : remote.browseMessage)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
        }
        .padding(.horizontal, 3)
    }
}

private struct RemoteBrowseCard: View {
    let item: RemoteBrowseItem
    let panel: Color
    let accent: Color

    private var icon: String {
        switch item.kind {
        case "tv": return "tv.fill"
        case "movies": return "film.fill"
        case "series": return "play.rectangle.on.rectangle"
        case "episode": return "play.circle.fill"
        case "providers": return "square.grid.2x2.fill"
        case "platform": return "play.rectangle.on.rectangle.fill"
        default: return "folder.fill"
        }
    }

    private var platformTint: Color {
        switch item.provider {
        case "netflix": return Color(red: 0.87, green: 0.10, blue: 0.12)
        case "hbo_max": return Color(red: 0.61, green: 0.43, blue: 0.94)
        case "apple_tv": return .white
        case "youtube": return Color(red: 1.0, green: 0.24, blue: 0.23)
        case "disney": return Color(red: 0.35, green: 0.63, blue: 1)
        case "prime_video": return Color(red: 0.31, green: 0.77, blue: 0.99)
        default: return accent
        }
    }

    private var platformMark: String {
        switch item.provider {
        case "netflix": return "N"
        case "hbo_max": return "max"
        case "apple_tv": return "tv+"
        case "youtube": return "▶"
        case "disney": return "Disney+"
        case "prime_video": return "prime"
        case "paramount": return "P+"
        case "vix": return "ViX"
        default: return String(item.title.prefix(3))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: [
                        panel, platformTint.opacity(0.17), panel
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                if item.kind == "platform" {
                    VStack(spacing: 10) {
                        Text(platformMark)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(platformTint)
                            .shadow(color: platformTint.opacity(0.3), radius: 14)
                        Text("CATÁLOGO XUPERTV")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                } else if item.kind == "providers" {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(accent)
                        Text("TUS PLATAFORMAS")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView().tint(accent)
                        default:
                            Image(systemName: icon)
                                .font(.system(size: 35))
                                .foregroundStyle(accent.opacity(0.65))
                        }
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(accent.opacity(0.70))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 188)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(item.kindLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.66), in: Capsule())
                    .padding(9)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 35,
                           alignment: .topLeading)
                if !item.description.isEmpty && item.kind == "platform" {
                    Text(item.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: item.kind == "tv" ||
                          item.kind == "episode" ? "play.fill" : "arrow.right")
                    Text(item.kind == "tv" || item.kind == "episode" ?
                         "Reproducir en PC" : "Explorar XuperTV")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .background(panel, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
                 .strokeBorder(.white.opacity(0.09)))
    }
}
