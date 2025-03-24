//
//  MultipeerService+MCNearbyServiceAdvertiserDelegate.swift
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

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📩 Received invitation from peer: \(peerID.displayName)")
        
        // Process invitation on the main thread
        DispatchQueue.main.async {
            self.processInvitation(peerID: peerID, context: context, invitationHandler: invitationHandler)
        }
    }
    
    private func processInvitation(peerID: MCPeerID, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Try to decode the context to extract user identity information
        let senderInfo = extractSenderInfo(from: context)
        
        // Check if this user is blocked
        if let userId = senderInfo["userId"], self.isUserBlocked(userId) {
            declineInvitationFromBlockedUser(peerID: peerID, userId: userId, invitationHandler: invitationHandler)
            return
        }
        
        // Only accept if not already connected
        let connectedPeerIDs = self.sessionConnectedPeers
        guard !connectedPeerIDs.contains(peerID) else {
            declineRedundantInvitation(peerID: peerID, invitationHandler: invitationHandler)
            return
        }
        
        // Check if we should auto-accept based on mutual knowledge
        if let userId = senderInfo["userId"], self.shouldAutoConnect(to: userId) {
            autoAcceptInvitation(peerID: peerID, userId: userId, invitationHandler: invitationHandler)
            return
        }
        
        // For peers we don't auto-connect with, store the invitation handler for later use
        handleStandardInvitation(peerID: peerID, senderInfo: senderInfo, invitationHandler: invitationHandler)
    }
    
    private func extractSenderInfo(from context: Data?) -> [String: String] {
        var senderInfo: [String: String] = [:]
        if let context = context {
            do {
                if let contextDict = try JSONSerialization.jsonObject(with: context, options: []) as? [String: String] {
                    senderInfo = contextDict
                    print("📝 Invitation context: \(senderInfo)")
                }
            } catch {
                print("⚠️ Could not parse invitation context: \(error.localizedDescription)")
            }
        }
        return senderInfo
    }
    
    private func declineInvitationFromBlockedUser(peerID: MCPeerID, userId: String, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("🚫 Declining invitation from blocked user: \(peerID.displayName)")
        self.messages.append(ChatMessage.systemMessage("Declined invitation from blocked user \(peerID.displayName)"))
        invitationHandler(false, nil)
    }
    
    private func declineRedundantInvitation(peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("⚠️ Already connected to peer: \(peerID.displayName), declining invitation")
        self.messages.append(ChatMessage.systemMessage("Declining duplicate invitation from \(peerID.displayName)"))
        invitationHandler(false, nil)
    }
    
    private func autoAcceptInvitation(peerID: MCPeerID, userId: String, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // A peer sending an invitation is definitely nearby - set its state
        if let peerIndex = discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            // Always update isNearby for peers sending invitations
            discoveredPeers[peerIndex].isNearby = true
            print("📡 Marking peer as nearby due to received invitation: \(peerID.displayName)")
        }
        
        // Auto-accept since a peer that sends an invitation is definitely nearby
        print("🤝 Auto-accepting invitation from known peer: \(peerID.displayName) with userId: \(userId)")
        
        // Update peer state in discovered peers list
        self.updatePeerState(peerID, to: .connecting, reason: "Auto-accepting invitation from known peer")
        
        self.messages.append(ChatMessage.systemMessage("Auto-accepting invitation from known peer \(peerID.displayName)"))
        
        // We MUST NOT store the invitation handler for auto-accepted invitations
        // Otherwise it will cause duplicate accept attempts
        
        // Accept the invitation
        invitationHandler(true, self.session as MCSession)
    }
    
    private func handleStandardInvitation(peerID: MCPeerID, senderInfo: [String: String], invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Skip auto-rejection logic for known peers with user IDs
        if let userId = senderInfo["userId"], !userId.isEmpty {
            // If this is the first time we see this peer, add it to known peers
            if !self.knownPeers.contains(where: { $0.userId == userId }) {
                print("🆕 First time seeing peer with userId: \(userId), adding to known peers")
                self.updateKnownPeer(displayName: peerID.displayName, userId: userId)
                
                // Auto-accept the first invitation from this peer
                print("✅ Auto-accepting first invitation from new known peer: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Auto-accepting first invitation from \(peerID.displayName)"))
                invitationHandler(true, self.session as MCSession)
                return
            }
        }
        
        // For peers we don't auto-connect with, store the invitation handler for later use
        self.pendingInvitations[peerID] = invitationHandler
        
        // Check if this peer is already in our list
        if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            updateExistingPeerWithInvitation(at: index, peerID: peerID)
        } else {
            addNewPeerFromInvitation(peerID: peerID, senderInfo: senderInfo)
        }
        
        self.messages.append(ChatMessage.systemMessage("Received invitation from \(peerID.displayName)"))
        
        // Notify delegate to immediately show connection request
        self.pendingInvitationHandler?(peerID, invitationHandler)
    }
    
    private func updateExistingPeerWithInvitation(at index: Int, peerID: MCPeerID) {
        // Update existing peer - keep as discovered so it appears in Available list
        let oldState = self.discoveredPeers[index].state
        self.discoveredPeers[index].state = .discovered
        
        // IMPORTANT: Always mark a peer sending an invitation as nearby
        self.discoveredPeers[index].isNearby = true
        
        // Store the userId in discoveryInfo if it wasn't there before
        if let userId = self.discoveredPeers[index].discoveryInfo?["userId"],
           self.knownPeers.contains(where: { $0.userId == userId }) {
            // Make sure this peer is added to knownPeers to allow auto-connection
            self.updateKnownPeer(displayName: peerID.displayName, userId: userId)
        }
        
        print("🔄 Peer state updated: \(peerID.displayName) from \(oldState.rawValue) to discovered. Reason: Received invitation, making peer available for connection")
        print("📡 Marking peer as nearby due to received invitation: \(peerID.displayName)")
    }
    
    private func addNewPeerFromInvitation(peerID: MCPeerID, senderInfo: [String: String]) {
        // Add new peer with discovered state
        self.discoveredPeers.append(PeerInfo(
            peerId: peerID,
            state: .discovered,
            discoveryInfo: senderInfo.isEmpty ? nil : senderInfo,
            isNearby: true
        ))
        
        // If this peer has a userId, add it to known peers to enable auto-connection
        if let userId = senderInfo["userId"] {
            // Update known peers so that future invitations will be auto-accepted
            self.updateKnownPeer(displayName: peerID.displayName, userId: userId)
        }
        
        print("➕ Added peer to discovered list: \(peerID.displayName) (Status: discovered, from invitation)")
        print("📡 New peer marked as nearby due to received invitation")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        let mcError = error as NSError
        if mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("📣 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Failed to start advertising - \(error.localizedDescription)"))
            // Reset state
            self.isHosting = false
        }
    }
}