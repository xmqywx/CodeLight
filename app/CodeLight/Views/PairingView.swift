import SwiftUI
import AVFoundation
import VisionKit
import CodeLightProtocol

/// QR code scanner for pairing with a CodeIsland instance.
struct PairingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var manualUrl = "https://island.wdao.chat"
    @State private var showManualEntry = false
    @State private var showScanner = false

    private var isScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text(String(localized: "scan_qr_code"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "scan_qr_instruction"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if isProcessing {
                ProgressView(String(localized: "connecting"))
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            // Scan button
            Button {
                if isScannerAvailable {
                    showScanner = true
                } else {
                    errorMessage = String(localized: "camera_not_available")
                }
            } label: {
                Label(String(localized: "scan_qr_code"), systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 40)

            Button(String(localized: "enter_url_manually")) {
                showManualEntry = true
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("CodeLight")
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRScannerView { code in
                    showScanner = false
                    Task { await handleQRCode(code) }
                }
                .navigationTitle(String(localized: "scan_qr_code"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "cancel")) { showScanner = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet(url: $manualUrl) {
                Task { await connectManually() }
            }
        }
    }

    private func handleQRCode(_ code: String) async {
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data) else {
            errorMessage = String(localized: "invalid_qr_code")
            return
        }

        isProcessing = true
        errorMessage = nil
        let config = ServerConfig(url: payload.serverUrl, name: payload.deviceName)
        appState.addServer(config)
        await appState.connectTo(config)
        isProcessing = false
    }

    private func connectManually() async {
        guard !manualUrl.isEmpty else { return }
        let url = manualUrl.hasPrefix("http") ? manualUrl : "https://\(manualUrl)"
        isProcessing = true
        showManualEntry = false
        errorMessage = nil
        let config = ServerConfig(url: url, name: String(localized: "server"))
        appState.addServer(config)
        await appState.connectTo(config)
        isProcessing = false
    }
}

/// Manual server URL entry sheet.
private struct ManualEntrySheet: View {
    @Binding var url: String
    let onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "server_url")) {
                    TextField("https://island.wdao.chat", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle(String(localized: "manual_entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "connect")) { onConnect() }
                        .disabled(url.isEmpty)
                }
            }
        }
    }
}
