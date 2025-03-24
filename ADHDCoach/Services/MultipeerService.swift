//
//  MultipeerService.swift
//  CosmicCoach
//
//  Created on 3/22/25.
//

import Foundation
import MultipeerConnectivity
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Main Service Class

class MultipeerService: NSObject, ObservableObject {
    // MARK: - Types
    
    /// Message model to track sender identity
    struct ChatMessage: Identifiable, Codable, Equatable {
        let id: UUID
        let senderId: UUID
        let senderName: String
        let content: String
        let isSystemMessage: Bool
        let timestamp: Date
        let isUser: Bool
        let isComplete: Bool
        
        // Convert from app's ChatMessage model - no longer used directly
        // We'll handle conversion using factory methods instead
        
        // This method is not used anymore - we pass properties as arrays instead
        // We'll comment it out to avoid type confusion
        /*
        func toAppMessage() -> ChatMessage {
            return ChatMessage(
                id: id,
                content: content,
                timestamp: timestamp, 
                isUser: isUser,
                isComplete: isComplete
            )
        }
        */
        
        // Helper method to get properties as an array - this is what we use now
        func getMessageProperties() -> [Any] {
            return [
                id,
                content,
                timestamp,
                isUser,
                isComplete
            ]
        }
        
        static func systemMessage(_ content: String) -> MultipeerService.ChatMessage {
            return MultipeerService.ChatMessage(
                id: UUID(),
                senderId: UUID(), // System messages have random sender IDs
                senderName: "System",
                content: content,
                isSystemMessage: true,
                timestamp: Date(),
                isUser: false,
                isComplete: true
            )
        }
        
        static func userMessage(senderId: UUID, senderName: String, content: String) -> MultipeerService.ChatMessage {
            return MultipeerService.ChatMessage(
                id: UUID(),
                senderId: senderId,
                senderName: senderName,
                content: content,
                isSystemMessage: false,
                timestamp: Date(),
                isUser: true,
                isComplete: true
            )
        }
        
        static func assistantMessage(senderId: UUID, senderName: String, content: String) -> MultipeerService.ChatMessage {
            return MultipeerService.ChatMessage(
                id: UUID(),
                senderId: senderId,
                senderName: senderName,
                content: content,
                isSystemMessage: false,
                timestamp: Date(),
                isUser: false,
                isComplete: true
            )
        }
    }
    
    /// Struct to track peer state information
    struct PeerInfo: Identifiable, Equatable {
        let id: UUID = UUID()
        var peerId: MCPeerID  // Changed from let to var so we can update it
        var state: PeerState
        var discoveryInfo: [String: String]?
        var isNearby: Bool = true // Default to true for newly discovered peers
        
        static func == (lhs: PeerInfo, rhs: PeerInfo) -> Bool {
            // If we have user IDs, compare those instead of peer IDs
            if let lhsUserId = lhs.discoveryInfo?["userId"],
               let rhsUserId = rhs.discoveryInfo?["userId"] {
                return lhsUserId == rhsUserId
            }
            // Fall back to comparing peer IDs if no user IDs are available
            return lhs.peerId == rhs.peerId
        }
    }
    
    /// Enum to track peer states
    enum PeerState: String {
        case discovered = "Discovered"
        case connecting = "Connecting..."
        case connected = "Connected"
        case disconnected = "Not Connected" // Previously connected device that is now disconnected
        case invitationSent = "Invitation Sent"
        case invitationReceived = "Invitation Received"
        case rejected = "Invitation Declined"
    }
    
    /// Structure to track known peer information
    struct KnownPeerInfo: Identifiable, Codable, Equatable {
        // Using var instead of let for id to allow it to be decoded
        var id: UUID = UUID()
        let displayName: String
        let userId: String
        let lastSeen: Date
        var syncEnabled: Bool = false
        
        static func == (lhs: KnownPeerInfo, rhs: KnownPeerInfo) -> Bool {
            return lhs.userId == rhs.userId
        }
    }
    
    /// Special message type for syncing
    struct SyncMessage: Codable {
        var type = "sync"
        let messages: [ChatMessage]
    }
    
    /// Message type for forget device requests
    struct ForgetDeviceRequest: Codable {
        var type = "forget_device"
        let userId: String
    }
    
    
    // MARK: - Constants
    
    /// UserDefaults keys
    enum UserDefaultsKeys {
        static let userId = "CosmicCoach.userId"
        static let messages = "CosmicCoach.multipeer.messages"
        static let peerID = "CosmicCoach.peerID"
        static let peerDisplayName = "CosmicCoach.peerDisplayName"
        static let knownPeers = "CosmicCoach.knownPeers"
        static let blockedPeers = "CosmicCoach.blockedPeers"
        static let syncEnabledPeers = "CosmicCoach.syncEnabledPeers"
        static let enableSync = "CosmicCoach.enableSync"
    }
    
    /// Service type should be a unique identifier, following Bonjour naming conventions:
    /// 1-15 characters, lowercase letters, numbers, and hyphens (no adjacent hyphens)
    let serviceType = "cosmiccoach"
    
    // MARK: - Properties
    
    /// The local peer ID representing this device - now persistent across app launches
    let myPeerId: MCPeerID = {
        let defaults = UserDefaults.standard
        
        // Get the current device name to check for changes
        #if canImport(UIKit)
        let currentDisplayName = UIDevice.current.name
        #else
        let currentDisplayName = Host.current().localizedName ?? "Unknown Mac"
        #endif
        
        // Check for stored display name
        let oldDisplayName = defaults.string(forKey: UserDefaultsKeys.peerDisplayName)
        
        // If we have a previous name and it matches the current name, try to restore the peer ID
        if let oldDisplayName = oldDisplayName, oldDisplayName == currentDisplayName,
           let peerIDData = defaults.data(forKey: UserDefaultsKeys.peerID),
           let savedPeerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIDData) {
            
            print("📱 Loaded saved peer ID: \(savedPeerID.displayName)")
            return savedPeerID
        } else {
            // Create a new peer ID and save it
            #if canImport(UIKit)
            let newPeerId = MCPeerID(displayName: currentDisplayName)
            #else
            let newPeerId = MCPeerID(displayName: currentDisplayName)
            #endif
            
            // Archive the peer ID and save it along with the display name
            if let peerIDData = try? NSKeyedArchiver.archivedData(withRootObject: newPeerId, requiringSecureCoding: true) {
                defaults.set(peerIDData, forKey: UserDefaultsKeys.peerID)
                defaults.set(currentDisplayName, forKey: UserDefaultsKeys.peerDisplayName)
                print("📱 Created and saved new peer ID: \(newPeerId.displayName)")
            } else {
                print("⚠️ Failed to archive peer ID")
            }
            
            return newPeerId
        }
    }()
    
    /// User identity that remains consistent across devices
    let userId: UUID
    private let userName = "Me" // The user is always displayed as "Me"
    
    // MARK: - MultipeerConnectivity objects
    
    /// Active session with other connected peers
    var session: MCSession
    
    /// Advertiser lets others know we're available
    var advertiser: MCNearbyServiceAdvertiser
    
    /// Browser to find other peers
    var browser: MCNearbyServiceBrowser
    
    // MARK: - Published properties
    
    /// Track connected peers
    @Published var connectedPeers: [MCPeerID] = []
    
    /// Track discovered peers and their states
    @Published var discoveredPeers: [PeerInfo] = []
    
    /// Messages array with ChatMessage objects instead of strings
    @Published var messages: [ChatMessage] = [] {
        didSet {
            // Only save messages when actually changed (not during initial load)
            if !isInitialLoad {
                self.saveMessages()
            }
        }
    }
    
    /// Store known and blocked peers
    @Published var knownPeers: [KnownPeerInfo] = []
    @Published var blockedPeers: Set<String> = []
    @Published var syncEnabledPeers: Set<String> = []
    
    /// Published property to indicate if there are pending sync decisions
    @Published var hasPendingSyncDecision = false
    @Published var pendingSyncPeer: MCPeerID? = nil
    
    /// Track if we're currently hosting and browsing
    @Published var isHosting = false
    @Published var isBrowsing = false
    
    /// Published property for sync enabled state
    @Published var isSyncEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: UserDefaultsKeys.enableSync)
            if isSyncEnabled {
                startHosting()
                startBrowsing()
            } else {
                disconnect()
            }
        }
    }
    
    /// Callback for syncing with ChatManager - passes arrays of [id, content, timestamp, isUser, isComplete]
    var syncWithChatManager: (([[Any]]) -> Void)? = nil
    
    // MARK: - Internal properties
    
    /// Flag to prevent saving during initial load
    var isInitialLoad = true
    
    /// Track devices we're syncing with and their message histories
    var pendingSyncs: [MCPeerID: [ChatMessage]] = [:]
    
    /// Store for pending invitations (peerId -> handler)
    var pendingInvitations: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    
    /// Delegate for handling invitations proactively
    var pendingInvitationHandler: ((MCPeerID, (Bool, MCSession?) -> Void) -> Void)?
    
    // MARK: - Helper computed properties
    
    /// Helper property to access session's connected peers
    var sessionConnectedPeers: [MCPeerID] {
        return session.connectedPeers
    }
    
    // MARK: - Initialization
    
    override init() {
        print("🔄 Initializing MultipeerService")
        
        // Load sync enabled state
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableSync)
        
        // Load or create a persistent user ID
        if let storedUserIdString = UserDefaults.standard.string(forKey: UserDefaultsKeys.userId),
           let storedUserId = UUID(uuidString: storedUserIdString) {
            print("📱 Loaded existing user ID: \(storedUserIdString)")
            userId = storedUserId
        } else {
            // Create a new user ID and save it
            let newUserId = UUID()
            UserDefaults.standard.set(newUserId.uuidString, forKey: UserDefaultsKeys.userId)
            print("📱 Created new user ID: \(newUserId.uuidString)")
            userId = newUserId
        }
        
        // Following Apple docs section "Creating a Session"
        // Initialize the session with encryption preference
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        // Initialize the advertiser with our peer ID and service type
        // Include user ID in discovery info to help identify the same user across devices
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: ["app": "CosmicCoach", "userId": userId.uuidString], // Add user identity
            serviceType: serviceType
        )
        
        // Initialize the browser with our peer ID and service type
        browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        
        super.init()
        
        print("🔄 Setting up delegates")
        // Set delegates for callbacks
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        
        // Load saved data
        self.loadMessages()
        self.loadKnownPeers()
        self.loadBlockedPeers()
        self.loadSyncEnabledPeers()
        
        // Start syncing if enabled
        if isSyncEnabled {
            startHosting()
            startBrowsing()
        }
    }
    
    // MARK: - Public Connection Methods
    
    func startHosting() {
        print("📣 Starting advertising for peer ID: \(myPeerId.displayName)")
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.messages.append(ChatMessage.systemMessage("Started advertising as \(self.myPeerId.displayName)"))
        }))
        advertiser.startAdvertisingPeer()
        isHosting = true
    }
    
    func stopHosting() {
        print("🛑 Stopping advertising")
        advertiser.stopAdvertisingPeer()
        isHosting = false
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.messages.append(ChatMessage.systemMessage("Stopped advertising"))
        }))
    }
    
    func startBrowsing() {
        print("🔍 Starting browsing for peers with service type: \(serviceType)")
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.messages.append(ChatMessage.systemMessage("Started looking for peers"))
        }))
        browser.startBrowsingForPeers()
        isBrowsing = true
    }
    
    func stopBrowsing() {
        print("🛑 Stopping browsing")
        browser.stopBrowsingForPeers()
        isBrowsing = false
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.messages.append(ChatMessage.systemMessage("Stopped looking for peers"))
            
            // Clear discovered peers list when stopping browsing
            self.discoveredPeers.removeAll(where: { $0.state == .discovered })
        }))
    }
    
    func disconnect() {
        print("🔌 Disconnecting from all peers")
        session.disconnect()
        stopHosting()
        stopBrowsing()
        
        // When MCF is turned off, don't completely clear discovered peers
        // but update state for known peers
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            // Make a temporary copy to avoid mutation during iteration
            let currentPeers = self.discoveredPeers
            
            // First mark all peers as disconnected and not nearby
            for peer in currentPeers {
                // Get the index in case the array is being modified by other operations
                if let index = self.discoveredPeers.firstIndex(where: { $0.id == peer.id }) {
                    // For connected and sync-enabled peers, set to disconnected
                    if peer.state == PeerState.connected || 
                       (peer.discoveryInfo?["userId"] != nil && 
                        self.syncEnabledPeers.contains(peer.discoveryInfo?["userId"] ?? "")) {
                        self.discoveredPeers[index].state = PeerState.disconnected
                        self.discoveredPeers[index].isNearby = false
                        print("🔌 Setting peer \(peer.peerId.displayName) to disconnected and not nearby")
                    } else if peer.state == PeerState.disconnected {
                        // Already disconnected peers just need to be marked as not nearby
                        self.discoveredPeers[index].isNearby = false
                        print("🔌 Setting disconnected peer \(peer.peerId.displayName) to not nearby")
                    } else {
                        // For non-connected, non-known peers, remove them
                        self.discoveredPeers.remove(at: index)
                        print("🔌 Removing transient peer: \(peer.peerId.displayName)")
                    }
                }
            }
            
            self.messages.append(ChatMessage.systemMessage("Disconnected from all peers"))
        }))
        
        // Clear pending invitations
        pendingInvitations.removeAll()
    }
    
    // MARK: - Peer Invitation Methods
    
    /// Invite a specific peer to connect
    func invitePeer(_ peerInfo: PeerInfo) {
        print("📨 Inviting peer: \(peerInfo.peerId.displayName)")
        
        // Update peer state
        self.updatePeerState(peerInfo.peerId, to: .invitationSent, reason: "User initiated invitation")
        
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.messages.append(ChatMessage.systemMessage("Sending invitation to \(peerInfo.peerId.displayName)"))
        }))
        
        // Include user identity with invitation context
        let invitationContext = ["userId": userId.uuidString, "userName": userName]
        let contextData = try? JSONEncoder().encode(invitationContext)
        browser.invitePeer(peerInfo.peerId, to: session, withContext: contextData, timeout: 60)
    }
    
    /// Accept a pending invitation
    func acceptInvitation(from peerInfo: PeerInfo, accept: Bool) {
        // The peer might not be in discoveredPeers when accepting from a proactive alert
        // so we'll proceed if there's a pending invitation handler
        
        // Check if invitation handler exists for this peer
        if let handler = pendingInvitations[peerInfo.peerId] {
            if accept {
                print("✅ Accepting invitation from: \(peerInfo.peerId.displayName)")
                self.updatePeerState(peerInfo.peerId, to: .connecting, reason: "Invitation accepted by user")
                
                DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                    self.messages.append(ChatMessage.systemMessage("Accepting invitation from \(peerInfo.peerId.displayName)"))
                }))
                
                // Accept the invitation
                handler(true, session)
            } else {
                print("❌ Declining invitation from: \(peerInfo.peerId.displayName)")
                self.updatePeerState(peerInfo.peerId, to: .rejected, reason: "Invitation declined by user")
                
                DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                    self.messages.append(ChatMessage.systemMessage("Declining invitation from \(peerInfo.peerId.displayName)"))
                }))
                
                // Decline the invitation
                handler(false, nil)
            }
            
            // Remove the handler once used
            pendingInvitations.removeValue(forKey: peerInfo.peerId)
        } else {
            print("⚠️ No pending invitation from: \(peerInfo.peerId.displayName)")
        }
    }
    
    // MARK: - Message Methods
    
    /// Send a chat message from the local app to connected peers
    func syncAppMessage(id: UUID, content: String, timestamp: Date, isUser: Bool, isComplete: Bool) {
        // Create a peer message with user identity and preserve the original ID
        let peerMessage: MultipeerService.ChatMessage
        if isUser {
            peerMessage = MultipeerService.ChatMessage(
                id: id,
                senderId: userId,
                senderName: userName,
                content: content,
                isSystemMessage: false,
                timestamp: timestamp,
                isUser: isUser,
                isComplete: isComplete
            )
        } else {
            peerMessage = MultipeerService.ChatMessage(
                id: id,
                senderId: userId,
                senderName: userName,
                content: content,
                isSystemMessage: false,
                timestamp: timestamp,
                isUser: isUser,
                isComplete: isComplete
            )
        }
        
        // Add message to our local peer list if not already there
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            if !self.messages.contains(where: { $0.id == peerMessage.id }) {
                // Prevent redundant saves when adding a single message
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                self.messages.append(peerMessage)
                
                // Restore state and save manually
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        }))
        
        // If we have no connected peers, just save the message locally
        guard !session.connectedPeers.isEmpty else { 
            print("⚠️ No peers connected, message saved locally")
            return 
        }
        
        // Convert chat message to data and send to connected peers
        do {
            let messageData = try JSONEncoder().encode(peerMessage)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            print("✅ Message sent to \(session.connectedPeers.count) peers")
        } catch {
            print("❌ Error sending message: \(error.localizedDescription)")
        }
    }
    
    /// Sync all app messages - not used in current implementation
    func syncAllMessages() {
        // Only sync if there are connected peers
        guard !session.connectedPeers.isEmpty else { 
            print("⚠️ No peers connected, not syncing batch messages")
            return 
        }
        
        // Use our existing messages
        let peerMessages = self.messages
        
        // Create a sync message
        let syncMessage = SyncMessage(messages: peerMessages)
        
        // Send sync message to all connected peers
        do {
            let syncData = try JSONEncoder().encode(syncMessage)
            try session.send(syncData, toPeers: session.connectedPeers, with: .reliable)
            print("✅ Synced \(peerMessages.count) messages to \(session.connectedPeers.count) peers")
        } catch {
            print("❌ Error sending sync message: \(error.localizedDescription)")
        }
    }
    
    // Original message function renamed to maintain compatibility
    func sendMessage(_ message: String) {
        print("📤 Attempting to send message: \(message)")
        
        // Create a chat message with user identity
        let chatMessage = ChatMessage.userMessage(
            senderId: userId,
            senderName: userName,
            content: message
        )
        
        // Add message to our local list
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            // Prevent redundant saves when adding a single message
            let wasInitialLoad = self.isInitialLoad
            self.isInitialLoad = true
            
            self.messages.append(chatMessage)
            
            // Restore state and save manually
            self.isInitialLoad = wasInitialLoad
            if !self.isInitialLoad {
                self.saveMessages()
            }
        }))
        
        // If we have no connected peers, just save the message locally
        guard !session.connectedPeers.isEmpty else { 
            print("⚠️ No peers connected, message saved locally")
            return 
        }
        
        // Convert chat message to data and send to connected peers
        do {
            let messageData = try JSONEncoder().encode(chatMessage)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            print("✅ Message sent to \(session.connectedPeers.count) peers")
        } catch {
            print("❌ Error sending message: \(error.localizedDescription)")
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                // Prevent redundant saves
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                self.messages.append(ChatMessage.systemMessage("Failed to send message - \(error.localizedDescription)"))
                
                // Restore state and save manually
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }))
        }
    }
    
    // Clear all messages
    func clearAllMessages() {
        print("🧹 Clearing all messages")
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            // Keep only a new system message and avoid redundant saves
            let wasInitialLoad = self.isInitialLoad
            self.isInitialLoad = true
            
            self.messages = [ChatMessage.systemMessage("Chat history cleared")]
            
            // Restore state and save manually
            self.isInitialLoad = wasInitialLoad
            if !self.isInitialLoad {
                self.saveMessages()
            }
        }))
    }
    
    // MARK: - App State Handling
    
    /// Call this method when app becomes active
    func handleAppDidBecomeActive() {
        print("🔄 App became active - resuming connections")
        
        // The framework automatically resumes advertising and browsing,
        // but we need to log our state to help with debugging
        
        // Log current state
        print("📊 Current state:")
        print("   isHosting: \(isHosting)")
        print("   isBrowsing: \(isBrowsing)") 
        let connectedPeerIDs = self.sessionConnectedPeers
        print("   connectedPeers: \(connectedPeerIDs.count)")
        print("   discoveredPeers: \(discoveredPeers.count)")
        
        // Restart hosting/browsing if needed
        if isSyncEnabled {
            if !isHosting {
                startHosting()
            }
            if !isBrowsing {
                startBrowsing()
            }
        }
        
        // Session will have been disconnected when app was backgrounded
        // Log all our discovered peers
        print("📋 Current discovered peers after becoming active:")
        for (index, peer) in discoveredPeers.enumerated() {
            print("   \(index): \(peer.peerId.displayName), state: \(peer.state.rawValue), userId: \(peer.discoveryInfo?["userId"] ?? "unknown")")
        }
    }
    
    /// Call this method when app enters background
    func handleAppDidEnterBackground() {
        print("⏸️ App entered background - framework will disconnect session")
        
        // Framework automatically stops advertising, browsing, and disconnects session
        // Just log our current state for debugging
        print("📊 State before backgrounding:")
        print("   isHosting: \(isHosting)")
        print("   isBrowsing: \(isBrowsing)")
        let connectedPeerIDs = self.sessionConnectedPeers
        print("   connectedPeers: \(connectedPeerIDs.count)")
        print("   discoveredPeers: \(discoveredPeers.count)")
    }
}