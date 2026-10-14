import Foundation

@main
struct CoreTests {
    static func check(_ test: @autoclosure () throws -> Bool) throws { let result = try test(); precondition(result) }
    static func main() throws {
        let payload: [UInt8] = [0,8,4,144,1,32,3,176,4,64,6,72,13,0,25,16,39,48,117,144,1,32,3,176,4,64,6,72,13,0,25,16,39,48,117]
        let dpi = try DPIState.parse(payload)
        try check(dpi.current.x == 3400 && dpi.current.y == 3400 && dpi.stageCount == 8)
        try check(dpi.stages.first?.x == 400 && dpi.stages.last?.y == 30000)
        let changed = expectedPayload(dpi, replacing: DPIStage(index: 0, x: 450, y: 450))
        let parsed = try DPIState.parse(changed)
        try check(parsed.stages[0].x == 450 && parsed.stages[0].y == 450)
        try check(Array(parsed.stages.dropFirst()) == Array(dpi.stages.dropFirst()))
        try check(parsed.currentIndex == dpi.currentIndex)
        try check(expectedPayload(parsed, replacing: dpi.stages[0]) == payload)
        for invalid in [Array(payload.prefix(10)), [UInt8](arrayLiteral: 0,9,0), [0,8,8] + Array(payload.dropFirst(3)), [1] + Array(payload.dropFirst())] {
            do { _ = try DPIState.parse(invalid); fatalError("Invalid DPI accepted") } catch {}
        }
        let battery = try BatteryState.parse([0,0,67,255,1,34,1])
        try check(battery.percent == 67 && battery.charging == false)
        try check(try BatteryState.parse([0,67,0]).charging == nil)
        do { _ = try BatteryState.parse([0,0,201,255,1,34,1]); fatalError("Invalid battery accepted") } catch {}
        func report(_ bytes: [UInt8], route: UInt8 = 128) -> [UInt8] { [0x14,UInt8(bytes.count),route] + bytes }
        let frame: [UInt8] = [5,0x5d,37,0,0xc5,0x30] + payload
        var decoder = RaceDecoder()
        try check(try decoder.append(report: report(Array(frame.prefix(13))), route: 128).isEmpty)
        let frames = try decoder.append(report: report(Array(frame.dropFirst(13))), route: 128)
        try check(frames.count == 1 && frames[0].command == 0x30c5 && frames[0].payload == payload)
        try check(try decoder.append(report: report(frame, route: 0), route: 128).isEmpty)
        let ack: [UInt8] = [5,0x5b,3,0,0xc4,0x30,0]
        try check(try decoder.append(report: report(ack + ack), route: 128).count == 2)
        for invalid: [UInt8] in [[0x14,60,128], [0x14,7,128,0], [0x15,0,128]] {
            do { _ = try decoder.append(report: invalid, route: 128); fatalError("Invalid HID accepted") } catch {}
        }
        print("PASS: real DPI/battery fixtures, all-stage restoration, malformed replies, fragmented replies, route isolation, multiple frames")
    }
}
