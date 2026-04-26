import AppKit
import Combine
import Foundation
import Security
import SwiftUI

let githubOAuthClientID = "Ov23liMEarmthhySRg1r"

class FlippedView: NSView { override var isFlipped: Bool { return true } }
class FlippedStackView: NSStackView { override var isFlipped: Bool { return true } }

struct Commit: Identifiable, Equatable {
    let id = UUID(); let hash: String; let message: String; let time: String; let author: String; let decoration: String; let dotColor: Color
}

let gitFieldSeparator = "\u{1f}"

@discardableResult
func runGitProcess(args: [String], environment: [String: String]? = nil) -> (output: String, success: Bool) {
    let task = Process()
    task.launchPath = "/usr/bin/git"
    task.arguments = args
    if let environment {
        task.environment = environment
    }

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
    } catch {
        return ("", false)
    }

    let handle = pipe.fileHandleForReading
    let outputQueue = DispatchQueue(label: "GitTracker.git-output-reader", qos: .userInitiated)
    var outputData = Data()
    let group = DispatchGroup()
    group.enter()
    outputQueue.async {
        outputData = handle.readDataToEndOfFile()
        group.leave()
    }

    task.waitUntilExit()
    group.wait()

    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (output, task.terminationStatus == 0)
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
            Image(systemName: status.contains("Modified") ? "pencil.circle.fill" : "checkmark.circle.fill").font(.system(size: 12))
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
            Text(text.uppercased()).font(.system(size: 11, weight: .bold)).foregroundColor(isActive ? .green : .red)
        }
        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(isActive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))).overlay(Capsule().stroke(isActive ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1))
    }
}

struct CommitDetailView: View {
    let commit: Commit; let repoPath: String; let onBack: () -> Void
    @State private var files: [String] = []; @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Modern Header
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commit Details")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(commit.hash.prefix(8))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                }
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(commit.hash, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Full Hash")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Commit Message Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(commit.message)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 12) {
                            Circle()
                                .fill(commit.dotColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: commit.dotColor.opacity(0.5), radius: 3)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                Text(commit.author)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                Text(commit.time)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    .padding(.horizontal, 16)
                    
                    // Changed Files Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CHANGED FILES")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.secondary)
                                .kerning(1)
                            
                            Spacer()
                            
                            if !isLoading {
                                Text("\(files.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing changes...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 1) {
                                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                                    FileRowView(file: file, commitHash: commit.hash, repoPath: repoPath)
                                        .background(index % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView())
        .onAppear(perform: loadFiles)
    }
    
    func loadFiles() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: (output: String, success: Bool)
            if self.commit.hash == "UNCOMMITTED" {
                result = runGitProcess(args: ["-C", self.repoPath, "status", "--porcelain"])
            } else {
                result = runGitProcess(args: ["-C", self.repoPath, "show", "--name-only", "--pretty=format:", self.commit.hash])
            }
            DispatchQueue.main.async {
                if result.success {
                    if self.commit.hash == "UNCOMMITTED" {
                        self.files = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }.map { String($0.dropFirst(3)) }
                    } else {
                        self.files = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
                    }
                } else {
                    self.files = []
                }
                self.isLoading = false
            }
        }
    }
}

struct FileRowView: View {
    let file: String
    let commitHash: String
    let repoPath: String
    
    @State private var isExpanded = false
    @State private var diffText: String? = nil
    @State private var isLoadingDiff = false
    
    var fileExtension: String {
        (file as NSString).pathExtension.lowercased()
    }
    
    var fileIcon: (String, Color) {
        switch fileExtension {
        case "swift": return ("swift", .orange)
        case "json": return ("braces", .yellow)
        case "plist": return ("list.bullet.rectangle.fill", .gray)
        case "md": return ("text.alignleft", .blue)
        case "png", "jpg", "jpeg", "svg": return ("photo.fill", .purple)
        default: return ("doc.fill", .blue)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
                if isExpanded && diffText == nil {
                    loadDiff()
                }
            }) {
                HStack(spacing: 12) {
                    let (icon, color) = fileIcon
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(color)
                        .frame(width: 20)
                    
                    Text(file)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoadingDiff {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else if let diff = diffText {
                        if diff.isEmpty {
                            Text("Binary or unsupported file diff.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 2) {
                                    let lines = diff.components(separatedBy: "\n")
                                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                        Text(line)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(colorForLine(line))
                                            .padding(.horizontal, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(backgroundColorForLine(line))
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.15))
                .overlay(Rectangle().frame(width: 2).foregroundColor(Color.blue.opacity(0.5)), alignment: .leading)
            }
        }
    }
    
    func colorForLine(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return .secondary
    }
    
    func backgroundColorForLine(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.1) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.1) }
        if line.hasPrefix("@@") { return Color.blue.opacity(0.05) }
        return .clear
    }
    
    func loadDiff() {
        isLoadingDiff = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: (output: String, success: Bool)
            if self.commitHash == "UNCOMMITTED" {
                result = runGitProcess(args: ["-C", self.repoPath, "diff", "HEAD", "--", self.file])
            } else {
                result = runGitProcess(args: ["-C", self.repoPath, "show", "--pretty=format:", self.commitHash, "--", self.file])
            }
            DispatchQueue.main.async {
                self.diffText = result.success ? result.output : "Error loading diff"
                self.isLoadingDiff = false
            }
        }
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
    var upToDateCount = 0, modifiedCount = 0, aheadCount = 0, behindCount = 0
    func update(upToDate: Int, modified: Int, ahead: Int, behind: Int) { self.upToDateCount = upToDate; self.modifiedCount = modified; self.aheadCount = ahead; self.behindCount = behind; self.needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let total = CGFloat(upToDateCount + modifiedCount + aheadCount + behindCount)
        if total == 0 { NSColor.white.withAlphaComponent(0.1).set(); NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill(); return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4); path.addClip()
        var currentX: CGFloat = 0; let segments: [(Int, NSColor)] = [(behindCount, .systemRed), (aheadCount, .systemBlue), (modifiedCount, .systemOrange), (upToDateCount, .systemGreen)]
        for (count, color) in segments { if count > 0 { let width = (CGFloat(count) / total) * bounds.width; color.set(); NSRect(x: currentX, y: 0, width: width, height: bounds.height).fill(); currentX += width } }
    }
}

let fileManager = FileManager.default
let homeDirectory = fileManager.homeDirectoryForCurrentUser
let trackerRoot = homeDirectory.appendingPathComponent("Documents/GitTracker").path
let legacyTrackerRoot = homeDirectory.appendingPathComponent("Documents/sidehustle/GitTrackerTracker").path
let configFilePath = "\(trackerRoot)/config.json"
let legacyConfigFilePath = "\(legacyTrackerRoot)/config.json"
struct TrackedRepo: Codable, Equatable { var url: String; var path: String; var name: String }
struct Config: Codable {
    var repos: [TrackedRepo] = []; var selectedRepoIndex = 0; var githubLogin: String?
    var username: String?; var token: String?
    var currentRepo: TrackedRepo? { if repos.isEmpty { return nil }; return (selectedRepoIndex >= 0 && selectedRepoIndex < repos.count) ? repos[selectedRepoIndex] : repos.first }
}

enum GitHubAuthError: LocalizedError {
    case missingClientID
    case invalidVerificationURL
    case server(String)
    case cancelled
    case missingAccessToken
    
    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Set your GitHub OAuth client ID first."
        case .invalidVerificationURL: return "GitHub returned an invalid verification URL."
        case .server(let message): return message
        case .cancelled: return "GitHub sign-in was cancelled."
        case .missingAccessToken: return "GitHub did not return an access token."
        }
    }
}

struct GitHubDeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int
}

struct GitHubAccessTokenResponse: Decodable {
    let access_token: String?
    let token_type: String?
    let scope: String?
    let error: String?
    let error_description: String?
    let interval: Int?
}

struct GitHubUserResponse: Decodable {
    let login: String
}

enum KeychainHelper {
    static let service = "com.gittracker.github"
    static let tokenAccount = "oauth-token"
    
    static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: tokenAccount]
        SecItemDelete(query as CFDictionary)
        var saveQuery = query
        saveQuery[kSecValueData as String] = data
        saveQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(saveQuery as CFDictionary, nil)
    }
    
    static func loadToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: tokenAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func deleteToken() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: tokenAccount]
        SecItemDelete(query as CFDictionary)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.blendingMode = .behindWindow; view.state = .active; view.material = .hudWindow; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AuthView: View {
    let githubLogin: String?
    var onStart: () -> Void; var onSignOut: () -> Void; var onCancel: () -> Void
    init(githubLogin: String?, onStart: @escaping () -> Void, onSignOut: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.githubLogin = githubLogin
        self.onStart = onStart; self.onSignOut = onSignOut; self.onCancel = onCancel
    }
    var body: some View {
        VStack(spacing: 20) {
            Text("GitHub Sign In").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Text(githubLogin == nil ? "Git Tracker will open GitHub in your browser and store the approved access token in your macOS Keychain." : "Signed in as \(githubLogin!). Signing in again will refresh the GitHub session.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                if githubLogin != nil {
                    Button("Sign Out", action: onSignOut).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.red.opacity(0.8)).foregroundColor(.white).cornerRadius(6)
                }
                Button(githubLogin == nil ? "Sign In" : "Refresh") { onStart() }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6)
            }
        }.padding(20).frame(width: 320).background(VisualEffectView())
    }
}

struct DeviceFlowView: View {
    let userCode: String
    let verificationURL: String
    var onOpenBrowser: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Authorize GitHub").font(.headline)
            Text("Enter this code in GitHub to finish signing in.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text(userCode)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
            Text(verificationURL)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Open GitHub", action: onOpenBrowser).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6)
            }
        }.padding(20).frame(width: 320).background(VisualEffectView())
    }
}

struct AddRepoView: View {
    @State private var input: String = ""
    var onAdd: (String) -> Void; var onBrowse: () -> Void; var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Repository").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("HTTPS URL OR LOCAL PATH").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                TextField("https://github.com/...", text: $input).textFieldStyle(.plain).padding(8).background(Color.white.opacity(0.1)).cornerRadius(6)
            }
            VStack(spacing: 8) {
                Button(action: { onAdd(input) }) {
                    HStack { Image(systemName: "plus.circle.fill"); Text("Add Repository") }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.blue).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain).disabled(input.isEmpty)
                Button(action: onBrowse) {
                    HStack { Image(systemName: "folder.fill"); Text("Choose Local Folder...") }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.white.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
                Button("Cancel", action: onCancel).buttonStyle(.plain).foregroundColor(.secondary).font(.system(size: 11))
            }
        }.padding(20).frame(width: 280).background(VisualEffectView())
    }
}

final class CloneDraft: ObservableObject {
    let url: String
    let repoName: String
    @Published var localPath: String
    
    init(url: String, repoName: String, localPath: String) {
        self.url = url
        self.repoName = repoName
        self.localPath = localPath
    }
    
    var finalPath: String {
        URL(fileURLWithPath: localPath).appendingPathComponent(repoName).standardized.path
    }
}

struct CloneRemoteView: View {
    @ObservedObject var draft: CloneDraft
    var onChoosePath: () -> Void
    var onClone: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clone Repository").font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("REPOSITORY URL").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Text(draft.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("LOCAL PATH").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("", text: $draft.localPath)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    Button("Choose...", action: onChoosePath)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("FINAL DESTINATION").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Text(draft.finalPath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                Button("Clone", action: onClone)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .disabled(draft.localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(VisualEffectView())
    }
}

struct CommitView: View {
    @State private var message: String = ""
    var onCommit: (String) -> Void
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Commit Changes").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("COMMIT MESSAGE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                if #available(macOS 13.0, *) {
                    TextEditor(text: $message)
                        .font(.system(size: 12))
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                } else {
                    TextEditor(text: $message)
                        .font(.system(size: 12))
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .frame(height: 80)
                }
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Commit") { onCommit(message) }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 320).background(VisualEffectView())
    }
}

struct RebaseView: View {
    let branches: [String]
    @State private var selectedBranch: String
    var onRebase: (String) -> Void
    var onCancel: () -> Void
    
    init(branches: [String], onRebase: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.branches = branches
        _selectedBranch = State(initialValue: branches.first ?? "")
        self.onRebase = onRebase
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rebase Branch").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("TARGET BRANCH").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Picker("", selection: $selectedBranch) {
                    ForEach(branches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Rebase") { onRebase(selectedBranch) }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6).disabled(selectedBranch.isEmpty)
            }
        }.padding(20).frame(width: 280).background(VisualEffectView())
    }
}

struct MergeView: View {
    let branches: [String]
    let currentBranch: String
    @State private var selectedBranch: String
    var onMerge: (String) -> Void
    var onCancel: () -> Void
    
    init(branches: [String], currentBranch: String, onMerge: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.branches = branches
        self.currentBranch = currentBranch
        _selectedBranch = State(initialValue: branches.first ?? "")
        self.onMerge = onMerge
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Merge Branch").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("MERGE INTO \(currentBranch.uppercased())").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Picker("", selection: $selectedBranch) {
                    ForEach(branches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Merge") { onMerge(selectedBranch) }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6).disabled(selectedBranch.isEmpty)
            }
        }.padding(20).frame(width: 280).background(VisualEffectView())
    }
}

struct StashPromptView: View {
    var onStashAndSwitch: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Uncommitted Changes").font(.headline)
            Text("Switching branches will overwrite your local changes. Do you want to stash them and continue?")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Stash & Switch", action: onStashAndSwitch).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.orange).foregroundColor(.white).cornerRadius(6)
            }
        }.padding(20).frame(width: 280).background(VisualEffectView())
    }
}

struct StashPopPromptView: View {
    var onPopStash: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Restore Stashed Changes").font(.headline)
            Text("You have changes that were auto-stashed before your last branch switch. Do you want to apply them to this branch?")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Button("Dismiss", action: onDismiss).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.1)).cornerRadius(6)
                Button("Pop Stash", action: onPopStash).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).foregroundColor(.white).cornerRadius(6)
            }
        }.padding(20).frame(width: 280).background(VisualEffectView())
    }
}

class GitTrackerController: NSViewController {
    var config: Config; var onAction: (String) -> Void
    let isAuthenticated: Bool
    var statusHostingView: NSHostingView<StatusBadgeView>!
    var selectionHostingView: NSHostingView<ProjectSelectionView>!
    var summaryBar: StackedStatusBar!; var summaryLabel: NSTextField!
    var upToDateLabel: NSTextField!, modifiedLabel: NSTextField!, aheadLabel: NSTextField!, behindLabel: NSTextField!
    var syncBtn: NSButton!; var historyArea: NSView!
    
    init(config: Config, isAuthenticated: Bool, onAction: @escaping (String) -> Void) { self.config = config; self.isAuthenticated = isAuthenticated; self.onAction = onAction; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { let effectView = NSVisualEffectView(); effectView.blendingMode = .behindWindow; effectView.state = .active; effectView.material = .hudWindow; self.view = effectView; self.view.setFrameSize(NSSize(width: 480, height: 820)) }
    override func viewDidLoad() { super.viewDidLoad(); setupUI() }
    
    func setupUI() {
        let rootStack = FlippedStackView(); rootStack.orientation = .vertical; rootStack.spacing = 14; rootStack.alignment = .leading
        rootStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24); rootStack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(rootStack)
        NSLayoutConstraint.activate([rootStack.topAnchor.constraint(equalTo: view.topAnchor), rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor), rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        
        let headerStack = NSStackView(); headerStack.orientation = .horizontal; headerStack.alignment = .centerY; headerStack.spacing = 12
        let titleLabel = NSTextField(labelWithString: "GitTracker"); titleLabel.font = .systemFont(ofSize: 26, weight: .heavy); titleLabel.textColor = .systemBlue; headerStack.addArrangedSubview(titleLabel)
        let vLabelTop = NSTextField(labelWithString: "V3.2"); vLabelTop.font = .systemFont(ofSize: 12, weight: .bold); vLabelTop.textColor = .white; vLabelTop.isBordered = false; vLabelTop.drawsBackground = false; headerStack.addArrangedSubview(vLabelTop)
        
        headerStack.addArrangedSubview(NSView()); headerStack.arrangedSubviews.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        statusHostingView = NSHostingView(rootView: StatusBadgeView(isActive: isAuthenticated, text: isAuthenticated ? "Auth Active" : "No Auth Set"))
        statusHostingView.translatesAutoresizingMaskIntoConstraints = false; headerStack.addArrangedSubview(statusHostingView); rootStack.addArrangedSubview(headerStack)
        
        let summaryBox = NSBox(); summaryBox.boxType = .custom; summaryBox.fillColor = NSColor.white.withAlphaComponent(0.05); summaryBox.cornerRadius = 12; summaryBox.borderWidth = 1; summaryBox.borderColor = NSColor.white.withAlphaComponent(0.1)
        let summaryStack = NSStackView(); summaryStack.orientation = .vertical; summaryStack.alignment = .leading; summaryStack.spacing = 10; summaryStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        summaryLabel = NSTextField(labelWithString: "REPOSITORY HEALTH"); summaryLabel.font = .systemFont(ofSize: 10, weight: .black); summaryLabel.textColor = .secondaryLabelColor; summaryStack.addArrangedSubview(summaryLabel)
        
        let metricsStack = NSStackView(); metricsStack.orientation = .horizontal; metricsStack.spacing = 20; metricsStack.alignment = .centerY
        behindLabel = createMetricLabel(color: .systemRed); metricsStack.addArrangedSubview(behindLabel)
        aheadLabel = createMetricLabel(color: .systemBlue); metricsStack.addArrangedSubview(aheadLabel)
        modifiedLabel = createMetricLabel(color: .systemOrange); metricsStack.addArrangedSubview(modifiedLabel)
        upToDateLabel = createMetricLabel(color: .systemGreen); metricsStack.addArrangedSubview(upToDateLabel)
        summaryStack.addArrangedSubview(metricsStack)
        
        summaryBar = StackedStatusBar(); summaryBar.translatesAutoresizingMaskIntoConstraints = false; summaryStack.addArrangedSubview(summaryBar)
        NSLayoutConstraint.activate([summaryBar.heightAnchor.constraint(equalToConstant: 12), summaryBar.widthAnchor.constraint(equalTo: summaryStack.widthAnchor, constant: -32)])
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
        syncBtn = createBtn(title: "Fetch origin", symbol: "arrow.triangle.2.circlepath", action: #selector(didSync)); syncBtn.bezelStyle = .texturedRounded; footer.addArrangedSubview(syncBtn)
        let actionsBtn = createBtn(title: "Actions", symbol: "ellipsis.circle", action: #selector(showActionsMenu)); actionsBtn.bezelStyle = .texturedRounded; footer.addArrangedSubview(actionsBtn)
        let authBtn = createBtn(title: "Auth", symbol: "person.fill", action: #selector(didAuth)); authBtn.bezelStyle = .texturedRounded; footer.addArrangedSubview(authBtn)
        let quitBtn = createBtn(title: "Quit", symbol: "power", action: #selector(didQuit)); quitBtn.bezelStyle = .texturedRounded; quitBtn.contentTintColor = .systemRed; footer.addArrangedSubview(quitBtn)
        footerBox.addSubview(footer); footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([footer.topAnchor.constraint(equalTo: footerBox.topAnchor), footer.leadingAnchor.constraint(equalTo: footerBox.leadingAnchor), footer.trailingAnchor.constraint(equalTo: footerBox.trailingAnchor), footer.bottomAnchor.constraint(equalTo: footerBox.bottomAnchor)])
        rootStack.addArrangedSubview(footerBox); NSLayoutConstraint.activate([footerBox.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48)])
        
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .vertical); rootStack.addArrangedSubview(spacer)
        
        updateUIState(); onAction("updateAllStatus")
    }
    
    func updateUIState() {
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else {
            let hasMissingRepo = config.currentRepo != nil
            selectionHostingView.rootView = ProjectSelectionView(repos: config.repos, selectedRepoIndex: config.selectedRepoIndex, selectedBranch: "N/A", branches: [], status: hasMissingRepo ? "Missing Folder" : "Ready", statusColor: hasMissingRepo ? .orange : .secondary, onRepoChange: { i in self.onAction("repoChanged:\(i)") }, onBranchChange: { _ in }, onAdd: { self.onAction("track") }, onRemove: { self.onAction("clear") })
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
        var statusStr = "✓ Up to Date", statusColor: Color = .secondary
        if !repoStatus.3 {
            var parts = [String]()
            if repoStatus.0 { parts.append("Modified") }
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
        let format = "%h\(gitFieldSeparator)%s\(gitFieldSeparator)%ar\(gitFieldSeparator)%an\(gitFieldSeparator)%D"
        let lines = runGit(args: ["-C", currentRepo.path, "log", "-n", "100", "--pretty=format:\(format)"]).output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var commits = [Commit]()
        
        let repoStatus = getRepoStatus(path: currentRepo.path)
        if repoStatus.0 {
            commits.append(Commit(hash: "UNCOMMITTED", message: "Uncommitted Changes", time: "just now", author: "Local Working Directory", decoration: "", dotColor: .orange))
        }
        
        for line in lines {
            let parts = line.components(separatedBy: gitFieldSeparator)
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
    @objc func showActionsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Commit...", action: #selector(didCommit), keyEquivalent: "")
        menu.addItem(withTitle: "Push", action: #selector(didPush), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Rebase...", action: #selector(didRebase), keyEquivalent: "")
        menu.addItem(withTitle: "Merge...", action: #selector(didMerge), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Stash Changes", action: #selector(didStash), keyEquivalent: "")
        menu.addItem(withTitle: "Stash Pop", action: #selector(didStashPop), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    @objc func didCommit() { onAction("promptCommit") }
    @objc func didPush() { onAction("push") }
    @objc func didRebase() { onAction("promptRebase") }
    @objc func didMerge() { onAction("promptMerge") }
    @objc func didStash() { onAction("stash") }
    @objc func didStashPop() { onAction("stashPop") }
    
    func createMetricLabel(color: NSColor) -> NSTextField {
        let tf = NSTextField(labelWithString: "0"); tf.font = .monospacedSystemFont(ofSize: 13, weight: .bold); tf.textColor = color; return tf
    }
    
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
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); let popover = NSPopover(); let dialogPopover = NSPopover(); var config = Config()
    var activeAuthSessionID: UUID?
    var cachedGitHubToken: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureTrackerDirectory()
        migrateConfig()
        loadConfig()
        cachedGitHubToken = KeychainHelper.loadToken()
        
        // Expert UI: Generate App Icon (Blue Background + White Glyph)
        let iconSize = NSSize(width: 128, height: 128)
        let icon = NSImage(size: iconSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
            NSColor.systemBlue.set(); path.fill()
            
            if #available(macOS 11.0, *), let glyph = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
                let glyphConfig = NSImage.SymbolConfiguration(pointSize: 64, weight: .black)
                let whiteGlyph = glyph.withSymbolConfiguration(glyphConfig)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))
                let glyphRect = NSRect(x: 32, y: 32, width: 64, height: 64)
                whiteGlyph?.draw(in: glyphRect)
            }
            return true
        }
        NSApp.applicationIconImage = icon
        
        if let b = statusItem.button {
            if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) { img.isTemplate = true; b.image = img } else { b.title = "ᚠ" }
            b.action = #selector(togglePopover); b.target = self
        }
        popover.contentViewController = GitTrackerController(config: config, isAuthenticated: hasGitHubAuth, onAction: handleAction); popover.behavior = .transient
        dialogPopover.behavior = .applicationDefined
        setupEditMenu()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.updateAllStatus() }    }
    func setupEditMenu() { let m = NSMenu(); let e = NSMenu(title: "Edit"); e.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); let i = NSMenuItem(); i.submenu = e; m.addItem(i); NSApp.mainMenu = m }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    func showPopover() {
        if let b = statusItem.button {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey()
            (popover.contentViewController as? GitTrackerController)?.updateUIState(); updateAllStatus()
        }
    }
    func refreshGitHubTokenCache() {
        cachedGitHubToken = KeychainHelper.loadToken()
    }

    func ensureTrackerDirectory() {
        try? FileManager.default.createDirectory(atPath: trackerRoot, withIntermediateDirectories: true, attributes: nil)
    }
    
    var hasGitHubAuth: Bool { !(config.githubLogin?.isEmpty ?? true) && !(cachedGitHubToken?.isEmpty ?? true) }
    
    func ensureAskPassScript() -> String? {
        let path = "\(trackerRoot)/gittracker-askpass.sh"
        let body = """
        #!/bin/sh
        case "$1" in
          *Username*) printf "%s" "$GITTRACKER_GH_USER" ;;
          *) printf "%s" "$GITTRACKER_GH_TOKEN" ;;
        esac
        """
        if !FileManager.default.fileExists(atPath: path) || ((try? String(contentsOfFile: path, encoding: .utf8)) != body) {
            try? body.write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    
    func githubEnvironment() -> [String: String]? {
        guard let login = config.githubLogin, let token = cachedGitHubToken, let askPass = ensureAskPassScript() else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["GIT_ASKPASS"] = askPass
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GITTRACKER_GH_USER"] = login
        env["GITTRACKER_GH_TOKEN"] = token
        return env
    }
    
    @discardableResult
    func runShell(args: [String], includeGitHubAuth: Bool = false) -> (output: String, success: Bool) {
        let env = includeGitHubAuth ? githubEnvironment() : nil
        return runGitProcess(args: args, environment: env)
    }
    
    func isGitHubURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("github.com") || lower.contains("git@github.com:")
    }
    
    func remoteURL(repoPath: String, remoteName: String) -> String? {
        let remote = runShell(args: ["-C", repoPath, "remote", "get-url", remoteName]).output
        return remote.isEmpty ? nil : remote
    }

    func remoteUsesGitHub(repoPath: String, remoteName: String) -> Bool {
        let remote = remoteURL(repoPath: repoPath, remoteName: remoteName) ?? ""
        return isGitHubURL(remote)
    }

    func repoName(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lastComponent = path.components(separatedBy: "/").last ?? trimmed
        let cleaned = lastComponent.replacingOccurrences(of: ".git", with: "")
        return cleaned.isEmpty ? "repo" : cleaned
    }
    
    func defaultCloneParentPath() -> String {
        let sidehustlePath = homeDirectory.appendingPathComponent("Documents/sidehustle").path
        if FileManager.default.fileExists(atPath: sidehustlePath) {
            return normalizedRepoPath(sidehustlePath)
        }
        return normalizedRepoPath(homeDirectory.appendingPathComponent("Documents").path)
    }
    
    func normalizedRepoPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func localGitRoot(for path: String) -> String? {
        let normalizedPath = normalizedRepoPath(path)
        let result = runShell(args: ["-C", normalizedPath, "rev-parse", "--show-toplevel"])
        guard result.success else { return nil }
        let root = normalizedRepoPath(result.output)
        return FileManager.default.fileExists(atPath: root) ? root : nil
    }
    
    func normalizedRemoteURL(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("git@github.com:") {
            value = "https://github.com/" + value.replacingOccurrences(of: "git@github.com:", with: "")
        }
        if value.hasPrefix("ssh://git@github.com/") {
            value = "https://github.com/" + value.replacingOccurrences(of: "ssh://git@github.com/", with: "")
        }
        if value.hasPrefix("https://") || value.hasPrefix("http://") {
            var components = URLComponents(string: value)
            components?.user = nil
            components?.password = nil
            value = components?.string ?? value
        }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return isGitHubURL(value) ? value.lowercased() : value
    }
    
    func repoOriginURL(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let result = runShell(args: ["-C", path, "remote", "get-url", "origin"])
        guard result.success else { return nil }
        let normalized = normalizedRemoteURL(result.output)
        return normalized.isEmpty ? nil : normalized
    }

    func isGitRepository(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path) && runShell(args: ["-C", path, "rev-parse", "--is-inside-work-tree"]).success
    }
    
    func existingRepoIndex(for repo: TrackedRepo) -> Int? {
        let candidatePath = normalizedRepoPath(repo.path)
        let candidateURL = normalizedRemoteURL(repo.url)
        let candidateOrigin = repoOriginURL(path: repo.path)
        for (index, existing) in config.repos.enumerated() {
            if normalizedRepoPath(existing.path) == candidatePath { return index }
            let existingURL = normalizedRemoteURL(existing.url)
            if !candidateURL.isEmpty && candidateURL == existingURL { return index }
            if let candidateOrigin, !existingURL.isEmpty, candidateOrigin == existingURL { return index }
            if let existingOrigin = repoOriginURL(path: existing.path) {
                if !candidateURL.isEmpty && candidateURL == existingOrigin { return index }
                if let candidateOrigin, candidateOrigin == existingOrigin { return index }
            }
        }
        return nil
    }

    func updateTrackedRepo(_ repo: TrackedRepo, at index: Int) {
        config.repos[index].path = normalizedRepoPath(repo.path)
        if !repo.url.isEmpty { config.repos[index].url = repo.url }
        config.repos[index].name = repo.name
        config.selectedRepoIndex = index
        saveConfig()
        reloadUI(status: "Updated Repository Path", show: true)
    }

    func promptForCloneDestination(repoName: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: defaultCloneParentPath())
        panel.prompt = "Clone Here"
        panel.message = "Choose the parent folder where GitTracker should create \(repoName)."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return normalizedRepoPath(url.path)
    }
    
    func promptForClonePath(currentPath: String, repoName: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: normalizedRepoPath(currentPath))
        panel.prompt = "Use Folder"
        panel.message = "Choose the parent folder where GitTracker should create \(repoName)."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return normalizedRepoPath(url.path)
    }
    
    func promptForRemoteClone(url: String) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoName = repoName(from: cleanURL)
        let draft = CloneDraft(url: cleanURL, repoName: repoName, localPath: defaultCloneParentPath())
        let cloneView = CloneRemoteView(draft: draft, onChoosePath: {
            if let selectedPath = self.promptForClonePath(currentPath: draft.localPath, repoName: repoName) {
                draft.localPath = selectedPath
            }
        }, onClone: {
            self.dialogPopover.performClose(nil)
            self.performRemoteClone(url: cleanURL, destinationParent: draft.localPath, repoName: repoName)
        }, onCancel: {
            self.dialogPopover.performClose(nil)
        })
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: cloneView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
    
    func performRemoteClone(url: String, destinationParent: String, repoName: String) {
        let cleanInput = url.replacingOccurrences(of: "file://", with: "")
        let parentPath = normalizedRepoPath((destinationParent as NSString).expandingTildeInPath)
        let path = normalizedRepoPath((parentPath as NSString).appendingPathComponent(repoName))
        if FileManager.default.fileExists(atPath: path) {
            if isGitRepository(path: path) {
                let repo = TrackedRepo(url: cleanInput, path: path, name: repoName)
                if let existingIndex = existingRepoIndex(for: repo) {
                    updateTrackedRepo(repo, at: existingIndex)
                } else {
                    addAndSelectRepo(repo)
                }
            } else {
                reloadUI(status: "❌ Destination Already Exists", show: true)
            }
            return
        }
        setStatus("⌛ Cloning...")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runShell(args: ["clone", cleanInput, path], includeGitHubAuth: self.isGitHubURL(cleanInput))
            DispatchQueue.main.async {
                if result.success {
                    let repo = TrackedRepo(url: cleanInput, path: path, name: repoName)
                    if let existingIndex = self.existingRepoIndex(for: repo) {
                        self.config.selectedRepoIndex = existingIndex
                        self.saveConfig()
                        self.reloadUI(status: "Already Tracking", show: true)
                    } else {
                        self.addAndSelectRepo(repo)
                    }
                }
                else { self.reloadUI(status: "❌ \(result.output.components(separatedBy: "\n").first { !$0.isEmpty } ?? "Clone Failed")", show: true) }
            }
        }
    }
    
    func handleAction(_ type: String) {
        if type.hasPrefix("repoChanged:") { if let index = Int(type.replacingOccurrences(of: "repoChanged:", with: "")) { config.selectedRepoIndex = index; saveConfig(); reloadUI() }; return }
        if type.hasPrefix("branchChanged:") {
            let branch = type.replacingOccurrences(of: "branchChanged:", with: "")
            if branch != "All Branches", let currentRepo = requireExistingCurrentRepo() {
                setStatus("⌛ Checking out...")
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self.checkoutBranch(repoPath: currentRepo.path, branch: branch)
                    let success = result.success
                    let output = result.output
                    DispatchQueue.main.async {
                        if success {
                            let stashList = self.runShell(args: ["-C", currentRepo.path, "stash", "list", "-n", "1"]).output
                            if stashList.contains("Auto-stashed before checkout") {
                                self.reloadUI(status: "✅ Switched to \(branch)", show: true)
                                self.promptForStashPop()
                            } else {
                                self.reloadUI(status: "✅ Switched to \(branch)", show: true)
                            }
                        } else {
                            if output.contains("stash them before you switch branches") || output.contains("would be overwritten by checkout") {
                                self.promptForStash(targetBranch: branch.replacingOccurrences(of: "origin/", with: ""))
                            } else {
                                self.setStatus("❌ Checkout Failed", color: .systemRed)
                            }
                        }
                    }
                }
            }; return
        }
        if type == "updateAllStatus" { updateAllStatus(); return }
        switch type {
        case "sync": refreshRepo(); case "track": promptForRepo(); case "auth": promptForAuth(); case "clear": clearRepo(); case "quit": NSApp.terminate(nil)
        case "promptCommit": promptForCommit(); case "push": pushCommits(); case "promptRebase": promptForRebase(); case "promptMerge": promptForMerge()
        case "stash": executeStash(); case "stashPop": executeStashPop()
        default: break
        }
    }
    func repoExists(_ repo: TrackedRepo) -> Bool {
        FileManager.default.fileExists(atPath: repo.path)
    }

    func requireExistingCurrentRepo(status: String = "❌ Repository folder is missing") -> TrackedRepo? {
        guard let currentRepo = config.currentRepo else { return nil }
        guard repoExists(currentRepo) else {
            reloadUI(status: status, show: true)
            return nil
        }
        return currentRepo
    }

    @discardableResult
    func checkoutBranch(repoPath: String, branch: String) -> (output: String, success: Bool) {
        if branch.hasPrefix("origin/") {
            let localName = branch.replacingOccurrences(of: "origin/", with: "")
            let exists = runShell(args: ["-C", repoPath, "rev-parse", "--verify", localName]).success
            if exists {
                return runShell(args: ["-C", repoPath, "checkout", localName])
            }
            return runShell(args: ["-C", repoPath, "checkout", "-b", localName, "--track", branch])
        }
        return runShell(args: ["-C", repoPath, "checkout", branch])
    }

    func currentBranchAndUpstream(repoPath: String) -> (branch: String, upstream: String?) {
        let branch = runShell(args: ["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamResult = runShell(args: ["-C", repoPath, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let upstream = upstreamResult.success ? upstreamResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (branch, upstream?.isEmpty == false ? upstream : nil)
    }

    func splitRemoteBranch(_ upstream: String) -> (remote: String, branch: String)? {
        let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    func branchTrackingInfo(repoPath: String) -> (branch: String, remote: String?, remoteBranch: String?) {
        let branchInfo = currentBranchAndUpstream(repoPath: repoPath)
        guard let upstream = branchInfo.upstream, let split = splitRemoteBranch(upstream) else {
            return (branchInfo.branch, nil, nil)
        }
        return (branchInfo.branch, split.remote, split.branch)
    }
    func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        DispatchQueue.main.async { 
            if let vc = self.popover.contentViewController as? GitTrackerController { 
                vc.statusHostingView.rootView = StatusBadgeView(isActive: self.hasGitHubAuth, text: text) 
            }
            if text.contains("❌") { self.showPopover() }
        }
    }
    func updateAllStatus() {
        DispatchQueue.global(qos: .background).async {
            var upToDate = 0, modified = 0, ahead = 0, behind = 0, attention = 0
            for repo in self.config.repos {
                if !FileManager.default.fileExists(atPath: repo.path) { continue }
                let s = (self.popover.contentViewController as? GitTrackerController)?.getRepoStatus(path: repo.path) ?? (false, 0, 0, true)
                if s.3 { upToDate += 1 } else { if s.2 > 0 { behind += 1; attention += 1 } else if s.1 > 0 { ahead += 1; attention += 1 } else if s.0 { modified += 1; attention += 1 } }
            }
            DispatchQueue.main.async {
                if let vc = self.popover.contentViewController as? GitTrackerController {
                    vc.summaryBar.update(upToDate: upToDate, modified: modified, ahead: ahead, behind: behind)
                    vc.summaryLabel.stringValue = attention > 0 ? "HEALTH: ATTENTION NEEDED" : "HEALTH: ALL CLEAR"
                    vc.behindLabel.stringValue = "↓ \(behind)"
                    vc.aheadLabel.stringValue = "↑ \(ahead)"
                    vc.modifiedLabel.stringValue = "✎ \(modified)"
                    vc.upToDateLabel.stringValue = "✓ \(upToDate)"
                }
                if let b = self.statusItem.button {
                    if attention > 0 { if #available(macOS 11.0, *) { b.image = b.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .systemOrange)) } }
                    else { if #available(macOS 11.0, *) { b.image = b.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: .controlTextColor)) } }
                }
            }
        }
    }
    func promptForAuth() {
        let authView = AuthView(githubLogin: config.githubLogin, onStart: {
            self.startGitHubSignIn()
        }, onSignOut: {
            self.signOutGitHub()
            self.dialogPopover.performClose(nil)
        }, onCancel: { self.cancelGitHubSignIn(closePopover: true) })
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: authView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
    func promptForRepo() {
        let addView = AddRepoView(onAdd: { input in
            self.trackRepo(input: input.trimmingCharacters(in: .whitespaces))
        }, onBrowse: {
            self.dialogPopover.performClose(nil)
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url { self.trackRepo(input: url.path) }
        }, onCancel: { self.dialogPopover.performClose(nil) })
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: addView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
    func trackRepo(input: String) {
        guard !input.isEmpty else { return }; let cleanInput = input.replacingOccurrences(of: "file://", with: ""), expanded = normalizedRepoPath((cleanInput as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: expanded) {
            guard let repoRoot = localGitRoot(for: expanded) else {
                reloadUI(status: "❌ Selected folder is not a Git repository", show: true)
                return
            }
            let repoName = URL(fileURLWithPath: repoRoot).lastPathComponent
            let repo = TrackedRepo(url: repoOriginURL(path: repoRoot) ?? cleanInput, path: repoRoot, name: repoName)
            if let existingIndex = existingRepoIndex(for: repo) {
                if normalizedRepoPath(config.repos[existingIndex].path) != expanded {
                    updateTrackedRepo(repo, at: existingIndex)
                } else {
                    config.selectedRepoIndex = existingIndex
                    saveConfig()
                    reloadUI(status: "Already Tracking", show: true)
                }
            } else {
                addAndSelectRepo(repo)
            }
        }
        else {
            let normalizedInputURL = normalizedRemoteURL(cleanInput)
            if let existingIndex = config.repos.enumerated().first(where: { _, existing in normalizedRemoteURL(existing.url) == normalizedInputURL || repoOriginURL(path: existing.path) == normalizedInputURL })?.offset {
                config.selectedRepoIndex = existingIndex
                saveConfig()
                reloadUI(status: "Already Tracking", show: true)
                return
            }
            promptForRemoteClone(url: cleanInput)
        }
    }
    func addAndSelectRepo(_ repo: TrackedRepo) {
        let normalizedPath = normalizedRepoPath(repo.path)
        let normalizedURL = normalizedRemoteURL(repo.url)
        if let existingIndex = config.repos.firstIndex(where: { normalizedRepoPath($0.path) == normalizedPath || (!normalizedURL.isEmpty && normalizedRemoteURL($0.url) == normalizedURL) }) {
            config.repos[existingIndex] = TrackedRepo(url: repo.url, path: normalizedPath, name: repo.name)
            config.selectedRepoIndex = existingIndex
        } else {
            config.repos.append(repo)
            config.selectedRepoIndex = config.repos.count - 1
        }
        saveConfig()
        reloadUI(show: true)
    }

    func refreshRepo() {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        DispatchQueue.main.async { if let vc = self.popover.contentViewController as? GitTrackerController { vc.syncBtn.isEnabled = false; vc.syncBtn.title = "Fetching..."; self.setStatus("⌛ Fetching...") } }
        DispatchQueue.global(qos: .userInitiated).async {
            let trackingInfo = self.branchTrackingInfo(repoPath: currentRepo.path)
            let remoteName = trackingInfo.remote ?? "origin"
            let useAuth = self.remoteUsesGitHub(repoPath: currentRepo.path, remoteName: remoteName)
            let fetchResult = self.runShell(args: ["-C", currentRepo.path, "fetch", remoteName], includeGitHubAuth: useAuth)
            let pullResult: (output: String, success: Bool)
            if let remote = trackingInfo.remote, let remoteBranch = trackingInfo.remoteBranch {
                pullResult = self.runShell(args: ["-C", currentRepo.path, "pull", "--ff-only", remote, remoteBranch], includeGitHubAuth: useAuth)
            } else {
                pullResult = ("No upstream configured for \(trackingInfo.branch)", false)
            }
            DispatchQueue.main.async { 
                if fetchResult.success && pullResult.success {
                    self.reloadUI(status: "✅ Fetch Complete", show: true)
                    self.updateAllStatus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.setStatus(self.hasGitHubAuth ? "Auth Active" : "Ready") }
                } else {
                    let err = (!fetchResult.success ? fetchResult.output : pullResult.output).components(separatedBy: "\n").first { !$0.isEmpty } ?? "Sync Failed"
                    self.reloadUI(status: "❌ \(err)", show: true)
                }
            }
        }
    }
    func clearRepo() { if !config.repos.isEmpty && config.selectedRepoIndex < config.repos.count { config.repos.remove(at: config.selectedRepoIndex); config.selectedRepoIndex = max(0, config.selectedRepoIndex - 1); saveConfig(); reloadUI() } }
    
    func promptForStash(targetBranch: String) {
        let stashView = StashPromptView(onStashAndSwitch: {
            self.dialogPopover.performClose(nil)
            self.stashAndSwitch(targetBranch: targetBranch)
        }, onCancel: { self.dialogPopover.performClose(nil) })
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: stashView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func executeStash() {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Stashing...")
        DispatchQueue.global(qos: .userInitiated).async {
            let (output, success) = self.runShell(args: ["-C", currentRepo.path, "stash"])
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Stashed Changes", show: true)
                } else {
                    self.setStatus("❌ Stash Failed", color: .systemRed)
                    print(output)
                }
            }
        }
    }

    func executeStashPop() {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Popping Stash...")
        DispatchQueue.global(qos: .userInitiated).async {
            let (output, success) = self.runShell(args: ["-C", currentRepo.path, "stash", "pop"])
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Restored Stash", show: true)
                } else {
                    self.setStatus("❌ Pop Failed (Conflicts?)", color: .systemRed)
                    print(output)
                }
            }
        }
    }

    func promptForStashPop() {
        let popView = StashPopPromptView(onPopStash: {
            self.dialogPopover.performClose(nil)
            self.executeStashPop()
        }, onDismiss: { self.dialogPopover.performClose(nil) })
        
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: popView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func stashAndSwitch(targetBranch: String) {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Stashing & Switching...")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.runShell(args: ["-C", currentRepo.path, "stash", "push", "-m", "Auto-stashed before checkout to \(targetBranch)"])
            let checkoutResult = self.checkoutBranch(repoPath: currentRepo.path, branch: targetBranch)
            DispatchQueue.main.async {
                if checkoutResult.success {
                    self.reloadUI(status: "✅ Switched to \(targetBranch)", show: true)
                } else {
                    self.setStatus("❌ Switch Failed", color: .systemRed)
                }
            }
        }
    }

    func promptForCommit() {
        let commitView = CommitView(onCommit: { message in
            self.commitChanges(message: message)
            self.dialogPopover.performClose(nil)
        }, onCancel: { self.dialogPopover.performClose(nil) })
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: commitView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func commitChanges(message: String) {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Committing...")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.runShell(args: ["-C", currentRepo.path, "add", "."])
            let (output, success) = self.runShell(args: ["-C", currentRepo.path, "commit", "-m", message])
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Committed", show: true)
                    self.updateAllStatus()
                } else {
                    self.setStatus("❌ Commit Failed", color: .systemRed)
                    print(output)
                }
            }
        }
    }

    func pushCommits() {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Pushing...")
        DispatchQueue.global(qos: .userInitiated).async {
            let trackingInfo = self.branchTrackingInfo(repoPath: currentRepo.path)
            let remoteName = trackingInfo.remote ?? "origin"
            let useAuth = self.remoteUsesGitHub(repoPath: currentRepo.path, remoteName: remoteName)
            let pushArgs: [String]
            if trackingInfo.remote != nil {
                pushArgs = ["-C", currentRepo.path, "push", remoteName, "HEAD"]
            } else {
                pushArgs = ["-C", currentRepo.path, "push", "-u", remoteName, "HEAD"]
            }
            let (output, success) = self.runShell(args: pushArgs, includeGitHubAuth: useAuth)
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Push Complete", show: true)
                } else {
                    let errorMsg = output.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? "Push Failed"
                    self.setStatus("❌ \(errorMsg)", color: .systemRed)
                    print(output)
                }
            }
        }
    }

    func promptForRebase() {
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else { return }
        let branchOut = runShell(args: ["-C", currentRepo.path, "branch", "-a", "--format=%(refname:short)"]).output
        var branches = [String]()
        for b in branchOut.components(separatedBy: "\n") {
            let clean = b.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && clean != "HEAD" && !clean.hasSuffix("/HEAD") && clean != "origin" {
                if !branches.contains(clean) { branches.append(clean) }
            }
        }
        
        let rebaseView = RebaseView(branches: branches, onRebase: { target in
            self.rebaseBranch(target: target)
            self.dialogPopover.performClose(nil)
        }, onCancel: { self.dialogPopover.performClose(nil) })
        
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: rebaseView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func rebaseBranch(target: String) {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Rebasing...")
        DispatchQueue.global(qos: .userInitiated).async {
            let (output, success) = self.runShell(args: ["-C", currentRepo.path, "rebase", target])
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Rebase Complete", show: true)
                    self.updateAllStatus()
                } else {
                    self.setStatus("❌ Rebase Failed", color: .systemRed)
                    print(output)
                    _ = self.runShell(args: ["-C", currentRepo.path, "rebase", "--abort"])
                }
            }
        }
    }

    func promptForMerge() {
        guard let currentRepo = config.currentRepo, FileManager.default.fileExists(atPath: currentRepo.path) else { return }
        let branchOut = runShell(args: ["-C", currentRepo.path, "branch", "-a", "--format=%(refname:short)"]).output
        var branches = [String]()
        for b in branchOut.components(separatedBy: "\n") {
            let clean = b.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && clean != "HEAD" && !clean.hasSuffix("/HEAD") && clean != "origin" {
                if !branches.contains(clean) { branches.append(clean) }
            }
        }
        let currentBranch = runShell(args: ["-C", currentRepo.path, "rev-parse", "--abbrev-ref", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mergeView = MergeView(branches: branches, currentBranch: currentBranch, onMerge: { target in
            self.mergeBranch(target: target)
            self.dialogPopover.performClose(nil)
        }, onCancel: { self.dialogPopover.performClose(nil) })
        
        self.popover.performClose(nil)
        dialogPopover.contentViewController = NSHostingController(rootView: mergeView)
        if let b = statusItem.button { dialogPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func mergeBranch(target: String) {
        guard let currentRepo = requireExistingCurrentRepo() else { return }
        setStatus("⌛ Merging...")
        DispatchQueue.global(qos: .userInitiated).async {
            let (output, success) = self.runShell(args: ["-C", currentRepo.path, "merge", target])
            DispatchQueue.main.async {
                if success {
                    self.reloadUI(status: "✅ Merge Complete", show: true)
                    self.updateAllStatus()
                } else {
                    self.setStatus("❌ Merge Failed", color: .systemRed)
                    print(output)
                    _ = self.runShell(args: ["-C", currentRepo.path, "merge", "--abort"])
                }
            }
        }
    }
    
    func postFormJSON<T: Decodable>(_ type: T.Type, urlString: String, parameters: [String: String]) throws -> T {
        guard let url = URL(string: urlString) else { throw GitHubAuthError.server("Invalid GitHub URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return try performJSONRequest(type, request: request)
    }
    
    func getJSON<T: Decodable>(_ type: T.Type, urlString: String, bearerToken: String) throws -> T {
        guard let url = URL(string: urlString) else { throw GitHubAuthError.server("Invalid GitHub URL.") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try performJSONRequest(type, request: request)
    }
    
    func performJSONRequest<T: Decodable>(_ type: T.Type, request: URLRequest) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let error = responseError { throw error }
        guard let data = responseData else { throw GitHubAuthError.server("GitHub returned no data.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func startGitHubSignIn() {
        let clientID = githubOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { setStatus("❌ Missing Client ID", color: .systemRed); return }
        let sessionID = UUID()
        activeAuthSessionID = sessionID
        setStatus("⌛ Connecting GitHub...")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try self.postFormJSON(GitHubDeviceCodeResponse.self, urlString: "https://github.com/login/device/code", parameters: ["client_id": clientID, "scope": "repo read:user"])
                guard let url = URL(string: response.verification_uri) else { throw GitHubAuthError.invalidVerificationURL }
                DispatchQueue.main.async {
                    let deviceView = DeviceFlowView(userCode: response.user_code, verificationURL: response.verification_uri, onOpenBrowser: {
                        NSWorkspace.shared.open(url)
                    }, onCancel: {
                        self.cancelGitHubSignIn(closePopover: true)
                    })
                    self.dialogPopover.contentViewController = NSHostingController(rootView: deviceView)
                    self.setStatus("⌛ Waiting for GitHub...")
                    NSWorkspace.shared.open(url)
                }
                try self.pollGitHubDeviceFlow(sessionID: sessionID, clientID: clientID, deviceCode: response.device_code, interval: max(response.interval, 5))
            } catch {
                DispatchQueue.main.async {
                    self.activeAuthSessionID = nil
                    self.reloadUI(status: "❌ \(error.localizedDescription)", show: true)
                    self.dialogPopover.performClose(nil)
                }
            }
        }
    }
    
    func pollGitHubDeviceFlow(sessionID: UUID, clientID: String, deviceCode: String, interval: Int) throws {
        var nextInterval = interval
        while activeAuthSessionID == sessionID {
            Thread.sleep(forTimeInterval: TimeInterval(nextInterval))
            let tokenResponse = try postFormJSON(GitHubAccessTokenResponse.self, urlString: "https://github.com/login/oauth/access_token", parameters: ["client_id": clientID, "device_code": deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            if let accessToken = tokenResponse.access_token, !accessToken.isEmpty {
                let user = try getJSON(GitHubUserResponse.self, urlString: "https://api.github.com/user", bearerToken: accessToken)
                DispatchQueue.main.async {
                    guard self.activeAuthSessionID == sessionID else { return }
                    KeychainHelper.saveToken(accessToken)
                    self.cachedGitHubToken = accessToken
                    self.config.githubLogin = user.login
                    self.config.username = nil
                    self.config.token = nil
                    self.activeAuthSessionID = nil
                    self.saveConfig()
                    self.dialogPopover.performClose(nil)
                    self.reloadUI(status: "✅ Signed in as \(user.login)", show: true)
                }
                return
            }
            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                nextInterval = tokenResponse.interval ?? (nextInterval + 5)
            case "access_denied":
                throw GitHubAuthError.cancelled
            case "expired_token":
                throw GitHubAuthError.server("GitHub sign-in expired. Try again.")
            case .some(let error):
                throw GitHubAuthError.server(tokenResponse.error_description ?? error)
            case .none:
                throw GitHubAuthError.missingAccessToken
            }
        }
        throw GitHubAuthError.cancelled
    }
    
    func cancelGitHubSignIn(closePopover: Bool) {
        activeAuthSessionID = nil
        if closePopover { dialogPopover.performClose(nil) }
        setStatus(hasGitHubAuth ? "Auth Active" : "No Auth Set")
    }
    
    func signOutGitHub() {
        activeAuthSessionID = nil
        KeychainHelper.deleteToken()
        cachedGitHubToken = nil
        config.githubLogin = nil
        config.username = nil
        config.token = nil
        saveConfig()
        reloadUI(status: "Signed Out", show: true)
    }
    func migrateConfig() {
        ensureTrackerDirectory()
        let sourcePath = FileManager.default.fileExists(atPath: configFilePath) ? configFilePath : (FileManager.default.fileExists(atPath: legacyConfigFilePath) ? legacyConfigFilePath : configFilePath)
        if sourcePath != configFilePath, let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)) {
            try? data.write(to: URL(fileURLWithPath: configFilePath), options: .atomic)
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var shouldSave = false
            if json["repos"] == nil {
                var m = Config()
                if let url = json["repoUrl"] as? String, let path = json["repoPath"] as? String { let name = url.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "repo"; m.repos.append(TrackedRepo(url: url, path: path, name: name)) }
                if let u = json["username"] as? String { m.githubLogin = u }
                if let t = json["token"] as? String, !t.isEmpty { KeychainHelper.saveToken(t); cachedGitHubToken = t }
                self.config = m
                saveConfig()
                return
            }
            if let legacyUser = json["username"] as? String, config.githubLogin == nil {
                config.githubLogin = legacyUser
                shouldSave = true
            }
            if let legacyToken = json["token"] as? String, !legacyToken.isEmpty {
                KeychainHelper.saveToken(legacyToken)
                cachedGitHubToken = legacyToken
                config.token = nil
                config.username = nil
                shouldSave = true
            }
            if shouldSave { saveConfig() }
        }
    }
    func loadConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)), let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            self.config = decoded
            if config.githubLogin == nil { config.githubLogin = config.username }
            if let legacyToken = config.token, !legacyToken.isEmpty {
                KeychainHelper.saveToken(legacyToken)
                cachedGitHubToken = legacyToken
                config.token = nil
                config.username = nil
                saveConfig()
            }
        }
    }
    func saveConfig() {
        ensureTrackerDirectory()
        config.token = nil
        config.username = nil
        if let data = try? JSONEncoder().encode(config) { try? data.write(to: URL(fileURLWithPath: configFilePath)) }
    }
    func reloadUI(status: String? = nil, show: Bool = false) { 
        DispatchQueue.main.async { 
            self.loadConfig(); 
            let vc = GitTrackerController(config: self.config, isAuthenticated: self.hasGitHubAuth, onAction: self.handleAction); 
            self.popover.contentViewController = vc; 
            if let s = status { self.setStatus(s) } 
            if show { self.showPopover() }
        } 
    }
}

let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.run()
