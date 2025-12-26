# GitHub Copilot Instructions for TOTP App

## Project Context
You are working on a **SwiftUI TOTP Authenticator** application that runs on iOS 26+ and macOS 26+. This app generates time-based one-time passwords (2FA codes) following RFC 4226 (HOTP) and RFC 6238 (TOTP) specifications. The app uses **iOS 26 Liquid Glass** design language.

## Quick Reference

### Project Structure
- `TOTP/Generator/` - HOTP/TOTP cryptographic code generation
- `TOTP/Model/` - Data models, persistence, CloudKit sync
- `TOTP/View/` - SwiftUI views and UI components
- `TOTP/Helper/` - Cross-platform utilities
- `TOTP Widget/` - iOS home screen widget

### Key Files
- `HOTP.swift` - HMAC-SHA1 based OTP generation
- `OTP.swift` - OtpEntry enum (TOTP/HOTP modes)
- `OtpModel.swift` - Account data model
- `SharedDataManager.swift` - Encrypted local storage
- `ContentView.swift` - Main account list
- `TotpView.swift` - Individual TOTP card component

## Code Generation Guidelines

### iOS 26 Native Styling (REQUIRED)
```swift
// ALWAYS add iOS 26 availability to views
@available(iOS 26.0, macOS 26.0, *)
struct MyView: View { ... }

// Use native card styling (similar to Journal app)
.padding()
.background {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
}
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

// Use Liquid Glass ONLY for floating action buttons (FAB)
.background {
    Circle()
        .fill(.background)
}
.glassEffect(.regular.interactive())  // Only for FAB, not cards
.clipShape(Circle())

// Use modern foregroundStyle instead of foregroundColor
.foregroundStyle(.secondary)
.foregroundStyle(
    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
)

// Use smooth animations
.animation(.smooth(duration: 0.3), value: state)
withAnimation(.smooth(duration: 0.3)) { ... }

// Use content transitions for numeric text
.contentTransition(.numericText())

// Use symbol effects for animated icons
.symbolEffect(.pulse.byLayer, options: .repeating)

// Use sensory feedback
.sensoryFeedback(.impact, trigger: someValue)
```

### When Writing SwiftUI Code
```swift
// Always use proper state management
@State private var // for local view state
@StateObject private var // for owned ObservableObjects
@Binding var // for parent-controlled state
@ObservedObject var // for injected ObservableObjects

// Always provide cross-platform support
#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif
```

### When Modifying OTP Logic
- OTP keys must be Base32 decoded before use
- TOTP uses 30-second intervals by default
- HOTP counters must be incremented after each code generation
- Always validate against RFC test vectors

### When Handling Sensitive Data
```swift
// ALWAYS encrypt OTP keys before storage
let encrypted = try ChaChaPoly.seal(keyData, using: encryptionKey).combined

// ALWAYS use Keychain for encryption keys
// NEVER log or print OTP keys or codes in production
// ALWAYS use App Groups for widget data sharing
```

### When Creating Views
```swift
// Use this pattern for native iOS card styling (like Journal app)
.padding()
.background {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
}
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

// Use platform utilities for cross-platform code
PlatformPasteboard.copyToClipboard(code)  // Instead of direct UIPasteboard/NSPasteboard
PlatformColors.secondarySystemBackground  // Instead of UIColor/NSColor
```

### When Adding Gestures
```swift
// Swipe gestures with smooth animations
.gesture(
    DragGesture(minimumDistance: 20, coordinateSpace: .local)
        .onEnded { value in
            withAnimation(.smooth(duration: 0.3)) {
                if value.translation.width < -60 { /* show actions */ }
            }
        }
)

// Context menu for long press
.contextMenu {
    Button(action: { }) { Label("Edit", systemImage: "pencil") }
    Button(role: .destructive, action: { }) { Label("Delete", systemImage: "trash") }
}
```

### When Working with Widget
- Widget cannot access clipboard directly - use URL schemes
- Widget must decrypt accounts independently
- Generate timeline entries every 30 seconds
- Use `AppIntentConfiguration` for configurable widgets
- Add `@available(iOS 26.0, macOS 26.0, *)` to all widget views

## Common Patterns to Follow

### Error Handling
```swift
public enum DataError: LocalizedError, Identifiable {
    case operationFailed(Error)
    
    public var id: String { /* unique identifier */ }
    public var errorDescription: String? { /* user-friendly message */ }
}
```

### Async Data Operations
```swift
public func operation() async throws {
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
            // Perform work
            continuation.resume()
        }
    }
}
```

### Responsive Layouts
```swift
// Use GeometryReader for adaptive layouts
GeometryReader { geometry in
    LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 16), 
                      count: geometry.size.width > 768 ? 3 : 1)
    ) { /* content */ }
}
```

## Do NOT

1. **Don't store unencrypted OTP keys** - Always use ChaChaPoly encryption
2. **Don't use hardcoded encryption keys** - Store in Keychain
3. **Don't break cross-platform compatibility** - Test on both iOS and macOS
4. **Don't ignore widget limitations** - Widgets are sandboxed
5. **Don't use external dependencies** - This project uses only Apple frameworks
6. **Don't use `.foregroundColor()`** - Use `.foregroundStyle()` instead
7. **Don't use `.shadow()`** - Cards get depth from background contrast
8. **Don't use `.spring()` animations** - Use `.smooth(duration:)` instead
9. **Don't forget `@available(iOS 26.0, macOS 26.0, *)`** - Required for all views
10. **Don't use `.glassEffect()` on cards** - Only use on FAB buttons

## Testing Expectations

- HOTP tests should verify RFC 4226 test vectors
- TOTP tests should validate time-based code generation
- Model tests should verify equality and construction
- Use Swift Testing framework (`@Test` macro)

## File Naming Conventions

- Views: `*View.swift` (e.g., `TotpView.swift`)
- Models: `*Model.swift` (e.g., `OtpModel.swift`)
- Managers: `*Manager.swift` (e.g., `SharedDataManager.swift`)
- Extensions: `Type+Feature.swift` (e.g., `Data+Base32.swift`)
