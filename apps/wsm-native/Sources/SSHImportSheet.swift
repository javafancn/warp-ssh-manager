import SwiftUI

private enum ImportStatus: String, Codable {
    case new, update, unchanged, managed, conflict, error

    var label: LocalizedStringKey {
        switch self {
        case .new: return "新增"
        case .update: return "更新"
        case .unchanged: return "无变化"
        case .managed: return "已由管理器托管"
        case .conflict: return "别名大小写冲突"
        case .error: return "解析失败"
        }
    }

    var isSelectable: Bool { self == .new || self == .update }
}

private struct ImportConnection: Codable {
    let hostname: String
    let username: String
    let port: Int
    let identityFile: String?
    let proxyJump: String?

    var target: String { "\(username)@\(hostname) · \(port)" }
}

private struct ImportCandidate: Codable, Identifiable {
    let alias: String
    let status: ImportStatus
    let existingId: String?
    let before: ImportConnection?
    let after: ImportConnection?
    let detail: String?

    var id: String { alias }
}

private struct ImportPreview: Decodable {
    let configPath: String
    let candidates: [ImportCandidate]
}

private struct ImportSelection: Encodable {
    let candidates: [ImportCandidate]
}

private struct ImportResult: Decodable {
    let added: Int
    let updated: Int
    let staleAliases: [String]
}

struct SSHImportSheet: View {
    @ObservedObject var store: ManagerStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ImportPreview?
    @State private var selected: Set<String> = []
    @State private var scanning = true
    @State private var applying = false
    @State private var error: String?
    @State private var staleAliases: [String] = []
    @State private var scanRevision = 0

    private var candidates: [ImportCandidate] { preview?.candidates ?? [] }
    private var selectable: Set<String> {
        Set(candidates.filter { $0.status.isSelectable }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("预览 SSH 导入").font(.title2.weight(.semibold))
            if let path = preview?.configPath {
                Text(verbatim: path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("SSH 配置路径"))
                    .accessibilityValue(Text(verbatim: path))
            }

            if scanning {
                ProgressView("正在读取 SSH 配置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if preview != nil && candidates.isEmpty {
                Text("未找到可导入的 SSH 别名")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !candidates.isEmpty {
                HStack {
                    Button("全选可导入项") { selected = selectable }
                        .disabled(selected == selectable)
                    Button("清空勾选") { selected.removeAll() }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Text(verbatim: String(format: AppLanguage.text("已选 %lld 项"), Int64(selected.count)))
                        .foregroundColor(.secondary)
                }
                .disabled(applying || !staleAliases.isEmpty)

                List(candidates) { candidate in
                    row(candidate)
                }
                .listStyle(.inset)
            } else {
                Spacer()
            }

            if !staleAliases.isEmpty {
                Text("配置或主机记录已变化，请重新扫描后再导入。")
                    .foregroundColor(.orange)
                Text(verbatim: staleAliases.joined(separator: ", "))
                    .lineLimit(2)
            }
            if let error = error {
                Text(verbatim: error)
                    .foregroundColor(.orange)
                    .lineLimit(4)
                    .help(error)
                    .textSelection(.enabled)
            }
            Divider()
            HStack {
                if !scanning {
                    Button("重新扫描") { scanRevision += 1 }.disabled(applying)
                }
                Spacer()
                if applying { ProgressView().controlSize(.small) }
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(applying)
                Button("导入所选主机") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(scanning || applying || selected.isEmpty || !staleAliases.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 560, idealWidth: 630, minHeight: 390, idealHeight: 480)
        .interactiveDismissDisabled(applying)
        .task(id: scanRevision) { await scan() }
    }

    private func row(_ candidate: ImportCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if candidate.status.isSelectable {
                Toggle(isOn: Binding(
                    get: { selected.contains(candidate.id) },
                    set: { checked in
                        if checked { selected.insert(candidate.id) }
                        else { selected.remove(candidate.id) }
                    }
                )) { Text(verbatim: candidate.alias) }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(applying || !staleAliases.isEmpty)
            } else {
                Color.clear.frame(width: 14, height: 14).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: candidate.alias).fontWeight(.semibold)
                    Spacer()
                    Text(candidate.status.label)
                        .font(.caption)
                        .foregroundColor(candidate.status.isSelectable ? Design.blue : .secondary)
                }
                if let after = candidate.after {
                    Text(verbatim: after.target).foregroundColor(.secondary)
                    if candidate.status == .update, let before = candidate.before {
                        change("主机 / IP", from: before.hostname, to: after.hostname)
                        change("用户名", from: before.username, to: after.username)
                        change("端口", from: String(before.port), to: String(after.port))
                        change("身份文件", from: before.identityFile, to: after.identityFile)
                        change("代理跳板", from: before.proxyJump, to: after.proxyJump)
                    }
                }
                if let detail = candidate.detail {
                    Text(verbatim: detail.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption).foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func change(_ title: LocalizedStringKey, from before: String?, to after: String?) -> some View {
        if before != after {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).foregroundColor(.secondary)
                Text(verbatim: "\(before ?? "—") → \(after ?? "—")")
            }
            .font(.caption)
        }
    }

    @MainActor
    private func scan() async {
        scanning = true
        preview = nil
        selected.removeAll()
        error = nil
        staleAliases = []
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                let data = try RustBridge.execute(["import-preview"])
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(ImportPreview.self, from: data)
            }
        }.value
        guard !Task.isCancelled else { return }
        scanning = false
        switch result {
        case .success(let value):
            preview = value
            selected = Set(value.candidates.filter { $0.status == .new }.map(\.id))
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }

    @MainActor
    private func submit() {
        guard !scanning, !applying, staleAliases.isEmpty, !selected.isEmpty else { return }
        let selection = ImportSelection(candidates: candidates.filter { selected.contains($0.id) })
        applying = true
        error = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    let data = try RustBridge.execute(["import-apply"], input: encoder.encode(selection))
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    return try decoder.decode(ImportResult.self, from: data)
                }
            }.value
            applying = false
            switch result {
            case .success(let report):
                staleAliases = report.staleAliases
                guard staleAliases.isEmpty else { return }
                store.errorMessage = nil
                store.noticeMessage = String(
                    format: AppLanguage.text("已新增 %lld 台主机，更新 %lld 台主机"),
                    Int64(report.added), Int64(report.updated)
                )
                store.refresh()
                dismiss()
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }
}
