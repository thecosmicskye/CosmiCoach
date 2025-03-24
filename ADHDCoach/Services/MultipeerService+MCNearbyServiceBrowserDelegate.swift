//
//  MultipeerService+MCNearbyServiceBrowserDelegate.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/20/25.
//

import Foundation
import MultipeerConnectivity

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("🔍 Found peer: \(peerID.displayName), info: \(info?.description ?? "none")")
        
        // Get app state information for diagnostics
        #if canImport(UIKit)
        let appStateString = UIApplication.shared.applicationState == .active ? "active" : 
                            UIApplication.shared.applicationState == .background ? "background" : "inactive"
        print("📱 App state when found peer: \(appStateString)")
        #endif
        
        // Get userId from discovery info if available
        let userId = info?["userId"]
        
        // Check if this peer is blocked
        if let userId = userId, self.isUserBlocked(userId) {
            print("🚫 Ignoring blocked peer: \(peerID.displayName) with userId \(userId)")
            return
        }
        
        // Process discovered peer on main thread
        DispatchQueue.main.async {
            self.processPeerFoundEvent(peerID: peerID, info: info)
        }
    }
    
    private func processPeerFoundEvent(peerID: MCPeerID, info: [String: String]?) {
        // Get userId from discovery info if available
        let userId = info?["userId"]
        
        // Only add to discoveredPeers if not already in the list and not connected
        // Check if already connected
        let connectedPeerIDs = self.sessionConnectedPeers
        if connectedPeerIDs.contains(peerID) {
            print("⚠️ Peer already connected: \(peerID.displayName)")
            return
        }
        
        // Check if this is a known peer
        let isKnownPeer = userId != nil && self.knownPeers.contains(where: { $0.userId == userId })
        print("ℹ️ Found peer: \(peerID.displayName), isKnown: \(isKnownPeer ? "Yes" : "No")")
        
        // Check if already in discovered list
        if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            handleExistingPeerFound(at: index, peerID: peerID, info: info, userId: userId)
        } else {
            handleNewPeerFound(peerID: peerID, info: info, userId: userId, isKnownPeer: isKnownPeer)
        }
        
        // Log current content of discoveredPeers
        print("📋 Current discovered peers list:")
        for (index, peer) in self.discoveredPeers.enumerated() {
            print("   \(index): \(peer.peerId.displayName), state: \(peer.state.rawValue), userId: \(peer.discoveryInfo?["userId"] ?? "unknown")")
        }
    }
    
    private func handleExistingPeerFound(at index: Int, peerID: MCPeerID, info: [String: String]?, userId: String?) {
        // Always update discovery info
        let oldInfo = self.discoveredPeers[index].discoveryInfo
        self.discoveredPeers[index].discoveryInfo = info
        
        // Always mark as nearby when found
        self.discoveredPeers[index].isNearby = true
        
        print("🔄 Updated discovery info for existing peer: \(peerID.displayName)")
        print("   Old info: \(oldInfo?.description ?? "none")")
        print("   New info: \(info?.description ?? "none")")
        
        // Try to auto-connect in several states, not just disconnected
        if self.discoveredPeers[index].state == .disconnected || 
           self.discoveredPeers[index].state == .discovered || 
           self.discoveredPeers[index].state == .rejected {
            
            print("🔍 Peer eligible for auto-connection is now nearby: \(peerID.displayName)")
            
            // Check if this is a peer we should auto-connect to,
            // AND if we should be the one to initiate (deterministic leader election)
            if let userId = userId, shouldAutoConnect(to: userId) {
                // Update the knownPeer record first to ensure sync is enabled
                updateKnownPeer(displayName: peerID.displayName, userId: userId)
                
                // Already connected? Skip invitation
                let connectedPeerIDs = self.sessionConnectedPeers
                if connectedPeerIDs.contains(where: { $0.displayName == peerID.displayName }) {
                    print("⚠️ Peer already connected in session, not inviting again: \(peerID.displayName)")
                    return
                }
                
                if shouldInitiateConnection(to: userId) {
                    print("🤝 Auto-connecting to peer that is now nearby: \(peerID.displayName) (we are the leader)")
                    self.invitePeer(self.discoveredPeers[index])
                } else {
                    print("⏳ Waiting for peer to initiate connection: \(peerID.displayName) (they are the leader)")
                }
            } else if let userId = userId {
                print("ℹ️ Not auto-connecting to \(peerID.displayName) - shouldAutoConnect: \(shouldAutoConnect(to: userId))")
            }
        } else {
            print("ℹ️ Peer not eligible for auto-connect due to current state: \(self.discoveredPeers[index].state.rawValue)")
        }
    }
    
    private func handleNewPeerFound(peerID: MCPeerID, info: [String: String]?, userId: String?, isKnownPeer: Bool) {
        // Before adding a new peer, check if we already know this user ID from another peer
        // This handles the case where the app restarts and rediscovers a known peer with a new peerID object
        var existingUserIdPeerIndex: Int? = nil
        
        if let userId = userId {
            existingUserIdPeerIndex = self.discoveredPeers.firstIndex(where: { 
                $0.discoveryInfo?["userId"] == userId 
            })
        }
        
        if let existingIndex = existingUserIdPeerIndex, isKnownPeer {
            handleExistingUserIdFound(existingIndex: existingIndex, peerID: peerID, info: info, userId: userId)
        } else {
            handleTotallyNewPeerFound(peerID: peerID, info: info, userId: userId, isKnownPeer: isKnownPeer)
        }
    }
    
    private func handleExistingUserIdFound(existingIndex: Int, peerID: MCPeerID, info: [String: String]?, userId: String?) {
        // We already have a peer with this userId, update it instead of adding a new one
        print("🔄 Found peer with existing userId: \(userId ?? "unknown"), updating instead of adding new")
        
        // Store the current state before updating
        let currentState = self.discoveredPeers[existingIndex].state
        
        // Update the existing peer with new peerID but maintain state if disconnected
        let updatedState = (currentState == PeerState.disconnected) ? PeerState.disconnected : PeerState.discovered
        self.discoveredPeers[existingIndex].peerId = peerID
        self.discoveredPeers[existingIndex].discoveryInfo = info
        self.discoveredPeers[existingIndex].state = updatedState
        self.discoveredPeers[existingIndex].isNearby = true
        
        print("🔄 Updated existing peer with userId \(userId ?? "unknown") to state: \(updatedState.rawValue)")
        
        // If this is a peer we should auto-connect to and was previously disconnected,
        // AND if we should be the one to initiate (deterministic leader election)
        if updatedState == .disconnected, let userId = userId, shouldAutoConnect(to: userId) {
            if shouldInitiateConnection(to: userId) {
                print("🤝 Auto-connecting to previously known peer with new peerID: \(peerID.displayName) (we are the leader)")
                self.invitePeer(self.discoveredPeers[existingIndex])
            } else {
                print("⏳ Waiting for peer to initiate connection: \(peerID.displayName) (they are the leader)")
            }
        }
    }
    
    private func handleTotallyNewPeerFound(peerID: MCPeerID, info: [String: String]?, userId: String?, isKnownPeer: Bool) {
        // Add new peer to discovered list
        let initialState: PeerState = isKnownPeer ? PeerState.disconnected : PeerState.discovered
        let newPeerInfo = PeerInfo(
            peerId: peerID,
            state: initialState,
            discoveryInfo: info,
            isNearby: true
        )
        self.discoveredPeers.append(newPeerInfo)
        
        print("➕ Added new peer to discovered list: \(peerID.displayName) with state: \(initialState.rawValue)")
        self.messages.append(ChatMessage.systemMessage("Discovered new peer \(peerID.displayName)"))
        
        // If this is a new peer with userId, add it to known peers to enable auto-connection
        if let userId = userId {
            // Always update the known peer record with latest info
            print("📝 Updating known peer info for: \(peerID.displayName)")
            updateKnownPeer(displayName: peerID.displayName, userId: userId)
            
            // Check if auto-connect is possible
            if shouldAutoConnect(to: userId) {
                // Already connected? Skip invitation
                let connectedPeerIDs = self.sessionConnectedPeers
                if connectedPeerIDs.contains(where: { $0.displayName == peerID.displayName }) {
                    print("⚠️ Peer already connected in session, not inviting again: \(peerID.displayName)")
                    return
                }
                
                // Use deterministic leader election to decide who initiates
                if shouldInitiateConnection(to: userId) {
                    print("🤝 Auto-connecting to newly added peer: \(peerID.displayName) (we are the leader)")
                    self.invitePeer(newPeerInfo)
                } else {
                    print("⏳ Waiting for peer to initiate connection: \(peerID.displayName) (they are the leader)")
                }
            } else {
                print("ℹ️ Not auto-connecting to \(peerID.displayName) - shouldAutoConnect: \(shouldAutoConnect(to: userId))")
            }
        } else {
            print("ℹ️ New peer doesn't have userId in discoveryInfo: \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        
        // Get app state information for diagnostics
        #if canImport(UIKit)
        let appStateString = UIApplication.shared.applicationState == .active ? "active" : 
                            UIApplication.shared.applicationState == .background ? "background" : "inactive"
        print("📱 App state when lost peer: \(appStateString)")
        #endif
        
        DispatchQueue.main.async {
            self.processPeerLostEvent(peerID: peerID)
        }
    }
    
    private func processPeerLostEvent(peerID: MCPeerID) {
        // If the peer is in our discovered list
        if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            let currentState = self.discoveredPeers[index].state
            let userId = self.discoveredPeers[index].discoveryInfo?["userId"]
            
            // When a peer is lost, it's definitely not nearby anymore
            self.discoveredPeers[index].isNearby = false
            print("📡 Marking peer as not nearby: \(peerID.displayName)")
            
            // Log info about the lost peer to help understand why it's being removed
            print("ℹ️ Lost peer details: peerID=\(peerID.displayName), state=\(currentState.rawValue), userId=\(userId ?? "unknown")")
            let connectedPeerIDs = self.sessionConnectedPeers
            print("ℹ️ Connected peers count: \(connectedPeerIDs.count)")
            print("ℹ️ Is known peer? \(userId != nil && self.knownPeers.contains(where: { $0.userId == userId }) ? "Yes" : "No")")
            print("ℹ️ Is sync enabled? \(userId != nil && self.syncEnabledPeers.contains(userId!) ? "Yes" : "No")")
            
            // Handle peer based on current state
            switch currentState {
            case .connected:
                handleLostConnectedPeer(peerID: peerID)
            case .disconnected:
                // Keep disconnected peers in the list but mark as not nearby
                self.discoveredPeers[index].isNearby = false
                print("🔄 Keeping disconnected peer in the list: \(peerID.displayName) (marked as not nearby)")
            case .rejected:
                // If rejected, keep it in the list (important for retrying connections)
                print("🔄 Keeping rejected peer in the list: \(peerID.displayName)")
            case .discovered:
                handleLostDiscoveredPeer(index: index, peerID: peerID, userId: userId)
            case .connecting, .invitationSent, .invitationReceived:
                handleLostTransientPeer(index: index, peerID: peerID, userId: userId)
            }
        } else {
            print("ℹ️ Lost peer not found in discoveredPeers: \(peerID.displayName)")
        }
        
        // Remove any pending invitations
        self.pendingInvitations.removeValue(forKey: peerID)
    }
    
    private func handleLostConnectedPeer(peerID: MCPeerID) {
        // For connected peers, we should KEEP them in the discovered list so they can appear in
        // the UI with the appropriate state. The session delegate will properly handle
        // disconnection when it receives the state change notification.
        // 
        // This is critical for backgrounded devices since we need to maintain UI awareness of the peer
        // and be ready for when they return to foreground.
        print("ℹ️ Keeping connected peer that was lost: \(peerID.displayName)")
        // Update message only if peer is not actually still connected (could be app state changes)
        let connectedPeerIDs = self.sessionConnectedPeers
        if !connectedPeerIDs.contains(peerID) {
            print("🔄 Peer no longer appears in session's connected peers list")
            self.messages.append(ChatMessage.systemMessage("Lost connection to \(peerID.displayName)"))
        } else {
            print("ℹ️ Peer still appears in session's connected peers list - keeping without changes")
        }
    }
    
    private func handleLostDiscoveredPeer(index: Int, peerID: MCPeerID, userId: String?) {
        // For discovered peers, if they're known or sync-enabled, mark as disconnected
        if let userId = userId,
           self.knownPeers.contains(where: { $0.userId == userId }) || 
           self.syncEnabledPeers.contains(userId) {
            self.discoveredPeers[index].state = PeerState.disconnected
            self.discoveredPeers[index].isNearby = false
            print("🔄 Changing discovered peer to disconnected state: \(peerID.displayName)")
        } else {
            // Only remove unknown discovered peers
            print("🔄 Removing unknown discovered peer: \(peerID.displayName)")
            self.discoveredPeers.remove(at: index)
        }
    }
    
    private func handleLostTransientPeer(index: Int, peerID: MCPeerID, userId: String?) {
        // For transient states, only remove if not in session.connectedPeers
        let connectedPeerIDs = self.sessionConnectedPeers
        if !connectedPeerIDs.contains(peerID) {
            // Check if this is a known peer we should keep
            if let userId = userId,
               (self.knownPeers.contains(where: { $0.userId == userId }) || 
                self.syncEnabledPeers.contains(userId)) {
                // For known peers, mark as disconnected when lost
                self.discoveredPeers[index].state = PeerState.disconnected
                self.discoveredPeers[index].isNearby = false
                print("🔄 Changing transient state peer to disconnected state: \(peerID.displayName)")
            } else {
                // Unknown peer in transient state, safe to remove
                print("🔄 Removing unknown peer: \(peerID.displayName) (not in known peers list)")
                self.discoveredPeers.remove(at: index)
                self.messages.append(ChatMessage.systemMessage("Lost sight of peer \(peerID.displayName)"))
            }
        } else {
            print("⚠️ Peer not in session's connected peers but keeping it: \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        let mcError = error as NSError
        if mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("🔍 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Failed to start browsing - \(error.localizedDescription)"))
            // Reset state
            self.isBrowsing = false
        }
    }
}