import SwiftUI

struct UpdatePanel: View {
    @EnvironmentObject var model: MouseModel
    @EnvironmentObject var updates: UpdateModel
    @AppStorage("updates.automatic") private var automatic = true
    var body: some View {
        Form {
            Section {
                Toggle("自动检查官方更新", isOn: $automatic)
                Text("App 运行时每天检查一次；新版本会显示在“更新”标签和菜单栏中。只查询版本，不自动下载或刷写。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(updates.checking ? "正在检查…" : "现在检查") {
                    Task { await model.readVersions(); await updates.check(current: model.versions) }
                }.disabled(updates.checking || model.busy)
                if let date = updates.checkedAt { Text("最近尝试：\(date.formatted())").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(updates.releases) { release in
                Section(release.title) {
                    LabeledContent("官方最新", value: release.version).monospacedDigit()
                    LabeledContent("当前版本", value: updates.current[release.id] ?? "未能读取")
                    if updates.isNew(release) { Label("有新版本", systemImage: "arrow.down.circle.fill").foregroundStyle(.tint) }
                    else if let local = updates.current[release.id], ReleaseVersion(local) == ReleaseVersion(release.version) {
                        Label("与官方最新版本一致", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    } else { Text("已记录官网版本，后续新发布时提醒。").font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("更新说明") { Text(release.notes).font(.callout).textSelection(.enabled) }
                    Link("打开官方页面", destination: release.officialURL)
                }
            }
            if !updates.errors.isEmpty {
                Section("未完成的检查") {
                    ForEach(updates.errors, id: \.self) { Text($0).foregroundStyle(.orange).font(.callout) }
                    Text("上方可能是上次缓存结果，不能据此认定没有更新。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if updates.newCount > 0 { Section { Button("标记发布提醒已读") { updates.acknowledge() } } }
        }.formStyle(.grouped)
    }
}
