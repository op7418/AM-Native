import AppKit

@main struct NavigationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let button = NavigationNSButton(frame: NSRect(x: 0, y: 0, width: 120, height: 38))
        precondition(button.isBordered && !button.showsBorderOnlyWhileMouseInside)
        precondition(button.acceptsFirstMouse(for: nil), "navigation must handle the activation click")
        button.updateTrackingAreas()
        precondition(button.trackingAreas.contains { $0.options.contains([.activeAlways, .inVisibleRect, .mouseEnteredAndExited]) })
        var hover: [Bool] = []
        button.hoverChanged = { hover.append($0) }
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        button.mouseEntered(with: event)
        precondition(button.hovered && button.layer!.borderWidth > 0)
        precondition(button.contentTintColor == .controlAccentColor)
        button.mouseExited(with: event)
        precondition(!button.hovered && button.layer!.borderWidth == 0 && hover == [true, false])
        button.selected = true
        button.mouseEntered(with: event)
        button.mouseExited(with: event)
        precondition(button.layer!.borderWidth > 0, "selection survives pointer exit")
        let toolbar = NavigationNSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        toolbar.appearanceStyle = .capsule
        toolbar.mouseEntered(with: event)
        precondition(toolbar.layer!.borderWidth == 0 && toolbar.contentTintColor == .labelColor)
        precondition(toolbar.layer!.backgroundColor == NSColor.labelColor.withAlphaComponent(0.07).cgColor)
        toolbar.selected = true
        toolbar.mouseExited(with: event)
        precondition(toolbar.layer!.borderWidth == 0 && toolbar.contentTintColor == .labelColor)
        precondition(toolbar.layer!.backgroundColor == NSColor.labelColor.withAlphaComponent(0.10).cgColor)
        var target = ""
        button.invoke = { target = "front" }
        button.performClick(nil)
        precondition(target == "front")
        button.invoke = { target = "back" }
        button.performClick(nil)
        precondition(target == "back", "reused native control must invoke its current action")
        target = ""
        button.isEnabled = false
        button.performClick(nil)
        precondition(target.isEmpty)
        print("PASS: navigation first-click, native tracking bounds, hover enter/exit, selected outline, action routing and disabled control")
    }
}
