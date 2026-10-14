import Foundation

enum MouseControl: Int, CaseIterable, Identifiable, Codable {
    case left = 1, right, middle, forward, back, scrollUp, scrollDown
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .left: "左键"; case .right: "右键"; case .middle: "滚轮点击"
        case .forward: "前侧键"; case .back: "后侧键"; case .scrollUp: "向上滚动"; case .scrollDown: "向下滚动"
        }
    }
    var symbol: String {
        switch self { case .left,.right: "computermouse"; case .middle: "circle.circle"; case .forward: "arrow.right"; case .back: "arrow.left"; case .scrollUp: "arrow.up"; case .scrollDown: "arrow.down" }
    }
    var defaultType: UInt8 { rawValue == 6 ? 12 : rawValue == 7 ? 13 : UInt8(rawValue) }
}

struct KeyMapping: Codable, Equatable, Sendable {
    let keyID: Int
    let type: UInt8
    let params: [UInt8]
    static func parse(_ bytes: [UInt8], expectedID: Int) throws -> Self {
        guard bytes.count >= 3, bytes[0] == 0, Int(bytes[1]) == expectedID, (1...7).contains(expectedID) else {
            throw MouseError.message("按键响应不匹配")
        }
        if bytes[2] == 6 && bytes.count < 7 { throw MouseError.message("快捷键响应不完整") }
        return Self(keyID: expectedID, type: bytes[2], params: Array(bytes.dropFirst(3)))
    }
    var title: String {
        if let action = MappingAction.all.first(where: { $0.type == type && $0.params == params }) { return action.title }
        return type == 8 ? "板载宏（保留）" : "自定义映射（保留）"
    }
}

struct MappingAction: Identifiable, Equatable {
    let id: String
    let title: String
    let type: UInt8
    var params: [UInt8] = []
    func mapping(for control: MouseControl) -> KeyMapping { KeyMapping(keyID: control.rawValue, type: type, params: params) }
    static let all: [Self] = [
        .init(id: "left", title: "左键点击", type: 1), .init(id: "right", title: "右键点击", type: 2),
        .init(id: "middle", title: "中键点击", type: 3), .init(id: "forward", title: "前进", type: 4),
        .init(id: "back", title: "后退", type: 5), .init(id: "up", title: "向上滚动", type: 12),
        .init(id: "down", title: "向下滚动", type: 13),
        .init(id: "copy", title: "拷贝 · ⌘C", type: 6, params: [0,0,6,8]),
        .init(id: "paste", title: "粘贴 · ⌘V", type: 6, params: [0,0,25,8]),
        .init(id: "undo", title: "撤销 · ⌘Z", type: 6, params: [0,0,29,8]),
        .init(id: "redo", title: "重做 · ⇧⌘Z", type: 6, params: [0,0,29,10]),
        .init(id: "mission", title: "调度中心 · ⌃↑", type: 6, params: [0,0,82,1]),
        .init(id: "spotlight", title: "聚焦搜索 · ⌘空格", type: 6, params: [0,0,44,8]),
        .init(id: "tab", title: "切换应用 · ⌘Tab", type: 6, params: [0,0,43,8]),
        .init(id: "play", title: "播放 / 暂停", type: 6, params: [205,0,0,0]),
        .init(id: "volumeUp", title: "调高音量", type: 6, params: [233,0,0,0]),
        .init(id: "volumeDown", title: "调低音量", type: 6, params: [234,0,0,0]),
        .init(id: "mute", title: "静音", type: 6, params: [226,0,0,0]),
        .init(id: "disabled", title: "不执行操作", type: 0)
    ]
}

struct MappingSnapshot: Codable, Equatable, Sendable {
    let identity: UInt64
    let profile: Int
    let mappings: [KeyMapping]
    func replacing(_ mapping: KeyMapping) -> Self {
        Self(identity: identity, profile: profile, mappings: mappings.map { $0.keyID == mapping.keyID ? mapping : $0 })
    }
}
struct MappingReceipt: Codable, Sendable {
    let before: MappingSnapshot
    let after: MappingSnapshot
    let keyID: Int
}

extension MouseDevice {
    func readMappings() throws -> MappingSnapshot {
        let profile = try readProfile()
        let maps = try (1...7).map { try KeyMapping.parse(command(0x30c3, payload: [UInt8($0)]), expectedID: $0) }
        guard try readProfile() == profile else { throw MouseError.message("读取期间配置已切换") }
        return MappingSnapshot(identity: identity, profile: profile, mappings: maps)
    }
    func writeMapping(_ mapping: KeyMapping, profile: Int) throws {
        guard (1...7).contains(mapping.keyID), mapping.params.count <= 51 else { throw MouseError.message("此映射长度尚不支持安全恢复") }
        guard try readProfile() == profile else { throw MouseError.message("板载配置已切换，取消写入") }
        _ = try command(0x30c2, payload: [UInt8(mapping.keyID), mapping.type] + mapping.params)
    }
    func firmwareVersions() -> [String: String] {
        var versions: [String: String] = [:]
        for (kind, route) in [("mouse", self.route), ("dongle", UInt8(0))] {
            if kind == "dongle" && productID != 1795 { continue }
            if let bytes = try? command(0x1c07, payload: [0], routeOverride: route),
               let text = String(bytes: bytes.filter { $0 >= 32 && $0 <= 126 }, encoding: .ascii),
               let range = text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
                versions[kind] = String(text[range])
            }
        }
        return versions
    }
}

actor MappingService {
    static var pendingURL: URL { MouseService.backupDirectory.appendingPathComponent("mapping-pending.json") }
    func read() throws -> MappingSnapshot { try MouseDevice().readMappings() }
    func versions() throws -> [String: String] { try MouseDevice().firmwareVersions() }
    func hasPending() -> Bool { FileManager.default.fileExists(atPath: Self.pendingURL.path) }
    private struct Journal: Codable { let before: MappingSnapshot; let changed: KeyMapping }
    func apply(_ changed: KeyMapping, expected: MappingSnapshot) throws -> MappingReceipt {
        guard !FileManager.default.fileExists(atPath: LightingService.pendingURL.path), !hasPending(), !FileManager.default.fileExists(atPath: MouseService.backupDirectory.appendingPathComponent("pending.json").path) else {
            throw MouseError.message("先恢复未完成的配置修改，再修改按键。")
        }
        let device = try MouseDevice(), before = try device.readMappings()
        guard before == expected, let original = before.mappings.first(where: { $0.keyID == changed.keyID }), original != changed else {
            throw MouseError.message("按键配置已变化或没有改动，请重新载入。")
        }
        guard original.params.count <= 51, changed.params.count <= 51 else { throw MouseError.message("原映射过长，此版本不能安全备份恢复，已取消修改。") }
        let target = before.replacing(changed)
        guard target.mappings.contains(where: { $0.type == 1 && $0.params.isEmpty }) else {
            throw MouseError.message("至少保留一个左键点击，避免鼠标无法操作。")
        }
        let journal = Journal(before: before, changed: changed)
        try save(journal, to: Self.pendingURL)
        do {
            try device.writeMapping(changed, profile: before.profile)
            let after = try device.readMappings()
            guard after == target else { throw MouseError.message("按键读回不一致") }
            try archive("verified")
            return MappingReceipt(before: before, after: after, keyID: changed.keyID)
        } catch {
            let reason = error.localizedDescription
            do {
                let now = try device.readMappings()
                guard now == before || now == target else { throw MouseError.message("映射出现额外变化") }
                if now != before { try device.writeMapping(original, profile: before.profile) }
                guard try device.readMappings() == before else { throw MouseError.message("恢复未确认") }
                try archive("rolled-back")
            } catch { throw MouseError.message("按键修改未完成，恢复尚未确认。请唤醒鼠标并使用“恢复按键配置”。原始备份已保留。") }
            throw MouseError.message("修改未完成，已恢复原映射：\(reason)")
        }
    }
    func undo(_ receipt: MappingReceipt) throws -> MappingSnapshot {
        guard let original = receipt.before.mappings.first(where: { $0.keyID == receipt.keyID }) else { throw MouseError.message("备份无效") }
        return try apply(original, expected: receipt.after).after
    }
    func recover() throws -> MappingSnapshot {
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: Self.pendingURL))
        let device = try MouseDevice(), now = try device.readMappings()
        let before = journal.before, target = before.replacing(journal.changed)
        guard now == before || now == target else { throw MouseError.message("设备连接或映射已变化，停止自动恢复；原始备份保留。") }
        if now != before, let original = before.mappings.first(where: { $0.keyID == journal.changed.keyID }) {
            try device.writeMapping(original, profile: before.profile)
        }
        let restored = try device.readMappings()
        guard restored == before else { throw MouseError.message("恢复读回不一致") }
        try archive("recovered")
        return restored
    }
    private func save(_ journal: Journal, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url); try file.synchronize(); try file.close()
    }
    private func archive(_ status: String) throws {
        try FileManager.default.moveItem(at: Self.pendingURL, to: Self.pendingURL.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString)-mapping-\(status).json"))
    }
}

/// A draft belongs to exactly one physical control; switching controls creates a new draft.
struct MappingDraft {
    let control: MouseControl
    let baseline: MappingSnapshot
    var actionID: String?
    var current: KeyMapping? { baseline.mappings.first { $0.keyID == control.rawValue } }
    var proposed: KeyMapping? { MappingAction.all.first { $0.id == actionID }?.mapping(for: control) }
    init(control: MouseControl, baseline: MappingSnapshot) {
        self.control = control
        self.baseline = baseline
        let mapping = baseline.mappings.first { $0.keyID == control.rawValue }
        actionID = MappingAction.all.first { $0.type == mapping?.type && $0.params == mapping?.params }?.id
    }
}
