import SwiftUI

// PC options exposed by the authenticated XuperTV LAN server.
// The UI only displays settings that the Windows backend explicitly supports.
struct DesktopSettingsScreen: View {
    @ObservedObject var remote: RemoteClient
    let changePC: () -> Void
    let forgetPC: () -> Void
    @State private var confirmForget = false
    @Environment(\.dismiss) private var dismiss

    private let background = Color(red: 0.055, green: 0.067, blue: 0.098)
    private let panel = Color(red: 0.112, green: 0.137, blue: 0.188)
    private let accent = Color(red: 0.71, green: 0.65, blue: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Conectado a XuperTV", systemImage: "desktopcomputer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(accent)
                        Text(remote.host)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Cambia los ajustes de Windows directamente desde tu iPhone.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                    .background(panel, in: RoundedRectangle(cornerRadius: 17))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(accent)
                            Text(remote.pcSettingsMessage)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .font(.system(size: 12))
                        if remote.pcSettingsLoading {
                            ProgressView("Leyendo ajustes de la PC…")
                                .tint(accent)
                        }
                    }

                    ForEach(["Reproduccion", "Imagen", "Sonido", "Subtitulos"], id: \.self) { section in
                        let items = remote.pcSettings.filter { $0.category == section }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(title(for: section))
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(1.7)
                                    .foregroundStyle(.white.opacity(0.58))
                                    .padding(.leading, 2)

                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                                        DesktopSettingRow(setting: item, accent: accent) { value in
                                            remote.updatePCSetting(item.key, value: value)
                                        }
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 13)
                                        if index + 1 < items.count {
                                            Rectangle().fill(.white.opacity(0.08))
                                                .frame(height: 1)
                                                .padding(.leading, 15)
                                        }
                                    }
                                }
                                .background(panel, in: RoundedRectangle(cornerRadius: 17))
                            }
                        }
                    }

                    NavigationLink {
                        PlaybackTrackSettingsScreen(remote: remote)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "waveform")
                                .font(.system(size: 24))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Idioma, subtítulos y fuente")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Cambia español, doblaje, subtítulos o calidad del video en la PC.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.66))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .foregroundStyle(.white)
                        .padding(17)
                        .background(panel, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("CONTROL DEL PROGRAMA")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.7)
                            .foregroundStyle(.white.opacity(0.58))
                        HStack(spacing: 10) {
                            action("Pantalla completa", icon: "arrow.up.left.and.arrow.down.right") {
                                remote.send("fullscreen")
                            }
                            action("Cambiar monitor", icon: "display.2") {
                                remote.send("monitor_next")
                            }
                        }
                        Text("La calidad de video se aplica al siguiente título. Algunas opciones de audio y subtítulos necesitan un video en reproducción.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.56))
                            .padding(.top, 4)
                    }

                    Button {
                        changePC()
                    } label: {
                        Label("Cambiar PC vinculada", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(15)
                            .background(panel, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        confirmForget = true
                    } label: {
                        Label("Olvidar esta PC en mi iPhone", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .background(panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    Text("Se borrará la vinculación guardada en este iPhone. No afecta otros controles.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(17)
                .padding(.bottom, 23)
            }
            .background(background.ignoresSafeArea())
            .navigationTitle("Ajustes de XuperTV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }.foregroundStyle(accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { remote.loadPCSettings() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Actualizar ajustes")
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
        .task { remote.loadPCSettings() }
        .confirmationDialog("¿Olvidar esta PC?", isPresented: $confirmForget) {
            Button("Olvidar conexión guardada", role: .destructive) {
                forgetPC()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tendrás que escanear el QR o introducir el PIN para vincularla otra vez.")
        }
    }

    private func title(for category: String) -> String {
        switch category {
        case "Reproduccion": return "REPRODUCCIÓN"
        case "Imagen": return "IMAGEN Y CALIDAD"
        case "Sonido": return "SONIDO"
        default: return "SUBTÍTULOS"
        }
    }

    private func action(_ label: String, icon: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(panel, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct DesktopSettingRow: View {
    let setting: RemotePCSetting
    let accent: Color
    let setValue: (Int) -> Void

    private var isToggle: Bool {
        setting.key == "mute" || setting.key == "auto_next"
    }

    private var selections: [(Int, String)]? {
        if setting.key == "video_preset" {
            return [(0,"Compatible (CPU)"), (1,"Equilibrado"),
                    (2,"Nitidez alta"), (3,"Detalle extra (CAS)"),
                    (4,"GPU FSRCNNX"), (5,"RTX AI Super Resolution")]
        }
        if setting.key == "aspect" {
            return [(0,"Original"), (1,"16:9"), (2,"4:3"), (3,"Rellenar")]
        }
        return nil
    }

    private var valueText: String {
        switch setting.key {
        case "speed":
            return String(format: "%.2fx", Double(setting.value) / 100)
        case "audio_delay", "sub_delay":
            return "\(setting.value) ms"
        case "volume", "brightness", "sub_scale":
            return "\(setting.value)%"
        default:
            return "\(setting.value)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isToggle {
                Toggle(isOn: Binding(
                    get: { setting.value != 0 },
                    set: { setValue($0 ? 1 : 0) }
                )) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                }
                .tint(accent)
            } else if let selections {
                HStack {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Menu {
                        ForEach(selections, id: \.0) { option in
                            Button {
                                setValue(option.0)
                            } label: {
                                if setting.value == option.0 {
                                    Label(option.1, systemImage: "checkmark")
                                } else {
                                    Text(option.1)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(selections.first(where: { $0.0 == setting.value })?.1 ?? "Seleccionar")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(accent)
                    }
                }
            } else {
                HStack {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Slider(value: Binding(
                    get: { Double(setting.value) },
                    set: { setValue(Int($0.rounded())) }
                ), in: Double(setting.min)...Double(setting.max),
                step: Double(setting.step))
                .tint(accent)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        switch setting.key {
        case "auto_next": return "Siguiente episodio automático"
        case "video_preset": return "Mejora de video"
        case "speed": return "Velocidad de reproducción"
        case "aspect": return "Formato de pantalla"
        case "sub_scale": return "Tamaño de subtítulos"
        case "sub_delay": return "Sincronización de subtítulos"
        case "audio_delay": return "Sincronización de audio"
        case "mute": return "Silenciar"
        default: return setting.label
        }
    }
}
