# Installation Guide for ADHD Coach

This guide will walk you through the process of installing the ADHD Coach app on your iOS device.

## Prerequisites

1. A Mac computer with Xcode 15.0 or later installed
2. An iOS device running iOS 17.0 or later
3. A USB cable to connect your device to your Mac
4. A Claude API key from Anthropic

## Installation Steps

### 1. Clone or Download the Project

If you received this project as a zip file, extract it to a location on your Mac.

### 2. Open the Project in Xcode

- Launch Xcode
- Select "Open a project or file"
- Navigate to the ADHDCoach folder and select the `ADHDCoach.xcodeproj` file
- Click "Open"

### 3. Connect Your iOS Device

- Connect your iPhone to your Mac using a USB cable
- If prompted on your iPhone, trust the computer

### 4. Select Your Device as the Build Target

- In Xcode, click on the device selector in the toolbar (near the top of the window)
- Select your connected iPhone from the dropdown list

### 5. Sign the App

- In Xcode, click on the "ADHDCoach" project in the Project Navigator (left sidebar)
- Select the "ADHDCoach" target
- Go to the "Signing & Capabilities" tab
- Check "Automatically manage signing"
- Select your personal team from the dropdown

### 6. Build and Run the App

- Click the "Play" button in the Xcode toolbar or press Cmd+R
- Xcode will build the app and install it on your device
- The first time you run the app, you may need to go to Settings > General > Device Management on your iPhone and trust the developer certificate

### 7. Configure the App

Once the app is installed and running:

1. You'll be prompted to allow access to your Calendar and Reminders
2. Tap the gear icon in the top right to access Settings
3. Enter your Claude API key in the settings screen
4. Adjust any other preferences as needed

## Troubleshooting

### App Installation Failed

- Make sure your device is unlocked
- Check that you have enough storage space on your device
- Ensure your Apple ID is set up correctly in Xcode

### Calendar or Reminders Access Issues

- Go to Settings > Privacy on your iPhone
- Check that ADHD Coach has permission to access Calendar and Reminders

### Claude API Not Working

- Verify that you've entered the correct API key in the app settings
- Check your internet connection
- Ensure your Claude API key has sufficient quota remaining

## Note on App Expiration

When installing apps directly via Xcode without an Apple Developer account, the app will expire after 7 days. To continue using the app after this period, you'll need to reconnect your device and reinstall the app using Xcode.
