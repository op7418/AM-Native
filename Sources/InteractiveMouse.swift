import SwiftUI
import AppKit

struct InteractiveMouse: View {
    let selected: MouseControl?
    let select: (MouseControl) -> Void
    @AppStorage("mouse.color") private var color = "black"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: MouseControl?
    private let controls: [MouseControl] = [.left, .right, .middle, .forward, .back]
    private var highlighted: MouseControl? { selected == .scrollUp || selected == .scrollDown ? .middle : selected }
    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for color in ["black", "white"] {
            let name = color == "black" ? "am-infinity-black" : "am-infinity"
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) { result[color] = image }
        }
        return result
    }()
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cardWidth = min(120.0, max(92.0, size.width * 0.23))
            let height = max(100, min(size.height - 12, 370, (size.width - cardWidth * 2 - 32) * 1305 / 713))
            let width = height * 713 / 1305
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            ZStack {
                if let image = Self.images[color] {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: width, height: height)
                        .id(color).transition(.opacity)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                        .accessibilityLabel("AM Infinity .97，\(color == "black" ? "黑色" : "白色")")
                }
                ForEach(controls) { control in
                    let point = anchor(control, in: rect)
                    let label = labelPosition(control, size: size, cardWidth: cardWidth)
                    let active = highlighted == control || hovered == control
                    let path = leader(from: point, to: label, left: label.x < size.width / 2, cardWidth: cardWidth)
                    path.stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                    path.trim(from: 0, to: active ? 1 : 0).stroke(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                    MacNavigationButton(title: "设置\(control.title)", symbol: "circle.fill",
                                        selected: highlighted == control, compact: true,
                                        identifier: "anchor-\(control.rawValue)", radius: 16, appearanceStyle: .circle,
                                        hoverChanged: { updateHover(control, inside: $0) }) { activate(control) }
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle()).position(point)
                    MacNavigationButton(title: control == .middle ? "滚轮" : control.title,
                                        symbol: control.symbol, selected: highlighted == control,
                                        identifier: "hotspot-\(control.rawValue)",
                                        hoverChanged: { updateHover(control, inside: $0) }) { activate(control) }
                        .frame(width: cardWidth, height: 38).nativeGlass(radius: 14).position(label)

                }
            }.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: color)
        }
    }
    private func activate(_ control: MouseControl) { select(control) }
    private func updateHover(_ control: MouseControl, inside: Bool) {
        if inside { hovered = control } else if hovered == control { hovered = nil }
    }
    private func anchor(_ control: MouseControl, in rect: CGRect) -> CGPoint {
        let point: CGPoint
        switch control {
        case .left: point = CGPoint(x: 0.27, y: 0.14)
        case .right: point = CGPoint(x: 0.73, y: 0.14)
        case .middle,.scrollUp,.scrollDown: point = CGPoint(x: 0.5, y: 0.23)
        case .forward: point = CGPoint(x: 0.035, y: 0.43)
        case .back: point = CGPoint(x: 0.035, y: 0.59)
        }
        return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
    private func labelPosition(_ control: MouseControl, size: CGSize, cardWidth: CGFloat) -> CGPoint {
        switch control {
        case .left: CGPoint(x: cardWidth / 2 + 6, y: size.height * 0.13)
        case .right: CGPoint(x: size.width - cardWidth / 2 - 6, y: size.height * 0.13)
        case .middle,.scrollUp,.scrollDown: CGPoint(x: size.width - cardWidth / 2 - 6, y: size.height * 0.39)
        case .forward: CGPoint(x: cardWidth / 2 + 6, y: size.height * 0.43)
        case .back: CGPoint(x: cardWidth / 2 + 6, y: size.height * 0.68)
        }
    }
    private func leader(from point: CGPoint, to label: CGPoint, left: Bool, cardWidth: CGFloat) -> Path {
        Path { p in
            let endpoint = CGPoint(x: label.x + (left ? cardWidth / 2 : -cardWidth / 2), y: label.y)
            p.move(to: point)
            p.addLine(to: CGPoint(x: endpoint.x + (left ? 24 : -24), y: point.y))
            p.addLine(to: endpoint)
        }
    }
}
