import AppKit
import Foundation
import SwiftUI

class FlippedView: NSView { override var isFlipped: Bool { return true } }
class FlippedStackView: NSStackView { override var isFlipped: Bool { return true } }

struct Commit: Identifiable, Equatable {
    let id = UUID(); let hash: String; let message: String; let time: String; let author: String; let decoration: String; let dotColor: Color
}

struct ProjectSelectionView: View {
    let repos: [TrackedRepo]; let selectedRepoIndex: Int; let selectedBranch: String; let branches: [String]; let status: String; let statusColor: Color
    let onRepoChange: (Int) -> Void; let onBranchChange: (String) -> Void; let onAdd: () -> Void; let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").foregroundColor(.blue).font(.system(size: 14)).symbolRenderingMode(.hierarchical)
                repoDropdown.frame(width: 180); Spacer(); actionButtons
            }
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").foregroundColor(.blue).font(.system(size: 14)).symbolRenderingMode(.hierarchical)
                branchDropdown.frame(width: 180); Spacer(); statusPill
            }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.2)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1)))
    }
    
    var repoDropdown: some View {
        Menu {
            ForEach(0..<repos.count, id: \.self) { index in Button(repos[index].name) { onRepoChange(index) } }
        } label: {
            HStack {
                Text(repos.isEmpty ? "No Repositories" : repos[selectedRepoIndex].name).font(.system(size: 14, weight: .bold))
                Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
            }.padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.08)).cornerRadius(8)
        }
    }
    
    var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) { Label("Add", systemImage: "plus").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.blue.opacity(0.15)).cornerRadius(6) }.buttonStyle(.plain).foregroundColor(.blue)
            Button(action: onRemove) { Label("Remove", systemImage: "minus").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.red.opacity(0.15)).cornerRadius(6) }.buttonStyle(.plain).foregroundColor(.red)
        }
    }
    
    var branchDropdown: some View {
        Menu {
            let localBranches = branches.filter { !$0.hasPrefix("origin/") }
            let remoteBranches = branches.filter { $0.hasPrefix("origin/") }
            
            if !localBranches.isEmpty {
                Section("Local") {
                    ForEach(localBranches, id: \.self) { branch in
                        Button { onBranchChange(branch) } label: {
                            Label(branch, systemImage: "laptopcomputer")
                        }
                    }
                }
            }
            
            if !remoteBranches.isEmpty {
                Section("Remote") {
                    ForEach(remoteBranches, id: \.self) { branch in
                        Button { onBranchChange(branch) } label: {
                            Label(branch.replacingOccurrences(of: "origin/", with: ""), systemImage: "cloud.fill")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selectedBranch).font(.system(size: 14, weight: .bold))
                Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
            }.padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.08)).cornerRadius(8)
        }.disabled(repos.isEmpty)
    }
    
    var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: status.contains("Dirty") ? "pencil.circle.fill" : "checkmark.circle.fill").font(.system(size: 12))
            Text(status).font(.system(size: 11, weight: .black))
        }.padding(.horizontal, 10).padding(.vertical, 5).background(statusColor.opacity(0.15)).cornerRadius(20).foregroundColor(statusColor)
    }
}

struct StatusBadgeView: View {
    let isActive: Bool; let text: String; @State private var pulse = 1.0
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(isActive ? Color.green : Color.red).frame(width: 8, height: 8)
                if isActive { Circle().stroke(Color.green, lineWidth: 2).frame(width: 14, height: 14).scaleEffect(pulse).opacity(2.0 - pulse).onAppear { withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) { pulse = 2.0 } } }
            }
            Text(text).font(.system(size: 11, weight: .bold)).foregroundColor(isActive ? .green : .red)
        }
        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(isActive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))).overlay(Capsule().stroke(isActive ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1))
    }
}

struct CommitDetailView: View {
    let commit: Commit; let repoPath: String; let onBack: () -> Void
    @State private var files: [String] = []; @State private var isLoading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundColor(.blue) }.buttonStyle(.plain)
                Text("Commit Details").font(.headline); Spacer()
                Text(commit.hash).font(.system(size: 10, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 4).background(.ultraThinMaterial).cornerRadius(4)
            }.padding().background(Color.black.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(commit.message).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        HStack { Image(systemName: "person.circle.fill").symbolRenderingMode(.hierarchical); Text(commit.author); Spacer(); Text(commit.time) }.font(.subheadline).foregroundColor(.secondary)
                    }.padding(.horizontal)
                    Divider().padding(.horizontal)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHANGED FILES").font(.system(size: 10, weight: .black)).foregroundColor(.secondary)
                        if isLoading { ProgressView().scaleEffect(0.5).frame(maxWidth: .infinity) }
                        else { ForEach(files, id: \.self) { file in HStack { Image(systemName: "doc.fill").symbolRenderingMode(.hierarchical).foregroundColor(.blue); Text(file).font(.system(size: 12, design: .monospaced)) }.padding(.vertical, 4) } }
                    }.padding(.horizontal)
                }.padding(.vertical)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial).onAppear(perform: loadFiles)
    }
    func loadFiles() {
        let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = ["-C", repoPath, "show", "--name-only", "--pretty=format:", commit.hash]
        let pipe = Pipe(); task.standardOutput = pipe; task.launch()
        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) { self.files = output.components(separatedBy: "\n").filter { !$0.isEmpty } }
        self.isLoading = false
    }
}

struct HistoryNavigationView: View {
    let commits: [Commit]; let repoPath: String; @State private var selectedCommit: Commit? = nil
    var body: some View {
        ZStack {
            if let commit = selectedCommit {
                CommitDetailView(commit: commit, repoPath: repoPath, onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedCommit = nil } }).transition(.move(edge: .trailing))
            } else {
                ScrollView { VStack(spacing: 4) { ForEach(commits) { commit in CommitRowView(commit: commit) { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedCommit = commit } } } }.padding(.vertical, 8) }.transition(.move(edge: .leading))
            }
        }
    }
}

struct CommitRowView: View {
    let commit: Commit; let action: () -> Void; @State private var isHovered = false; @State private var isPressed = false
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 2).padding(.top, 0)
                Circle().fill(commit.dotColor).frame(width: 12, height: 12).overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 2)).padding(.top, 14)
            }.frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if !commit.decoration.isEmpty {
                        let branches = commit.decoration.replacingOccurrences(of: "HEAD -> ", with: "").components(separatedBy: ", ")
                        ForEach(branches, id: \.self) { branch in
                            let name = branch.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty && name != "origin/HEAD" {
                                let isTag = name.hasPrefix("tag: ")
                                let isRemote = name.hasPrefix("origin/")
                                let cleanName = name.replacingOccurrences(of: "tag: ", with: "")
                                let bgColor = isTag ? Color.orange.opacity(0.6) : (isRemote ? Color.gray.opacity(0.6) : Color.blue.opacity(0.6))
                                Text(cleanName).font(.system(size: 9, weight: .bold, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(bgColor).cornerRadius(4).foregroundColor(.white)
                            }
                        }
                    }
                    Text(commit.message).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundColor(.white)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.fill").font(.system(size: 10)).symbolRenderingMode(.hierarchical).foregroundColor(.secondary)
                    Text("\(commit.author) • \(commit.hash) • \(commit.time)").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }.padding(.vertical, 12).padding(.trailing, 8); Spacer()
        }
        .padding(.horizontal, 8).background(.ultraThinMaterial.opacity(isHovered ? 1.0 : 0.4)).cornerRadius(8).scaleEffect(isPressed ? 0.98 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered).animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed).onHover { hovering in isHovered = hovering }.onTapGesture { isPressed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isPressed = false; action() } }
    }
}

class StackedStatusBar: NSView {
    var cleanCount = 0, dirtyCount = 0, aheadCount = 0, behindCount = 0
    func update(clean: Int, dirty: Int, ahead: Int, behind: Int) { self.cleanCount = clean; self.dirtyCount = dirty; self.aheadCount = ahead; self.behindCount = behind; self.needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let total = CGFloat(cleanCount + dirtyCount + aheadCount + behindCount)
        if total == 0 { NSColor.white.withAlphaComponent(0.1).set(); NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill(); return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4); path.addClip()
        var currentX: CGFloat = 0; let segments: [(Int, NSColor)] = [(behindCount, .systemRed), (aheadCount, .systemBlue), (dirtyCount, .systemOrange), (cleanCount, .systemGreen)]
        for (count, color) in segments { if count > 0 { let width = (CGFloat(count) / total) * bounds.width; color.set(); NSRect(x: currentX, y: 0, width: width, height: bounds.height).fill(); currentX += width } }
    }
}

let trackerRoot = "/Users/dessy/Documents/sidehustle/GitTrackerTracker"; let configFilePath = "\(trackerRoot)/config.json"
struct TrackedRepo: Codable, Equatable { var url: String; var path: String; var name: String }
struct Config: Codable {
    var repos: [TrackedRepo] = []; var selectedRepoIndex = 0; var username: String?; var token: String?
    var currentRepo: TrackedRepo? { if repos.isEmpty { return nil }; return (selectedRepoIndex >= 0 && selectedRepoIndex < repos.count) ? repos[selectedRepoIndex] : repos.first }
}

class GitTrackerController: NSViewController {
    var config: Config; var onAction: (String) -> Void
    var statusHostingView: NSHostingView<StatusBadgeView>!
    var selectionHostingView: NSHostingView<ProjectSelectionView>!
    var summaryBar: StackedStatusBar!; var summaryLabel: NSTextField!
    var syncBtn: NSButton!; var historyArea: NSView!
    
    init(config: Config, onAction: @escaping (String) -> Void) { self.config = config; self.onAction = onAction; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { let effectView = NSVisualEffectView(); effectView.blendingMode = .behindWindow; effectView.state = .active; effectView.material = .hudWindow; self.view = effectView; self.view.setFrameSize(NSSize(width: 480, height: 780)) }
    override func viewDidLoad() { super.viewDidLoad(); setupUI() }
    
    func setupUI() {
        let rootStack = FlippedStackView(); rootStack.orientation = .vertical; rootStack.spacing = 18; rootStack.alignment = .leading
        rootStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24); rootStack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(rootStack)
        NSLayoutConstraint.activate([rootStack.topAnchor.constraint(equalTo: view.topAnchor), rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor), rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor), rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        
        let headerStack = NSStackView(); headerStack.orientation = .horizontal; headerStack.alignment = .centerY; headerStack.spacing = 12
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
            let iv = NSImageView(image: img); iv.contentTintColor = .systemBlue; iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 24).isActive = true; iv.heightAnchor.constraint(equalToConstant: 24).isActive = true; headerStack.addArrangedSubview(iv)
        }
        let titleLabel = NSTextField(labelWithString: "GitTracker"); titleLabel.font = .systemFont(ofSize: 26, weight: .heavy); headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(NSView()); headerStack.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        statusHostingView = NSHostingView(rootView: StatusBadgeView(isActive: config.token != nil, text: config.token != nil ? "Auth Active" : "No Auth Set"))
        statusHostingView.translatesAutoresizingMaskIntoConstraints = false; headerStack.addArrangedSubview(statusHostingView); rootStack.addArrangedSubview(headerStack)
        
        let summaryBox = NSBox(); summaryBox.boxType = .custom; summaryBox.fillColor = NSColor.white.withAlphaComponent(0.03); summaryBox.cornerRadius = 8; summaryBox.borderWidth = 0
        let summaryStack = NSStackView(); summaryStack.orientation = .vertical; summaryStack.alignment = .leading; summaryStack.spacing = 8; summaryStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        summaryLabel = NSTextField(labelWithString: "OVERVIEW"); summaryLabel.font = .systemFont(ofSize: 10, weight: .black); summaryLabel.textColor = .secondaryLabelColor; summaryStack.addArrangedSubview(summaryLabel)
        summaryBar = StackedStatusBar(); summaryBar.translatesAutoresizingMaskIntoConstraints = false; summaryStack.addArrangedSubview(summaryBar)
        NSLayoutConstraint.activate([summaryBar.heightAnchor.constraint(equalToConstant: 8), summaryBar.widthAnchor.constraint(equalTo: summaryStack.widthAnchor, constant: -32)])
        summaryBox.addSubview(summaryStack); summaryStack.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([summaryStack.topAnchor.constraint(equalTo: summaryBox.topAnchor), summaryStack.leadingAnchor.constraint(equalTo: summaryBox.leadingAnchor), summaryStack.trailingAnchor.constraint(equalTo: summaryBox.trailingAnchor), summaryStack.bottomAnchor.constraint(equalTo: summaryBox.bottomAnchor)])
        rootStack.addArrangedSubview(summaryBox); NSLayoutConstraint.activate([summaryBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])
        
        selectionHostingView = NSHostingView(rootView: ProjectSelectionView(repos: config.repos, selectedRepoIndex: config.selectedRepoIndex, selectedBranch: "All Branches", branches: ["All Branches"], status: "Clean", statusColor: .secondary, onRepoChange: { i in self.onAction("repoChanged:\(i)") }, onBranchChange: { b in self.onAction("branchChanged:\(b)") }, onAdd: { self.onAction("track") }, onRemove: { self.onAction("clear") }))
        selectionHostingView.translatesAutoresizingMaskIntoConstraints = false; rootStack.addArrangedSubview(selectionHostingView)
        NSLayoutConstraint.activate([selectionHostingView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])

        let commitTitle = NSTextField(labelWithString: "COMMIT HISTORY"); commitTitle.font = .systemFont(ofSize: 12, weight: .black); commitTitle.textColor = .secondaryLabelColor; rootStack.addArrangedSubview(commitTitle)
        historyArea = NSView(); historyArea.translatesAutoresizingMaskIntoConstraints = false; rootStack.addArrangedSubview(historyArea)
        NSLayoutConstraint.activate([historyArea.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48), historyArea.heightAnchor.constraint(equalToConstant: 400)])
        
        let footerBox = NSBox(); footerBox.boxType = .custom; footerBox.fillColor = NSColor.black.withAlphaComponent(0.2); footerBox.cornerRadius = 12; footerBox.borderWidth = 1; footerBox.borderColor = NSColor.white.withAlphaComponent(0.1)
        let footer = NSStackView(); footer.distribution = .fillEqually; footer.spacing = 12; footer.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        syncBtn = createBtn(title: "Sync", symbol: "arrow.triangle.2.circlepath", action: #selector(didSync)); syncBtn.bezelStyle = .texturedRounded; footer.addArrangedSubview(syncBtn)
        let authBtn = createBtn(title: "Auth", symbol: "person.crop.circle.badge.key", action: #selector(didAuth)); authBtn.bezelStyle = .texturedRounded; footer.addArrangedSubview(authBtn)
        let quitBtn = createBtn(title: "Quit", symbol: "power", action: #selector(didQuit)); quitBtn.bezelStyle = .texturedRounded; quitBtn.contentTintColor = .systemRed; footer.addArrangedSubview(quitBtn)
        footerBox.addSubview(footer); footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([footer.topAnchor.constraint(equalTo: footerBox.topAnchor), footer.leadingAnchor.constraint(equalTo: footerBox.leadingAnchor), footer.trailingAnchor.constraint(equalTo: footerBox.trailingAnchor), footer.bottomAnchor.constraint(equalTo: footerBox.bottomAnchor)])
        rootStack.addArrangedSubview(footerBox); NSLayoutConstraint.activate([footerBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])
        
        updateUIState(); onAction("updateAllStatus")
    }
    
    func updateUIState() {
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else {
            selectionHostingView.rootView = ProjectSelectionView(repos: config.repos, selectedRepoIndex: 0, selectedBranch: "N/A", branches: [], status: "Ready", statusColor: .secondary, onRepoChange: { i in self.onAction("repoChanged:\(i)") }, onBranchChange: { _ in }, onAdd: { self.onAction("track") }, onRemove: { self.onAction("clear") })
            return
        }
        let branchOut = runGit(args: ["-C", currentRepo.path, "branch", "-a", "--format=%(refname:short)"]).output
        var branches = [String]()
        for b in branchOut.components(separatedBy: "\n") {
            let clean = b.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && clean != "HEAD" && !clean.hasSuffix("/HEAD") && clean != "origin" {
                if !branches.contains(clean) { branches.append(clean) }
            }
        }
        let repoStatus = getRepoStatus(path: currentRepo.path)
        var statusStr = "✓ Clean", statusColor: Color = .secondary
        if !repoStatus.3 {
            var parts = [String]()
            if repoStatus.0 { parts.append("Dirty") }
            if repoStatus.1 > 0 { parts.append("↑\(repoStatus.1)") }
            if repoStatus.2 > 0 { parts.append("↓\(repoStatus.2)") }
            statusStr = parts.joined(separator: " "); statusColor = .orange
        }
        let currentBranch = runGit(args: ["-C", currentRepo.path, "rev-parse", "--abbrev-ref", "HEAD"]).output
        selectionHostingView.rootView = ProjectSelectionView(repos: config.repos, selectedRepoIndex: config.selectedRepoIndex, selectedBranch: currentBranch, branches: branches, status: statusStr, statusColor: statusColor, onRepoChange: { i in self.onAction("repoChanged:\(i)") }, onBranchChange: { b in self.onAction("branchChanged:\(b)") }, onAdd: { self.onAction("track") }, onRemove: { self.onAction("clear") })
        updateCommits()
    }
    
    func updateCommits() {
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else { return }
        let lines = runGit(args: ["-C", currentRepo.path, "log", "-n", "100", "--pretty=format:%h|%s|%ar|%an|%D"]).output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var commits = [Commit]()
        for line in lines {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 4 {
                let deco = parts.count > 4 ? parts[4] : ""
                commits.append(Commit(hash: parts[0], message: parts[1], time: parts[2], author: parts[3], decoration: deco, dotColor: Color(getBranchColor(deco: deco))))
            }
        }
        let hostingView = NSHostingView(rootView: HistoryNavigationView(commits: commits, repoPath: currentRepo.path))
        hostingView.translatesAutoresizingMaskIntoConstraints = false; historyArea.subviews.forEach { $0.removeFromSuperview() }; historyArea.addSubview(hostingView)
        NSLayoutConstraint.activate([hostingView.topAnchor.constraint(equalTo: historyArea.topAnchor), hostingView.leadingAnchor.constraint(equalTo: historyArea.leadingAnchor), hostingView.trailingAnchor.constraint(equalTo: historyArea.trailingAnchor), hostingView.bottomAnchor.constraint(equalTo: historyArea.bottomAnchor)])
    }
    
    func getBranchColor(deco: String) -> NSColor {
        if deco.contains("main") || deco.contains("master") { return .systemGreen }
        if deco.contains("dev") || deco.contains("develop") { return .systemYellow }
        return .systemBlue
    }
    func getRepoStatus(path: String) -> (Bool, Int, Int, Bool) {
        let dirty = !runGit(args: ["-C", path, "status", "--porcelain"]).output.isEmpty
        let revList = runGit(args: ["-C", path, "rev-list", "--left-right", "--count", "HEAD...@{u}"]).output
        var ahead = 0, behind = 0
        if !revList.isEmpty && !revList.hasPrefix("fatal") {
            let counts = revList.components(separatedBy: .whitespaces)
            if counts.count == 2 { ahead = Int(counts[0]) ?? 0; behind = Int(counts[1]) ?? 0 }
        }
        return (dirty, ahead, behind, !dirty && ahead == 0 && behind == 0)
    }
    func createBtn(title: String, symbol: String? = nil, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .recessed; b.controlSize = .regular
        if #available(macOS 11.0, *), let sym = symbol, let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
            img.isTemplate = true; b.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(scale: .medium)); b.imagePosition = .imageLeft
        }
        return b
    }
    @objc func didSync() { onAction("sync") }; @objc func didTrack() { onAction("track") }; @objc func didAuth() { onAction("auth") }; @objc func didClear() { onAction("clear") }; @objc func didQuit() { onAction("quit") }
    
    @discardableResult
    func runGit(args: [String]) -> (output: String, success: Bool) {
        let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = args; let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        do { try task.run(); task.waitUntilExit() } catch { return ("", false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus == 0)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); let popover = NSPopover(); var config = Config()
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateConfig(); loadConfig()
        if let b = statusItem.button { 
            if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) { img.isTemplate = true; b.image = img } else { b.title = "ᚠ" }
            b.action = #selector(togglePopover); b.target = self 
        }
        popover.contentViewController = GitTrackerController(config: config, onAction: handleAction); popover.behavior = .transient; setupEditMenu()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.updateAllStatus() }
    }
    func setupEditMenu() { let m = NSMenu(); let e = NSMenu(title: "Edit"); e.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); let i = NSMenuItem(); i.submenu = e; m.addItem(i); NSApp.mainMenu = m }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let b = statusItem.button {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey()
            (popover.contentViewController as? GitTrackerController)?.updateUIState(); updateAllStatus()
        }
    }
    @discardableResult
    func runShell(args: [String]) -> (output: String, success: Bool) {
        let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = args; let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        do { try task.run(); task.waitUntilExit() } catch { return ("", false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus == 0)
    }
    
    func handleAction(_ type: String) {
        if type.hasPrefix("repoChanged:") { if let index = Int(type.replacingOccurrences(of: "repoChanged:", with: "")) { config.selectedRepoIndex = index; saveConfig(); reloadUI() }; return }
        if type.hasPrefix("branchChanged:") {
            let branch = type.replacingOccurrences(of: "branchChanged:", with: "")
            if branch != "All Branches", let currentRepo = config.currentRepo {
                setStatus("⌛ Checking out...")
                DispatchQueue.global(qos: .userInitiated).async {
                    var success = false
                    if branch.hasPrefix("origin/") {
                        let localName = branch.replacingOccurrences(of: "origin/", with: "")
                        let exists = self.runShell(args: ["-C", currentRepo.path, "rev-parse", "--verify", localName]).success
                        if !exists {
                            success = self.runShell(args: ["-C", currentRepo.path, "checkout", "-b", localName, "--track", branch]).success
                        } else {
                            success = self.runShell(args: ["-C", currentRepo.path, "checkout", localName]).success
                        }
                    } else {
                        success = self.runShell(args: ["-C", currentRepo.path, "checkout", branch]).success
                    }
                    DispatchQueue.main.async {
                        if success { self.reloadUI(status: "✅ Switched to \(branch)") }
                        else { self.setStatus("❌ Checkout Failed", color: .systemRed) }
                    }
                }
            }; return
        }
        if type == "updateAllStatus" { updateAllStatus(); return }
        switch type {
        case "sync": refreshRepo(); case "track": promptForRepo(); case "auth": promptForAuth(); case "clear": clearRepo(); case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        DispatchQueue.main.async { if let vc = self.popover.contentViewController as? GitTrackerController { vc.statusHostingView.rootView = StatusBadgeView(isActive: self.config.token != nil, text: text) } }
    }
    func updateAllStatus() {
        DispatchQueue.global(qos: .background).async {
            var clean = 0, dirty = 0, ahead = 0, behind = 0, attention = 0
            for repo in self.config.repos {
                if !FileManager.default.fileExists(atPath: repo.path) { continue }
                let s = (self.popover.contentViewController as? GitTrackerController)?.getRepoStatus(path: repo.path) ?? (false, 0, 0, true)
                if s.3 { clean += 1 } else { if s.2 > 0 { behind += 1; attention += 1 } else if s.1 > 0 { ahead += 1; attention += 1 } else if s.0 { dirty += 1; attention += 1 } }
            }
            DispatchQueue.main.async {
                if let vc = self.popover.contentViewController as? GitTrackerController {
                    vc.summaryBar.update(clean: clean, dirty: dirty, ahead: ahead, behind: behind); vc.summaryLabel.stringValue = "OVERVIEW: \(attention) REPOS NEED ATTENTION"
                }
                if let b = self.statusItem.button {
                    if attention > 0 { if #available(macOS 11.0, *) { b.image = b.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .systemOrange)) } }
                    else { if #available(macOS 11.0, *) { b.image = b.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .controlTextColor)) } }
                }
            }
        }
    }
    func promptForAuth() {
        let a = NSAlert(); a.messageText = "GitHub Credentials"; let v = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 60)); v.orientation = .vertical; v.spacing = 8
        let userT = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); userT.placeholderString = "Username"; userT.stringValue = config.username ?? ""
        let tokenT = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); tokenT.placeholderString = "PAT Token"; tokenT.stringValue = config.token ?? ""
        v.addArrangedSubview(userT); v.addArrangedSubview(tokenT); a.accessoryView = v; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { config.username = userT.stringValue.trimmingCharacters(in: .whitespaces); config.token = tokenT.stringValue.trimmingCharacters(in: .whitespaces); saveConfig(); reloadUI() }
    }
    func promptForRepo() {
        let a = NSAlert(); a.messageText = "Add Repository"; let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); t.placeholderString = "HTTPS URL or local folder path"; a.accessoryView = t
        a.addButton(withTitle: "Add"); a.addButton(withTitle: "Choose Local Folder..."); a.addButton(withTitle: "Cancel")
        let response = a.runModal()
        if response == .alertFirstButtonReturn { trackRepo(input: t.stringValue.trimmingCharacters(in: .whitespaces)) }
        else if response == .alertSecondButtonReturn {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url { trackRepo(input: url.path) }
        }
    }
    func trackRepo(input: String) {
        guard !input.isEmpty else { return }; let cleanInput = input.replacingOccurrences(of: "file://", with: ""), expanded = (cleanInput as NSString).expandingTildeInPath; let repoName = cleanInput.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"
        if FileManager.default.fileExists(atPath: expanded) { addAndSelectRepo(TrackedRepo(url: cleanInput, path: expanded, name: repoName)) }
        else {
            let path = "\(trackerRoot)/\(repoName)"; setStatus("⌛ Cloning..."); DispatchQueue.global(qos: .userInitiated).async {
                var url = cleanInput; if let tok = self.config.token, url.contains("github.com") { url = url.replacingOccurrences(of: "https://", with: "https://\(tok)@") }
                if FileManager.default.fileExists(atPath: path) { try? FileManager.default.removeItem(atPath: path) }
                let task = Process(); task.launchPath = "/usr/bin/git"; task.arguments = ["clone", url, path]; task.launch(); task.waitUntilExit()
                DispatchQueue.main.async { if task.terminationStatus == 0 { self.addAndSelectRepo(TrackedRepo(url: cleanInput, path: path, name: repoName)) } }
            }
        }
    }
    func addAndSelectRepo(_ repo: TrackedRepo) { if !config.repos.contains(where: { $0.path == repo.path }) { config.repos.append(repo) }; config.selectedRepoIndex = config.repos.firstIndex(where: { $0.path == repo.path }) ?? 0; saveConfig(); reloadUI() }
    func refreshRepo() {
        guard let currentRepo = config.currentRepo else { return }
        DispatchQueue.main.async { if let vc = self.popover.contentViewController as? GitTrackerController { vc.syncBtn.isEnabled = false; vc.syncBtn.title = "Syncing..."; self.setStatus("⌛ Syncing...") } }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.runShell(args: ["-C", currentRepo.path, "fetch", "--all"]); _ = self.runShell(args: ["-C", currentRepo.path, "pull"])
            DispatchQueue.main.async { self.reloadUI(status: "✅ Sync Complete"); self.updateAllStatus(); DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.setStatus("Auth Active") } }
        }
    }
    func clearRepo() { if !config.repos.isEmpty && config.selectedRepoIndex < config.repos.count { config.repos.remove(at: config.selectedRepoIndex); config.selectedRepoIndex = max(0, config.selectedRepoIndex - 1); saveConfig(); reloadUI() } }
    func migrateConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["repos"] != nil { return }; var m = Config(); if let url = json["repoUrl"] as? String, let path = json["repoPath"] as? String { let name = url.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"; m.repos.append(TrackedRepo(url: url, path: path, name: name)) }
            if let u = json["username"] as? String { m.username = u }; if let t = json["token"] as? String { m.token = t }; self.config = m; saveConfig()
        }
    }
    func loadConfig() { if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let decoded = try? JSONDecoder().decode(Config.self, from: data) { self.config = decoded } }
    func saveConfig() { if let data = try? JSONEncoder().encode(config) { try? data.write(to: URL(fileURLWithPath: configFilePath)) } }
    func reloadUI(status: String? = nil) { DispatchQueue.main.async { self.loadConfig(); let vc = GitTrackerController(config: self.config, onAction: self.handleAction); self.popover.contentViewController = vc; if let s = status { self.setStatus(s) } } }
}

let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.run()
