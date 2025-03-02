# ADHD Coach iOS App - Dev Reference

## Build & Test Commands
- Build: `⌘+B` in Xcode
- Run: `⌘+R` in Xcode
- Run all tests: `⌘+U` in Xcode
- Run single test: Place cursor in test method, press `⌃⌘U`
- Clean build folder: `⇧⌘K` in Xcode

## Code Style Guidelines
- **Naming**: camelCase variables/functions, PascalCase types
- **Structure**: Follow MVVM pattern with separate Managers for services
- **SwiftUI**: Use environment for theme values, custom view modifiers when appropriate
- **Imports**: Group by system frameworks first, then custom modules
- **Error Handling**: Use async/await with do/catch blocks, descriptive error messages
- **Documentation**: Use doc comments for public interfaces with parameter and return descriptions
- **Testing**: XCTest with setUp/tearDown, use mocks for dependencies, follow AAA pattern

## Project-Specific Patterns
- Use ThemeManager for consistent UI theming
- ChatManager orchestrates all chat-related functionality
- Always handle memory persistence for chat interactions