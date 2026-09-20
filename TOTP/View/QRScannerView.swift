//
//  QRScannerView.swift
//  TOTP
//
//  QR code capture: live camera (VisionKit) on iPhone/iPad, still-image decoding (Vision) everywhere.
//

import SwiftUI
import Vision

#if os(iOS)
import VisionKit
#endif

enum QRCodeDecoder {
    enum DecodeError: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            String(localized: "The image couldn't be read.")
        }
    }

    /// Returns the payload of every QR code found in the image.
    static func payloads(inImageData data: Data) async throws -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        let observations = try await request.perform(on: data)
        return observations.compactMap(\.payloadString)
    }
}

#if os(iOS)
/// Full-screen live scanner. Calls `onScan` with the first QR payload it recognises.
struct QRScannerView: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            DataScannerRepresentable(onScan: onScan)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Label("Point the camera at the setup QR code", systemImage: "qrcode.viewfinder")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .floatingGlass(in: .capsule)
                        .padding(.bottom, 32)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: onCancel)
                    }
                }
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}
#endif
