import Foundation
import IOKit.hid
import Darwin

enum MouseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct DPIStage: Codable, Equatable, Identifiable, Sendable {
    let index: Int
    var x: Int
    var y: Int
    var id: Int { index }
}

struct DPIState: Codable, Equatable, Sendable {
    let currentIndex: Int
    let stageCount: Int
    let stages: [DPIStage]
    let rawPayload: [UInt8]
    var current: DPIStage { stages[currentIndex] }
    static func parse(_ bytes: [UInt8]) throws -> DPIState {
        guard bytes.count >= 3, bytes[0] == 0 else { throw MouseError.message("DPI 响应无效") }
        let count = Int(bytes[1]), current = Int(bytes[2])
        guard (1...8).contains(count), current < count else { throw MouseError.message("DPI 档位数量或索引无效") }
        let slots = bytes.count >= 35 ? 8 : count
        guard bytes.count >= 3 + slots * 4 else { throw MouseError.message("DPI 响应不完整") }
        let stages = (0..<slots).map { i in
            DPIStage(index: i, x: word(bytes, 3 + i * 2), y: word(bytes, 3 + slots * 2 + i * 2))
        }
        guard stages.prefix(count).allSatisfy({ (100...30000).contains($0.x) && (100...30000).contains($0.y) }) else {
            throw MouseError.message("DPI 数值超出已知范围，停止写入")
        }
        return DPIState(currentIndex: current, stageCount: count, stages: stages, rawPayload: bytes)
    }
}

struct BatteryState: Codable, Sendable {
    let percent: Int
    let charging: Bool?
    let rawPayload: [UInt8]
    static func parse(_ bytes: [UInt8]) throws -> BatteryState {
        guard bytes.count >= 3, bytes[0] == 0 else { throw MouseError.message("电量响应无效") }
        let modern = bytes.count >= 7
        let value = modern ? Int(bytes[2]) : word(bytes, 1)
        guard (0...100).contains(value) else { throw MouseError.message("电量数值无效") }
        return BatteryState(percent: value, charging: modern ? bytes[1] != 0 : nil, rawPayload: bytes)
    }
}

func word(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
func littleEndian(_ n: Int) -> [UInt8] { [UInt8(n & 255), UInt8((n >> 8) & 255)] }

struct RaceFrame: Equatable {
    let command: UInt16
    let type: UInt8
    let payload: [UInt8]
}

// Reassembles split RACE frames; discards unsolicited commands at the caller.
struct RaceDecoder {
    private var buffer: [UInt8] = []
    mutating func append(report: [UInt8], route: UInt8) throws -> [RaceFrame] {
        guard report.count >= 3, report[0] == 0x14 else { throw MouseError.message("HID Report ID 不匹配") }
        let size = Int(report[1])
        guard size <= 59, report.count >= size + 3 else { throw MouseError.message("HID 长度无效") }
        guard report[2] == route, size > 0 else { return [] }
        return append(bytes: Array(report[3..<(size + 3)]))
    }
    mutating func append(bytes: [UInt8]) -> [RaceFrame] {
        buffer += bytes
        var frames: [RaceFrame] = []
        while buffer.count >= 6 {
            guard (buffer[0] == 5 || buffer[0] == 21), [0x5b, 0x5d].contains(buffer[1]) else {
                buffer.removeFirst(); continue
            }
            let length = word(buffer, 2) + 4
            guard length >= 6, length <= 16384 else { buffer.removeFirst(); continue }
            guard buffer.count >= length else { break }
            frames.append(RaceFrame(command: UInt16(word(buffer, 4)), type: buffer[1], payload: Array(buffer[6..<length])))
            buffer.removeFirst(length)
        }
        return frames
    }
}

struct MouseSnapshot: Codable, Sendable {
    let capturedAt: Date
    let productID: Int
    let deviceIdentity: UInt64
    let connection: String
    var connectionSymbol: String {
        switch connection {
        case MouseConnection.usb.rawValue: "cable.connector"
        case MouseConnection.bluetooth.rawValue: "wave.3.right"
        default: "antenna.radiowaves.left.and.right"
        }
    }
    let profile: Int
    let battery: BatteryState
    let dpi: DPIState
}

enum MouseConnection: String, Codable {
    case usb = "USB 直连", bluetooth = "蓝牙", receiver = "2.4 GHz 接收器"
    var priority: Int { switch self { case .usb: 0; case .bluetooth: 1; case .receiver: 2 } }
    var route: UInt8 { self == .receiver ? 0x80 : 0 }
}

struct MouseInterface {
    let vendorID: Int
    let productID: Int
    let productName: String
    let transport: String
    let usagePage: Int
    let featureSize: Int
    var connection: MouseConnection? {
        if transport == "Bluetooth Low Energy", vendorID == 328, productID == 0,
           productName == "AM Infinity .97", usagePage == 12 { return .bluetooth }
        guard transport == "USB", usagePage == 0xff13, featureSize == 62 else { return nil }
        if vendorID == 3725 && productID == 1795 { return .receiver }
        if (vendorID == 3725 && productID == 2176) || (vendorID == 13729 && productID == 53) { return .usb }
        return nil
    }
    static func select(_ interfaces: [MouseInterface]) throws -> Int {
        let supported = interfaces.indices.filter { interfaces[$0].connection != nil }
        guard let priority = supported.map({ interfaces[$0].connection!.priority }).min() else {
            throw MouseError.message("未找到 AM Infinity .97。请连接 USB、2.4G 接收器，或在系统蓝牙设置中连接鼠标。")
        }
        let preferred = supported.filter { interfaces[$0].connection!.priority == priority }
        guard preferred.count == 1 else { throw MouseError.message("检测到多只相同连接方式的鼠标，请只保留一只连接。") }
        return preferred[0]
    }
}

// Use only on one serial worker. No device seizure, event tap, helper, or network.
final class MouseDevice {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var bluetooth: BluetoothTransport?
    let connectionKind: MouseConnection
    let productID: Int
    let identity: UInt64
    let route: UInt8
    var connection: String { connectionKind.rawValue }
    var trace: ((String) -> Void)?
    private var lockFD: Int32 = -1

    private static func discover() -> (IOHIDManager, [IOHIDDevice], [MouseInterface]) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: 3725], [kIOHIDVendorIDKey: 13729],
            [kIOHIDVendorIDKey: 328, kIOHIDProductIDKey: 0]
        ] as CFArray)
        let candidates = Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
        let interfaces = candidates.map { d in
            MouseInterface(vendorID: Self.property(d, kIOHIDVendorIDKey), productID: Self.property(d, kIOHIDProductIDKey),
                productName: IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "",
                transport: IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "",
                usagePage: Self.property(d, kIOHIDPrimaryUsagePageKey), featureSize: Self.property(d, kIOHIDMaxFeatureReportSizeKey))
        }
        return (manager, candidates, interfaces)
    }

    static func currentIdentity() -> UInt64? {
        let (manager, devices, interfaces) = discover()
        defer { _ = manager }
        guard let index = try? MouseInterface.select(interfaces) else { return nil }
        var identity: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(devices[index]), &identity)
        return identity
    }

    init(preferredConnection: MouseConnection? = nil) throws {
        let discovery = Self.discover()
        manager = discovery.0
        let indices = discovery.2.indices.filter { preferredConnection == nil || discovery.2[$0].connection == preferredConnection }
        let candidates = indices.map { discovery.1[$0] }, interfaces = indices.map { discovery.2[$0] }
        let index = try MouseInterface.select(interfaces), selected = candidates[index]
        connectionKind = interfaces[index].connection!
        productID = interfaces[index].productID
        route = connectionKind.route
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(selected), &registryID)
        identity = registryID
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("am-native-hid-\(getuid()).lock")
        lockFD = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw MouseError.message("无法建立通信锁") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD); lockFD = -1
            throw MouseError.message("另一份 AM Native 正在使用设备，请稍后重试")
        }
        do {
            if connectionKind == .bluetooth {
                bluetooth = try BluetoothTransport(productName: interfaces[index].productName)
            } else {
                let code = IOHIDDeviceOpen(selected, 0)
                guard code == kIOReturnSuccess else {
                    throw MouseError.message(String(format: "无法打开鼠标接口（0x%08x）。请退出官方驱动及其网页后重试。", code))
                }
                device = selected
            }
        } catch { Darwin.close(lockFD); lockFD = -1; throw error }
    }
    deinit {
        bluetooth?.close()
        if let device { IOHIDDeviceClose(device, 0) }
        if lockFD >= 0 { Darwin.close(lockFD) }
    }
    private static func property(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    func command(_ command: UInt16, payload: [UInt8] = [], routeOverride: UInt8? = nil, waitForReply: Bool = true) throws -> [UInt8] {
        // Narrow allowlist: configuration and firmware VERSION reads only; no flashing, pairing or reset.
        guard [0x30c5, 0x30cf, 0x30c9, 0x30c4, 0x30c7, 0x30c3, 0x30c2, 0x1c07, 0x0a0c, 0x0a0d, 0x30b3, 0x30c0, 0x300d, 0x300e].contains(command) else { throw MouseError.message("此版本未启用该命令") }
        guard waitForReply || [0x0a0d, 0x30b3, 0x30c0, 0x300d].contains(command) else { throw MouseError.message("此命令必须等待回复") }
        if command == 0x0a0c {
            guard payload.count == 4, [24586,25088].contains(word(payload,0)), (1...8192).contains(word(payload,2)) else { throw MouseError.message("仅允许读取灯效配置") }
        }
        if connectionKind == .receiver, routeOverride == nil {
            if command == 0x0a0c, word(payload,2) > 128 { throw MouseError.message("接收器长动画请通过蓝牙或 USB 读取。") }
            if command == 0x0a0d, payload.count > 130 { throw MouseError.message("接收器长动画请通过蓝牙或 USB 保存。") }
        }
        if command == 0x0a0d {
            guard payload.count >= 6, word(payload,0) == 25088, payload[2] == 1,
                  word(payload,3) == payload.count - 6, payload.count <= 8198, payload[5] > 0 else { throw MouseError.message("灯效数据无效") }
        }
        if command == 0x30b3 { guard payload.count == 3, payload[0] <= 1, payload[1] <= 2, (1...10).contains(payload[2]) else { throw MouseError.message("灯效参数无效") } }
        if command == 0x30c0 { guard payload.count == 7, payload[0...3] == [128,0,16,1] else { throw MouseError.message("实时颜色参数无效") } }
        if [0x300d,0x300e].contains(command) {
            guard connectionKind == .receiver, routeOverride == 0, (command == 0x300e ? payload.isEmpty : payload.count == 13) else { throw MouseError.message("接收器灯效仅允许本地接收器接口") }
        }
        guard routeOverride == nil || (command == 0x1c07 && [UInt8(0),0x80].contains(routeOverride!)) || ([0x300d,0x300e].contains(command) && routeOverride == 0) else { throw MouseError.message("不允许覆盖写入路由") }
        let route = routeOverride ?? self.route
        let race: [UInt8] = [5, 0x5a] + littleEndian(payload.count + 2) + littleEndian(Int(command)) + payload
        if let bluetooth {
            guard routeOverride == nil || routeOverride == 0 else { throw MouseError.message("蓝牙不支持接收器路由") }
            return try bluetooth.exchange(race, command: command, trace: trace, waitForReply: waitForReply)
        }
        guard let device else { throw MouseError.message("鼠标已断开") }
        guard race.count <= 8204 else { throw MouseError.message("命令过长") }
        for start in stride(from: 0, to: race.count, by: 59) {
            let part = Array(race[start..<min(start + 59, race.count)])
            var report = [UInt8(0x14), UInt8(part.count), route] + part
            report += Array(repeating: 0, count: 62 - report.count)
            trace?("TX " + report.map { String(format: "%02x", $0) }.joined(separator: " "))
            let code = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x14, report, report.count)
            guard code == kIOReturnSuccess else { throw MouseError.message(String(format: "HID 写入失败 0x%08x", code)) }
            Thread.sleep(forTimeInterval: 0.002)
        }
        if !waitForReply { Thread.sleep(forTimeInterval: 0.12); return [] }
        var decoder = RaceDecoder()
        let deadline = Date().addingTimeInterval(command == 0x0a0c ? 12 : 3)
        repeat {
            var buffer = [UInt8](repeating: 0, count: 62); buffer[0] = 0x14
            var length = buffer.count
            let code = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x14, &buffer, &length)
            guard code == kIOReturnSuccess else { throw MouseError.message(String(format: "HID 读取失败 0x%08x", code)) }
            let bytes = Array(buffer.prefix(length))
            if bytes.count > 1, bytes[1] > 0 { trace?("RX " + bytes.map { String(format: "%02x", $0) }.joined(separator: " ")) }
            for frame in try decoder.append(report: bytes, route: route) where frame.command == command {
                guard command == 0x300e || frame.payload.first == 0 else { throw MouseError.message(String(format: "设备拒绝命令 0x%04x", command)) }
                if command == 0x1c07 || command == 0x0a0c { if frame.payload.count > 1 { return frame.payload }; continue }
                return frame.payload
            }
            // Drain fragmented animation replies promptly; pause only on empty reports.
            Thread.sleep(forTimeInterval: bytes.count > 1 && bytes[1] > 0 ? 0.001 : 0.02)
        } while Date() < deadline
        throw MouseError.message(String(format: "读取超时 0x%04x，请唤醒鼠标并重试", command))
    }

    func readDPI() throws -> DPIState { try DPIState.parse(command(0x30c5)) }
    func readProfile() throws -> Int {
        let bytes = try command(0x30c9)
        guard bytes.count >= 2, bytes[1] < 5 else { throw MouseError.message("配置编号无效") }
        return Int(bytes[1])
    }
    func snapshot() throws -> MouseSnapshot {
        let profile = try readProfile()
        let dpi = try readDPI()
        let battery = try BatteryState.parse(command(0x30cf))
        guard try readProfile() == profile else { throw MouseError.message("配置在读取期间切换，请重试") }
        return MouseSnapshot(capturedAt: Date(), productID: productID, deviceIdentity: identity, connection: connection, profile: profile, battery: battery, dpi: dpi)
    }
    func writeStage(_ stage: DPIStage, expectedProfile: Int, currentIndex: Int) throws {
        guard (0..<8).contains(stage.index), [stage.x, stage.y].allSatisfy({ (100...30000).contains($0) && $0 % 50 == 0 }) else { throw MouseError.message("DPI 需为 100–30000 之间的 50 倍数") }
        guard try readProfile() == expectedProfile else { throw MouseError.message("设备配置已切换，写入取消") }
        _ = try command(0x30c4, payload: [UInt8(stage.index)] + littleEndian(stage.x) + littleEndian(stage.y))
        if stage.index == currentIndex { _ = try command(0x30c7, payload: [UInt8(currentIndex)]) }
    }
}

func expectedPayload(_ state: DPIState, replacing stage: DPIStage) -> [UInt8] {
    var bytes = state.rawPayload
    let x = 3 + stage.index * 2, y = 3 + state.stages.count * 2 + stage.index * 2
    bytes.replaceSubrange(x..<(x + 2), with: littleEndian(stage.x))
    bytes.replaceSubrange(y..<(y + 2), with: littleEndian(stage.y))
    return bytes
}
