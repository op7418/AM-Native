import SwiftUI

struct LightingPanel: View {
    @EnvironmentObject var model: MouseModel
    @State private var target: LightTarget = .mouse
    @State private var baseline: LightSnapshot?
    @State private var enabled = false
    @State private var mode = 0
    @State private var speed = 6.0
    @State private var brightness = 240.0
    @State private var palette = ["#FFFFFF"]
    @State private var hue = [0.0,0.0,0.0]
    @State private var saturation = [100.0,100.0,100.0]
    private let mouseModes = ["常亮","呼吸","霓虹"]
    private let receiverModes = ["常亮","呼吸","弧光","马赛克","极光","夜城","流光"]
    private func rgb(_ hex: String) -> [UInt8]? {
        let h = hex.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"#",with:"")
        guard h.count == 6, let value = UInt32(h,radix:16) else { return nil }
        return [UInt8((value>>16)&255),UInt8((value>>8)&255),UInt8(value&255)]
    }
    private var mousePatternLimit: Int { model.snapshot?.connection == MouseConnection.receiver.rawValue ? 128 : 1000 }
    private var paletteError: String? {
        let colors=palette.compactMap(rgb)
        guard colors.count == palette.count else { return "请输入有效的 #RRGGBB 颜色。" }
        do { _ = try LightState.pattern(mode:mode,speed:Int(speed),colors:colors,maximumBytes:mousePatternLimit); return nil }
        catch { return error.localizedDescription }
    }
    private var proposed: LightState? {
        guard let baseline, baseline.target == target else { return nil }
        var state = baseline.state
        state.settings[0] = enabled ? 1 : 0; state.settings[1] = UInt8(mode)
        if target == .mouse {
            let colors = palette.compactMap(rgb)
            guard colors.count == palette.count else { return nil }
            state.settings[2] = UInt8(speed)
            // Preserve arbitrary existing frame data when only changing the switch.
            let previous = baseline.state.colors.map(hex)
            if mode != Int(baseline.state.settings[1]) || Int(speed) != Int(baseline.state.settings[2]) || palette.map({$0.uppercased()}) != previous {
                guard let pattern = try? LightState.pattern(mode:mode,speed:Int(speed),colors:colors,maximumBytes:mousePatternLimit) else { return nil }
                state.pattern = pattern
            }
        } else {
            for i in 0..<3 {
                let offset=2+i*3, value=Int(hue[i])
                state.settings[offset]=UInt8(value>>8); state.settings[offset+1]=UInt8(value&255)
                state.settings[offset+2]=UInt8(saturation[i])
            }
            state.settings[11]=UInt8(speed)+80; state.settings[12]=UInt8(brightness)
        }
        return state
    }
    private var stale: Bool { baseline != model.lighting }
    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Picker("灯效设备",selection:$target) {
                        ForEach(LightTarget.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.busy).accessibilityIdentifier("light-target")
                    Text(target == .mouse ? "设置鼠标的灯光。保存前自动备份，退出 App 后仍有效。" : "设置接收器自身的灯光。插入接收器即可调整，与鼠标的连接方式无关。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let baseline, baseline.target == target {
                        Toggle("开启灯效",isOn:$enabled).toggleStyle(.switch).accessibilityIdentifier("light-enabled")
                        VStack(alignment:.leading,spacing:10) {
                            Text("效果").font(.headline)
                            if target == .mouse {
                                Picker("效果",selection:$mode) {
                                    ForEach(0..<3) { Text(mouseModes[$0]).tag($0) }
                                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("light-mode")
                            } else {
                                Picker("效果",selection:$mode) {
                                    ForEach(1..<8) { Text(receiverModes[$0-1]).tag($0) }
                                }.pickerStyle(.radioGroup).labelsHidden().accessibilityIdentifier("light-mode")
                            }
                        }
                        if target == .receiver || mode != 0 { slider("速度",value:$speed,range:1...(target == .mouse ? 10 : 20)) }
                        if target == .receiver {
                            slider("亮度",value:$brightness,range:1...255)
                            if let index = [1:0,2:1,7:2][mode] {
                                slider("色相",value:$hue[index],range:0...360)
                                slider("饱和度",value:$saturation[index],range:1...100)
                                RoundedRectangle(cornerRadius:10).fill(Color(hue:hue[index]/360,saturation:saturation[index]/100,brightness:1)).frame(height:30)
                            }
                        } else {
                            VStack(alignment:.leading,spacing:12) {
                                Text("颜色").font(.headline)
                                ForEach(palette.indices,id:\.self) { index in
                                    HStack {
                                        let c = rgb(palette[index]) ?? [0,0,0]
                                        Circle().fill(Color(red:Double(c[0])/255,green:Double(c[1])/255,blue:Double(c[2])/255))
                                            .overlay(Circle().stroke(.secondary.opacity(0.3))).frame(width:24,height:24)
                                        TextField("#RRGGBB",text:$palette[index]).textFieldStyle(.roundedBorder).monospaced()
                                            .accessibilityLabel("颜色 \(index+1)").accessibilityIdentifier("light-color-\(index)")
                                        if mode != 0 && palette.count > 1 {
                                            Button { palette.remove(at:index) } label: { Image(systemName:"minus.circle") }.buttonStyle(.borderless).help("移除颜色")
                                        }
                                    }
                                }
                                if mode != 0 && palette.count < 7 { Button("添加颜色",systemImage:"plus") { palette.append("#4080FF") }.buttonStyle(.borderless) }
                                Text("输入十六进制颜色，例如 #4080FF。常亮使用第一种颜色；呼吸和霓虹最多 7 色。")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let error=paletteError { Text(error).font(.caption).foregroundStyle(.orange) }
                            }
                        }
                        if target == .mouse && mousePatternLimit == 128 {
                            Text("接收器模式使用精简动画。较慢的多色呼吸灯请用蓝牙或 USB 设置。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !enabled { Text("灯效已关闭，保存颜色和效果后可随时打开。").font(.caption).foregroundStyle(.secondary) }
                        if stale {
                            Text("连接或配置已变化，请重新读取后再保存。").font(.caption).foregroundStyle(.orange)
                        }
                    } else if model.busy { ProgressView("读取灯效…") }
                    Button("重新读取",systemImage:"arrow.clockwise") { Task { await model.readLighting(target); load() } }.disabled(model.busy)
                }.padding(.horizontal,22).padding(.bottom,22)
                    .disabled(model.busy)
            }
            VStack(alignment:.leading,spacing:12) {
                if let message = model.lightingMessage {
                    Text(message).font(.caption).foregroundStyle(model.lightingFailed ? Color.orange : Color.secondary).textSelection(.enabled)
                }
                HStack {
                    Button("撤销",systemImage:"arrow.uturn.backward") { Task { await model.undoLighting(); load() } }
                        .nativeAction().disabled(model.busy || model.lightingPending || model.lightingReceipt?.after != baseline || baseline == nil)
                    Spacer()
                    Button("保存光效") {
                        if let state=proposed,let baseline { Task { await model.saveLighting(state,expected:baseline); load() } }
                    }.nativeAction(prominent:true)
                        .disabled(model.busy || model.pending || model.mappingPending || model.lightingPending || stale || proposed == nil || proposed == baseline?.state)
                        .accessibilityIdentifier("save-lighting")
                }
            }.padding(20).background(SidebarSurface.color)
        }
        .task(id:target) { await readWhenReady() }
        .onChange(of:model.snapshot?.deviceIdentity) { baseline=nil; Task { await readWhenReady() } }
        .onChange(of:model.lighting) { if baseline == nil { load() } }
    }
    private func readWhenReady() async {
        while model.busy { do { try await Task.sleep(for:.milliseconds(100)) } catch { return } }
        guard !Task.isCancelled else { return }
        await model.readLighting(target); load()
    }
    private func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value:Binding(get:{ value.wrappedValue },set:{ value.wrappedValue = $0.rounded() }),in:range).accessibilityLabel(title).accessibilityValue(String(Int(value.wrappedValue)))
        }
    }
    private func hex(_ color:[UInt8]) -> String { "#"+color.map{String(format:"%02X",$0)}.joined() }
    private func load() {
        guard let s=model.lighting,s.target==target else { baseline=nil; return }
        baseline=s;enabled=s.state.settings[0] != 0;mode=Int(s.state.settings[1])
        if target == .mouse { speed=Double(s.state.settings[2]);palette=s.state.colors.map(hex) }
        else {
            speed=Double(s.state.settings[11])-80;brightness=Double(s.state.settings[12])
            for i in 0..<3 { hue[i]=Double(Int(s.state.settings[2+i*3])*256+Int(s.state.settings[3+i*3]));saturation[i]=Double(s.state.settings[4+i*3]) }
        }
    }
}
