import Foundation
import SwiftUI
import AppKit

struct HostRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var alias: String
    var hostname: String
    var username: String
    var port: Int
    var identityFile: String?
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
            "group_id": groupId as Any? ?? NSNull(), "favorite": favorite,
            "tags": tags, "notes": notes
        ]
        return try JSONSerialization.data(withJSONObject: record)
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
    func connect(_ host: HostRecord) { act(["connect",host.id]) }
    func delete() {
        guard let id = selectedID else { return }
        act(["delete",id]) { _ in
            self.selectedID = nil; self.isNew = false
        }
    }
    func addGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in:.whitespacesAndNewlines)
        if !trimmed.isEmpty { act(["add-group",trimmed]) }
    }
    func removeGroup(_ id: String) { act(["delete-group",id]) }
}
