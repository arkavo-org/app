import Foundation
import MultipeerConnectivity

actor StreamManager {
    private var activeInputStreams: [String: UUID] = [:]
    private var streams: [String: InputStream] = [:]

    func setPeerID(_ peerID: UUID, forStreamID streamID: String) {
        activeInputStreams[streamID] = peerID
    }

    func setStream(_ stream: InputStream, forStreamID streamID: String) {
        streams[streamID] = stream
    }

    func getPeerID(forStreamID streamID: String) -> UUID? {
        return activeInputStreams[streamID]
    }

    func removeStream(withID streamID: String) -> (UUID?, InputStream?) {
        let peerID = activeInputStreams[streamID]
        let stream = streams[streamID]
        activeInputStreams.removeValue(forKey: streamID)
        streams.removeValue(forKey: streamID)
        return (peerID, stream)
    }

    func streams(for peerID: UUID) -> [InputStream] {
        return activeInputStreams.filter { $1 == peerID }.keys.compactMap { streams[$0] }
    }

    func removeAllStreams() {
        streams.values.forEach { $0.close() }
        activeInputStreams.removeAll()
        streams.removeAll()
    }
}
