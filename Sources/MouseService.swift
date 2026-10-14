import Foundation

struct ChangeReceipt: Codable, Sendable {
    let id: UUID
    let before: MouseSnapshot
    let after: MouseSnapshot
    let stageIndex: Int
    let backupPath: String
}

actor MouseService {
    private var recoveryRequired = false
    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AM Native/Backups", isDirectory: true)
    }
    private var pendingURL: URL { Self.backupDirectory.appendingPathComponent("pending.json") }

    func read() throws -> MouseSnapshot { try MouseDevice().snapshot() }

    func apply(stage: DPIStage, expected: MouseSnapshot) throws -> ChangeReceipt {
        guard !recoveryRequired, !FileManager.default.fileExists(atPath: Self.backupDirectory.appendingPathComponent("mapping-pending.json").path), !FileManager.default.fileExists(atPath: pendingURL.path) else {
            throw MouseError.message("上次写入尚未确认恢复。请先使用“恢复未完成的修改”。")
        }
        let device = try MouseDevice()
        let before = try device.snapshot()
        guard device.identity == expected.deviceIdentity, before.profile == expected.profile,
              before.dpi == expected.dpi, stage.index < before.dpi.stageCount, stage.index >= 0 else {
            throw MouseError.message("鼠标配置已变化，请刷新后重新修改。")
        }
        let original = before.dpi.stages[stage.index]
        guard stage != original else { throw MouseError.message("DPI 没有变化") }
        let id = UUID()
        let directory = Self.backupDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("\(id.uuidString)-before.json")
        try save(before, to: backup)
        let pending = Pending(before: before, changed: stage)
        try save(pending, to: pendingURL)
        do {
            try device.writeStage(stage, expectedProfile: before.profile, currentIndex: before.dpi.currentIndex)
            let after = try device.snapshot()
            guard after.profile == before.profile, after.dpi.rawPayload == expectedPayload(before.dpi, replacing: stage) else {
                throw MouseError.message("DPI 读回不一致")
            }
            let receipt = ChangeReceipt(id: id, before: before, after: after, stageIndex: stage.index, backupPath: backup.path)
            try save(receipt, to: directory.appendingPathComponent("\(id.uuidString)-verified.json"))
            try archivePending("verified")
            return receipt
        } catch {
            let originalError = error
            do {
                try device.writeStage(original, expectedProfile: before.profile, currentIndex: before.dpi.currentIndex)
                guard try device.readDPI().rawPayload == before.dpi.rawPayload else { throw MouseError.message("恢复读回不一致") }
                try archivePending("rolled-back")
            } catch {
                recoveryRequired = true
                throw MouseError.message("修改未完成，恢复也未确认。请保持鼠标连接并点“恢复未完成的修改”。备份：\(backup.path)")
            }
            throw MouseError.message("修改未完成，已恢复原值：\(originalError.localizedDescription)")
        }
    }

    func undo(_ receipt: ChangeReceipt) throws -> MouseSnapshot {
        // Uses the same stale-state checks and durable transaction as normal edits.
        let original = receipt.before.dpi.stages[receipt.stageIndex]
        return try apply(stage: original, expected: receipt.after).after
    }

    func hasPending() -> Bool { FileManager.default.fileExists(atPath: pendingURL.path) }

    func recover() throws -> MouseSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let pending = try decoder.decode(Pending.self, from: Data(contentsOf: pendingURL))
        let device = try MouseDevice(), now = try device.snapshot()
        // Never apply an old backup to a reconnected/different physical interface automatically.
        guard now.deviceIdentity == pending.before.deviceIdentity, now.profile == pending.before.profile else {
            throw MouseError.message("连接或配置已变化，不能自动恢复；原始备份保留在备份文件夹。")
        }
        if now.dpi.rawPayload != pending.before.dpi.rawPayload {
            guard now.dpi.rawPayload == expectedPayload(pending.before.dpi, replacing: pending.changed) else {
                throw MouseError.message("设备参数出现额外变化，自动恢复已停止；请核对备份。")
            }
            try device.writeStage(pending.before.dpi.stages[pending.changed.index], expectedProfile: now.profile, currentIndex: now.dpi.currentIndex)
        }
        let restored = try device.snapshot()
        guard restored.dpi.rawPayload == pending.before.dpi.rawPayload else { throw MouseError.message("恢复读回仍不一致") }
        try archivePending("recovered"); recoveryRequired = false
        return restored
    }

    private struct Pending: Codable { let before: MouseSnapshot; let changed: DPIStage }
    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url); try handle.synchronize(); try handle.close()
    }
    private func archivePending(_ status: String) throws {
        // Preserve every journal instead of deleting it.
        try FileManager.default.moveItem(at: pendingURL, to: Self.backupDirectory.appendingPathComponent("\(UUID().uuidString)-\(status).json"))
    }
}
