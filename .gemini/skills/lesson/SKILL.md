---
name: lesson
description: Architectural decisions, technical pivots, and lessons learned during the development of GitTracker. Use this to maintain engineering consistency and avoid repeating past layout or authentication mistakes.
---

# GitTracker Development Lessons

This skill documents the critical decisions and technical hurdles encountered during the development of the GitTracker macOS menu bar application. Refer to these lessons to ensure future modifications adhere to the established standards.

## 🛠 Technical & Architectural Lessons

### 1. The "Flipped" Coordinate Trap (AppKit vs. SwiftUI)
- **Problem**: macOS (AppKit) uses a bottom-up coordinate system by default. Using `NSStackView` normally caused UI elements to disappear or align to the bottom.
- **Solution**: Always use a helper class that overrides `isFlipped`:
  ```swift
  class FlippedStackView: NSStackView {
      override var isFlipped: Bool { return true }
  }
  ```
- **Standard**: For all top-down menu bar layouts, use `FlippedView` or `FlippedStackView`.

### 2. Shallow Clones vs. Full History
- **Problem**: Initial clones used `--depth=1` to save time, resulting in `grafted` commits and missing branches.
- **Solution**: Always perform a **full clone** and **full fetch** to ensure the Git Graph and all branches are visible.
- **Command**: Use `git clone [URL] [PATH]` without depth flags.

### 3. Background Authentication Reliability
- **Problem**: Modern GitHub security and background execution make "interactive" or "device flow" logins prone to "Not Found" errors or silent failures.
- **Solution**: Standardized on **Explicit Credentials (Username + PAT)** stored locally.
- **Implementation**: Injected via the URL format: `https://TOKEN@github.com/...`.

## 🎨 UI/UX & Design Lessons

### 4. Popover Focus Management
- **Problem**: Opening system dialogs (like `NSOpenPanel`) often forces the app to "Activate", which automatically hides the menu bar popover.
- **Solution**: Avoid `NSApp.activate(ignoringOtherApps: true)` when presenting alerts or panels from a popover.

### 5. SF Symbols over Emojis
- **Problem**: Emojis lack depth and don't adapt to system tinting or font weights.
- **Solution**: Use **Hierarchical SF Symbols** (e.g., `folder.fill`, `arrow.triangle.branch`) for a native, premium feel.

### 6. Branch Color Coding Strategy
- **Standard**: To improve visual scanning of the commit graph, we use a high-contrast color scheme:
  - **Green** (`.systemGreen`): Stable/Production branches (`main`, `master`).
  - **Yellow** (`.systemYellow`): Integration branches (`dev`, `develop`).
  - **Blue** (`.systemBlue`): Feature branches and all others.
- **Implementation**: Managed via the `getBranchColor(deco:)` function in `GitTracker.swift`.

### 7. SwiftUI-in-AppKit Bridge
- **Problem**: Complex list animations and glassmorphism (Material) are difficult in pure AppKit.
- **Solution**: Use **`NSHostingView`** to embed SwiftUI views within the AppKit architecture.
- **Pattern**: `let hostingView = NSHostingView(rootView: MySwiftUIView())`.

## 🛡 Security & Process Lessons

### 7. Configuration Sanitization
- **Standard**: Always add `config.json` (containing the PAT) to **`.gitignore`** immediately. Use `git rm --cached` if a secret was accidentally tracked.

### 8. Progressive Disclosure
- **Lesson**: Don't clutter the main view. Use dropdowns for Repo/Branch selection and slide-in Detail views for commit files.
