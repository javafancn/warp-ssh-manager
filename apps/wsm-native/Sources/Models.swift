import Foundation
import SwiftUI
import AppKit
import Security
import Darwin

struct HostRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var alias: String
    var hostname: String
    var username: String
    var port: Int
    var identityFile: String?
    var authMode: String
    var proxyJump: String?
    var groupId: String?
    var favorite: Bool
    var source: String
    var lastConnected: Int64?
    var tags: String
    var notes: String
    var isImported: Bool { source == "Imported" }
    var tagNames: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
}

struct GroupRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var parentId: String?
    var sortOrder: Int
}
struct ManagerSnapshot: Codable {
    var hosts: [HostRecord]
    var groups: [GroupRecord]
    var includeEnabled: Bool
}
struct HostDraft {
    var id: String? = nil
    var name = ""
    var alias = ""
    var hostname = ""
    var username = "root"
    var port = "22"
    var identityFile = ""
    var proxyJump = ""
    var authMode = "auto"
    var groupId: String? = nil
    var favorite = false
    var source = "Managed"
    var tags = ""
    var notes = ""
    init() {}
    init(_ host: HostRecord) {
        id = host.id
        name = host.name
        alias = host.alias
        hostname = host.hostname
        username = host.username
        port = String(host.port)
        identityFile = host.identityFile ?? ""
        proxyJump = host.proxyJump ?? ""
        authMode = host.authMode
        groupId = host.groupId
        favorite = host.favorite
        source = host.source
        tags = host.tags
        notes = host.notes
    }
    var imported: Bool { source == "Imported" }
    var tagNames: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    func json() throws -> Data {
        guard let number = UInt16(port), number > 0 else {
            throw NSError(domain:"Warp SSH", code:1, userInfo:[NSLocalizedDescriptionKey:"端口必须为 1–65535 之间的数字"])
        }
        let record: [String: Any] = [
            "id": id as Any? ?? NSNull(),
            "name": name, "alias": alias, "hostname": hostname, "username": username,
            "port": Int(number), "identity_file": identityFile.isEmpty ? NSNull() : identityFile as Any,
            "proxy_jump": proxyJump.isEmpty ? NSNull() : proxyJump as Any,
            "auth_mode": authMode,
            "group_id": groupId as Any? ?? NSNull(), "favorite": favorite,
            "tags": tags, "notes": notes
        ]
        return try JSONSerialization.data(withJSONObject: record)
    }
}
// Passwords never enter the Rust JSON bridge, SQLite, SSH config, or Warp Tab config.
// Keychain handles at-rest encryption; the UI only reads on explicit copy.
enum CredentialVault {
    enum Kind: String { case ssh, sudo }
    static let service = "dev.warpsshmanager.app.credentials.v1"
    static func account(_ hostID: String, _ kind: Kind) -> String { "\(hostID):\(kind.rawValue)" }
    static func status(_ hostID: String, _ kind: Kind) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(hostID,kind),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary,nil) == errSecSuccess
    }
    static func load(_ hostID: String, _ kind: Kind) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(hostID,kind),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data:data,encoding:.utf8) else {
            throw NSError(domain:"WSM Keychain",code:Int(status),
                          userInfo:[NSLocalizedDescriptionKey:"读取钥匙串密码失败 (\(status))"])
        }
        return password
    }
    static func save(_ password: String, for hostID: String, kind: Kind) throws {
        guard !password.isEmpty else { throw NSError(domain:"WSM Keychain",code:1,
            userInfo:[NSLocalizedDescriptionKey:"密码不能为空"]) }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(hostID,kind)
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(item as CFDictionary,attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = item
            insertion[kSecValueData as String] = Data(password.utf8)
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(insertion as CFDictionary,nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain:"WSM Keychain",code:Int(status),
                 userInfo:[NSLocalizedDescriptionKey:"保存到钥匙串失败 (\(status))"])
        }
    }
    static func remove(_ hostID: String, _ kind: Kind) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(hostID,kind)
        ]
        let code = SecItemDelete(query as CFDictionary)
        if code != errSecSuccess && code != errSecItemNotFound {
            throw NSError(domain:"WSM Keychain",code:Int(code),
                userInfo:[NSLocalizedDescriptionKey:"删除钥匙串密码失败 (\(code))"])
        }
    }
}

/// A 120-second, single-use capability: only the signed askpass helper reads
/// the saved password, and only after OpenSSH requests an actual password.
enum AutoLoginSession {
    static func create(for hostID:String) throws -> UUID {
        guard UUID(uuidString:hostID) != nil else {
            throw NSError(domain:"WSM Askpass",code:1,
                userInfo:[NSLocalizedDescriptionKey:"无效的主机 ID"])
        }
        let root:URL
        if let home=ProcessInfo.processInfo.environment["WSM_HOME"], !home.isEmpty {
            root=URL(fileURLWithPath:home,isDirectory:true)
        } else {
            root=FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WarpSSHManager",isDirectory:true)
        }
        let folder=root.appendingPathComponent("askpass_sessions",isDirectory:true)
        try FileManager.default.createDirectory(
            at:folder,withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions:0o700],ofItemAtPath:folder.path
        )
        let session=UUID()
        let file=folder.appendingPathComponent(
            session.uuidString.lowercased().replacingOccurrences(of:"-",with:"") + ".json"
        )
        let record:[String:Any] = [
            "host_id":hostID,
            "created_at":Int64(Date().timeIntervalSince1970)
        ]
        let data=try JSONSerialization.data(withJSONObject:record)
        // O_EXCL + O_NOFOLLOW + 0600, no temporary world-readable window.
        let fd=Darwin.open(file.path,O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,0o600)
        guard fd >= 0 else {
            throw NSError(domain:"WSM Askpass",code:2,
                userInfo:[NSLocalizedDescriptionKey:"无法创建安全的临时认证会话"])
        }
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        do { try handle.write(contentsOf:data);try handle.close() }
        catch { try? FileManager.default.removeItem(at:file);throw error }
        return session
    }
}

enum PasswordClipboard {
    static func copy(_ value: String) {
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(value,forType:.string) else { return }
        let change = board.changeCount
        DispatchQueue.main.asyncAfter(deadline:.now() + 30) {
            if board.changeCount == change { board.clearContents() }
        }
    }
}

enum HostFilter: Hashable {
    case all, favorites, recent, group(String), ungrouped
}
enum InspectorTab: String, CaseIterable {
    case basic = "基本信息", connection = "连接配置", tags = "标签与分组", advanced = "高级设置"
}

// A JSON command boundary keeps the original Rust wsm-core as the sole writer
// of ~/.ssh/config, Warp tab configs and hosts.sqlite3.
enum RustBridge {
    static func execute(_ arguments: [String], input: Data? = nil) throws -> Data {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("wsm"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain:"Warp SSH", code:2, userInfo:[NSLocalizedDescriptionKey:"缺少应用内部的 Rust SSH 核心 (Contents/MacOS/wsm)"])
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["ui"] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try process.run()
        if let input = input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors, as: UTF8.self)
            throw NSError(domain:"Warp SSH", code:Int(process.terminationStatus), userInfo:[
                NSLocalizedDescriptionKey: message.isEmpty ? "Rust SSH 操作失败" : message
            ])
        }
        return output
    }
    static func snapshot() throws -> ManagerSnapshot {
        let data = try execute(["snapshot"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ManagerSnapshot.self, from: data)
    }
}

final class ManagerStore: ObservableObject {
    @Published var hosts: [HostRecord] = []
    @Published var groups: [GroupRecord] = []
    @Published var selectedID: String? = nil
    @Published var filter: HostFilter = .all
    @Published var search = ""
    @Published var draft = HostDraft()
    @Published var isNew = false
    @Published var tab: InspectorTab = .basic
    @Published var includeEnabled = false
    @Published var busy = false
    @Published var credentialRevision = 0
    @Published var noticeMessage: String? = nil
    @Published var errorMessage: String? = nil
    @AppStorage("warp.appearance") var appearance: String = "auto"

    var selected: HostRecord? { hosts.first { $0.id == selectedID } }
    var favoriteCount: Int { hosts.filter { $0.favorite }.count }
    var recentCount: Int { hosts.filter { $0.lastConnected != nil }.count }
    var filtered: [HostRecord] {
        hosts.filter { host in
            let match: Bool
            switch filter {
            case .all: match = true
            case .favorites: match = host.favorite
            case .recent: match = host.lastConnected != nil
            case .ungrouped: match = host.groupId == nil
            case .group(let id): match = host.groupId == id
            }
            guard match else { return false }
            let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
            let groupName = groups.first(where: { $0.id == host.groupId })?.name ?? ""
            return query.isEmpty || [host.name,host.alias,host.hostname,host.tags,groupName].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }
    func select(_ host: HostRecord) {
        selectedID = host.id; draft = HostDraft(host); isNew = false; tab = .basic
    }
    func newHost() {
        selectedID = nil; draft = HostDraft(); isNew = true; tab = .basic
    }
    func refresh() {
        busy = true
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try RustBridge.snapshot() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let snapshot):
                    let selected = self.selectedID
                    self.hosts = snapshot.hosts
                    // Honor the user's stored sort order, not hard-coded
                    // prototype group names.
                    self.groups = snapshot.groups.sorted {
                        if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    self.includeEnabled = snapshot.includeEnabled
                    if self.isNew { return }
                    if let id = selected, let host = snapshot.hosts.first(where: { $0.id == id }) {
                        self.draft = HostDraft(host)
                    } else if let first = snapshot.hosts.first {
                        self.select(first)
                    } else {
                        self.selectedID = nil
                    }
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    func act(_ args: [String], input: Data? = nil,
             after: ((Data)->Void)? = nil,
             onError: ((Error)->Void)? = nil) {
        busy = true
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try RustBridge.execute(args, input: input) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let data):
                    after?(data)
                    self.refresh()
                case .failure(let error):
                    onError?(error)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    func save() {
        do {
            let data = try draft.json()
            act(["save"],input:data) { output in
                if let dictionary = try? JSONSerialization.jsonObject(with: output) as? [String:String] {
                    self.selectedID = dictionary["id"]
                    self.isNew = false
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func toggleFavorite(_ host: HostRecord) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        let oldValue = hosts[index].favorite
        // A user's click has visible feedback immediately, while the Rust
        // command and file/database persistence run off the main thread.
        hosts[index].favorite = !oldValue
        if selectedID == host.id && !isNew { draft.favorite = !oldValue }
        act(["favorite",host.id,!oldValue ? "true" : "false"],
            onError: { [weak self] _ in
                guard let self = self else { return }
                if let current = self.hosts.firstIndex(where: { $0.id == host.id }) {
                    self.hosts[current].favorite = oldValue
                }
                if self.selectedID == host.id && !self.isNew {
                    self.draft.favorite = oldValue
                }
            })
    }
    func connectManual(_ host: HostRecord) { act(["connect",host.id]) }
    func connect(_ host: HostRecord) {
        // No SSH wrapper: Rust emits an export command, a standalone "ssh alias",
        // then environment cleanup in this Warp tab only.
        if host.authMode == "password" && hasPassword(.ssh,for:host.id) {
            do {
                let token=try AutoLoginSession.create(for:host.id)
                act(["connect",host.id,"--askpass-session",token.uuidString])
                return
            } catch {
                noticeMessage="自动登录初始化失败，改为普通 SSH 连接"
            }
        }
        act(["connect",host.id])
    }
    func hasPassword(_ kind: CredentialVault.Kind, for id: String) -> Bool {
        CredentialVault.status(id,kind)
    }
    func copyPassword(_ kind: CredentialVault.Kind, for host: HostRecord) {
        do {
            // The SSH credential is reused only when no separate sudo credential exists.
            let requested = kind == .sudo && !CredentialVault.status(host.id,.sudo)
                ? CredentialVault.Kind.ssh : kind
            guard let value = try CredentialVault.load(host.id,requested) else {
                noticeMessage = "这台主机还没有保存对应的密码"
                return
            }
            PasswordClipboard.copy(value)
            noticeMessage = "密码已复制，30 秒后尝试清空剪贴板"
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult
    func savePassword(_ password: String, kind: CredentialVault.Kind, hostID: String) -> Bool {
        do {
            try CredentialVault.save(password,for:hostID,kind:kind)
            credentialRevision += 1
            noticeMessage = "密码已安全保存到 macOS 钥匙串"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    @discardableResult
    func removePassword(_ kind: CredentialVault.Kind, hostID: String) -> Bool {
        do {
            try CredentialVault.remove(hostID,kind)
            credentialRevision += 1
            noticeMessage = "保存的密码已删除"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    func delete() {
        guard let id = selectedID else { return }
        act(["delete",id]) { _ in
            // Only delete secrets once the host deletion has succeeded.
            do {
                try CredentialVault.remove(id,.ssh)
                try CredentialVault.remove(id,.sudo)
            } catch { self.errorMessage = error.localizedDescription }
            self.selectedID = nil; self.isNew = false
        }
    }
    func addGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in:.whitespacesAndNewlines)
        if !trimmed.isEmpty { act(["add-group",trimmed]) }
    }
    func removeGroup(_ id: String) { act(["delete-group",id]) }
}
