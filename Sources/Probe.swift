import Foundation

@main
struct Probe {
    static func main() {
        do { try run() } catch { fputs("ERROR: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        let arguments = CommandLine.arguments
        let mode = arguments.dropFirst().first ?? "read"
        guard ["read", "verify"].contains(mode) else { throw MouseError.message("Usage: am-probe read | verify <backup-directory>") }
        let mouse = try MouseDevice()
        mouse.trace = { fputs($0 + "\n", stderr) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let before = try mouse.snapshot()
        print(String(data: try encoder.encode(before), encoding: .utf8)!)
        guard mode == "verify" else { return }
        guard arguments.count == 3 else { throw MouseError.message("验证必须指定备份目录") }
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = directory.appendingPathComponent("dpi-before-\(stamp).json")
        try encoder.encode(before).write(to: backup, options: .withoutOverwriting)
        // Prefer an inactive stage: this exercises hardware writes without changing cursor speed.
        let index = (0..<before.dpi.stageCount).first { $0 != before.dpi.currentIndex } ?? before.dpi.currentIndex
        let original = before.dpi.stages[index]
        var changed = original; changed.x += original.x <= 29950 ? 50 : -50; changed.y += original.y <= 29950 ? 50 : -50
        print("BACKUP \(backup.path)")
        print("TEST stage=\(index + 1) \(original.x)/\(original.y) → \(changed.x)/\(changed.y)")
        var failure: Error?
        var readBack: DPIState?
        // Always attempt restoration, including a lost acknowledgement after a successful device write.
        do {
            try mouse.writeStage(changed, expectedProfile: before.profile, currentIndex: before.dpi.currentIndex)
            let actual = try mouse.readDPI(); readBack = actual
            var expected = before.dpi.rawPayload
            let slots = before.dpi.stages.count
            expected.replaceSubrange((3 + index * 2)..<(5 + index * 2), with: littleEndian(changed.x))
            expected.replaceSubrange((3 + slots * 2 + index * 2)..<(5 + slots * 2 + index * 2), with: littleEndian(changed.y))
            guard actual.rawPayload == expected else { throw MouseError.message("修改读回与预期不一致") }
            print("MODIFY_READBACK_PASS")
        } catch { failure = error }
        var restored: DPIState?
        var restorationError: Error?
        for _ in 0..<3 {
            do {
                try mouse.writeStage(original, expectedProfile: before.profile, currentIndex: before.dpi.currentIndex)
                let actual = try mouse.readDPI()
                guard actual.rawPayload == before.dpi.rawPayload else { throw MouseError.message("恢复读回与原始备份不一致") }
                restored = actual; restorationError = nil; break
            } catch { restorationError = error; Thread.sleep(forTimeInterval: 0.1) }
        }
        struct Result: Codable { let before: MouseSnapshot; let changed: DPIState?; let restored: DPIState?; let success: Bool; let error: String? }
        let report = Result(before: before, changed: readBack, restored: restored, success: failure == nil && restored != nil, error: (restorationError ?? failure)?.localizedDescription)
        try encoder.encode(report).write(to: directory.appendingPathComponent("verification-\(stamp).json"), options: .atomic)
        if let restorationError { throw MouseError.message("恢复未确认。保留备份 \(backup.path)：\(restorationError.localizedDescription)") }
        print("RESTORE_EXACT_PAYLOAD_PASS")
        if let failure { throw failure }
        print("VERIFICATION_PASS")
    }
}
