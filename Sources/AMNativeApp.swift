import SwiftUI
import AppKit

@MainActor
final class MouseModel: ObservableObject {
    @Published var snapshot: MouseSnapshot?
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var receipt: ChangeReceipt?
    @Published var pending = false
    @Published var mapping: MappingSnapshot?
    @Published var mappingError: String?
    @Published var mappingNotice: String?
    @Published var mappingReceipt: MappingReceipt?
    @Published var mappingPending = false
    @Published var versions: [String: String] = [:]
    @Published var lighting: LightSnapshot?
    @Published var lightingReceipt: LightReceipt?
    @Published var lightingPending = false
    @Published var lightingMessage: String?
    @Published var lightingFailed = false
    private let lightingService = LightingService()
    func readLighting(_ target: LightTarget) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        lightingMessage = nil; lightingFailed = false
        lightingPending = await lightingService.hasPending()
        do { lighting = try await lightingService.read(target) }
        catch { lighting = nil; lightingMessage = error.localizedDescription; lightingFailed = true }
    }
    func saveLighting(_ state: LightState, expected: LightSnapshot) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let result = try await lightingService.apply(state,expected:expected)
            lighting = result.after; lightingReceipt = result; lightingFailed = false
            lightingMessage = "已保存，灯效完整读回一致。"
        } catch { lightingMessage = error.localizedDescription; lightingFailed = true }
        lightingPending = await lightingService.hasPending()
    }
    func undoLighting() async {
        guard !busy, let receipt = lightingReceipt else { return }; busy = true; defer { busy = false }
        do {
            lighting = try await lightingService.undo(receipt); lightingReceipt = nil; lightingFailed = false
            lightingMessage = "已恢复原灯效，完整读回一致。"
        } catch { lightingMessage = error.localizedDescription; lightingFailed = true }
        lightingPending = await lightingService.hasPending()
    }
    func recoverLighting() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            lighting = try await lightingService.recover(); lightingReceipt = nil; lightingFailed = false
            lightingMessage = "原始灯效已恢复。"
        } catch { lightingMessage = error.localizedDescription; lightingFailed = true }
        lightingPending = await lightingService.hasPending()
    }
    private var observedIdentity: UInt64?
    private let mappingService = MappingService()
    private let service = MouseService()

    func refresh() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        observedIdentity = await service.connectionIdentity()
        pending = await service.hasPending()
        lightingPending = await lightingService.hasPending()
        mappingPending = await mappingService.hasPending()
        let previousIdentity = snapshot?.deviceIdentity
        do { snapshot = try await service.read(); error = nil }
        catch { self.error = error.localizedDescription; snapshot = nil }
        if snapshot?.deviceIdentity != previousIdentity {
            receipt = nil; mappingReceipt = nil; lighting = nil; lightingReceipt = nil; notice = nil; mappingNotice = nil; versions = [:]
        }
        if snapshot != nil {
            do { mapping = try await mappingService.read(); mappingError = nil }
            catch { mapping = nil; mappingError = error.localizedDescription }
        } else { mapping = nil }
    }
    func refreshConnectionIfNeeded() async -> Bool {
        guard !busy else { return false }
        let identity = await service.connectionIdentity()
        guard identity != observedIdentity else { return false }
        await refresh()
        await readVersions()
        return true
    }
    func apply(_ stage: DPIStage, expected: MouseSnapshot) async {
        guard !busy, snapshot != nil else { return }; busy = true
        notice = nil; error = nil
        defer { busy = false }
        do {
            let result = try await service.apply(stage: stage, expected: expected)
            receipt = result; snapshot = result.after
            notice = "已保存到鼠标，并确认读回一致。"
        } catch { self.error = error.localizedDescription; snapshot = nil }
        pending = await service.hasPending()
    }
    func undo() async {
        guard !busy, let receipt else { return }; busy = true
        defer { busy = false }
        do { snapshot = try await service.undo(receipt); self.receipt = nil; error = nil; notice = "已恢复修改前的 DPI，并确认读回一致。" }
        catch { self.error = error.localizedDescription; snapshot = nil }
        pending = await service.hasPending()
    }
    func recover() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do { snapshot = try await service.recover(); receipt = nil; error = nil; notice = "已恢复原始配置。" }
        catch { self.error = error.localizedDescription }
        pending = await service.hasPending()
    }
    func applyMapping(_ changed: KeyMapping, expected: MappingSnapshot) async {
        guard !busy else { return }; busy = true; mappingNotice = nil
        defer { busy = false }
        do {
            let receipt = try await mappingService.apply(changed, expected: expected)
            mappingReceipt = receipt; mapping = receipt.after; mappingError = nil
            mappingNotice = "已保存，全部按键读回一致。"
        } catch { mappingError = error.localizedDescription; mappingNotice = error.localizedDescription }
        mappingPending = await mappingService.hasPending()
    }
    func undoMapping() async {
        guard !busy, let receipt = mappingReceipt else { return }; busy = true
        defer { busy = false }
        do { mapping = try await mappingService.undo(receipt); mappingReceipt = nil; mappingNotice = "已恢复原映射并读回确认。"; mappingError = nil }
        catch { mappingNotice = error.localizedDescription }
        mappingPending = await mappingService.hasPending()
    }
    func recoverMapping() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do { mapping = try await mappingService.recover(); mappingReceipt = nil; mappingNotice = "原始按键配置已恢复。"; mappingError = nil }
        catch { mappingNotice = error.localizedDescription }
        mappingPending = await mappingService.hasPending()
    }
    func readVersions() async {
        guard snapshot != nil else { versions = [:]; return }
        guard !busy else { return }; busy = true
        defer { busy = false }
        versions = (try? await mappingService.versions()) ?? [:]
    }
    func showBackups() {
        let url = MouseService.backupDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

enum Page: String, CaseIterable, Identifiable {
    case lighting = "光效", overview = "概览", buttons = "按键", pointer = "指针", device = "设备信息", updates = "更新"
    var id: String { rawValue }
    var icon: String {
        switch self { case .lighting: "lightbulb"; case .buttons: "cursorarrow.click.2"; case .updates: "arrow.down.circle"; case .overview: "computermouse"; case .pointer: "cursorarrow.motionlines"; case .device: "info.circle" }
    }
}

@main
struct AMNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MouseModel()
    @StateObject private var updates = UpdateModel()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("AM Native", id: "main") { RootView().environmentObject(model).environmentObject(updates) }
            .defaultSize(width: 1180, height: 820)
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .toolbar) {
                    Button("紧凑窗口") { NSApp.keyWindow?.setContentSize(NSSize(width: 760, height: 580)) }
                    Button("标准窗口") { NSApp.keyWindow?.setContentSize(NSSize(width: 1180, height: 820)) }
                    Divider()
                    Button("刷新设备") { Task { await model.refresh() } }
                        .keyboardShortcut("r").disabled(model.busy)
                }
            }
        MenuBarExtra("AM Native", systemImage: "computermouse") {
            if let snapshot = model.snapshot {
                Text("AM Infinity .97 · \(snapshot.battery.percent)%")
                Text("DPI \(snapshot.dpi.current.displayValue)")
            } else { Text("鼠标未连接") }
            if updates.newCount > 0 { Text("官方有 \(updates.newCount) 项更新") }
            Divider()
            Button("打开 AM Native") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("刷新") { Task { await model.refresh() } }.disabled(model.busy)
            Divider()
            Button("退出 AM Native") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: MouseModel
    @EnvironmentObject var updates: UpdateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Page = .buttons
    @State private var selectedControl: MouseControl = .middle
    @State private var sidebarVisible = true
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if sidebarVisible {
                    VStack(spacing: 0) {
                        if selection != .buttons {
                            HStack(spacing: 10) {
                                Image(systemName: selection.icon).foregroundStyle(.tint)
                                Text(selection.rawValue).font(.title3.weight(.semibold))
                                Spacer()
                            }.padding(22)
                        }
                        Group {
                            switch selection {
                            case .overview: OverviewPanel(editPointer: { selection = .pointer })
                            case .buttons: MappingPanel(control: selectedControl, selectControl: { selectedControl = $0 }).id(selectedControl)
                            case .pointer: PointerView()
                            case .device: DevicePanel()
                            case .lighting: LightingPanel()
                            case .updates: UpdatePanel()
                            }
                        }.scrollContentBackground(.hidden)
                    }
                    .frame(width: min(340, max(280, geometry.size.width * 0.30)))
                    .frame(maxHeight: .infinity)
                    .background(SidebarSurface.color)
                }
                VStack(spacing: 0) {
                    if model.pending || model.mappingPending || model.lightingPending {
                        HStack {
                            Label("有一笔配置修改等待恢复", systemImage: "arrow.uturn.backward.circle.fill").foregroundStyle(.orange)
                            Spacer()
                            Button(model.lightingPending ? "恢复灯效" : model.mappingPending ? "恢复按键配置" : "恢复 DPI") {
                                Task { if model.lightingPending { await model.recoverLighting() } else if model.mappingPending { await model.recoverMapping() } else { await model.recover() } }
                            }.nativeAction(prominent: true).disabled(model.busy)
                        }.padding(16)
                    }
                    DeviceCanvas(selected: $selectedControl, activePage: sidebarVisible ? selection : nil, select: { control in
                        selectedControl = control; selection = .buttons; sidebarVisible = true
                    }, editPointer: { selection = .pointer; sidebarVisible = true },
                       showBattery: { selection = .overview; sidebarVisible = true })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    DeviceStatusBar()
                }.background(Color(nsColor: .textBackgroundColor))
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    MacNavigationButton(title: "切换侧边栏", symbol: "sidebar.left", compact: true,
                                        identifier: "toggle-sidebar", tooltip: "显示或隐藏设置侧边栏", appearanceStyle: .capsule) { sidebarVisible.toggle() }
                        .frame(width: 32, height: 30)

                }
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .primaryAction) {
                        GlassPageTabs(selection: pageBinding, updateCount: updates.newCount)
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        GlassPageTabs(selection: pageBinding, updateCount: updates.newCount)
                    }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if sidebarVisible { SidebarSurface.color.frame(width: min(340, max(280, geometry.size.width * 0.30))) }
                    Color(nsColor: .textBackgroundColor)
                }.ignoresSafeArea(.container, edges: .top).allowsHitTesting(false)
            }
        }
        .background(WindowChrome())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("AM Native")
        .navigationSubtitle("AM Infinity .97")
        .frame(minWidth: 760, minHeight: 580)
        .task {
            await model.refresh()
            await model.readVersions()
            updates.setCurrent(model.versions)
            if updates.due { await updates.check(current: model.versions) }
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                ticks += 1
                if await model.refreshConnectionIfNeeded() { updates.setCurrent(model.versions) }
                else if ticks % 15 == 0 { await model.refresh() }
                if updates.due { await model.readVersions(); await updates.check(current: model.versions) }
            }
        }
    }
    private var pageBinding: Binding<Page?> {
        Binding(get: { sidebarVisible ? selection : nil }, set: { page in
            guard let page else { return }
            selection = page
            sidebarVisible = true
        })
    }

}

struct DeviceStatusBar: View {
    @EnvironmentObject var model: MouseModel
    @State private var showsError = false
    var body: some View {
        HStack(spacing: 8) {
            if model.busy {
                ProgressView().controlSize(.mini)
                Text("正在与鼠标通信…")
            } else if model.error != nil {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text("设备操作未完成")
                Button("详情") { showsError.toggle() }.buttonStyle(.link)
                    .popover(isPresented: $showsError) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("连接详情").font(.headline)
                            Text(model.error ?? "暂无错误").textSelection(.enabled)
                            Text("请退出官方设置程序与网页，唤醒鼠标后重试。").foregroundStyle(.secondary)
                        }.padding(20).frame(width: 350)
                    }
            } else {
                Label("直接连接 · 无需官方程序", systemImage: "checkmark.shield")
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 7) {
                Label(model.snapshot?.connection ?? "等待连接", systemImage: model.snapshot?.connectionSymbol ?? "antenna.radiowaves.left.and.right")
                HStack(spacing: 10) {
                    if let date = model.snapshot?.capturedAt {
                        Text("更新于 \(date.formatted(date: .omitted, time: .standard))").monospacedDigit()
                    }
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                }
            }

        }.font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 26).padding(.bottom, 14).frame(height: 64, alignment: .bottom)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Each navigation item is a real AppKit button with native press handling.
struct GlassPageTabs: View {
    @Binding var selection: Page?
    let updateCount: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach([Page.lighting, Page.device, Page.updates]) { page in
                MacNavigationButton(title: page == .updates && updateCount > 0 ? "更新 · \(updateCount)" : page.rawValue,
                                    symbol: page.icon, selected: selection == page,
                                    identifier: "page-\(page.id)", appearanceStyle: .capsule) { selection = page }
                    .frame(width: page == .device ? 104 : (updateCount > 0 ? 94 : 76), height: 30)
            }
        }.padding(5).nativeGlass(radius: 20).fixedSize()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Explicit runtime binding also handles Launch Services' cached generic icon.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
    }
}
