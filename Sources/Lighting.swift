import Foundation

enum LightTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case mouse = "鼠标", receiver = "接收器"
    var id: String { rawValue }
}

// Raw NV bytes are retained; never reconstruct an unknown animation to restore it.
struct LightState: Codable, Equatable, Sendable {
    var settings: [UInt8]
    var pattern: [UInt8]
    func validate(_ target: LightTarget) throws {
        if target == .mouse {
            guard settings.count == 3, settings[0] <= 1, settings[1] <= 2, (1...10).contains(settings[2]),
                  pattern.count >= 7, pattern.count <= 8192, pattern[0] == 1,
                  word(pattern,1) == pattern.count - 4, (pattern.count - 4) % 3 == 0, pattern[3] > 0 else {
                throw MouseError.message("鼠标灯效数据不完整或格式未知，未启用写入。")
            }
        } else {
            guard settings.count == 13, pattern.isEmpty, settings[0] <= 1, (1...7).contains(settings[1]),
                  [2,5,8].allSatisfy({ Int(settings[$0]) * 256 + Int(settings[$0+1]) <= 360 }),
                  [4,7,10].allSatisfy({ settings[$0] <= 100 }), (81...100).contains(settings[11]), settings[12] > 0 else {
                throw MouseError.message("接收器灯效数据不完整或格式未知，未启用写入。")
            }
        }
    }
    static func nv(_ bytes: [UInt8], id: Int) throws -> [UInt8] {
        guard bytes.count >= 5, bytes[0] == 0, word(bytes,1) == id,
              word(bytes,3) > 0, bytes.count == word(bytes,3) + 5 else {
            throw MouseError.message("灯效备份不完整，停止写入。")
        }
        return Array(bytes.dropFirst(5))
    }
    static func patternLength(header: [UInt8]) throws -> Int {
        guard header.count == 4, header[0] == 1, header[3] > 0,
              (3...8188).contains(word(header,1)), word(header,1) % 3 == 0 else {
            throw MouseError.message("灯效动画头部无效，停止读取和写入。")
        }
        return word(header,1) + 4
    }
    static func pattern(mode: Int, speed: Int, colors: [[UInt8]], maximumBytes: Int = 1000) throws -> [UInt8] {
        guard (0...2).contains(mode), (1...10).contains(speed), (1...7).contains(colors.count), colors.allSatisfy({ $0.count == 3 }) else { throw MouseError.message("灯效颜色或速度无效") }
        // Bound complete readback on the selected transport. Preserve cycle duration
        // by reducing sample count; reject combinations that exceed the u8 interval.
        guard maximumBytes >= 10, maximumBytes <= 8192 else { throw MouseError.message("灯效数据范围无效") }
        let period = Double(10-speed) * 3500 / 9 + 500
        let cycles = mode == 1 ? colors.count : 1
        let frameBudget = min(294, (maximumBytes-4)/3) / cycles / 2 * 2
        let frames = min(max(2, Int((period/16/2).rounded())*2), frameBudget)
        guard frames >= 2 else { throw MouseError.message("此颜色组合请使用蓝牙或 USB 设置。") }
        let interval = max(16, Int((period/Double(frames)).rounded()))
        guard mode == 0 || interval <= 255 else {
            throw MouseError.message("接收器不支持此速度的多色呼吸灯，请减少颜色、提高速度，或切换蓝牙 / USB。")
        }
        var rgb: [UInt8] = []
        if mode == 0 { rgb = colors[0] }
        else if mode == 1 {
            for color in colors {
                for frame in 1...frames {
                    let phase = Double(frame) * 2 / Double(frames)
                    let brightness = max(0, min(phase, 2-phase))
                    rgb += color.map { UInt8((Double($0) * brightness).rounded()) }
                }
            }
        } else {
            for (index,color) in colors.enumerated() {
                for _ in 0..<(frames / colors.count + (index < frames % colors.count ? 1 : 0)) { rgb += color }
            }
        }
        return [1] + littleEndian(rgb.count) + [UInt8(mode == 0 ? 16 : interval)] + rgb
    }
    // Recover distinct palette peaks from known generated waveforms. The raw
    // pattern remains authoritative until the user explicitly edits it.
    var colors: [[UInt8]] {
        guard pattern.count >= 7 else { return [[255,255,255]] }
        let frames = stride(from: 4, to: pattern.count-2, by: 3).map { Array(pattern[$0..<$0+3]) }
        var palette: [[UInt8]] = []
        if settings[1] == 1 {
            var peak = [UInt8](repeating: 0,count: 3), last = 0
            for frame in frames {
                let level = frame.map(Int.init).reduce(0,+)
                if level > peak.map(Int.init).reduce(0,+) { peak = frame }
                if level == 0 && last > 0 { if !palette.contains(peak) { palette.append(peak) }; peak = [0,0,0] }
                last = level
            }
        } else {
            for frame in frames where palette.last != frame { palette.append(frame); if palette.count >= 7 { break } }
        }
        return palette.isEmpty ? [frames.max(by: {$0.map(Int.init).reduce(0,+) < $1.map(Int.init).reduce(0,+)}) ?? [255,255,255]] : Array(palette.prefix(7))
    }
}
struct LightSnapshot: Codable, Equatable, Sendable {
    let target: LightTarget
    let identity: UInt64
    let profile: Int
    let state: LightState
    func replacing(_ state: LightState) -> Self { Self(target: target,identity: identity,profile: profile,state: state) }
    func sameDevice(_ other: Self) -> Bool { target == other.target && identity == other.identity && profile == other.profile }
}
struct LightReceipt: Codable, Sendable { let before: LightSnapshot; let after: LightSnapshot }

extension MouseDevice {
    func readLight(_ target: LightTarget) throws -> LightSnapshot {
        let profile = target == .mouse ? try readProfile() : -1
        let state: LightState
        if target == .mouse {
            let settings = try LightState.nv(command(0x0a0c,payload:littleEndian(24586)+littleEndian(3)),id:24586)
            let header = try LightState.nv(command(0x0a0c,payload:littleEndian(25088)+littleEndian(4)),id:25088)
            let length = try LightState.patternLength(header:header)
            if connectionKind == .receiver && length > 128 {
                throw MouseError.message("当前动画较长，接收器无法完整读取。请切换蓝牙或 USB 读取和修改；现有灯效不受影响。")
            }
            let pattern = try LightState.nv(command(0x0a0c,payload:littleEndian(25088)+littleEndian(length)),id:25088)
            guard pattern.count == length, Array(pattern.prefix(4)) == header else {
                throw MouseError.message("灯效动画在读取期间发生变化，请重新读取。")
            }
            state = LightState(settings:settings,pattern:pattern)
            guard try readProfile() == profile else { throw MouseError.message("读取期间板载配置变化") }
        } else { state = LightState(settings:try command(0x300e,routeOverride:0),pattern:[]) }
        try state.validate(target)
        return LightSnapshot(target:target,identity:identity,profile:profile,state:state)
    }
    func writeLight(_ desired: LightSnapshot) throws {
        try desired.state.validate(desired.target)
        guard identity == desired.identity else { throw MouseError.message("连接已变化，请重新读取灯效") }
        if desired.target == .receiver {
            _ = try command(0x300d,payload:desired.state.settings,routeOverride:0,waitForReply:false)
        } else {
            guard try readProfile() == desired.profile else { throw MouseError.message("配置已变化，停止灯效写入") }
            // The official feature-report path does not promise a write ACK.
            // Success is determined exclusively by full persisted readback.
            let current = try readLight(.mouse)
            if current.state.pattern != desired.state.pattern {
                _ = try command(0x0a0d,payload:littleEndian(25088)+desired.state.pattern,waitForReply:false)
            }
            _ = try command(0x30b3,payload:desired.state.settings,waitForReply:false)
            if desired.state.settings[0] == 1 && desired.state.settings[1] == 0 {
                _ = try command(0x30c0,payload:[128,0,16,1]+Array(desired.state.pattern[4..<7]),waitForReply:false)
            }
        }
        Thread.sleep(forTimeInterval:0.15)
    }
}

actor LightingService {
    static var pendingURL: URL { MouseService.backupDirectory.appendingPathComponent("lighting-pending.json") }
    func hasPending() -> Bool { FileManager.default.fileExists(atPath:Self.pendingURL.path) }
    private func device(_ target: LightTarget) throws -> MouseDevice { try MouseDevice(preferredConnection:target == .receiver ? .receiver : nil) }
    func read(_ target: LightTarget) throws -> LightSnapshot { try device(target).readLight(target) }
    static func canRestore(_ now: LightSnapshot, before: LightSnapshot, after: LightSnapshot) -> Bool {
        now.sameDevice(before) && now.sameDevice(after) &&
        [before.state.settings,after.state.settings].contains(now.state.settings) &&
        [before.state.pattern,after.state.pattern].contains(now.state.pattern)
    }
    func apply(_ state: LightState, expected: LightSnapshot) throws -> LightReceipt {
        guard !hasPending(), !["pending.json","mapping-pending.json"].contains(where:{FileManager.default.fileExists(atPath:MouseService.backupDirectory.appendingPathComponent($0).path)}) else { throw MouseError.message("请先恢复未完成的配置修改") }
        try state.validate(expected.target)
        let d = try device(expected.target), before = try d.readLight(expected.target)
        if expected.target == .mouse && d.connectionKind == .receiver && state.pattern.count > 128 {
            throw MouseError.message("此动画请使用蓝牙或 USB 保存。")
        }
        guard before == expected, state != before.state else { throw MouseError.message("灯效已变化或没有改动，请重新读取") }
        let receipt = LightReceipt(before:before,after:before.replacing(state))
        try save(receipt)
        do {
            try d.writeLight(receipt.after)
            guard try d.readLight(expected.target) == receipt.after else { throw MouseError.message("灯效读回不一致") }
            try archive("verified"); return receipt
        } catch {
            let reason = error.localizedDescription
            do { _ = try restore(receipt, device:d); try archive("rolled-back") }
            catch { throw MouseError.message("灯效保存未完成，恢复尚未确认。原始备份已保留，请保持原连接并恢复灯效。保存错误：\(reason)；恢复错误：\(error.localizedDescription)") }
            throw MouseError.message("保存未完成，原灯效已恢复：\(reason)")
        }
    }
    func undo(_ receipt: LightReceipt) throws -> LightSnapshot { try apply(receipt.before.state,expected:receipt.after).after }
    func recover() throws -> LightSnapshot {
        let receipt = try JSONDecoder().decode(LightReceipt.self,from:Data(contentsOf:Self.pendingURL))
        let restored = try restore(receipt,device:device(receipt.before.target))
        try archive("recovered"); return restored
    }
    private func restore(_ receipt: LightReceipt, device d: MouseDevice) throws -> LightSnapshot {
        let now = try d.readLight(receipt.before.target)
        guard Self.canRestore(now,before:receipt.before,after:receipt.after) else { throw MouseError.message("连接或灯效出现额外变化，停止自动恢复") }
        if now != receipt.before { try d.writeLight(receipt.before) }
        let restored = try d.readLight(receipt.before.target)
        guard restored == receipt.before else { throw MouseError.message("原始灯效未恢复完整") }
        return restored
    }
    private func save(_ receipt: LightReceipt) throws {
        try FileManager.default.createDirectory(at:Self.pendingURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(receipt).write(to:Self.pendingURL,options:.atomic)
        let file = try FileHandle(forWritingTo:Self.pendingURL); try file.synchronize(); try file.close()
    }
    private func archive(_ status: String) throws {
        try FileManager.default.moveItem(at:Self.pendingURL,to:Self.pendingURL.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString)-lighting-\(status).json"))
    }
}
