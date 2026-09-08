import CoreNFC
import Foundation

/// Reads one NFC tag's hardware identifier as a single async call, on top of CoreNFC's
/// delegate API. The identifier is what the Anchor profile pairs with; any NTAG sticker or an
/// existing Brick device works, and nothing is written to the tag.
final class TagScanner: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    enum ScanError: LocalizedError, Equatable {
        case unavailable
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "NFC is not available on this device."
            case .cancelled: "Cancelled."
            case .failed(let message): message
            }
        }
    }

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?

    /// Shows the system NFC sheet with `prompt` and returns the first tag's identifier.
    func scan(prompt: String) async throws -> Data {
        guard Self.isAvailable else { throw ScanError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil) else {
                finish(.failure(ScanError.unavailable))
                return
            }
            session.alertMessage = prompt
            session.begin()
        }
    }

    /// Resumes the waiting call exactly once; later delegate callbacks are ignored.
    private func finish(_ result: Result<Data, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            let current = continuation
            continuation = nil
            return current
        }
        pending?.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        if let nfc = error as? NFCReaderError, nfc.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(ScanError.cancelled))
        } else {
            finish(.failure(ScanError.failed(error.localizedDescription)))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        let identifier: Data
        switch tag {
        case .miFare(let mifare): identifier = mifare.identifier
        case .iso7816(let iso): identifier = iso.identifier
        case .iso15693(let iso): identifier = iso.identifier
        case .feliCa(let felica): identifier = felica.currentIDm
        @unknown default: identifier = Data()
        }
        guard !identifier.isEmpty else {
            session.invalidate(errorMessage: "Could not read that tag.")
            return
        }
        session.alertMessage = "Tag read."
        session.invalidate()
        finish(.success(identifier))
    }
}
