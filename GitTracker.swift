import AppKit
import Foundation

// --- Core Helper: Fixes the Top-to-Bottom coordinate system ---
class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

class FlippedStackView: NSStackView {
    override var isFlipped: Bool { return true }
}

// --- Configuration ---
let trackerRoot = "/Users/dessy/Documents/sidehustle/GitTrackerTracker"
let configFilePath = "\(trackerRoot)/config.json"

struct TrackedRepo: Codable, Equatable {
    var url: String
    var path: String
    var name: String
}

struct Config: Codable {
    var repos: [TrackedRepo] = []
    var selectedRepoIndex: Int = 0
    var username: String?
    var token: String?
    
    var currentRepo: TrackedRepo? {
        if repos.isEmpty { return nil }
        if selectedRepoIndex >= 0 && selectedRepoIndex < repos.count {
            return repos[selectedRepoIndex]
        }
        return repos.first
    }
}

class GitTrackerController: NSViewController {
    var config: Config
    var onAction: (String) -> Void
    var commitStack: FlippedStackView!
    var statusLabel: NSTextField!
    var branchPicker: NSPopUpButton!
    var repoPicker: NSPopUpButton!
    
    init(config: Config, onAction: @escaping (String) -> Void) {
        self.config = config
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .hudWindow
        self.view = effectView
        self.view.setFrameSize(NSSize(width: 480, height: 740))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    func setupUI() {
        let rootStack = FlippedStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 18
        rootStack.alignment = .leading
        rootStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // --- Header (Redesigned) ---
        let headerBox = NSBox()
        headerBox.boxType = .custom
        headerBox.titlePosition = .noTitle
        headerBox.fillColor = .clear
        headerBox.borderWidth = 0
        
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 16
        
        // App Icon/Title
        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.spacing = 8
        titleStack.alignment = .centerY
        
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
            let iconImg = NSImageView(image: img)
            iconImg.contentTintColor = .systemBlue
            iconImg.translatesAutoresizingMaskIntoConstraints = false
            iconImg.widthAnchor.constraint(equalToConstant: 24).isActive = true
            iconImg.heightAnchor.constraint(equalToConstant: 24).isActive = true
            titleStack.addArrangedSubview(iconImg)
        } else {
            let iconLabel = NSTextField(labelWithString: "ᚠ")
            iconLabel.font = .systemFont(ofSize: 28, weight: .black)
            iconLabel.textColor = .systemBlue
            titleStack.addArrangedSubview(iconLabel)
        }
        
        let titleLabel = NSTextField(labelWithString: "GitTracker")
        titleLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        titleLabel.textColor = .white
        
        titleStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(titleStack)
        
        // Push status to the right
        headerStack.addArrangedSubview(NSView()) 
        headerStack.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let statusBox = NSBox()
        statusBox.boxType = .custom
        statusBox.titlePosition = .noTitle
        statusBox.fillColor = config.token != nil ? NSColor.systemGreen.withAlphaComponent(0.15) : NSColor.systemRed.withAlphaComponent(0.15)
        statusBox.cornerRadius = 12
        statusBox.borderWidth = 1
        statusBox.borderColor = config.token != nil ? NSColor.systemGreen.withAlphaComponent(0.3) : NSColor.systemRed.withAlphaComponent(0.3)
        
        statusLabel = NSTextField(labelWithString: config.token != nil ? "● Authenticated" : "○ Unauthenticated")
        statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusLabel.textColor = config.token != nil ? .systemGreen : .systemRed
        statusLabel.alignment = .center
        
        statusBox.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: statusBox.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: statusBox.centerYAnchor),
            statusBox.heightAnchor.constraint(equalToConstant: 24),
            statusBox.widthAnchor.constraint(equalTo: statusLabel.widthAnchor, constant: 20)
        ])
        
        headerStack.addArrangedSubview(statusBox)
        
        headerBox.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: headerBox.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: headerBox.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerBox.trailingAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerBox.bottomAnchor)
        ])
        
        rootStack.addArrangedSubview(headerBox)
        
        // --- Project Selection (Redesigned) ---
        let projBox = NSBox()
        projBox.boxType = .custom
        projBox.titlePosition = .noTitle
        projBox.fillColor = NSColor.black.withAlphaComponent(0.2)
        projBox.cornerRadius = 12
        projBox.borderWidth = 1
        projBox.borderColor = NSColor.white.withAlphaComponent(0.1)
        
        let projStack = NSStackView()
        projStack.orientation = .vertical
        projStack.alignment = .leading
        projStack.spacing = 14
        projStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        
        // Repo Row
        let repoRow = NSStackView()
        repoRow.orientation = .horizontal
        repoRow.alignment = .centerY
        repoRow.spacing = 10
        
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
            let iconImg = NSImageView(image: img)
            iconImg.contentTintColor = .systemBlue
            repoRow.addArrangedSubview(iconImg)
        } else {
            let repoIcon = NSTextField(labelWithString: "📁")
            repoIcon.font = .systemFont(ofSize: 16)
            repoRow.addArrangedSubview(repoIcon)
        }
        
        let repoLabel = NSTextField(labelWithString: "Repository")
        repoLabel.font = .systemFont(ofSize: 13, weight: .bold)
        repoLabel.textColor = .secondaryLabelColor
        repoRow.addArrangedSubview(repoLabel)
        
        repoPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        repoPicker.target = self
        repoPicker.action = #selector(repoChanged)
        repoPicker.controlSize = .large
        repoPicker.font = .systemFont(ofSize: 14, weight: .semibold)
        repoRow.addArrangedSubview(repoPicker)
        
        // Push buttons to right
        repoRow.addArrangedSubview(NSView())
        repoRow.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let addBtn = createBtn(title: "Add", symbol: "plus", action: #selector(didTrack))
        addBtn.controlSize = .small
        addBtn.contentTintColor = .systemBlue
        repoRow.addArrangedSubview(addBtn)
        
        let removeBtn = createBtn(title: "Remove", symbol: "minus", action: #selector(didClear))
        removeBtn.controlSize = .small
        removeBtn.contentTintColor = .systemRed
        repoRow.addArrangedSubview(removeBtn)
        
        projStack.addArrangedSubview(repoRow)
        
        // Branch Row
        let branchRow = NSStackView()
        branchRow.orientation = .horizontal
        branchRow.alignment = .centerY
        branchRow.spacing = 10
        
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
            let iconImg = NSImageView(image: img)
            iconImg.contentTintColor = .systemTeal
            branchRow.addArrangedSubview(iconImg)
        } else {
            let branchIcon = NSTextField(labelWithString: "🌿")
            branchIcon.font = .systemFont(ofSize: 16)
            branchRow.addArrangedSubview(branchIcon)
        }
        
        let branchLabel = NSTextField(labelWithString: "Branch")
        branchLabel.font = .systemFont(ofSize: 13, weight: .bold)
        branchLabel.textColor = .secondaryLabelColor
        branchRow.addArrangedSubview(branchLabel)
        
        branchPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        branchPicker.target = self
        branchPicker.action = #selector(branchChanged)
        branchPicker.controlSize = .large
        branchPicker.font = .systemFont(ofSize: 14, weight: .semibold)
        branchRow.addArrangedSubview(branchPicker)
        
        projStack.addArrangedSubview(branchRow)
        
        projBox.addSubview(projStack)
        projStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            projStack.topAnchor.constraint(equalTo: projBox.topAnchor),
            projStack.leadingAnchor.constraint(equalTo: projBox.leadingAnchor),
            projStack.trailingAnchor.constraint(equalTo: projBox.trailingAnchor),
            projStack.bottomAnchor.constraint(equalTo: projBox.bottomAnchor)
        ])
        
        rootStack.addArrangedSubview(projBox)
        
        // Ensure Project Box spans full width minus padding
        NSLayoutConstraint.activate([
            projBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)
        ])

        let commitTitle = NSTextField(labelWithString: "COMMIT HISTORY")
        commitTitle.font = .systemFont(ofSize: 12, weight: .black)
        commitTitle.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(commitTitle)
        
        // --- Scrollable Area ---
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        
        commitStack = FlippedStackView()
        commitStack.orientation = .vertical
        commitStack.spacing = 0 // Critical for graph connecting lines
        commitStack.alignment = .leading
        commitStack.translatesAutoresizingMaskIntoConstraints = false
        
        docView.addSubview(commitStack)
        NSLayoutConstraint.activate([
            commitStack.topAnchor.constraint(equalTo: docView.topAnchor),
            commitStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            commitStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            commitStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor)
        ])
        
        scrollView.documentView = docView
        rootStack.addArrangedSubview(scrollView)
        
        NSLayoutConstraint.activate([
            docView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -16)
        ])
        
        loadRepos()
        loadBranches()
        updateCommits()
        
        // --- Footer (Redesigned) ---
        let footerBox = NSBox()
        footerBox.boxType = .custom
        footerBox.titlePosition = .noTitle
        footerBox.fillColor = NSColor.black.withAlphaComponent(0.2)
        footerBox.cornerRadius = 12
        footerBox.borderWidth = 1
        footerBox.borderColor = NSColor.white.withAlphaComponent(0.1)
        
        let footer = NSStackView()
        footer.distribution = .fillEqually
        footer.spacing = 12
        footer.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        let syncBtn = createBtn(title: "Sync", symbol: "arrow.triangle.2.circlepath", action: #selector(didSync))
        syncBtn.bezelStyle = .texturedRounded
        syncBtn.contentTintColor = .white
        footer.addArrangedSubview(syncBtn)
        
        let authBtn = createBtn(title: "Auth", symbol: "person.crop.circle.badge.key", action: #selector(didAuth))
        authBtn.bezelStyle = .texturedRounded
        footer.addArrangedSubview(authBtn)
        
        let quitBtn = createBtn(title: "Quit", symbol: "power", action: #selector(didQuit))
        quitBtn.bezelStyle = .texturedRounded
        quitBtn.contentTintColor = .systemRed
        footer.addArrangedSubview(quitBtn)
        
        footerBox.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: footerBox.topAnchor),
            footer.leadingAnchor.constraint(equalTo: footerBox.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: footerBox.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: footerBox.bottomAnchor)
        ])
        
        rootStack.addArrangedSubview(footerBox)
        footerBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footerBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)
        ])
    }
    
    @objc func repoChanged() {
        onAction("repoChanged:\(repoPicker.indexOfSelectedItem)")
    }
    
    @objc func branchChanged() {
        updateCommits()
    }
    
    func loadRepos() {
        repoPicker.removeAllItems()
        if config.repos.isEmpty {
            repoPicker.addItem(withTitle: "No Repositories")
            repoPicker.isEnabled = false
        } else {
            repoPicker.isEnabled = true
            let titles = config.repos.map { $0.name }
            repoPicker.addItems(withTitles: titles)
            if config.selectedRepoIndex >= 0 && config.selectedRepoIndex < config.repos.count {
                repoPicker.selectItem(at: config.selectedRepoIndex)
            }
        }
    }
    
    func loadBranches() {
        branchPicker.removeAllItems()
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else {
            branchPicker.addItem(withTitle: "N/A")
            branchPicker.isEnabled = false
            return
        }
        
        branchPicker.isEnabled = true
        let out = runGit(args: ["-C", currentRepo.path, "branch", "-a", "--format=%(refname:short)"])
        var branches = ["All Branches"]
        for b in out.components(separatedBy: "\n") {
            let clean = b.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && clean != "HEAD" && !clean.hasSuffix("/HEAD") {
                let displayName = clean.replacingOccurrences(of: "origin/", with: "")
                if !branches.contains(displayName) {
                    branches.append(displayName)
                }
            }
        }
        
        branchPicker.addItems(withTitles: branches)
        branchPicker.selectItem(at: 0)
    }
    
    func updateCommits() {
        commitStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else {
            let label = NSTextField(labelWithString: "Please add a repository to track.")
            label.textColor = .secondaryLabelColor
            commitStack.addArrangedSubview(label)
            return
        }
        
        var gitArgs = ["-C", currentRepo.path, "log", "-n", "100", "--pretty=format:%h|%s|%ar|%an|%D"]
        if branchPicker.isEnabled && branchPicker.indexOfSelectedItem > 0 {
            let sel = branchPicker.titleOfSelectedItem!
            let localCheck = runGit(args: ["-C", currentRepo.path, "rev-parse", "--verify", sel])
            if localCheck.isEmpty {
                gitArgs.insert("origin/\(sel)", at: 3)
            } else {
                gitArgs.insert(sel, at: 3)
            }
        } else {
            gitArgs.insert("--all", at: 3)
        }
        
        let log = runGit(args: gitArgs)
        let lines = log.components(separatedBy: "\n")
        
        var validLines = [String]()
        for line in lines where !line.isEmpty {
            validLines.append(line)
        }
        
        if validLines.isEmpty {
            let label = NSTextField(labelWithString: "No commits found on this branch.")
            label.textColor = .secondaryLabelColor
            commitStack.addArrangedSubview(label)
            return
        }
        
        for (index, line) in validLines.enumerated() {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 4 {
                let row = createCommitRow(
                    hash: parts[0], 
                    msg: parts[1], 
                    time: parts[2], 
                    author: parts[3], 
                    deco: parts.count > 4 ? parts[4] : "",
                    isLast: index == validLines.count - 1
                )
                commitStack.addArrangedSubview(row)
            }
        }
    }
    
    func createCommitRow(hash: String, msg: String, time: String, author: String, deco: String, isLast: Bool) -> NSView {
        let row = NSStackView()
        row.spacing = 16
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        
        // --- Graph Column ---
        let graphContainer = NSView()
        graphContainer.translatesAutoresizingMaskIntoConstraints = false
        graphContainer.widthAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Vertical Line
        let line = NSBox()
        line.boxType = .custom
        line.titlePosition = .noTitle
        line.fillColor = NSColor.white.withAlphaComponent(0.15)
        line.borderWidth = 0
        graphContainer.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.centerXAnchor.constraint(equalTo: graphContainer.centerXAnchor),
            line.topAnchor.constraint(equalTo: graphContainer.topAnchor),
            line.widthAnchor.constraint(equalToConstant: 2)
        ])
        
        if !isLast {
            line.bottomAnchor.constraint(equalTo: graphContainer.bottomAnchor).isActive = true
        } else {
            line.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
        
        // Dot
        let dot = NSBox()
        dot.boxType = .custom
        dot.titlePosition = .noTitle
        dot.fillColor = NSColor.systemBlue
        dot.cornerRadius = 6
        dot.borderWidth = 2
        dot.borderColor = NSColor.windowBackgroundColor
        graphContainer.addSubview(dot)
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: graphContainer.centerXAnchor),
            dot.topAnchor.constraint(equalTo: graphContainer.topAnchor, constant: 14),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12)
        ])
        
        // --- Content Column ---
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 16, right: 0)
        
        let msgStack = NSStackView()
        msgStack.spacing = 8
        msgStack.alignment = .centerY
        
        if !deco.isEmpty {
            let cleanDeco = deco.replacingOccurrences(of: "HEAD -> ", with: "")
            let branches = cleanDeco.components(separatedBy: ", ")
            for b in branches {
                let name = b.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let isTag = name.hasPrefix("tag: ")
                    let cleanName = name.replacingOccurrences(of: "tag: ", with: "")
                    let color = isTag ? NSColor.systemOrange.withAlphaComponent(0.6) : NSColor.systemTeal.withAlphaComponent(0.6)
                    msgStack.addArrangedSubview(createPill(text: cleanName, color: color))
                }
            }
        }
        
        let m = NSTextField(labelWithString: msg)
        m.font = .systemFont(ofSize: 14, weight: .semibold)
        m.lineBreakMode = .byWordWrapping
        m.maximumNumberOfLines = 0
        m.textColor = .white
        m.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        msgStack.addArrangedSubview(m)
        
        let infoStack = NSStackView()
        infoStack.orientation = .horizontal
        infoStack.alignment = .centerY
        infoStack.spacing = 4
        
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil) {
            let iconImg = NSImageView(image: img)
            iconImg.contentTintColor = .secondaryLabelColor
            let config = NSImage.SymbolConfiguration(scale: .small)
            iconImg.symbolConfiguration = config
            infoStack.addArrangedSubview(iconImg)
        } else {
            let icon = NSTextField(labelWithString: "👤")
            icon.font = .systemFont(ofSize: 10)
            icon.textColor = .secondaryLabelColor
            infoStack.addArrangedSubview(icon)
        }
        
        let info = NSTextField(labelWithString: "\(author) • \(hash) • \(time)")
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(info)
        
        content.addArrangedSubview(msgStack)
        content.addArrangedSubview(infoStack)
        
        row.addArrangedSubview(graphContainer)
        row.addArrangedSubview(content)
        
        graphContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor).isActive = true
        
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 400).isActive = true
        
        return row
    }
    
    func createPill(text: String, color: NSColor) -> NSView {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 10, weight: .bold)
        f.textColor = .white
        let b = NSBox()
        b.boxType = .custom
        b.titlePosition = .noTitle
        b.fillColor = color
        b.cornerRadius = 4
        b.borderWidth = 0
        b.addSubview(f)
        f.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            f.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            f.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            b.heightAnchor.constraint(equalToConstant: 18),
            b.widthAnchor.constraint(equalTo: f.widthAnchor, constant: 12)
        ])
        return b
    }
    
    func createBtn(title: String, symbol: String? = nil, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .recessed
        b.controlSize = .regular
        
        if #available(macOS 11.0, *), let sym = symbol, let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(scale: .medium)
            img.isTemplate = true
            b.image = img.withSymbolConfiguration(config)
            b.imagePosition = .imageLeft
        }
        
        return b
    }
    
    @objc func didSync() { onAction("sync") }
    @objc func didTrack() { onAction("track") }
    @objc func didAuth() { onAction("auth") }
    @objc func didClear() { onAction("clear") }
    @objc func didQuit() { onAction("quit") }
    
    func runGit(args: [String]) -> String {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    var config = Config()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateConfig()
        loadConfig()
        if let b = statusItem.button { 
            if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
                img.isTemplate = true
                b.image = img
            } else {
                b.title = "ᚠ"
            }
            b.action = #selector(togglePopover)
            b.target = self 
        }
        popover.contentViewController = GitTrackerController(config: config, onAction: handleAction)
        popover.behavior = .transient
        setupEditMenu()
    }
    
    func setupEditMenu() {
        let m = NSMenu(); let e = NSMenu(title: "Edit")
        e.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let i = NSMenuItem(); i.submenu = e; m.addItem(i); NSApp.mainMenu = m
    }
    
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let b = statusItem.button {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            (popover.contentViewController as? GitTrackerController)?.loadBranches()
            (popover.contentViewController as? GitTrackerController)?.updateCommits()
        }
    }
    
    func handleAction(_ type: String) {
        if type.hasPrefix("repoChanged:") {
            if let index = Int(type.replacingOccurrences(of: "repoChanged:", with: "")) {
                config.selectedRepoIndex = index
                saveConfig()
                reloadUI()
            }
            return
        }
        
        switch type {
        case "sync": refreshRepo()
        case "track": promptForRepo()
        case "auth": promptForAuth()
        case "clear": clearRepo()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    
    func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        DispatchQueue.main.async {
            if let vc = self.popover.contentViewController as? GitTrackerController {
                vc.statusLabel.stringValue = text
                vc.statusLabel.textColor = color
            }
        }
    }

    func promptForAuth() {
        let a = NSAlert()
        a.messageText = "GitHub Credentials"
        let v = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        v.orientation = .vertical; v.spacing = 8
        let userT = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        userT.placeholderString = "Username"
        userT.stringValue = config.username ?? ""
        let tokenT = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tokenT.placeholderString = "PAT Token"
        tokenT.stringValue = config.token ?? ""
        v.addArrangedSubview(userT); v.addArrangedSubview(tokenT)
        a.accessoryView = v
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            config.username = userT.stringValue.trimmingCharacters(in: .whitespaces)
            config.token = tokenT.stringValue.trimmingCharacters(in: .whitespaces)
            saveConfig(); reloadUI()
        }
    }

    func promptForRepo() {
        let a = NSAlert()
        a.messageText = "Add Repository"
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        t.placeholderString = "HTTPS URL or local folder path"
        a.accessoryView = t
        a.addButton(withTitle: "Add")
        a.addButton(withTitle: "Choose Local Folder...")
        a.addButton(withTitle: "Cancel")
        
        let response = a.runModal()
        
        if response == .alertFirstButtonReturn { 
            trackRepo(input: t.stringValue.trimmingCharacters(in: .whitespaces)) 
        } else if response == .alertSecondButtonReturn {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                trackRepo(input: url.path)
            }
        }
    }
    
    func trackRepo(input: String) {
        guard !input.isEmpty else { return }
        setStatus("⌛ Processing...")
        
        let cleanInput = input.replacingOccurrences(of: "file://", with: "")
        let expanded = (cleanInput as NSString).expandingTildeInPath
        let repoName = cleanInput.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"
        
        if FileManager.default.fileExists(atPath: expanded) { 
            let newRepo = TrackedRepo(url: cleanInput, path: expanded, name: repoName)
            addAndSelectRepo(newRepo)
            setStatus("● Local project loaded")
        } else {
            let path = "\(trackerRoot)/\(repoName)"
            let newRepo = TrackedRepo(url: cleanInput, path: path, name: repoName)
            
            setStatus("⌛ Cloning...")
            DispatchQueue.global(qos: .userInitiated).async {
                var url = cleanInput
                if let tok = self.config.token, url.contains("github.com") { 
                    url = url.replacingOccurrences(of: "https://", with: "https://\(tok)@") 
                }
                
                if FileManager.default.fileExists(atPath: path) { 
                    try? FileManager.default.removeItem(atPath: path) 
                }
                
                let task = Process()
                task.launchPath = "/usr/bin/git"
                task.arguments = ["clone", url, path]
                let errPipe = Pipe()
                task.standardError = errPipe
                task.launch()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 { 
                        self.addAndSelectRepo(newRepo)
                        self.setStatus("● Clone successful", color: .systemGreen) 
                    } else { 
                        self.setStatus("○ Clone failed", color: .systemRed) 
                    }
                }
            }
        }
    }
    
    func addAndSelectRepo(_ repo: TrackedRepo) {
        if !config.repos.contains(where: { $0.path == repo.path }) {
            config.repos.append(repo)
        }
        config.selectedRepoIndex = config.repos.firstIndex(where: { $0.path == repo.path }) ?? 0
        saveConfig()
        reloadUI()
    }
    
    func refreshRepo() {
        guard let currentRepo = config.currentRepo else { return }
        setStatus("⌛ Syncing...")
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchTask = Process()
            fetchTask.launchPath = "/usr/bin/git"
            fetchTask.arguments = ["-C", currentRepo.path, "fetch", "--all"]
            fetchTask.launch()
            fetchTask.waitUntilExit()
            
            let pullTask = Process()
            pullTask.launchPath = "/usr/bin/git"
            pullTask.arguments = ["-C", currentRepo.path, "pull"]
            pullTask.launch()
            pullTask.waitUntilExit()
            
            DispatchQueue.main.async { 
                self.reloadUI()
                self.setStatus("● Sync complete", color: .systemGreen) 
            }
        }
    }
    
    func clearRepo() { 
        if !config.repos.isEmpty && config.selectedRepoIndex >= 0 && config.selectedRepoIndex < config.repos.count {
            config.repos.remove(at: config.selectedRepoIndex)
            config.selectedRepoIndex = max(0, config.selectedRepoIndex - 1)
            saveConfig()
            reloadUI()
            setStatus("Project removed.")
        }
    }
    
    func migrateConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            var needsMigration = false
            var migratedConfig = Config()
            
            if let repos = json["repos"] as? [[String: String]] { return }
            
            if let repoUrl = json["repoUrl"] as? String, let repoPath = json["repoPath"] as? String {
                let repoName = repoUrl.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"
                migratedConfig.repos.append(TrackedRepo(url: repoUrl, path: repoPath, name: repoName))
                needsMigration = true
            }
            
            if let user = json["username"] as? String { migratedConfig.username = user; needsMigration = true }
            if let tok = json["token"] as? String { migratedConfig.token = tok; needsMigration = true }
            
            if needsMigration {
                self.config = migratedConfig
                saveConfig()
            }
        }
    }
    
    func loadConfig() { 
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), 
           let decoded = try? JSONDecoder().decode(Config.self, from: data) { 
            self.config = decoded 
        } 
    }
    
    func saveConfig() { 
        if let data = try? JSONEncoder().encode(config) { 
            try? data.write(to: URL(fileURLWithPath: configFilePath)) 
        } 
    }
    
    func reloadUI() { 
        DispatchQueue.main.async { 
            self.loadConfig()
            self.popover.contentViewController = GitTrackerController(config: self.config, onAction: self.handleAction) 
        } 
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
