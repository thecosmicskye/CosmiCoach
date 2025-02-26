# ADHD Coach iOS App

An iOS mobile app that uses Claude 3.7 to help manage Apple Reminders and Calendar, providing empathic coaching for people with ADHD.

## Features

- Chat interface with Claude 3.7 AI
- Integration with Apple Calendar and Reminders
- Persistent memory for the AI to learn about the user over time
- Proactive task prioritization
- Daily check-ins for basics (medication, eating, drinking water)
- Pattern analysis for task completion
- Minimizes decision fatigue by asking one question at a time

## Technical Details

### Architecture

The app is built using SwiftUI and follows a clean architecture pattern with:

- **Models**: Data structures for chat messages, calendar events, and reminders
- **Managers**: Service classes that handle business logic
- **Views**: UI components

### Key Components

- **ChatManager**: Handles communication with Claude API and manages chat history
- **EventKitManager**: Interfaces with Apple's EventKit to access Calendar and Reminders
- **MemoryManager**: Maintains persistent memory for Claude in a markdown file

### Requirements

- iOS 17.0+
- Xcode 15.0+
- Claude API key (from Anthropic)
- Apple Calendar and Reminders access

## Installation

1. Clone the repository
2. Open the project in Xcode
3. Connect your iOS device
4. Build and run the app on your device
5. When first launched, you'll need to:
   - Grant Calendar and Reminders permissions
   - Enter your Claude API key in Settings

## Usage

1. Open the app and you'll be greeted by Claude
2. Type messages to interact with Claude
3. Claude can:
   - View your upcoming calendar events
   - See your reminders
   - Create new events or reminders
   - Modify existing events or reminders
   - Delete events or reminders
   - Provide coaching based on your schedule and tasks

## Privacy

- All data is stored locally on your device
- Your Claude API key is stored securely in the iOS keychain
- Calendar and Reminders data is accessed only with your permission
- No data is sent to external servers except to the Claude API for processing

## Development Notes

This app is designed for personal use and direct installation on your device. It does not require an Apple Developer account for distribution through the App Store, as it can be installed directly via Xcode (with a 7-day expiration).

To modify the Claude system prompt or adjust how the app interacts with your data, see the `ChatManager.swift` file.
