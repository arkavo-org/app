#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
    import CoreNFC
    import Foundation

    @MainActor
    protocol RemoteCameraNFCReaderDelegate: AnyObject {
        func remoteCameraNFCReader(_ reader: RemoteCameraNFCReader, didResolve host: String, port: String)
        func remoteCameraNFCReader(_ reader: RemoteCameraNFCReader, didFailWith error: Error)
    }

    final class RemoteCameraNFCReader: NSObject, @preconcurrency NFCNDEFReaderSessionDelegate {
        weak var delegate: RemoteCameraNFCReaderDelegate?
        private var session: NFCNDEFReaderSession?

        func begin() {
            guard NFCNDEFReaderSession.readingAvailable else {
                notifyFailure(
                    NSError(domain: "RemoteCameraNFC", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "NFC not supported on this device",
                    ])
                )
                return
            }

            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = "Hold near the ArkavoCreator NFC pairing tag."
            session.begin()
            self.session = session
        }

        func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
            notifyFailure(error)
            self.session = nil
        }

        func readerSessionDidBecomeActive(_: NFCNDEFReaderSession) {}

        func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
            guard let tag = tags.first else { return }

            session.connect(to: tag) { [weak self] error in
                if let error {
                    self?.notifyFailure(error)
                    session.invalidate()
                    return
                }

                tag.readNDEF { message, error in
                    if let error {
                        self?.notifyFailure(error)
                        session.invalidate()
                        return
                    }

                    guard
                        let payload = message?.records.first,
                        let string = RemoteCameraNFCReader.decodeTextPayload(payload)
                    else {
                        self?.notifyFailure(
                            NSError(domain: "RemoteCameraNFC", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Invalid NFC payload",
                            ])
                        )
                        session.invalidate()
                        return
                    }

                    self?.processResolvedString(string, session: session)
                    session.invalidate()
                }
            }
        }

        func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
            guard let record = messages.first?.records.first,
                  let string = RemoteCameraNFCReader.decodeTextPayload(record)
            else {
                return
            }
            processResolvedString(string, session: session)
            session.invalidate()
        }

        private static func decodeTextPayload(_ payload: NFCNDEFPayload) -> String? {
            guard payload.typeNameFormat == .nfcWellKnown,
                  payload.type.count == 1,
                  payload.type.first == 0x54,
                  let statusByte = payload.payload.first
            else {
                return nil
            }

            let languageCodeLength = Int(statusByte & 0x3F)
            let textData = payload.payload.dropFirst(1 + languageCodeLength)
            return String(data: textData, encoding: .utf8)
        }

        private static func parseConnectionString(_ string: String) -> (String, String)? {
            let trimmed = string
                .replacingOccurrences(of: "arkavo://", with: "")
                .replacingOccurrences(of: "ARKAVO://", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let components = trimmed.split(separator: ":")
            guard components.count >= 2 else { return nil }

            let host = String(components.dropLast().joined(separator: ":"))
            let port = String(components.last!)
            return (host, port)
        }

        private func processResolvedString(_ string: String, session: NFCNDEFReaderSession) {
            if let (host, port) = RemoteCameraNFCReader.parseConnectionString(string) {
                notifyResolved(host: host, port: port)
            } else {
                notifyFailure(
                    NSError(domain: "RemoteCameraNFC", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not parse NFC host/port",
                    ])
                )
            }
            session.alertMessage = "Paired with ArkavoCreator."
        }

        private func notifyResolved(host: String, port: String) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.remoteCameraNFCReader(self, didResolve: host, port: port)
            }
        }

        private func notifyFailure(_ error: Error) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.remoteCameraNFCReader(self, didFailWith: error)
            }
        }
    }

    extension RemoteCameraNFCReader: @unchecked Sendable {}
#endif
