import SwiftUI
import AppKit

/// System glass for floating controls; opaque fallback honors accessibility.
struct NativeGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 20
    var interactive = false
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.separator, lineWidth: 0.5))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.separator, lineWidth: 0.5))
        }
    }
}

struct NativeAction: ViewModifier {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

struct GlassCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16, content: content)
        } else { content() }
    }
}

extension View {
    func nativeGlass(radius: CGFloat = 20, interactive: Bool = false) -> some View { modifier(NativeGlass(radius: radius, interactive: interactive)) }
    func nativeAction(prominent: Bool = false) -> some View { modifier(NativeAction(prominent: prominent)) }
}

extension DPIStage {
    var displayValue: String { x == y ? "\(x)" : "\(x) × \(y)" }
}

extension BatteryState {
    var statusLabel: String {
        switch charging {
        case true?: "正在充电"
        case false?: "电池供电"
        case nil: "充电状态未知"
        }
    }
    var symbol: String {
        if charging == true { return "battery.100percent.bolt" }
        switch percent {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...60: return "battery.50percent"
        case 61...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct ConnectionBadge: View {
    @EnvironmentObject var model: MouseModel
    var body: some View {
        Label(model.snapshot == nil ? "未连接" : "已连接",
              systemImage: model.snapshot == nil ? "circle.dashed" : "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(model.snapshot == nil ? Color.secondary : Color.green)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .nativeGlass(radius: 30)
            .accessibilityLabel(model.snapshot == nil ? "鼠标未连接" : "鼠标已连接")
    }
}

/// Keeps choices in the owning window's view hierarchy, never in an NSMenu window.
struct InlineChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var expanded = false
    @FocusState private var hasFocus: Bool
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedTitle: String { options.first { $0.value == selection }?.title ?? "—" }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options, id: \.value) { option in
                        Button {
                            selection = option.value
                            expanded = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selection == option.value ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection == option.value ? Color.accentColor : Color.secondary)
                                Text(option.title).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 8).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == option.value ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityValue(selection == option.value ? "已选择" : "未选择")
                    }
                }.padding(.vertical, 4)
            }.frame(height: min(CGFloat(options.count) * 36 + 8, 220))
        } label: {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    Text(selectedTitle).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(title + "，" + selectedTitle)
                .accessibilityValue(expanded ? "已展开" : "已收起")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
        .focusable().focusEffectDisabled().focused($hasFocus)
        .onChange(of: expanded) { hasFocus = expanded }
        .onExitCommand { expanded = false }
        .onChange(of: selection) { expanded = false }
        .onChange(of: activeState) { if activeState == .inactive { expanded = false } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in expanded = false }
    }
}

/// One opaque surface avoids material flashes while switching sidebar content.
enum SidebarSurface { static let color = Color(nsColor: .windowBackgroundColor) }

struct WindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.insert(.fullSizeContentView)
            window?.titlebarAppearsTransparent = true
            window?.backgroundColor = .textBackgroundColor
            window?.titlebarSeparatorStyle = .none
        }
    }
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
