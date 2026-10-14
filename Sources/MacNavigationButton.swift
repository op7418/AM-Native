import AppKit
import SwiftUI

/// Navigation only: first-click activation must never be applied to device writes.
enum NavigationAppearance { case outlined, capsule, circle }

final class NavigationNSButton: NSButton {
    var appearanceStyle: NavigationAppearance = .outlined { didSet {
        isBordered = appearanceStyle == .outlined
        updateAppearance()
    } }
    var invoke: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var selected = false { didSet { updateAppearance() } }
    var radius: CGFloat = 12 { didSet { updateAppearance() } }
    private(set) var hovered = false
    private var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.momentaryPushIn)
        isBordered = true
        showsBorderOnlyWhileMouseInside = false
        target = self
        action = #selector(activate)
        wantsLayer = true
        focusRingType = .default
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 13, weight: .medium)
        if #available(macOS 26, *) { bezelStyle = .glass }
        else { bezelStyle = .rounded }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    // NSButton bezel alignment insets otherwise enlarge the native view beyond
    // the SwiftUI frame, causing a circular background and oval outline.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override func layout() {
        super.layout()
        updateAppearance()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func activate() { if isEnabled { invoke?() } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
    }
    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        updateAppearance()
        hoverChanged?(value)
    }
    func updateAppearance() {
        contentTintColor = appearanceStyle == .capsule ? .labelColor : (selected || hovered ? .controlAccentColor : .labelColor)
        bezelColor = appearanceStyle == .capsule ? nil : (selected ? .controlAccentColor.withAlphaComponent(0.16) : hovered ? .controlAccentColor.withAlphaComponent(0.08) : nil)
        layer?.cornerRadius = appearanceStyle == .outlined ? min(radius, bounds.height / 2) : min(bounds.width, bounds.height) / 2
        layer?.cornerCurve = .circular
        layer?.borderWidth = appearanceStyle == .capsule ? 0 : (selected || hovered ? 1.5 : 0)
        if appearanceStyle == .capsule {
            layer?.backgroundColor = selected ? NSColor.labelColor.withAlphaComponent(hovered ? 0.14 : 0.10).cgColor : hovered ? NSColor.labelColor.withAlphaComponent(0.07).cgColor : NSColor.clear.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(selected ? 0.65 : 0.32).cgColor
        setAccessibilityValue(selected ? "已选择" : "未选择")
        needsDisplay = true
    }
}

struct MacNavigationButton: NSViewRepresentable {
    var title: String
    var symbol: String
    var selected = false
    var compact = false
    var identifier = ""
    var tooltip: String? = nil
    var radius: CGFloat = 12
    var appearanceStyle: NavigationAppearance = .outlined
    var hoverChanged: ((Bool) -> Void)? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> NavigationNSButton { NavigationNSButton(frame: .zero) }
    func updateNSView(_ button: NavigationNSButton, context: Context) {
        button.title = compact ? "" : title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        button.imagePosition = compact ? .imageOnly : .imageLeading
        button.toolTip = tooltip ?? title
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.isEnabled = isEnabled
        button.appearanceStyle = appearanceStyle
        button.selected = selected
        button.radius = radius
        button.invoke = action
        button.hoverChanged = hoverChanged
        button.updateAppearance()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NavigationNSButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: proposal.height ?? 32)
    }
}
