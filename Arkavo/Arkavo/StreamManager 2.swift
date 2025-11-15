//
//  StreamManager.swift
//  
//
//  Created to provide concurrency-safe management of InputStream to MCPeerID mappings
//  for use in P2PGroupViewModel within GroupViewModel.swift.
//
//  This actor maintains two dictionaries:
//  - streamToPeer: maps InputStream instances to their associated MCPeerID
//  - peerToStreams: maps MCPeerID to a Set of ObjectIdentifier representing InputStreams
//
//  It provides async methods to set, get, remove streams, and query streams per peer.
//  The actor ensures thread safety when called from async contexts.
//

import Foundation
import MultipeerConnectivity

actor StreamManager {
    private var streamToPeer: [ObjectIdentifier: MCPeerID] = [:]
    private var peerToStreams: [MCPeerID: Set<ObjectIdentifier>] = [:]

    /// Associates a MCPeerID with a given InputStream using its ObjectIdentifier.
    /// If the stream was previously associated with a different peer, the old association is removed.
    func setPeerID(_ peerID: MCPeerID, forStreamID streamID: ObjectIdentifier) {
        // Remove previous association if any
        if let oldPeer = streamToPeer[streamID] {
            if oldPeer != peerID {
                peerToStreams[oldPeer]?.remove(streamID)
                if peerToStreams[oldPeer]?.isEmpty == true {
                    peerToStreams.removeValue(forKey: oldPeer)
                }
            }
        }

        streamToPeer[streamID] = peerID

        var set = peerToStreams[peerID] ?? Set<ObjectIdentifier>()
        set.insert(streamID)
        peerToStreams[peerID] = set
    }

    /// Returns the MCPeerID associated with the given stream ObjectIdentifier, or nil if none.
    func getPeerID(forStreamID streamID: ObjectIdentifier) -> MCPeerID? {
        return streamToPeer[streamID]
    }

    /// Removes the stream with the given ObjectIdentifier from the manager and returns the associated MCPeerID if any.
    /// Cleans up the peerToStreams mapping accordingly.
    func removeStream(withID streamID: ObjectIdentifier) -> MCPeerID? {
        guard let peerID = streamToPeer.removeValue(forKey: streamID) else {
            return nil
        }
        peerToStreams[peerID]?.remove(streamID)
        if peerToStreams[peerID]?.isEmpty == true {
            peerToStreams.removeValue(forKey: peerID)
        }
        return peerID
    }

    /// Returns the stream IDs associated with the given MCPeerID.
    func streamIDs(for peerID: MCPeerID) -> Set<ObjectIdentifier> {
        return peerToStreams[peerID] ?? []
    }

    /// Removes all streams from the manager.
    func removeAllStreams() {
        streamToPeer.removeAll()
        peerToStreams.removeAll()
    }
}
