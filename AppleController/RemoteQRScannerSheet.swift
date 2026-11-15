import SwiftUI
import AVFoundation
import UIKit

// The code contains only a private LAN IPv4 address and a short-lived PIN.
// It never contains or exposes the permanent paired bearer token.
struct RemoteQRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed = false
    @State private var permissionChecked = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.068, blue: 0.096).ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                    Text("Escanea el QR de XuperTV")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("En Windows, pulsa «QR iPhone» o F9 y apunta la cámara al código.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    if cameraAllowed {
                        RemoteQRCodeCamera { value in
                            onScan(value)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(.purple.opacity(0.7), lineWidth: 2))
                    } else if permissionChecked {
                        VStack(spacing: 12) {
                            Text("Permite usar la cámara para escanear el QR, o conecta con IP y PIN.")
                                .multilineTextAlignment(.center)
                            Button("Abrir ajustes del iPhone") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(22)
                    } else {
                        ProgressView("Preparando cámara…").tint(.purple)
                    }
                    Spacer()
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .navigationTitle("Vincular con QR")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cameraAllowed = true
            case .notDetermined:
                cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            default: cameraAllowed = false
            }
            permissionChecked = true
        }
    }
}

private struct RemoteQRCodeCamera: UIViewControllerRepresentable {
    let scanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRViewController {
        let controller = QRViewController()
        controller.onScan = scanned
        return controller
    }
    func updateUIViewController(_ uiViewController: QRViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: QRViewController, coordinator: ()) {
        uiViewController.stop()
    }

    final class QRViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var layer: AVCaptureVideoPreviewLayer?
        private var didScan = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            layer = preview
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            layer?.frame = view.bounds
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let qr = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = qr.stringValue else { return }
            didScan = true
            onScan?(value)
        }
        func stop() {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }
    }
}
