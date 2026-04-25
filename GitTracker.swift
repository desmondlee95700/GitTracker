import AppKit
import Foundation

// --- Core Helper: Fixes the Top-to-Bottom coordinate system ---
class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

class FlippedStackView: NSStackView {
    override var isFlipped: Bool { return true }
}

// --- Custom View for the Segmented Status Bar ---
class StackedStatusBar: NSView {
    var cleanCount: Int = 0
    var dirtyCount: Int = 0
    var aheadCount: Int = 0
    var behindCount: Int = 0
    
    func update(clean: Int, dirty: Int, ahead: Int, behind: Int) {
        self.cleanCount = clean
        self.dirtyCount = dirty
        self.aheadCount = ahead
        self.behindCount = behind
        self.needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let total = CGFloat(cleanCount + dirtyCount + aheadCount + behindCount)
        if total == 0 { 
            NSColor.white.withAlphaComponent(0.1).set()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
            path.fill()
            return 
        }
        
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        path.addClip()
        
        var currentX: CGFloat = 0
        let segments: [(Int, NSColor)] = [
            (behindCount, .systemRed),
            (aheadCount, .systemBlue),
            (dirtyCount, .systemOrange),
            (cleanCount, .systemGreen)
        ]
        
        for (count, color) in segments {
            if count > 0 {
                let width = (CGFloat(count) / total) * bounds.width
                color.set()
                let rect = NSRect(x: currentX, y: 0, width: width, height: bounds.height)
                rect.fill()
                currentX += width
            }
        }
    }
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
    var branchStatusLabel: NSTextField!
    var summaryBar: StackedStatusBar!
    var summaryLabel: NSTextField!
    
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
        self.view.setFrameSize(NSSize(width: 480, height: 780))
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
        
        // --- Header ---
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
            let iconImg = NSImageView(image: img)
            iconImg.contentTintColor = .systemBlue
            iconImg.translatesAutoresizingMaskIntoConstraints = false
            iconImg.widthAnchor.constraint(equalToConstant: 24).isActive = true
            iconImg.heightAnchor.constraint(equalToConstant: 24).isActive = true
            headerStack.addArrangedSubview(iconImg)
        }
        
        let titleLabel = NSTextField(labelWithString: "GitTracker")
        titleLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        headerStack.addArrangedSubview(titleLabel)
        
        headerStack.addArrangedSubview(NSView())
        headerStack.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        statusLabel = NSTextField(labelWithString: config.token != nil ? "● Auth Active" : "○ No Auth Set")
        statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusLabel.textColor = config.token != nil ? .systemGreen : .systemRed
        headerStack.addArrangedSubview(statusLabel)
        
        rootStack.addArrangedSubview(headerStack)
        
        // --- Global Summary Bar ---
        let summaryBox = NSBox()
        summaryBox.boxType = .custom
        summaryBox.fillColor = NSColor.white.withAlphaComponent(0.03)
        summaryBox.cornerRadius = 8
        summaryBox.borderWidth = 0
        
        let summaryStack = NSStackView()
        summaryStack.orientation = .vertical
        summaryStack.alignment = .leading
        summaryStack.spacing = 8
        summaryStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        summaryLabel = NSTextField(labelWithString: "OVERVIEW")
        summaryLabel.font = .systemFont(ofSize: 10, weight: .black)
        summaryLabel.textColor = .secondaryLabelColor
        summaryStack.addArrangedSubview(summaryLabel)
        
        summaryBar = StackedStatusBar()
        summaryBar.translatesAutoresizingMaskIntoConstraints = false
        summaryStack.addArrangedSubview(summaryBar)
        
        NSLayoutConstraint.activate([
            summaryBar.heightAnchor.constraint(equalToConstant: 8),
            summaryBar.widthAnchor.constraint(equalTo: summaryStack.widthAnchor, constant: -32)
        ])
        
        summaryBox.addSubview(summaryStack)
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            summaryStack.topAnchor.constraint(equalTo: summaryBox.topAnchor),
            summaryStack.leadingAnchor.constraint(equalTo: summaryBox.leadingAnchor),
            summaryStack.trailingAnchor.constraint(equalTo: summaryBox.trailingAnchor),
            summaryStack.bottomAnchor.constraint(equalTo: summaryBox.bottomAnchor)
        ])
        
        rootStack.addArrangedSubview(summaryBox)
        NSLayoutConstraint.activate([summaryBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])
        
        // --- Project Selection ---
        let projBox = NSBox()
        projBox.boxType = .custom
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
        }
        
        repoPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        repoPicker.target = self
        repoPicker.action = #selector(repoChanged)
        repoPicker.controlSize = .large
        repoPicker.font = .systemFont(ofSize: 14, weight: .semibold)
        repoRow.addArrangedSubview(repoPicker)
        
        repoRow.addArrangedSubview(NSView())
        repoRow.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let addBtn = createBtn(title: "Add", symbol: "plus", action: #selector(didTrack))
        addBtn.bezelStyle = .inline
        addBtn.contentTintColor = .systemBlue
        repoRow.addArrangedSubview(addBtn)
        
        let removeBtn = createBtn(title: "Remove", symbol: "minus", action: #selector(didClear))
        removeBtn.bezelStyle = .inline
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
        }
        
        branchPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        branchPicker.target = self
        branchPicker.action = #selector(branchChanged)
        branchPicker.controlSize = .large
        branchPicker.font = .systemFont(ofSize: 14, weight: .semibold)
        branchRow.addArrangedSubview(branchPicker)
        
        branchRow.addArrangedSubview(NSView())
        branchRow.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        branchStatusLabel = NSTextField(labelWithString: "")
        branchStatusLabel.font = .systemFont(ofSize: 12, weight: .bold)
        branchRow.addArrangedSubview(branchStatusLabel)
        
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
        NSLayoutConstraint.activate([projBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])

        let commitTitle = NSTextField(labelWithString: "COMMIT HISTORY")
        commitTitle.font = .systemFont(ofSize: 12, weight: .black)
        commitTitle.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(commitTitle)
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        
        commitStack = FlippedStackView()
        commitStack.orientation = .vertical
        commitStack.spacing = 0
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
        NSLayoutConstraint.activate([docView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -16)])
        
        loadRepos()
        loadBranches()
        updateCommits()
        
        // --- Footer ---
        let footerBox = NSBox()
        footerBox.boxType = .custom
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
        NSLayoutConstraint.activate([footerBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])
        
        onAction("updateAllStatus")
    }
    
    @objc func repoChanged() { onAction("repoChanged:\(repoPicker.indexOfSelectedItem)") }
    @objc func branchChanged() { updateCommits() }
    
    func loadRepos() {
        repoPicker.removeAllItems()
        if config.repos.isEmpty {
            repoPicker.addItem(withTitle: "No Repositories")
            repoPicker.isEnabled = false
        } else {
            repoPicker.isEnabled = true
            repoPicker.addItems(withTitles: config.repos.map { $0.name })
            if config.selectedRepoIndex < config.repos.count { repoPicker.selectItem(at: config.selectedRepoIndex) }
        }
    }
    
    func loadBranches() {
        branchPicker.removeAllItems()
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else {
            branchPicker.addItem(withTitle: "N/A"); branchPicker.isEnabled = false; return
        }
        branchPicker.isEnabled = true
        let out = runGit(args: ["-C", currentRepo.path, "branch", "-a", "--format=%(refname:short)"])
        var branches = ["All Branches"]
        for b in out.components(separatedBy: "\n") {
            let clean = b.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && clean != "HEAD" && !clean.hasSuffix("/HEAD") {
                let name = clean.replacingOccurrences(of: "origin/", with: "")
                if !branches.contains(name) { branches.append(name) }
            }
        }
        branchPicker.addItems(withTitles: branches); branchPicker.selectItem(at: 0)
    }
    
    func updateCommits() {
        commitStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else { return }
        
        var args = ["-C", currentRepo.path, "log", "-n", "100", "--pretty=format:%h|%s|%ar|%an|%D"]
        if branchPicker.indexOfSelectedItem > 0 {
            let sel = branchPicker.titleOfSelectedItem!
            let check = runGit(args: ["-C", currentRepo.path, "rev-parse", "--verify", sel])
            args.insert(check.isEmpty ? "origin/\(sel)" : sel, at: 3)
        } else { args.insert("--all", at: 3) }
        
        let lines = runGit(args: args).components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.isEmpty {
            commitStack.addArrangedSubview(NSTextField(labelWithString: "No commits found."))
            return
        }
        
        for (index, line) in lines.enumerated() {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 4 {
                let deco = parts.count > 4 ? parts[4] : ""
                let color = getBranchColor(deco: deco)
                commitStack.addArrangedSubview(createCommitRow(hash: parts[0], msg: parts[1], time: parts[2], author: parts[3], deco: deco, color: color, isLast: index == lines.count - 1))
            }
        }
        updateBranchStatus(path: currentRepo.path)
    }
    
    func getBranchColor(deco: String) -> NSColor {
        if deco.contains("main") || deco.contains("master") { return .systemGreen }
        if deco.contains("dev") || deco.contains("develop") { return .systemPurple }
        if deco.contains("feature") { return .systemTeal }
        return .systemBlue
    }
    
    func updateBranchStatus(path: String) {
        if branchStatusLabel == nil { return }
        let status = getRepoStatus(path: path)
        if status.3 { 
            branchStatusLabel.stringValue = "✓ Clean"; branchStatusLabel.textColor = .secondaryLabelColor
        } else {
            var parts = [String]()
            if status.0 { parts.append("✏️ Dirty") }
            if status.1 > 0 { parts.append("↑ \(status.1)") }
            if status.2 > 0 { parts.append("↓ \(status.2)") }
            branchStatusLabel.stringValue = parts.joined(separator: "  ")
            branchStatusLabel.textColor = .systemOrange
        }
    }
    
    func getRepoStatus(path: String) -> (Bool, Int, Int, Bool) {
        let dirty = !runGit(args: ["-C", path, "status", "--porcelain"]).isEmpty
        let revList = runGit(args: ["-C", path, "rev-list", "--left-right", "--count", "HEAD...@{u}"])
        var ahead = 0, behind = 0
        if !revList.isEmpty && !revList.hasPrefix("fatal") {
            let counts = revList.components(separatedBy: .whitespaces)
            if counts.count == 2 { ahead = Int(counts[0]) ?? 0; behind = Int(counts[1]) ?? 0 }
        }
        return (dirty, ahead, behind, !dirty && ahead == 0 && behind == 0)
    }

    func createCommitRow(hash: String, msg: String, time: String, author: String, deco: String, color: NSColor, isLast: Bool) -> NSView {
        let row = NSStackView(); row.spacing = 16; row.alignment = .top; row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let graph = NSView(); graph.translatesAutoresizingMaskIntoConstraints = false; graph.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let line = NSBox(); line.boxType = .custom; line.fillColor = NSColor.white.withAlphaComponent(0.15); line.borderWidth = 0
        graph.addSubview(line); line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.centerXAnchor.constraint(equalTo: graph.centerXAnchor), line.topAnchor.constraint(equalTo: graph.topAnchor), line.widthAnchor.constraint(equalToConstant: 2)])
        if !isLast { line.bottomAnchor.constraint(equalTo: graph.bottomAnchor).isActive = true } else { line.heightAnchor.constraint(equalToConstant: 20).isActive = true }
        let dot = NSBox(); dot.boxType = .custom; dot.fillColor = color; dot.cornerRadius = 6; dot.borderWidth = 2; dot.borderColor = NSColor.windowBackgroundColor
        graph.addSubview(dot); dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.centerXAnchor.constraint(equalTo: graph.centerXAnchor), dot.topAnchor.constraint(equalTo: graph.topAnchor, constant: 14), dot.widthAnchor.constraint(equalToConstant: 12), dot.heightAnchor.constraint(equalToConstant: 12)])
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 6; content.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 16, right: 0)
        let msgStack = NSStackView(); msgStack.spacing = 8; msgStack.alignment = .centerY
        if !deco.isEmpty {
            let branches = deco.replacingOccurrences(of: "HEAD -> ", with: "").components(separatedBy: ", ")
            for b in branches {
                let name = b.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let isTag = name.hasPrefix("tag: "); let clean = name.replacingOccurrences(of: "tag: ", with: "")
                    let pColor = isTag ? NSColor.systemOrange : (clean == "main" || clean == "master" ? .systemGreen : .systemTeal)
                    msgStack.addArrangedSubview(createPill(text: clean, color: pColor.withAlphaComponent(0.6)))
                }
            }
        }
        let m = NSTextField(labelWithString: msg); m.font = .systemFont(ofSize: 14, weight: .semibold); m.lineBreakMode = .byWordWrapping; m.maximumNumberOfLines = 0; m.textColor = .white; m.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        msgStack.addArrangedSubview(m); let info = NSStackView(); info.spacing = 4; info.alignment = .centerY
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil) {
            let iv = NSImageView(image: img); iv.contentTintColor = .secondaryLabelColor; iv.symbolConfiguration = NSImage.SymbolConfiguration(scale: .small); info.addArrangedSubview(iv)
        }
        let it = NSTextField(labelWithString: "\(author) • \(hash) • \(time)"); it.font = .systemFont(ofSize: 11); it.textColor = .secondaryLabelColor; info.addArrangedSubview(it)
        content.addArrangedSubview(msgStack); content.addArrangedSubview(info); row.addArrangedSubview(graph); row.addArrangedSubview(content)
        graph.bottomAnchor.constraint(equalTo: content.bottomAnchor).isActive = true; row.translatesAutoresizingMaskIntoConstraints = false; row.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return row
    }
    
    func createPill(text: String, color: NSColor) -> NSView {
        let f = NSTextField(labelWithString: text); f.font = .systemFont(ofSize: 10, weight: .bold); f.textColor = .white
        let b = NSBox(); b.boxType = .custom; b.fillColor = color; b.cornerRadius = 4; b.borderWidth = 0; b.addSubview(f)
        f.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([f.centerXAnchor.constraint(equalTo: b.centerXAnchor), f.centerYAnchor.constraint(equalTo: b.centerYAnchor), b.heightAnchor.constraint(equalToConstant: 18), b.widthAnchor.constraint(equalTo: f.widthAnchor, constant: 12)])
        return b
    }
    
    func createBtn(title: String, symbol: String? = nil, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .recessed; b.controlSize = .regular
        if #available(macOS 11.0, *), let sym = symbol, let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
            img.isTemplate = true; b.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(scale: .medium)); b.imagePosition = .imageLeft
        }
        return b
    }
    
    @objc func didSync() { onAction("sync") }
    @objc func didTrack() { onAction("track") }
    @objc func didAuth() { onAction("auth") }
    @objc func didClear() { onAction("clear") }
    @objc func didQuit() { onAction("quit") }
    
    func runGit(args: [String]) -> String {
        let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = args
        let pipe = Pipe(); task.standardOutput = pipe; task.launch(); task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    var config = Config()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateConfig(); loadConfig()
        if let b = statusItem.button { 
            if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
                img.isTemplate = true; b.image = img
            } else { b.title = "ᚠ" }
            b.action = #selector(togglePopover); b.target = self 
        }
        popover.contentViewController = GitTrackerController(config: config, onAction: handleAction)
        popover.behavior = .transient; setupEditMenu()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.updateAllStatus() }
    }
    
    func setupEditMenu() {
        let m = NSMenu(); let e = NSMenu(title: "Edit"); e.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); let i = NSMenuItem(); i.submenu = e; m.addItem(i); NSApp.mainMenu = m
    }
    
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let b = statusItem.button {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            (popover.contentViewController as? GitTrackerController)?.loadBranches()
            (popover.contentViewController as? GitTrackerController)?.updateCommits()
            updateAllStatus()
        }
    }
    
    func handleAction(_ type: String) {
        if type.hasPrefix("repoChanged:") {
            if let index = Int(type.replacingOccurrences(of: "repoChanged:", with: "")) {
                config.selectedRepoIndex = index; saveConfig(); reloadUI()
            }
            return
        }
        if type == "updateAllStatus" { updateAllStatus(); return }
        switch type {
        case "sync": refreshRepo()
        case "track": promptForRepo()
        case "auth": promptForAuth()
        case "clear": clearRepo()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    
    func updateAllStatus() {
        DispatchQueue.global(qos: .background).async {
            var clean = 0, dirty = 0, ahead = 0, behind = 0, attention = 0
            for repo in self.config.repos {
                if !FileManager.default.fileExists(atPath: repo.path) { continue }
                let s = (self.popover.contentViewController as? GitTrackerController)?.getRepoStatus(path: repo.path) ?? (false, 0, 0, true)
                if s.3 { clean += 1 } 
                else {
                    if s.2 > 0 { behind += 1; attention += 1 }
                    else if s.1 > 0 { ahead += 1; attention += 1 }
                    else if s.0 { dirty += 1; attention += 1 }
                }
            }
            DispatchQueue.main.async {
                if let vc = self.popover.contentViewController as? GitTrackerController {
                    vc.summaryBar.update(clean: clean, dirty: dirty, ahead: ahead, behind: behind)
                    vc.summaryLabel.stringValue = "OVERVIEW: \(attention) REPOS NEED ATTENTION"
                }
                if let b = self.statusItem.button {
                    if attention > 0 {
                        if #available(macOS 11.0, *) {
                            let config = NSImage.SymbolConfiguration(hierarchicalColor: .systemOrange)
                            b.image = b.image?.withSymbolConfiguration(config)
                        }
                    } else {
                        if #available(macOS 11.0, *) {
                            b.image = b.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .controlTextColor))
                        }
                    }
                }
            }
        }
    }
    
    func promptForAuth() {
        let a = NSAlert(); a.messageText = "GitHub Credentials"
        let v = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 60)); v.orientation = .vertical; v.spacing = 8
        let userT = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); userT.placeholderString = "Username"; userT.stringValue = config.username ?? ""
        let tokenT = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); tokenT.placeholderString = "PAT Token"; tokenT.stringValue = config.token ?? ""
        v.addArrangedSubview(userT); v.addArrangedSubview(tokenT); a.accessoryView = v
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { config.username = userT.stringValue.trimmingCharacters(in: .whitespaces); config.token = tokenT.stringValue.trimmingCharacters(in: .whitespaces); saveConfig(); reloadUI() }
    }

    func promptForRepo() {
        let a = NSAlert(); a.messageText = "Add Repository"
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); t.placeholderString = "HTTPS URL or local folder path"; a.accessoryView = t
        a.addButton(withTitle: "Add"); a.addButton(withTitle: "Choose Local Folder..."); a.addButton(withTitle: "Cancel")
        let response = a.runModal()
        if response == .alertFirstButtonReturn { trackRepo(input: t.stringValue.trimmingCharacters(in: .whitespaces)) }
        else if response == .alertSecondButtonReturn {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url { trackRepo(input: url.path) }
        }
    }
    
    func trackRepo(input: String) {
        guard !input.isEmpty else { return }
        let cleanInput = input.replacingOccurrences(of: "file://", with: ""), expanded = (cleanInput as NSString).expandingTildeInPath
        let repoName = cleanInput.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"
        if FileManager.default.fileExists(atPath: expanded) { 
            addAndSelectRepo(TrackedRepo(url: cleanInput, path: expanded, name: repoName))
        } else {
            let path = "\(trackerRoot)/\(repoName)"
            DispatchQueue.global(qos: .userInitiated).async {
                var url = cleanInput
                if let tok = self.config.token, url.contains("github.com") { url = url.replacingOccurrences(of: "https://", with: "https://\(tok)@") }
                if FileManager.default.fileExists(atPath: path) { try? FileManager.default.removeItem(atPath: path) }
                let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = ["clone", url, path]
                task.launch(); task.waitUntilExit()
                DispatchQueue.main.async { if task.terminationStatus == 0 { self.addAndSelectRepo(TrackedRepo(url: cleanInput, path: path, name: repoName)) } }
            }
        }
    }
    
    func addAndSelectRepo(_ repo: TrackedRepo) {
        if !config.repos.contains(where: { $0.path == repo.path }) { config.repos.append(repo) }
        config.selectedRepoIndex = config.repos.firstIndex(where: { $0.path == repo.path }) ?? 0
        saveConfig(); reloadUI()
    }
    
    func refreshRepo() {
        guard let currentRepo = config.currentRepo else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.runShell(args: ["-C", currentRepo.path, "fetch", "--all"])
            _ = self.runShell(args: ["-C", currentRepo.path, "pull"])
            DispatchQueue.main.async { self.reloadUI(); self.updateAllStatus() }
        }
    }
    
    func clearRepo() { 
        if !config.repos.isEmpty && config.selectedRepoIndex < config.repos.count {
            config.repos.remove(at: config.selectedRepoIndex); config.selectedRepoIndex = max(0, config.selectedRepoIndex - 1); saveConfig(); reloadUI()
        }
    }
    
    func migrateConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["repos"] != nil { return }
            var m = Config()
            if let url = json["repoUrl"] as? String, let path = json["repoPath"] as? String {
                let name = url.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"
                m.repos.append(TrackedRepo(url: url, path: path, name: name))
            }
            if let u = json["username"] as? String { m.username = u }; if let t = json["token"] as? String { m.token = t }
            self.config = m; saveConfig()
        }
    }
    
    func loadConfig() { if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let decoded = try? JSONDecoder().decode(Config.self, from: data) { self.config = decoded } }
    func saveConfig() { if let data = try? JSONEncoder().encode(config) { try? data.write(to: URL(fileURLWithPath: configFilePath)) } }
    func reloadUI() { DispatchQueue.main.async { self.loadConfig(); self.popover.contentViewController = GitTrackerController(config: self.config, onAction: self.handleAction) } }
    func runShell(args: [String]) -> String {
        let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = args
        let pipe = Pipe(); task.standardOutput = pipe; task.launch(); task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
