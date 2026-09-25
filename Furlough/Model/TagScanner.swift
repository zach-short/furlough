import CoreNFC
import Foundation

/// Reads one NFC tag's hardware identifier as a single async call, on top of CoreNFC's
/// delegate API. Nothing is written to the tag; any NTAG sticker or existing Brick device works.
final class TagScanner: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    enum ScanError: LocalizedError, Equatable {
        case unavailable
        case cancelled
        /// Core NFC holds a session open for about a minute before ending it on its own. Kept
        /// distinct from `cancelled` only so neither is treated as a real failure.
        case timedOut
        case failed(String)

        /// Neither an answer nor a fault — a scan armed unprompted often ends this way and has
        /// nothing to report.
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

    /// Shows the system NFC sheet with `prompt` and returns the first tag's identifier. Ends
    /// any scan already in flight first: Core NFC allows only one session at a time, and the
    /// Anchor screen arms one automatically, so a later button tap must be able to take the
    /// reader back.
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

    /// Ends a scan in flight, as a cancellation. Does nothing when idle.
    func cancel() {
        let running = lock.withLock { () -> NFCTagReaderSession? in
            let current = session
            session = nil
            return current
        }
        // Invalidating calls back into the delegate, but `finish` (below) only resumes once,
        // and this is that once.
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
        // Timeout, or the app backgrounding (which iOS also ends the session for). Neither
        // needs an alert — the screen that armed the reader is still there to arm it again.
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
        // EXPERIMENTAL (HANDOFF step 62): invalidating in the same tick as the detection
        // callback may be giving the system sheet no time to show a success checkmark before
        // it's told to close — on a real phone, calling `invalidate()` immediately here showed
        // neither a checkmark nor a sound. Unverified against Apple's own documentation (this
        // session could not read it — see step 61) and unverified whether this delay actually
        // helps. `finish` runs first so the app's own state change stays instant either way
        // ("press answers at once" holds regardless); only the system sheet's own dismissal is
        // delayed. `Thread.sleep`, not `Task`/`DispatchQueue.main.asyncAfter`: this delegate
        // callback is not main-actor-isolated (`NFCTagReaderSession(..., queue: nil)` runs it on
        // a private queue, confirmed by the Swift 6 sendability error either of those threw
        // trying to hand `session` to a main-actor closure), and blocking that queue briefly
        // costs nothing else waiting on it.
        finish(.success(identifier))
        Thread.sleep(forTimeInterval: 0.5)
        session.invalidate()
    }
}
