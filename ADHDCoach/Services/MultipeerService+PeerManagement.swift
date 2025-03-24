//
//  MultipeerService+PeerManagement.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/22/25.
//

import Foundation
import MultipeerConnectivity

/// Extension for MultipeerService to handle peer management
extension MultipeerService {
    // MARK: - Peer State Management
    
    /// Helper to update peer state in the discoveredPeers array
    func updatePeerState(_ peerId: MCPeerID, to state: PeerState, reason: String = "No reason provided") {
        DispatchQueue.main.async {
            let oldState: PeerState?
            
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerId }) {
                oldState = self.discoveredPeers[index].state
                let wasNearby = self.discoveredPeers[index].isNearby
                
                // Only log if state actually changed
                if oldState != state {
                    print("🔄 Peer state change: \(peerId.displayName) changed from \(oldState!.rawValue) to \(state.rawValue). Reason: \(reason)")
                    self.discoveredPeers[index].state = state
                    
                    // When changing to connecting or connected state, peer must be nearby
                    if state == .connecting || state == .connected {
                        if !wasNearby {
                            self.discoveredPeers[index].isNearby = true
                            print("📡 Marking peer as nearby due to connection state: \(peerId.displayName)")
                        }
                    }
                }
            } else {
                // Add the peer if it doesn't exist yet (for proactive approaches)
                oldState = nil
                
                // When adding a new peer with connecting or connected state, it's definitely nearby
                let isNearby = (state == .connecting || state == .connected)
                
                self.discoveredPeers.append(PeerInfo(
                    peerId: peerId,
                    state: state,
                    isNearby: isNearby
                ))
                
                print("➕ New peer added: \(peerId.displayName) with initial state \(state.rawValue). Reason: \(reason)")
                if isNearby {
                    print("📡 New peer marked as nearby due to connection state")
                }
            }
            
            // Log section placement information
            let userIdInfo = self.discoveredPeers.first(where: { $0.peerId == peerId })?.discoveryInfo?["userId"] ?? "unknown"
            let isSyncEnabled = userIdInfo != "unknown" && self.isSyncEnabled(for: userIdInfo)
            
            if state == .connected || isSyncEnabled {
                print("📱 Device placement: \(peerId.displayName) will appear in 'My Devices' section (connected: \(state == .connected), sync enabled: \(isSyncEnabled))")
            } else {
                print("📱 Device placement: \(peerId.displayName) will appear in 'Other Devices' section")
            }
        }
    }
    
    // MARK: - Known Peers Management
    
    /// Update or add a known peer
    func updateKnownPeer(displayName: String, userId: String) {
        DispatchQueue.main.async {
            // Check if this peer is already known
            if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                // Update existing entry with new display name and timestamp, preserving sync status
                var updatedPeer = KnownPeerInfo(
                    displayName: displayName,
                    userId: userId,
                    lastSeen: Date()
                )
                // Maintain existing sync status
                updatedPeer.syncEnabled = self.knownPeers[index].syncEnabled
                
                // Add to the sync enabled peers set if not already there
                // This ensures previously known peers are automatically included in sync
                if !self.syncEnabledPeers.contains(userId) {
                    print("🔄 Adding previously known user ID to sync enabled peers: \(userId)")
                    self.syncEnabledPeers.insert(userId)
                    self.saveSyncEnabledPeers()
                    updatedPeer.syncEnabled = true
                }
                
                self.knownPeers[index] = updatedPeer
            } else {
                // Add new known peer (automatically enable sync for newly discovered peers)
                let newPeer = KnownPeerInfo(
                    displayName: displayName,
                    userId: userId,
                    lastSeen: Date(),
                    syncEnabled: true
                )
                self.knownPeers.append(newPeer)
                
                // Add to sync enabled peers Set
                self.syncEnabledPeers.insert(userId)
                self.saveSyncEnabledPeers()
            }
            
            self.saveKnownPeers()
        }
    }
    
    // MARK: - Sync Management
    
    /// Toggle sync for a specific peer by userId
    func toggleSync(for userId: String) {
        DispatchQueue.main.async {
            let newSyncState: Bool
            
            if self.syncEnabledPeers.contains(userId) {
                // Disable sync
                self.syncEnabledPeers.remove(userId)
                newSyncState = false
                print("🔄 Disabled sync for user: \(userId)")
            } else {
                // Enable sync
                self.syncEnabledPeers.insert(userId)
                newSyncState = true
                print("🔄 Enabled sync for user: \(userId)")
            }
            
            // Update the syncEnabled flag in knownPeers
            if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                self.knownPeers[index].syncEnabled = newSyncState
                self.saveKnownPeers()
            }
            
            self.saveSyncEnabledPeers()
            
            // Find any related discovered peers to log section change
            let affectedPeers = self.discoveredPeers.filter { peer in
                peer.discoveryInfo?["userId"] == userId
            }
            
            for peer in affectedPeers {
                if newSyncState {
                    if peer.state != .connected {
                        print("📱 Section change: \(peer.peerId.displayName) will move from 'Other Devices' to 'My Devices' section (reason: sync enabled)")
                    }
                } else {
                    if peer.state != .connected {
                        print("📱 Section change: \(peer.peerId.displayName) will move from 'My Devices' to 'Other Devices' section (reason: sync disabled)")
                    } else {
                        print("📱 No section change for \(peer.peerId.displayName) - remains in 'My Devices' (reason: still connected)")
                    }
                }
            }
            
            // Add system message
            let status = newSyncState ? "enabled" : "disabled"
            self.messages.append(ChatMessage.systemMessage("Sync \(status) for peer"))
        }
    }
    
    /// Check if a device is sync-enabled
    func isSyncEnabled(for userId: String) -> Bool {
        return syncEnabledPeers.contains(userId)
    }
    
    // MARK: - Sync History Management
    
    /// Send all messages to a newly connected peer to sync histories
    func syncMessages(with peerID: MCPeerID) {
        guard !messages.isEmpty else { return }
        
        do {
            // Create a special sync message that contains the entire message history
            let syncMessage = SyncMessage(messages: messages)
            let syncData = try JSONEncoder().encode(syncMessage)
            
            try session.send(syncData, toPeers: [peerID], with: .reliable)
            print("🔄 Sent message sync to \(peerID.displayName) with \(messages.count) messages")
        } catch {
            print("❌ Failed to sync messages: \(error.localizedDescription)")
        }
    }
    
    /// Resolve message sync conflict by choosing either local or remote messages
    func resolveMessageSyncConflict(useRemote: Bool) {
        guard hasPendingSyncDecision, let peerID = pendingSyncPeer else {
            print("❌ No sync conflict to resolve")
            return
        }
        
        guard let remoteMessages = pendingSyncs[peerID] else {
            print("❌ Cannot find remote messages for \(peerID.displayName)")
            return
        }
        
        // First, send the decision to the other device
        sendSyncDecision(useRemote: useRemote, toPeer: peerID)
        
        // Then apply the decision locally
        applySyncDecision(useRemote: useRemote, peerID: peerID, remoteMessages: remoteMessages)
    }
    
    // MARK: - User Blocking
    
    /// Block a user by userId
    func blockUser(userId: String) {
        DispatchQueue.main.async {
            self.blockedPeers.insert(userId)
            print("🚫 Blocked user: \(userId)")
            self.messages.append(ChatMessage.systemMessage("Blocked peer"))
            
            // Disconnect from any connected peers with this userId
            self.disconnectBlockedUser(userId: userId)
            
            self.saveBlockedPeers()
        }
    }
    
    /// Unblock a user by userId
    func unblockUser(userId: String) {
        DispatchQueue.main.async {
            self.blockedPeers.remove(userId)
            print("✅ Unblocked user: \(userId)")
            self.messages.append(ChatMessage.systemMessage("Unblocked peer"))
            
            self.saveBlockedPeers()
        }
    }
    
    /// Check if a user is blocked
    func isUserBlocked(_ userId: String) -> Bool {
        return blockedPeers.contains(userId)
    }
    
    /// Check if we should auto-connect to a user
    func shouldAutoConnect(to userId: String) -> Bool {
        // Auto-connect only to mutual known peers (peers that are in knownPeers and have sync enabled)
        return !isUserBlocked(userId) && 
               knownPeers.contains(where: { $0.userId == userId }) && 
               syncEnabledPeers.contains(userId)
    }
    
    /// Determine if this device should initiate the connection based on deterministic leader election
    /// Uses UUID comparison to ensure only one side initiates, preventing race conditions
    func shouldInitiateConnection(to remoteUserId: String) -> Bool {
        guard let remoteUUID = UUID(uuidString: remoteUserId) else {
            // If can't parse remote UUID, default to initiating connection
            print("⚠️ Could not parse remote UUID, defaulting to initiating connection")
            return true
        }
        
        // Get string representations for clear logging
        let localUUIDString = self.userId.uuidString
        let remoteUUIDString = remoteUserId
        
        // Compare UUIDs lexicographically - device with "lower" UUID is the leader and initiates
        let shouldInitiate = self.userId.uuidString.compare(remoteUserId) == .orderedAscending
        
        print("🔄 Leadership determination:")
        print("   Local UUID: \(localUUIDString)")
        print("   Remote UUID: \(remoteUUIDString)")
        print("   Result: \(shouldInitiate ? "We are the leader" : "They are the leader")")
        
        return shouldInitiate
    }
    
    // MARK: - Device Management
    
    /// Forget a device - remove from known peers, sync-enabled peers, and optionally block
    func forgetDevice(userId: String, andBlock: Bool = false) {
        print("🧹 Forgetting device with userId: \(userId)")
        
        // Perform UI-related operations on the main thread
        DispatchQueue.main.async {
            // Send forget request to connected peers if possible
            // This will attempt to have the other device also forget us (best-effort)
            self.sendForgetRequest(forUserId: userId)
            
            // Remove from known peers
            self.knownPeers.removeAll { $0.userId == userId }
            
            // Remove from sync-enabled peers
            self.syncEnabledPeers.remove(userId)
            
            // Update discovered peers
            for index in (0..<self.discoveredPeers.count).reversed() {
                if self.discoveredPeers[index].discoveryInfo?["userId"] == userId {
                    let peer = self.discoveredPeers[index]
                    
                    if self.discoveredPeers[index].isNearby {
                        // If the peer is nearby, we update its state to "discovered" instead of
                        // removing it, so it will appear in the "Other Devices" section
                        self.discoveredPeers[index].state = PeerState.discovered
                        print("🔄 Peer \(peer.peerId.displayName) forgotten - moved to 'Other Devices' section")
                    } else {
                        // If not nearby, remove it completely
                        self.discoveredPeers.remove(at: index)
                        print("🔄 Peer \(peer.peerId.displayName) forgotten and removed (not nearby)")
                    }
                }
            }
            
            // Always disconnect active connections when forgetting
            self.disconnectUser(userId: userId)
            
            // Block if requested
            if andBlock {
                self.blockedPeers.insert(userId)
                // When blocking, always remove from discovered peers
                self.discoveredPeers.removeAll(where: { 
                    $0.discoveryInfo?["userId"] == userId 
                })
                print("🚫 User blocked: \(userId)")
            }
            
            // Save changes
            self.saveKnownPeers()
            self.saveSyncEnabledPeers()
            self.saveBlockedPeers()
            
            self.messages.append(ChatMessage.systemMessage(andBlock ? "Forgot and blocked device" : "Forgot device"))
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Send the sync decision to the other device
    private func sendSyncDecision(useRemote: Bool, toPeer peerID: MCPeerID) {
        // Create a decision message
        // If we choose useRemote=true (we want to use their messages), we send "useRemote=true" 
        // so they know we're adopting their messages and they should keep their history
        // If we choose useRemote=false (we want to keep our messages), we send "useRemote=false"
        // so they know we're keeping our history and they should adopt our messages
        let decision = SyncDecision(useRemote: useRemote)
        
        do {
            let decisionData = try JSONEncoder().encode(decision)
            try self.session.send(decisionData, toPeers: [peerID], with: MCSessionSendDataMode.reliable)
            print("📤 Sent sync decision (\(useRemote ? "use remote" : "keep local")) to \(peerID.displayName)")
        } catch {
            print("❌ Failed to send sync decision: \(error.localizedDescription)")
        }
    }
    
    /// Apply the sync decision locally
    private func applySyncDecision(useRemote: Bool, peerID: MCPeerID, remoteMessages: [ChatMessage]) {
        if useRemote {
            // Replace our entire message history with the remote one
            print("🔄 Using remote message history from \(peerID.displayName)")
            DispatchQueue.main.async {
                // Temporarily disable saving during batch operations
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                // Create a copy of remote messages
                var newMessages = remoteMessages
                
                // Add info message
                newMessages.append(ChatMessage.systemMessage("Adopted message history from \(peerID.displayName)"))
                
                // Sort by timestamp
                newMessages.sort(by: { $0.timestamp < $1.timestamp })
                
                // Replace our entire message list
                self.messages = newMessages
                
                // Sync with ChatManager using NotificationCenter
                // We need a full history replacement - this requires notifying the app to clear its history
                NotificationCenter.default.post(name: NSNotification.Name("ChatHistoryDeleted"), object: nil)
                
                // Then sync all non-system messages to rebuild the history
                if let callback = self.syncWithChatManager {
                    // Extract only user messages (not system messages)
                    let userMessages = newMessages.filter { !$0.isSystemMessage }
                    
                    if !userMessages.isEmpty {
                        // Extract properties for each message and send to ChatManager
                        let messageArrays = userMessages.map { message -> [Any] in
                            return message.getMessageProperties()
                        }
                        callback(messageArrays)
                        print("🔄 Replaced chat history with \(userMessages.count) messages from \(peerID.displayName)")
                    }
                }
                
                // Restore previous state and trigger a single save
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        } else {
            // Keep our message history and add a system message
            print("🔄 Keeping local message history")
            DispatchQueue.main.async {
                // Temporarily disable saving
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                self.messages.append(ChatMessage.systemMessage("Kept local message history"))
                
                // Restore previous state and trigger a single save
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        }
        
        // Clear the pending sync
        pendingSyncs.removeValue(forKey: peerID)
        pendingSyncPeer = nil
        hasPendingSyncDecision = false
    }
    
    /// Disconnect from a specific user by ID
    private func disconnectUser(userId: String) {
        // Make sure we're on the main thread for all UI updates and property access
        DispatchQueue.main.async {
            // Find all connected peers with this userId
            let peersToDisconnect = self.discoveredPeers.filter { 
                $0.state == .connected && 
                $0.discoveryInfo?["userId"] == userId 
            }.map { $0.peerId }
            
            for peerId in peersToDisconnect {
                // We can't directly disconnect a specific peer in MCSession
                // So we'll need to create a new session without this peer
                print("❌ Disconnecting from user \(userId) on device \(peerId.displayName)")
            }
            
            // If we need to disconnect from specific peers but keep others connected,
            // we'd need to recreate the session and only invite the peers we want to keep
            if !peersToDisconnect.isEmpty {
                print("🔄 Recreating session to remove specific peers")
                
                // Store current browsing and hosting states
                let wasBrowsing = self.isBrowsing
                let wasHosting = self.isHosting
                
                // Stop current browsing and advertising
                if wasBrowsing {
                    self.stopBrowsing()
                }
                if wasHosting {
                    self.stopHosting()
                }
                
                // Disconnect current session
                self.session.disconnect() // This will disconnect all peers
                
                // Create a new session
                self.session = MCSession(
                    peer: self.myPeerId,
                    securityIdentity: nil,
                    encryptionPreference: .required
                )
                self.session.delegate = self
                
                // Update connection state for all peers and remove connected peers
                self.discoveredPeers.removeAll(where: { $0.state == .connected })
                self.connectedPeers = []
                
                // Restart browsing and advertising if they were active
                if wasBrowsing {
                    self.startBrowsing()
                }
                if wasHosting {
                    self.startHosting()
                }
            }
        }
    }
    
    /// Special case for disconnecting blocked users
    private func disconnectBlockedUser(userId: String) {
        disconnectUser(userId: userId)
    }
    
    /// Send a request to other devices to forget this device (best effort)
    private func sendForgetRequest(forUserId userId: String) {
        // Capture session to avoid potential threading issues
        let currentSession = self.session
        
        // Identify peers with the target userId
        let targetPeers = currentSession.connectedPeers.filter { peer in
            // Find the peer in our discoveredPeers list to get its userId
            if let index = discoveredPeers.firstIndex(where: { $0.peerId == peer }),
               let peerUserId = discoveredPeers[index].discoveryInfo?["userId"] {
                // Only target peers with the matching userId
                return peerUserId == userId
            }
            return false
        }
        
        do {
            // Create a forget request using our own userId, so the remote device 
            // knows which userId to forget (our userId, not its own)
            let forgetRequest = ForgetDeviceRequest(userId: self.userId.uuidString)
            let forgetData = try JSONEncoder().encode(forgetRequest)
            
            // Only attempt to send if we have matching peers
            if !targetPeers.isEmpty {
                try currentSession.send(forgetData, toPeers: targetPeers, with: .reliable)
                print("📤 Sent forget request for our userId to \(targetPeers.count) peers with userId \(userId)")
            } else {
                // Also try sending to all connected peers as a fallback
                if !currentSession.connectedPeers.isEmpty {
                    try currentSession.send(forgetData, toPeers: currentSession.connectedPeers, with: .reliable)
                    print("📤 Sent forget request for our userId to all \(currentSession.connectedPeers.count) connected peers (fallback)")
                } else {
                    print("ℹ️ No connected peers to send forget request to")
                }
            }
        } catch {
            print("❌ Failed to send forget request: \(error.localizedDescription)")
        }
    }
    
    /// Message type for sync decision
    struct SyncDecision: Codable {
        var type = "sync_decision"
        let useRemote: Bool // true = sender is using receiver's history, false = sender is keeping their own history
    }
}