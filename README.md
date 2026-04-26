# GitTracker v3.1

GitTracker is a beautiful, native macOS menu bar app designed to help you track multiple local and remote Git repositories from one place. It offers a sleek, modern interface, a visual Git graph, and simple authentication for private GitHub repositories.

![GitTracker](https://github.com/desmondlee95700/GitTracker/assets/61727180/example-image.png) <!-- Update this link with a real screenshot! -->

## Features

- **Menu Bar Convenience:** Access your commits instantly by clicking the `ᚠ` branch icon in your macOS menu bar.
- **Multi-Repo Support:** Track an unlimited number of local repositories or remote GitHub URLs.
- **Visual Git Graph:** View your commit history with a VS Code-style connected commit graph, branch pills, and author tags.
- **Branch Filtering:** Easily filter commits by selecting specific branches or view all branches combined.
- **Seamless Authentication:** Add your GitHub Username and Personal Access Token (PAT) once, and GitTracker securely handles all your private repository clones and syncs.
- **Instant Sync:** Pull the latest changes for your active repository with a single click.

## Installation

### Prerequisites

- macOS 11.0 (Big Sur) or newer.
- Swift toolchain installed (via Xcode Command Line Tools).

### Build from Source

1. Clone this repository to your local machine:

   ```bash
   git clone https://github.com/desmondlee95700/GitTracker.git
   cd GitTracker
   ```

2. Compile the Swift file into an executable:

   ```bash
   swiftc GitTracker.swift -o GitTracker
   ```

3. Create the standard macOS Application bundle structure:

   ```bash
   mkdir -p GitTracker.app/Contents/MacOS
   cp GitTracker GitTracker.app/Contents/MacOS/
   ```

4. _(Optional)_ Create an `Info.plist` inside `GitTracker.app/Contents/` to hide the dock icon:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>CFBundleExecutable</key>
       <string>GitTracker</string>
       <key>LSUIElement</key>
       <true/>
   </dict>
   </plist>
   ```

5. Move it to your Applications folder:

   ```bash
   mv GitTracker.app /Applications/
   ```

6. Open `/Applications/GitTracker.app` to run!

## Usage

1. **Auth:** Click the "Auth" button and enter your GitHub username and a Personal Access Token (with `repo` permissions) if you plan to track private repositories.
2. **Track:** Click the "Add" button. You can either paste an HTTPS GitHub URL or click "Choose Local Folder..." to track a repository already cloned on your Mac.
3. **Switch Repos:** Use the "📁 Repo:" dropdown to switch between your active projects.
4. **Switch Branches:** Use the "🌿 Branch:" dropdown to filter the history graph to a specific branch.

## How it Works

GitTracker acts as a lightweight wrapper around your local `git` installation.

- When tracking a remote URL, GitTracker clones a background copy to `~/Documents/sidehustle/GitTrackerTracker`.
- When tracking a local folder, GitTracker simply reads the `.git` data from that folder directly.
- All configuration (including your PAT) is stored locally in `config.json` in the tracker directory. This file is intentionally `.gitignore`d.

## License

This project is open-source and free to use.
