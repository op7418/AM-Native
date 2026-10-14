import Foundation
import CoreBluetooth

// Completion and timeout can race; only the first result wins. In particular,
// waiting for the system permission prompt must not block the caller indefinitely.
final class BluetoothOperation {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var result: Result<[UInt8], Error>?
    @discardableResult func complete(_ value: Result<[UInt8], Error>) -> Bool {
        lock.lock()
        guard result == nil else { lock.unlock(); return false }
        result = value; lock.unlock(); signal.signal(); return true
    }
    func wait(timeout: TimeInterval) throws -> [UInt8] {
        if signal.wait(timeout: .now() + timeout) == .timedOut {
            complete(.failure(MouseError.message("蓝牙通信超时。首次使用请允许系统蓝牙权限，然后唤醒鼠标并重新连接。")))
        }
        lock.lock(); let value = result!; lock.unlock()
        return try value.get()
    }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
}

// CoreBluetooth callbacks live on their own queue. Callers serialize complete
// transactions with MouseDevice's process lock; the UI never runs this worker.
final class BluetoothTransport: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let serviceID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    private static let txID = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")
    private static let rxID = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")
    private let queue = DispatchQueue(label: "AMNative.Bluetooth")
    private let productName: String
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var tx: CBCharacteristic?
    private var rx: CBCharacteristic?
    private var ready = false
    private var discovering = false
    private var closed = false
    private var completion: ((Result<[UInt8], Error>) -> Void)?
    private var commandID: UInt16?
    private var decoder = RaceDecoder()
    private var trace: ((String) -> Void)?

    init(productName: String) throws {
        self.productName = productName
        super.init()
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            throw MouseError.message("请在系统设置 → 隐私与安全性 → 蓝牙中允许 AM Native 访问蓝牙。")
        }
        do {
            _ = try perform(timeout: 12) {
                self.central = CBCentralManager(delegate: self, queue: self.queue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false])
            }
        } catch { close(); throw error }
    }

    private func perform(timeout: TimeInterval, start: @escaping () -> Void) throws -> [UInt8] {
        let operation = BluetoothOperation()
        queue.async {
            guard !self.closed, !operation.isFinished else { return }
            self.completion = { operation.complete($0) }
            start()
        }
        do { return try operation.wait(timeout: timeout) }
        catch { close(); throw error }
    }
    private func finish(_ result: Result<[UInt8], Error>) {
        let callback = completion; completion = nil; commandID = nil
        callback?(result)
    }
    private func fail(_ message: String) { finish(.failure(MouseError.message(message))) }

    func exchange(_ request: [UInt8], command: UInt16, trace: ((String) -> Void)?) throws -> [UInt8] {
        try perform(timeout: 4) {
            guard self.ready, let p = self.peripheral, p.state == .connected, let tx = self.tx else {
                self.fail("蓝牙鼠标已断开，请重新连接。"); return
            }
            guard request.count <= p.maximumWriteValueLength(for: .withResponse) else {
                self.fail("蓝牙命令超过当前传输长度，未发送。"); return
            }
            self.commandID = command; self.decoder = RaceDecoder(); self.trace = trace
            trace?("BLE TX " + request.map { String(format: "%02x", $0) }.joined(separator: " "))
            p.writeValue(Data(request), for: tx, type: .withResponse)
        }
    }

    func close() {
        // Never queue.sync here: CoreBluetooth may be waiting for a human to
        // answer its first permission prompt. Release the caller promptly.
        queue.async {
            guard !self.closed else { return }; self.closed = true; self.ready = false
            self.completion = nil; self.commandID = nil
            if let p = self.peripheral {
                p.delegate = nil
                if let rx = self.rx, rx.isNotifying { p.setNotifyValue(false, for: rx) }
                self.central?.cancelPeripheralConnection(p)
            }
            self.central?.delegate = nil
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !closed else { return }
        switch central.state {
        case .poweredOn:
            guard !discovering else { return }; discovering = true
            // Use an already connected mouse only. Do not scan/pair arbitrary nearby devices.
            let devices = central.retrieveConnectedPeripherals(withServices: [Self.serviceID, CBUUID(string: "1812"), CBUUID(string: "180F")])
                .filter { $0.name == productName }
            guard devices.count == 1, let p = devices.first else {
                fail(devices.isEmpty ? "请先在 macOS 蓝牙设置中连接 AM Infinity .97，再重试。" : "检测到多只同名蓝牙鼠标，请只保留一只连接。"); return
            }
            peripheral = p; p.delegate = self; central.connect(p)
        case .unauthorized: ready = false; fail("请在系统设置 → 隐私与安全性 → 蓝牙中允许 AM Native 访问蓝牙。")
        case .poweredOff: ready = false; fail("蓝牙已关闭，请在系统设置中打开蓝牙。")
        case .unsupported: fail("这台 Mac 不支持所需的蓝牙连接。")
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !closed else { return }; peripheral.discoverServices([Self.serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail("蓝牙连接失败：" + (error?.localizedDescription ?? "请唤醒鼠标后重试"))
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready = false; fail("蓝牙鼠标已断开，请重新连接。")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            fail("此蓝牙鼠标未提供已知的配置服务。"); return
        }
        peripheral.discoverCharacteristics([Self.txID, Self.rxID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        tx = service.characteristics?.first { $0.uuid == Self.txID && $0.properties.contains(.write) }
        rx = service.characteristics?.first { $0.uuid == Self.rxID && $0.properties.contains(.notify) }
        guard error == nil, tx != nil, let rx else { fail("蓝牙配置通道不完整，未发送配置命令。"); return }
        peripheral.setNotifyValue(true, for: rx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.rxID else { return }
        guard error == nil, characteristic.isNotifying else { fail("无法接收蓝牙鼠标回复。"); return }
        guard !ready else { return }
        ready = true; finish(.success([]))
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("蓝牙请求发送失败：" + error.localizedDescription) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.rxID, let commandID else { return }
        if let error { fail("蓝牙读取失败：" + error.localizedDescription); return }
        let bytes = Array(characteristic.value ?? Data())
        trace?("BLE RX " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        for frame in decoder.append(bytes: bytes) where frame.command == commandID {
            guard frame.payload.first == 0 else { fail(String(format: "设备拒绝命令 0x%04x", commandID)); return }
            if commandID == 0x1c07 && frame.payload.count <= 1 { continue }
            finish(.success(frame.payload)); return
        }
    }
}
