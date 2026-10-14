import SwiftUI

struct PointerView: View {
    @EnvironmentObject var model: MouseModel
    @State private var index = 0
    @State private var x = ""
    @State private var y = ""
    @State private var linked = true
    @State private var baseline: MouseSnapshot?
    @State private var initialized = false

    private var proposed: DPIStage? {
        guard let xv = Int(x), let yv = Int(linked ? x : y),
              [xv, yv].allSatisfy({ (100...30000).contains($0) && $0 % 50 == 0 }) else { return nil }
        return DPIStage(index: index, x: xv, y: yv)
    }
    private var hasChange: Bool {
        guard let p = proposed, let s = model.snapshot, s.dpi.stages.indices.contains(index) else { return false }
        return p != s.dpi.stages[index]
    }
    private var isDirty: Bool {
        guard let baseline, baseline.dpi.stages.indices.contains(index) else { return false }
        let stage = baseline.dpi.stages[index]
        return x != String(stage.x) || (linked ? x : y) != String(stage.y)
    }
    private var stale: Bool {
        guard let baseline, let s = model.snapshot else { return false }
        return baseline.deviceIdentity != s.deviceIdentity || baseline.profile != s.profile || baseline.dpi != s.dpi
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let s = model.snapshot {
                    Section {
                        InlineChoicePicker(title: "编辑档位", selection: $index,
                            options: s.dpi.stages.prefix(s.dpi.stageCount).map { stage in
                                (value: stage.index, title: "第 \(stage.index + 1) 档\(stage.index == s.dpi.currentIndex ? " · 使用中" : "")")
                            })
                            .accessibilityIdentifier("dpi-stage-picker")
                            .onChange(of: index) { loadFields() }
                        Toggle("同步 X / Y 轴", isOn: Binding(get: { linked }, set: { value in
                            if linked && !value { y = x }
                            linked = value
                        }))
                    } header: { Text("DPI 档位") }
                    footer: { Text("编辑其他档位不会切换正在使用的档位。") }
                    Section("灵敏度") {
                        axisEditor(label: linked ? "DPI" : "横向 DPI", text: $x, identifier: "dpi-x")
                        if !linked { axisEditor(label: "纵向 DPI", text: $y, identifier: "dpi-y") }
                        if proposed == nil {
                            Label("请输入 100–30000 之间的 50 倍数。", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if stale {
                        Section {
                            Label("鼠标配置已变化", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                            Text("重新载入最新配置后再编辑，避免覆盖其他修改。")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("载入最新配置") { loadFields() }
                        }
                    }
                    Section("全部档位") {
                        ForEach(Array(s.dpi.stages.prefix(s.dpi.stageCount))) { stage in
                            Button { index = stage.index } label: {
                                HStack(spacing: 10) {
                                    Text("\(stage.index + 1)")
                                        .font(.caption.weight(.semibold)).frame(width: 24, height: 24)
                                        .background(index == stage.index ? Color.accentColor.opacity(0.12) : Color.clear, in: Circle())
                                        .foregroundStyle(index == stage.index ? Color.accentColor : Color.secondary)
                                    Text(stage.displayValue).monospacedDigit().foregroundStyle(.primary)
                                    Spacer()
                                    if stage.index == s.dpi.currentIndex {
                                        Text("使用中").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if index == stage.index { Image(systemName: "pencil").font(.caption).foregroundStyle(.tint) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("编辑第 \(stage.index + 1) 档，DPI \(stage.displayValue)\(stage.index == s.dpi.currentIndex ? "，当前使用中" : "")")
                        }
                    }
                } else { ConnectionHelp() }
            }.formStyle(.grouped).disabled(model.busy)
            if model.snapshot != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = model.notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button { Task { await model.undo(); loadFields() } } label: {
                            Label("撤销", systemImage: "arrow.uturn.backward")
                        }.nativeAction().disabled(model.receipt == nil || model.pending || model.busy)
                            .help("恢复本次运行中的上一次修改")
                        Spacer()
                        Button("保存到鼠标") {
                            if let p = proposed, let baseline {
                                Task { await model.apply(p, expected: baseline); loadFields() }
                            }
                        }.nativeAction(prominent: true)
                            .disabled(!hasChange || stale || model.pending || model.busy)
                            .accessibilityIdentifier("save-dpi")
                    }.controlSize(.large)
                    Text("自动备份 · 读回确认").font(.caption2).foregroundStyle(.secondary)
                }.padding(20).background(SidebarSurface.color)
            }
        }
        .onAppear { synchronize() }
        .onChange(of: model.snapshot?.capturedAt) { synchronize() }
    }

    private func axisEditor(label: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                Spacer()
                TextField(label, text: text).labelsHidden().textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing).monospacedDigit().frame(width: 98)
                    .accessibilityLabel(label).accessibilityIdentifier(identifier)
                Stepper(label, onIncrement: { nudge(text, by: 50) }, onDecrement: { nudge(text, by: -50) })
                    .labelsHidden().accessibilityLabel("调整\(label)，步长 50")
            }
            Slider(value: Binding(get: { sliderValue(text.wrappedValue) },
                                  set: { text.wrappedValue = String(Int($0.rounded())) }),
                   in: 100...30000, step: 50)
                .accessibilityLabel(label).accessibilityValue(text.wrappedValue)
            HStack { Text("100"); Spacer(); Text("30,000") }
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }.padding(.vertical, 4)
    }
    private func sliderValue(_ text: String) -> Double {
        guard let value = Double(text), value.isFinite else { return 100 }
        return min(30000, max(100, value))
    }
    private func nudge(_ text: Binding<String>, by amount: Int) {
        let value = min(30000, max(100, Int(text.wrappedValue) ?? 100))
        text.wrappedValue = String(min(30000, max(100, (value / 50) * 50 + amount)))
    }
    private func synchronize() {
        guard let s = model.snapshot else { return }
        if !initialized {
            index = s.dpi.currentIndex; initialized = true; loadFields()
        } else if !isDirty { loadFields() }
    }
    private func loadFields() {
        guard let s = model.snapshot else { return }
        if !s.dpi.stages.prefix(s.dpi.stageCount).contains(where: { $0.index == index }) { index = s.dpi.currentIndex }
        guard s.dpi.stages.indices.contains(index) else { return }
        baseline = s
        let stage = s.dpi.stages[index]
        x = String(stage.x); y = String(stage.y); linked = stage.x == stage.y
    }
}
