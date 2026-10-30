import SwiftUI

struct MappingPanel: View {
    @EnvironmentObject var model: MouseModel
    let control: MouseControl
    let selectControl: (MouseControl) -> Void
    @State private var draft: MappingDraft?
    private var stale: Bool { draft?.baseline != nil && draft?.baseline != model.mapping }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("按键 - \(control.title)", systemImage: control.symbol)
                        .font(.title3.weight(.semibold)).accessibilityIdentifier("mapping-heading")
                    Text("选择此键的操作，保存后退出 App 仍有效。快捷键使用 Mac 默认组合；至少保留一个左键点击。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if ["desktopPrevious", "desktopNext"].contains(draft?.actionID ?? "") {
                        Text("直接切到相邻桌面，无需打开调度中心。请在系统设置 → 键盘 → 键盘快捷键 → 调度中心中启用对应的 Control + 方向键快捷键。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if [.middle, .scrollUp, .scrollDown].contains(control) {
                        Picker("滚轮动作", selection: Binding(get: { control }, set: selectControl)) {
                            Text("点击").tag(MouseControl.middle)
                            Text("向上").tag(MouseControl.scrollUp)
                            Text("向下").tag(MouseControl.scrollDown)
                        }.pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("映射").font(.headline)
                        LabeledContent("当前操作", value: model.mapping?.mappings.first { $0.keyID == control.rawValue }?.title ?? "等待读取")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("改为").font(.headline).padding(.bottom, 4)
                        if let current = draft?.current, draft?.actionID == nil {
                            Label(current.title, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(MappingAction.all) { action in
                            Button {
                                draft?.actionID = action.id
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: draft?.actionID == action.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft?.actionID == action.id ? Color.accentColor : Color.secondary)
                                    Text(action.title).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }.font(.callout).padding(.horizontal, 10).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(draft?.actionID == action.id ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(draft == nil)
                                .accessibilityValue(draft?.actionID == action.id ? "已选择" : "未选择")
                                .accessibilityIdentifier("mapping-action-\(action.id)")
                        }
                    }
                    Button("使用此按键的默认操作") {
                        draft?.actionID = MappingAction.all.first { $0.type == control.defaultType && $0.params.isEmpty }?.id
                    }.disabled(draft == nil)
                    if stale {
                        Text("设备配置已变化，请重新载入后编辑。").font(.caption).foregroundStyle(.orange)
                        Button("载入最新映射") { load() }.disabled(model.busy)
                    }
                    if model.mapping == nil {
                        Text(model.mappingError ?? "连接鼠标后读取按键设置。").font(.caption).foregroundStyle(.secondary)
                        Button("重新读取") { Task { await model.refresh() } }.disabled(model.busy)
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 10) {
                if let message = model.mappingNotice {
                    Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("撤销映射", systemImage: "arrow.uturn.backward") {
                        Task { await model.undoMapping(); load() }
                    }.nativeAction().disabled(model.mappingReceipt == nil || model.busy || model.mappingPending || model.pending)
                    Spacer(minLength: 8)
                    Button("保存到鼠标") {
                        // Capture the immutable physical key and snapshot before suspension.
                        if let change = draft?.proposed, let baseline = draft?.baseline {
                            Task { await model.applyMapping(change, expected: baseline); load() }
                        }
                    }.nativeAction(prominent: true)
                        .disabled(model.busy || model.pending || model.mappingPending || stale || draft?.proposed == nil || draft?.proposed == draft?.current)
                        .accessibilityIdentifier("save-mapping")
                }.controlSize(.regular)
            }.padding(18).background(SidebarSurface.color)
        }.onAppear { load(); model.mappingNotice = nil }
            .onChange(of: model.mapping) { if draft == nil { load() } }
    }
    private func load() { draft = model.mapping.map { MappingDraft(control: control, baseline: $0) } }
}
