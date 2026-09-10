import CoreNFC
import Foundation

/// Reads one NFC tag's hardware identifier as a single async call, on top of CoreNFC's
/// delegate API. The identifier is what the Anchor profile pairs with; any NTAG sticker or an
/// existing Brick device works, and nothing is written to the tag.
final class TagScanner: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    enum ScanError: LocalizedError, Equatable {
        case unavailable
        case cancelled
        /// The reader stopped listening on its own: Core NFC holds a session open for about a
        /// minute. Told apart from `cancelled` only so nothing tries to call it a failure —
        /// both are a scan that simply did not happen.
        case timedOut
        case failed(String)

        /// Neither an answer nor a fault: the sheet closed with no tag read. A scan armed
        /// without being asked for ends this way most times it ends at all, and has nothing
        /// to report when it does.
        var isQuiet: Bool { self == .cancelled || self == .timedOut }

        var errorDescription: String? {
            switch self {
            case .unavailable: "NFC is not available on this device."
            case .cancelled: "Cancelled."
            case .timedOut: "The reader stopped listening."
            case .failed(let message): message
            }
        }
    }

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: NFCTagReaderSession?

    /// Shows the system NFC sheet with `prompt` and returns the first tag's identifier.
    ///
    /// A scan already in flight is ended first. Core NFC allows one session at a time, and the
    /// Anchor screen arms one the moment it appears, so a button tapped after that sheet has
    /// gone must be able to take the reader back rather than queue behind a session nobody is
    /// waiting on any more.
    func scan(prompt: String) async throws -> Data {
        guard Self.isAvailable else { throw ScanError.unavailable }
        cancel()
        return try await withCheckedThrowingContinuation { continuation in
            guard let started = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil) else {
                continuation.resume(throwing: ScanError.unavailable)
                return
            }
            lock.withLock {
                self.continuation = continuation
                self.session = started
            }
            started.alertMessage = prompt
            started.begin()
        }
    }

    /// Ends a scan in flight, as a cancellation. For the Anchor screen leaving with its sheet
    /// still up, and for a second scan taking the reader over. Does nothing when idle.
    func cancel() {
        let running = lock.withLock { () -> NFCTagReaderSession? in
            let current = session
            session = nil
            return current
        }
        // Invalidating calls back into the delegate, which finishes nothing: `finish` resumes
        // the waiting call exactly once, and this is that once.
        running?.invalidate()
        finish(.failure(ScanError.cancelled))
    }

    /// Resumes the waiting call exactly once; later delegate callbacks are ignored.
    private func finish(_ result: Result<Data, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            let current = continuation
            continuation = nil
            session = nil
            return current
        }
        pending?.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        switch (error as? NFCReaderError)?.code {
        case .readerSessionInvalidationErrorUserCanceled:
            finish(.failure(ScanError.cancelled))
        // The minute running out, and the app being sent to the background, which iOS ends a
        // session for. Neither is worth an alert: the screen that armed the reader is still
        // there, with the row that arms it again.
        case .readerSessionInvalidationErrorSessionTimeout,
             .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
            finish(.failure(ScanError.timedOut))
        default:
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
