import SwiftUI
import AppKit

struct DeviceCanvas: View {
    @EnvironmentObject var model: MouseModel
    @Binding var selected: MouseControl
    let activePage: Page?
    let select: (MouseControl) -> Void
    let editPointer: () -> Void
    let showBattery: () -> Void
    @AppStorage("mouse.color") private var color = "black"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("AM Infinity .97").font(.system(size: 24, weight: .semibold))
                    Text("点选鼠标上的部件，设置它的操作").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ConnectionBadge()
            }
            InteractiveMouse(selected: activePage == .buttons ? selected : nil, select: select).frame(maxWidth: 850, maxHeight: 500).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer(minLength: 0)
                MacNavigationButton(title: "DPI  " + (model.snapshot?.dpi.current.displayValue ?? "—"),
                                    symbol: "cursorarrow.motionlines", selected: activePage == .pointer,
                                    identifier: "open-dpi", radius: 22, action: editPointer)
                    .frame(width: 134, height: 44).nativeGlass(radius: 22)
                MacNavigationButton(title: model.snapshot.map { "电量  \($0.battery.percent)%" } ?? "电量  —",
                                    symbol: model.snapshot?.battery.symbol ?? "battery.0percent", selected: activePage == .overview,
                                    identifier: "open-battery", radius: 22, action: showBattery)
                    .frame(width: 134, height: 44).nativeGlass(radius: 22)
                Spacer(minLength: 0)
            }.padding(.top, 8)
            HStack {
                Spacer()
                Picker("鼠标外观", selection: $color) {
                    Text("黑色").tag("black")
                    Text("白色").tag("white")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 115).help("手动选择鼠标外观，仅影响展示")
            }.padding(.top, 6)

        }.padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 4)
    }
}

struct OverviewPanel: View {
    @EnvironmentObject var model: MouseModel
    let editPointer: () -> Void
    var body: some View {
        Form {
            if let s = model.snapshot {
                Section("指针") {
                    LabeledContent("当前 DPI", value: s.dpi.current.displayValue).monospacedDigit()
                    LabeledContent("正在使用", value: "第 \(s.dpi.currentIndex + 1) 档 / 共 \(s.dpi.stageCount) 档")
                    Button(action: editPointer) {
                        HStack { Text("调整指针灵敏度"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(.link).padding(.vertical, 3)
                }
                Section("电池") {
                    HStack {
                        Label("剩余电量", systemImage: s.battery.symbol)
                        Spacer()
                        Text("\(s.battery.percent)%").monospacedDigit()
                    }
                    ProgressView(value: Double(s.battery.percent), total: 100)
                        .tint(s.battery.percent <= 10 ? .orange : .accentColor)
                        .accessibilityLabel("鼠标剩余电量").accessibilityValue("百分之 \(s.battery.percent)")
                    Text(s.battery.statusLabel).font(.callout).foregroundStyle(.secondary)
                }
                Section("连接") {
                    LabeledContent("连接方式", value: s.connection)
                    LabeledContent("板载配置", value: "配置 \(s.profile + 1)")
                }
            } else {
                ConnectionHelp()
            }
            Section {
                Label("按你的习惯调整", systemImage: "slider.horizontal.3").font(.headline)
                Text("分别调整横向和纵向 DPI，或同步两轴。每次保存都可以恢复到修改前的设置。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct ConnectionHelp: View {
    @EnvironmentObject var model: MouseModel
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "computermouse").font(.largeTitle).foregroundStyle(.secondary)
                Text(model.busy ? "正在连接你的鼠标" : "等待你的鼠标").font(.title3.weight(.semibold))
                Text("通过 USB 直连、2.4G 接收器，或在 macOS 蓝牙设置中连接鼠标，然后移动鼠标将它唤醒。请先退出官方设置程序及网页。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("重新连接") { Task { await model.refresh() } }
                    .nativeAction(prominent: true).disabled(model.busy)
            }.padding(.vertical, 8)
        }
    }
}

struct DevicePanel: View {
    @EnvironmentObject var model: MouseModel
    @AppStorage("mouse.color") private var color = "black"
    var body: some View {
        Form {
            Section("外观") {
                Picker("鼠标配色", selection: $color) { Text("黑色").tag("black"); Text("白色").tag("white") }.pickerStyle(.segmented)
                Text("当前为手动选择，已按你的黑色鼠标设置默认外观。此选择不改变设备灯光。").font(.caption).foregroundStyle(.secondary)
            }
            Section("设备") {
                LabeledContent("型号", value: "AM Infinity .97")
                LabeledContent("连接", value: model.snapshot?.connection ?? "未连接")
                Text("同时连接时优先使用 USB，其次蓝牙，最后是 2.4G 接收器。").font(.caption).foregroundStyle(.secondary)
                if let snapshot = model.snapshot {
                    LabeledContent("板载配置", value: "配置 \(snapshot.profile + 1)")
                }
            }
            Section("本地备份") {
                Text("保存前自动备份，保存后读取确认。配置记录只保存在这台 Mac 上。")
                    .foregroundStyle(.secondary)
                Button("打开备份文件夹", systemImage: "folder") { model.showBackups() }
            }
            Section("关于 AM Native") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    Text("独立的 macOS 鼠标设置程序").font(.headline)
                }
                Text("使用 SwiftUI 与系统 HID 接口，无需安装官方程序。").foregroundStyle(.secondary)
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · 本地预览")
                LabeledContent("作者", value: "歸藏")
                LabeledContent("Twitter") {
                    Link("@op7418", destination: URL(string: "https://twitter.com/op7418")!)
                }
                DisclosureGroup("支持范围") {
                    Text("支持蓝牙、USB 直连和 2.4G 接收器。蓝牙首次连接需允许系统蓝牙权限；请先在 macOS 中完成配对。")
                    Text("支持板载按键和常用 Mac 快捷键映射。支持鼠标和接收器光效。手势、平滑滚动和固件刷写尚未加入。")
                }.foregroundStyle(.secondary)
                DisclosureGroup("图片来源") {
                    Text("外观示意来自 Angry Miao 官方设置页面，配色不代表检测结果。图片及商标归各自权利人所有，不属于本项目的 MIT 许可范围。")
                        .foregroundStyle(.secondary)
                    Link("Angry Miao", destination: URL(string: "https://ammaster.angrymiao.com/mouse")!)
                }
            }
        }.formStyle(.grouped)
    }
}
