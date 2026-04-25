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

### 2. Threading & Concurrency (Beachball Prevention)
- **Problem**: Running heavy Git commands (cloning, checkout, fetch) on the Main Thread causes the macOS menu bar to freeze.
- **Solution**: Move all shell operations to background queues:
  ```swift
  DispatchQueue.global(qos: .userInitiated).async {
      let result = self.runShell(args: ["checkout", branch])
      DispatchQueue.main.async { self.reloadUI() }
  }
  ```
- **Standard**: Never block the main thread with `Process` execution. Use status messages ("⌛ Checking out...") to provide feedback.

### 3. Robust Git Utilities
- **Lesson**: `git checkout` can fail (e.g., local conflicts). Silent failures lead to UI desync.
- **Standard**: Always use a `runShell` utility that returns both the `output` string and a `success` boolean. Only update state if `success` is true.

### 4. Background Authentication Reliability
- **Standard**: Standardized on **Explicit Credentials (Username + PAT)** stored locally. Injected via the URL format: `https://TOKEN@github.com/...`.

## 🎨 UI/UX & Design Lessons

### 5. Branch Switching Best Practices
- **Problem**: Checking out a remote branch directly (`origin/main`) puts the user in a "Detached HEAD" state.
- **Expert Solution**: Automatically create a local tracking branch:
  ```bash
  git checkout -b <name> --track origin/<name>
  ```
- **UI Standard**: If a user clicks a Remote branch, check for a local version first; if missing, create and track it automatically.

### 6. Menu Categorization & Iconography
- **Standard**: Group branches into "Local" (💻 `laptopcomputer`) and "Remote" (☁️ `cloud.fill`) sections.
- **Dual-Checkmarks**: If the current branch tracks an upstream, show checkmarks on **both** the local and remote entries to signify the link.
- **Upstream Detection**: Display a small cloud icon in the dropdown label if the current branch has an upstream connection.

### 7. Branch Color Coding Strategy
- **Standard**: 
  - **Green**: Production branches (`main`, `master`).
  - **Yellow**: Development/Integration (`dev`, `develop`).
  - **Blue**: Features and others.
  - **Gray**: Tracking branches (`origin/...`) to reduce visual weight.

### 8. Professional App Branding
- **Lesson**: Missing `.app` bundles cause white square icons in Spotlight.
- **Standard**: 
  - Set `LSUIElement` to `true` in `Info.plist` for menu-bar-only behavior.
  - **Programmatic Fallback**: Generate a high-quality branded icon (Blue Background + White Glyph) in code during `applicationDidFinishLaunching` to ensure consistent branding regardless of the build environment.

## 🛡 Security & Process Lessons

### 9. Configuration Sanitization
- **Standard**: Always add `config.json` and compiled binaries/bundles to **`.gitignore`**. Use `git rm --cached` if a secret or binary was accidentally tracked.

### 10. Progressive Disclosure
- **Lesson**: Don't clutter the main view. Use dropdowns for Repo/Branch selection and slide-in Detail views for commit files.

### 11. Persistent Dialogs in Menu Bar Apps (Copy-Paste Support)
- **Problem**: Standard `NSPopover` with `.transient` behavior closes automatically when the user switches to a browser to copy a Personal Access Token.
- **Solution**: Use `.applicationDefined` behavior for dialog popovers (Auth, Add Repo) to ensure they stay open until explicitly dismissed or saved.
- **Standard**: For any view requiring user input from external sources, bypass transient behavior.

### 12. SwiftUI-AppKit Hybrid Architecture
- **Lesson**: Modernizing a legacy AppKit app is most efficient using `NSHostingController`.
- **Standard**: Build complex dialogs and detail sections in SwiftUI, then bridge them into the `AppDelegate` or `NSViewController` using `NSHostingController` and `NSHostingView`.

### 13. Data Scanability in Commit Details
- **Lesson**: Flat text lists of files are hard to parse.
- **Standard**: 
  - Use **Cards** with background materials (`Color.white.opacity(0.05)`) to group related commit info.
  - Implement **File-Type Iconography** (e.g., `swift`, `braces` for JSON, `photo` for images) using SF Symbols to provide immediate visual context for changed files.
  - Use **Monospaced Fonts** for hashes and file paths to maintain alignment and technical feel.
