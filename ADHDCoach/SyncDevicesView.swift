import SwiftUI
import MultipeerConnectivity

struct SyncDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var multipeerService: MultipeerService
    
    @State private var selectedPeer: MultipeerService.PeerInfo?
    @State private var showForgetConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var currentInvitationPeer: MultipeerService.PeerInfo?
    @State private var showConnectionRequestAlert = false
    
    // Helper computed properties
    private var deviceType: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
    
    private var deviceName: String {
        multipeerService.myPeerId.displayName
    }
    
    // Helper methods to simplify complex expressions for Swift type-checking
    private func getMyDevicesPeers() -> [MultipeerService.PeerInfo] {
        return multipeerService.discoveredPeers.filter { peer in
            // Include connected peers
            if peer.state == MultipeerService.PeerState.connected {
                return true
            }
            
            // Include disconnected peers (previously connected)
            if peer.state == MultipeerService.PeerState.disconnected {
                return true
            }
            
            // Get the userId if available
            let userId = peer.discoveryInfo?["userId"]
            
            // Check if this is a known peer with sync enabled
            let isKnownSyncEnabled = userId != nil && 
                                    multipeerService.isSyncEnabled(for: userId!)
            
            // Don't include rejected peers regardless of other conditions
            if peer.state == MultipeerService.PeerState.rejected {
                return false
            }
            
            // Include all connection state peers (discovered, connecting, invitationSent)
            // that are known and have sync enabled
            if isKnownSyncEnabled {
                return true
            }
            
            return false
        }
    }
    
    private func getOtherDevicesPeers() -> [MultipeerService.PeerInfo] {
        return multipeerService.discoveredPeers.filter { peer in
            // Exclude connected peers (already in My Devices)
            if peer.state == MultipeerService.PeerState.connected {
                return false
            }
            
            // Exclude disconnected peers (already in My Devices)
            if peer.state == MultipeerService.PeerState.disconnected {
                return false
            }
            
            // Get the userId if available
            let userId = peer.discoveryInfo?["userId"]
            
            // Check if this is a known peer with sync enabled
            let isKnownSyncEnabled = userId != nil && 
                                  multipeerService.isSyncEnabled(for: userId!)
            
            // Exclude ALL known sync-enabled peers (they go in My Devices)
            // except for rejected ones
            if isKnownSyncEnabled && peer.state != MultipeerService.PeerState.rejected {
                return false
            }
            
            // Include all other non-connected peers:
            // - All peers without sync enabled in any state
            // - Rejected peers (even if they were known/sync enabled)
            return true
        }
    }
    
    // Helper method to get status color for peer
    private func statusColor(for peer: MultipeerService.PeerInfo) -> Color {
        switch peer.state {
        case .connected:
            return .green
        case .connecting, .invitationSent:
            return .orange
        case .disconnected:
            return peer.isNearby ? .yellow : .gray
        case .discovered:
            return .blue
        case .rejected:
            return .red
        default:
            return .gray
        }
    }
    
    // Helper method to get status text for peer
    private func statusText(for peer: MultipeerService.PeerInfo) -> String {
        switch peer.state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .invitationSent:
            return "Invitation Sent"
        case .disconnected:
            return peer.isNearby ? "Not Connected, Nearby" : "Not Connected"
        case .discovered:
            return "Available"
        case .rejected:
            return "Invitation Declined"
        default:
            return "Unknown"
        }
    }
    
    // Helper method to get button text based on peer state
    private func actionButtonText(for peer: MultipeerService.PeerInfo) -> String {
        switch peer.state {
        case .discovered:
            return "Connect"
        case .disconnected:
            return peer.isNearby ? "Reconnect" : "Connect"
        case .rejected:
            return "Try Again"
        default:
            return ""
        }
    }
    
    // Determine if peer state is actionable (can be tapped to connect)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        // Discovered, disconnected and rejected peers can be tapped to connect/retry
        return state == .discovered || state == .rejected || state == .disconnected
    }
    
    // Handle peer action based on its current state
    private func handlePeerAction(_ peer: MultipeerService.PeerInfo) {
        if peer.state == .discovered || peer.state == .rejected || peer.state == .disconnected {
            // Invite peer (or retry invitation for rejected/disconnected peers)
            print("👆 User tapped \(peer.peerId.displayName) with state \(peer.state.rawValue)")
            multipeerService.invitePeer(peer)
        }
    }
    
    var body: some View {
        List {
            // Top section: Sync Devices with toggle
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Devices")
                        .font(.headline)
                    
                    Text("Connect your Mac, iPhone, or iPad to seamlessly sync chat history and memories via peer-to-peer networking—no internet required.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                
                Toggle("Sync Devices", isOn: $multipeerService.isSyncEnabled)
                    .onChange(of: multipeerService.isSyncEnabled) { oldValue, newValue in
                        if newValue {
                            multipeerService.startHosting()
                            multipeerService.startBrowsing()
                        } else {
                            multipeerService.disconnect()
                        }
                    }
            } footer: {
                Text("This \(deviceType) is discoverable as \"\(deviceName)\" while Sync Devices is enabled.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            // My Devices section
            Section(header: Text("MY DEVICES").font(.footnote).foregroundColor(.secondary)) {
                let myDevicesPeers = getMyDevicesPeers()
                
                if !myDevicesPeers.isEmpty {
                    ForEach(myDevicesPeers) { peer in
                        deviceRowView(for: peer)
                    }
                } else {
                    Text("No devices")
                        .foregroundColor(.secondary)
                        .italic()
                        .font(.subheadline)
                }
            }
            
            // Other Devices section
            Section(header: Text("OTHER DEVICES").font(.footnote).foregroundColor(.secondary)) {
                let otherDevicesPeers = getOtherDevicesPeers()
                
                if !otherDevicesPeers.isEmpty {
                    ForEach(otherDevicesPeers) { peer in
                        deviceRowView(for: peer)
                    }
                } else {
                    Text("No devices")
                        .foregroundColor(.secondary)
                        .italic()
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Sync Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme)
        .applyThemeColor()
        .listStyle(InsetGroupedListStyle())
        
        // Forget device alert
        .alert("Forget Device", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            
            Button("Forget", role: .destructive) {
                if let peer = selectedPeer, let userId = peer.discoveryInfo?["userId"] {
                    multipeerService.forgetDevice(userId: userId)
                }
                selectedPeer = nil
            }
        } message: {
            if let peer = selectedPeer {
                Text("Do you want to forget device \"\(peer.peerId.displayName)\"? This will remove it from known peers.")
            } else {
                Text("Do you want to forget this device?")
            }
        }
        
        // Block device alert
        .alert("Block Device", isPresented: $showBlockConfirmation) {
            Button("Cancel", role: .cancel) { }
            
            Button("Block", role: .destructive) {
                if let peer = selectedPeer, let userId = peer.discoveryInfo?["userId"] {
                    multipeerService.blockUser(userId: userId)
                }
                selectedPeer = nil
            }
        } message: {
            if let peer = selectedPeer {
                Text("Do you want to block device \"\(peer.peerId.displayName)\"? This will prevent it from connecting to you in the future.")
            } else {
                Text("Do you want to block this device?")
            }
        }
        
        // Connection request alert
        .alert("Connection Request", isPresented: $showConnectionRequestAlert) {
            Button("Connect") {
                if let peer = currentInvitationPeer {
                    // The invitation was rejected by default, but the user wants to connect,
                    // so we'll invite the peer ourselves
                    multipeerService.invitePeer(peer)
                    multipeerService.updatePeerState(peer.peerId, to: .invitationSent, reason: "User initiated connection")
                }
                currentInvitationPeer = nil
            }
            Button("Ignore", role: .cancel) {
                if let peer = currentInvitationPeer {
                    // The invitation was already rejected, just update UI
                    multipeerService.updatePeerState(peer.peerId, to: .rejected, reason: "User confirmed rejection")
                }
                currentInvitationPeer = nil
            }
        } message: {
            if let peer = currentInvitationPeer {
                Text("\(peer.peerId.displayName) wants to connect. Would you like to connect to this device?")
            } else {
                Text("A device wants to connect. Would you like to connect to this device?")
            }
        }
        .onAppear {
            // Record that we want to be notified of invitation events
            multipeerService.pendingInvitationHandler = { (peerID, invitationHandler) in
                // Non-escaping parameters must be used immediately or discarded
                // We'll decide whether to accept based on whether the peer is already known
                
                // Check if this is a known peer with sync enabled
                let userId = multipeerService.discoveredPeers.first(where: { $0.peerId == peerID })?.discoveryInfo?["userId"]
                let shouldAutoAccept = userId != nil && multipeerService.isSyncEnabled(for: userId!)
                
                if shouldAutoAccept {
                    // Auto-accept for known peers with sync enabled
                    print("🤝 Auto-accepting invitation from known peer: \(peerID.displayName)")
                    invitationHandler(true, multipeerService.session)
                } else {
                    // For unknown peers, reject by default for security
                    // The user will need to initiate the connection from their end
                    print("🛑 Auto-rejecting invitation from unknown peer: \(peerID.displayName)")
                    invitationHandler(false, nil)
                    
                    // But still notify the user so they can connect if they want
                    DispatchQueue.main.async {
                        // Find or create a PeerInfo object to show in the UI
                        let existingPeer = multipeerService.discoveredPeers.first(where: { $0.peerId == peerID })
                        
                        if let peer = existingPeer {
                            // Use existing peer
                            self.currentInvitationPeer = peer
                        } else {
                            // Create a new peer object
                            let newPeer = MultipeerService.PeerInfo(
                                peerId: peerID,
                                state: .invitationReceived,
                                discoveryInfo: nil
                            )
                            self.currentInvitationPeer = newPeer
                        }
                        
                        // Show alert to let the user know about the invitation
                        self.showConnectionRequestAlert = true
                    }
                }
            }
        }
        .onDisappear {
            // Clear the invitation handler when the view disappears
            multipeerService.pendingInvitationHandler = nil
        }
    }
    
    // Helper view to create consistent device rows in the list
    @ViewBuilder
    private func deviceRowView(for peer: MultipeerService.PeerInfo) -> some View {
        HStack {
            // Device name and status
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.peerId.displayName)
                    .font(.system(size: 16))
                Text(statusText(for: peer))
                    .font(.caption)
                    .foregroundColor(statusColor(for: peer))
            }
            
            Spacer()
            
            // Action button based on peer state
            if isActionable(peer.state) {
                Button(action: {
                    handlePeerAction(peer)
                }) {
                    Text(actionButtonText(for: peer))
                        .font(.subheadline)
                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                }
                .buttonStyle(.plain)
            } else if peer.state == .connected {
                // For connected peers, show a "Connected" indicator
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if peer.state == .invitationSent {
                // For peers with sent invitations, show a waiting indicator
                Image(systemName: "hourglass")
                    .foregroundColor(.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActionable(peer.state) {
                handlePeerAction(peer)
            }
        }
        .contextMenu {
            if peer.discoveryInfo?["userId"] != nil {
                Button(action: {
                    selectedPeer = peer
                    showForgetConfirmation = true
                }) {
                    Label("Forget Device", systemImage: "trash")
                }
                
                Button(action: {
                    selectedPeer = peer
                    showBlockConfirmation = true
                }) {
                    Label("Block Device", systemImage: "nosign")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SyncDevicesView()
            .environmentObject(ThemeManager())
            .environmentObject(MultipeerService())
    }
}