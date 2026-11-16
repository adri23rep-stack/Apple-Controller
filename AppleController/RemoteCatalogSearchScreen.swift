import SwiftUI

struct RemoteCatalogSearchScreen: View {
    @ObservedObject var remote: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var category = "all"
    @State private var opening: Int?

    private let accent = Color(red: 0.94, green: 0.18, blue: 0.29)
    private let background = Color(red: 0.035, green: 0.04, blue: 0.075)
    private let card = Color(red: 0.10, green: 0.12, blue: 0.18)

    private var visible: [RemoteSearchItem] {
        remote.searchItems.filter { category == "all" || $0.kind == category }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 15) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(accent)
                    TextField("Canal, película o serie", text: $query)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit { find() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            focused = true
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.gray)
                            .accessibilityLabel("Limpiar búsqueda")
                    }
                }
                .padding(14)
                .background(card, in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 8) {
                    ForEach(["all", "tv", "movies", "series"], id: \.self) { value in
                        Button { category = value } label: {
                            Text(value == "all" ? "Todos" : value == "tv" ? "TV" :
                                 value == "movies" ? "Películas" : "Series")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(category == value ? accent : card,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(action: find) {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Buscar en el catálogo")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(remote.searching || query.trimmingCharacters(in: .whitespaces).count < 2)

                HStack(spacing: 8) {
                    if remote.searching { ProgressView().tint(accent) }
                    Text(remote.searchMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .padding(.vertical, 3)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visible) { item in
                            Button {
                                focused = false
                                opening = item.index
                                Task {
                                    let success = await remote.openSearchItem(item)
                                    opening = nil
                                    if success { dismiss() }
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 14) {
                                    RemotePoster(imageURL: item.imageURL,
                                                 isChannel: item.kind == "tv")
                                        .frame(width: item.kind == "tv" ? 100 : 83,
                                               height: 113)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.kindLabel)
                                            .font(.system(size: 10, weight: .heavy))
                                            .tracking(1.1)
                                            .foregroundStyle(accent)
                                        Text(item.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                        if !item.description.isEmpty {
                                            Text(item.description)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.white.opacity(0.62))
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(3)
                                        }
                                        Spacer(minLength: 1)
                                        Text(item.kind == "tv" ? "Ver canal en la TV" :
                                                "Abrir ficha en la TV")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer(minLength: 0)
                                    if opening == item.index { ProgressView().tint(accent) }
                                    else { Image(systemName: "play.circle.fill").foregroundStyle(accent) }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(card, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .background(background.ignoresSafeArea())
            .navigationTitle("Buscar en Xuper TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { remote.cancelSearch() }
    }

    private func find() {
        focused = false
        remote.searchCatalog(query)
    }
}

private struct RemotePoster: View {
    let imageURL: URL?
    let isChannel: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(Color(red: 0.18, green: 0.20, blue: 0.27))
            if let imageURL {
                AsyncImage(url: imageURL, transaction: Transaction(animation: .easeInOut)) {
                    phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView().tint(.white.opacity(0.4))
                    @unknown default:
                        fallback
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var fallback: some View {
        Image(systemName: isChannel ? "tv.fill" : "film.fill")
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.45))
    }
}
