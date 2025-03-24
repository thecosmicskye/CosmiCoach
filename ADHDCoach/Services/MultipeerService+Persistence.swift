//
//  MultipeerService+Persistence.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/22/25.
//

import Foundation

/// Extension for MultipeerService to handle data persistence
extension MultipeerService {
    // Make these methods internal instead of private so they can be accessed from other extensions
    // MARK: - Message Persistence
    
    /// Save messages to UserDefaults
    func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: MultipeerService.UserDefaultsKeys.messages)
            print("💾 Saved \(messages.count) messages to UserDefaults")
        } catch {
            print("❌ Failed to save messages: \(error.localizedDescription)")
        }
    }
    
    /// Load messages from UserDefaults
    func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: MultipeerService.UserDefaultsKeys.messages) else {
            print("ℹ️ No messages found in UserDefaults")
            isInitialLoad = false
            return
        }
        
        do {
            let loadedMessages = try JSONDecoder().decode([ChatMessage].self, from: data)
            // Use main thread for UI updates
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                self.messages = loadedMessages
                print("📂 Loaded \(loadedMessages.count) messages from UserDefaults")
                // Set isInitialLoad to false after successfully loading messages
                self.isInitialLoad = false
            }))
        } catch {
            print("❌ Failed to load messages: \(error.localizedDescription)")
            isInitialLoad = false
        }
    }
    
    // MARK: - Known Peers Persistence
    
    /// Save known peers to UserDefaults
    func saveKnownPeers() {
        do {
            let data = try JSONEncoder().encode(knownPeers)
            UserDefaults.standard.set(data, forKey: MultipeerService.UserDefaultsKeys.knownPeers)
            print("💾 Saved \(knownPeers.count) known peers to UserDefaults")
        } catch {
            print("❌ Failed to save known peers: \(error.localizedDescription)")
        }
    }
    
    /// Load known peers from UserDefaults
    func loadKnownPeers() {
        guard let data = UserDefaults.standard.data(forKey: MultipeerService.UserDefaultsKeys.knownPeers) else {
            print("ℹ️ No known peers found in UserDefaults")
            return
        }
        
        do {
            let loadedPeers = try JSONDecoder().decode([KnownPeerInfo].self, from: data)
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                self.knownPeers = loadedPeers
                print("📂 Loaded \(loadedPeers.count) known peers from UserDefaults")
            }))
        } catch {
            print("❌ Failed to load known peers: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Blocked Peers Persistence
    
    /// Save blocked peers to UserDefaults
    func saveBlockedPeers() {
        // Convert Set<String> to Array for encoding
        let blockedArray = Array(blockedPeers)
        UserDefaults.standard.set(blockedArray, forKey: MultipeerService.UserDefaultsKeys.blockedPeers)
        print("💾 Saved \(blockedPeers.count) blocked peers to UserDefaults")
    }
    
    /// Load blocked peers from UserDefaults
    func loadBlockedPeers() {
        guard let blockedArray = UserDefaults.standard.array(forKey: MultipeerService.UserDefaultsKeys.blockedPeers) as? [String] else {
            print("ℹ️ No blocked peers found in UserDefaults")
            return
        }
        
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.blockedPeers = Set(blockedArray)
            print("📂 Loaded \(self.blockedPeers.count) blocked peers from UserDefaults")
        }))
    }
    
    // MARK: - Sync-Enabled Peers Persistence
    
    /// Save sync-enabled peers to UserDefaults
    func saveSyncEnabledPeers() {
        // Convert Set<String> to Array for storage
        let syncArray = Array(syncEnabledPeers)
        UserDefaults.standard.set(syncArray, forKey: MultipeerService.UserDefaultsKeys.syncEnabledPeers)
        print("💾 Saved \(syncEnabledPeers.count) sync-enabled peers to UserDefaults")
    }
    
    /// Load sync-enabled peers from UserDefaults
    func loadSyncEnabledPeers() {
        guard let syncArray = UserDefaults.standard.array(forKey: MultipeerService.UserDefaultsKeys.syncEnabledPeers) as? [String] else {
            print("ℹ️ No sync-enabled peers found in UserDefaults")
            return
        }
        
        DispatchQueue.main.async(execute: DispatchWorkItem(block: {
            self.syncEnabledPeers = Set(syncArray)
            
            // Update the sync status in knownPeers to match
            for userId in syncArray {
                if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                    self.knownPeers[index].syncEnabled = true
                }
            }
            
            print("📂 Loaded \(self.syncEnabledPeers.count) sync-enabled peers from UserDefaults")
        }))
    }
}