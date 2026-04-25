# GitTracker Project Context

## Project Overview
GitTracker is a native macOS menu bar application built with Swift and AppKit. It provides a real-time overview of multiple Git repositories, allowing users to track commits, branches, and synchronization status directly from the system menu bar.

### Core Technologies
- **Language:** Swift 6.2
- **Framework:** AppKit (macOS Native UI)
- **Git Integration:** Direct execution of `/usr/bin/git` via `Process`
- **Architecture:** `AppDelegate` manages the `NSStatusItem` and `NSPopover`, while `GitTrackerController` (an `NSViewController`) manages the main UI stack and commit graph.
- **Storage:** Local JSON configuration (`config.json`) stored in the project's root tracker directory.

## Building and Running
The project is designed to be compiled as a standalone macOS application bundle.

### Compilation Command
```bash
swiftc GitTracker.swift -o GitTracker
```

### Installation and Bundle Creation
To create a standard `.app` bundle:
1. Create the structure: `mkdir -p GitTracker.app/Contents/MacOS`
2. Move the binary: `cp GitTracker GitTracker.app/Contents/MacOS/GitTracker`
3. Add `Info.plist` to `GitTracker.app/Contents/` (with `LSUIElement` set to `true` for menu-bar-only behavior).
4. Launch with: `open GitTracker.app`

## Development Conventions
- **UI Coordinate System:** Uses a custom `FlippedView` and `FlippedStackView` (overriding `isFlipped`) to ensure layouts start from the top-left (macOS standard is bottom-left).
- **Authentication:** Uses GitHub Personal Access Tokens (PAT) passed via URL injection (`https://TOKEN@github.com/...`) or native macOS Keychain integration.
- **Concurrency:** Git operations are performed on background queues (`DispatchQueue.global(qos: .userInitiated)`) to prevent UI freezing, with UI updates dispatched back to the main thread.
- **Data Model:** `Config` and `TrackedRepo` structs are used for persistence, implementing the `Codable` protocol for JSON serialization.
- **Git Graph Rendering:** Implements a custom visual graph using `NSBox` elements for connecting lines and dots, with branch-specific color coding (Main: Green, Dev: Yellow, Others: Blue).

## Key Files
- `GitTracker.swift`: The monolithic source file containing the UI logic, Git command integration, and App Delegate.
- `config.json`: Local storage for tracked repositories and authentication credentials (ignored by Git).
- `README.md`: End-user documentation and installation guide.
