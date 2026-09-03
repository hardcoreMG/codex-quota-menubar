import AppKit
import Combine

@main
enum CodexQuotaBarMain {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController()
    }
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = QuotaStore()
    private let lowQuotaOverlay = LowQuotaStatusOverlayView()
    private var cancellable: AnyCancellable?
    private var lastRenderState: StatusRenderState?

    override init() {
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        if let button = statusItem.button {
            lowQuotaOverlay.frame = button.bounds
            lowQuotaOverlay.autoresizingMask = [.width, .height]
            button.addSubview(lowQuotaOverlay)
        }
        updateStatusView()

        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusView()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func updateStatusViewForEnvironmentChange() {
        updateStatusView()
    }

    private func updateStatusView(force: Bool = false) {
        let renderState = StatusRenderState(
            topValue: store.snapshot.menuFiveHourValue,
            bottomValue: store.snapshot.menuWeeklyValue,
            topIsLow: shouldHighlightLowQuota(store.snapshot.fiveHourRemainingPercent),
            bottomIsLow: shouldHighlightLowQuota(store.snapshot.weeklyRemainingPercent),
            toolTip: store.snapshot.menuTitle
        )

        guard force || renderState != lastRenderState else {
            return
        }

        let image = QuotaStatusImageRenderer.render(
            topValue: renderState.topValue,
            bottomValue: renderState.bottomValue,
            topIsLow: renderState.topIsLow,
            bottomIsLow: renderState.bottomIsLow
        )
        statusItem.button?.image = image
        statusItem.button?.toolTip = renderState.toolTip
        statusItem.length = image.size.width
        lowQuotaOverlay.topIsLow = renderState.topIsLow
        lowQuotaOverlay.bottomIsLow = renderState.bottomIsLow
        lastRenderState = renderState
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusView()

        Task {
            await store.refresh()
        }

        menu.removeAllItems()

        menu.addItem(alignedInfoItem(label: store.snapshot.fiveHourResetLabel, value: store.snapshot.fiveHourResetValue))
        menu.addItem(alignedInfoItem(label: store.snapshot.weeklyResetLabel, value: store.snapshot.weeklyResetValue))

        if let errorMessage = store.snapshot.errorMessage {
            menu.addItem(.separator())
            let error = NSMenuItem(title: "错误 \(errorMessage)", action: nil, keyEquivalent: "")
            error.isEnabled = false
            menu.addItem(error)
        }

        if store.isRefreshing {
            menu.addItem(.separator())
            let refreshing = NSMenuItem(title: "正在刷新...", action: nil, keyEquivalent: "")
            refreshing.isEnabled = false
            menu.addItem(refreshing)
        }

        menu.addItem(.separator())

        let lowQuotaAlert = NSMenuItem()
        let lowQuotaSwitch = LowQuotaSwitchView(isOn: store.lowQuotaAlertEnabled)
        lowQuotaSwitch.onToggle = { [weak self] isOn in
            self?.store.setLowQuotaAlertEnabled(isOn)
            self?.updateStatusView()
        }
        lowQuotaAlert.view = lowQuotaSwitch
        menu.addItem(lowQuotaAlert)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func alignedInfoItem(label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuInfoRowView(label: label, value: value)
        return item
    }

    private func shouldHighlightLowQuota(_ remainingPercent: Int?) -> Bool {
        guard store.lowQuotaAlertEnabled, let remainingPercent else {
            return false
        }

        return remainingPercent <= 20
    }

    @objc private func refresh() {
        Task {
            await store.refresh()
            await MainActor.run {
                self.updateStatusView(force: true)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct StatusRenderState: Equatable {
    let topValue: String
    let bottomValue: String
    let topIsLow: Bool
    let bottomIsLow: Bool
    let toolTip: String
}

private final class LowQuotaSwitchView: NSView {
    var onToggle: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "低额度提醒")
    private let toggle = PillSwitchControl()

    init(isOn: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 30))

        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .left
        label.frame = NSRect(x: 14, y: 6, width: 110, height: 18)

        toggle.isOn = isOn
        toggle.syncVisualState()
        toggle.onToggle = { [weak self] isOn in
            self?.onToggle?(isOn)
        }
        toggle.frame = NSRect(x: 170, y: 5, width: 46, height: 20)

        addSubview(label)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        toggle.toggleAnimated()
    }
}

private final class MenuInfoRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 28))

        configure(labelField, alignment: .left)
        configure(valueField, alignment: .right)

        labelField.stringValue = label
        valueField.stringValue = value

        labelField.frame = NSRect(x: 14, y: 5, width: 86, height: 18)
        valueField.frame = NSRect(x: 92, y: 5, width: 124, height: 18)

        addSubview(labelField)
        addSubview(valueField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ field: NSTextField, alignment: NSTextAlignment) {
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.alignment = alignment
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false
        field.lineBreakMode = .byClipping
    }
}

private final class PillSwitchControl: NSControl {
    var onToggle: ((Bool) -> Void)?

    var isOn = false

    private var animationProgress: CGFloat = 0
    private var animationTimer: Timer?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
        let trackColor = blendedColor(
            from: NSColor(calibratedWhite: 0.58, alpha: 1),
            to: .systemRed,
            progress: animationProgress
        )
        trackColor.setFill()
        trackPath.fill()

        let knobDiameter = trackRect.height - 4
        let offX = trackRect.minX + 2
        let onX = trackRect.maxX - knobDiameter - 2
        let knobX = offX + (onX - offX) * animationProgress
        let knobRect = NSRect(x: knobX, y: trackRect.minY + 2, width: knobDiameter, height: knobDiameter)
        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor.white.setFill()
        knobPath.fill()
        NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
        knobPath.lineWidth = 0.5
        knobPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        toggleAnimated()
    }

    func toggleAnimated() {
        setOn(!isOn, animated: true)
        onToggle?(isOn)
    }

    func syncVisualState() {
        animationTimer?.invalidate()
        animationProgress = isOn ? 1 : 0
        needsDisplay = true
    }

    private func setOn(_ newValue: Bool, animated: Bool) {
        animationTimer?.invalidate()

        guard animated else {
            isOn = newValue
            animationProgress = newValue ? 1 : 0
            needsDisplay = true
            return
        }

        let start = animationProgress
        let end: CGFloat = newValue ? 1 : 0
        isOn = newValue
        let startTime = Date()
        let duration: TimeInterval = 0.16

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(1, elapsed / duration)
            let eased = 1 - pow(1 - t, 3)
            self.animationProgress = start + (end - start) * eased
            self.needsDisplay = true

            if t >= 1 {
                timer.invalidate()
                self.animationProgress = end
                self.needsDisplay = true
            }
        }
        animationTimer = timer
        RunLoop.current.add(timer, forMode: .eventTracking)
        RunLoop.current.add(timer, forMode: .common)
    }

    private func blendedColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        let fromRGB = from.usingColorSpace(.deviceRGB) ?? from
        let toRGB = to.usingColorSpace(.deviceRGB) ?? to
        let p = max(0, min(1, progress))

        return NSColor(
            calibratedRed: fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * p,
            green: fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * p,
            blue: fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * p,
            alpha: fromRGB.alphaComponent + (toRGB.alphaComponent - fromRGB.alphaComponent) * p
        )
    }
}

private enum QuotaStatusImageRenderer {
    private static let horizontalPadding: CGFloat = 5
    private static let badgeWidth: CGFloat = 17
    private static let badgeHeight: CGFloat = 8
    private static let badgeGap: CGFloat = 4
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private static let badgeFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    static func render(topValue: String, bottomValue: String, topIsLow: Bool, bottomIsLow: Bool) -> NSImage {
        let valueWidth = max(measuredWidth(topValue), measuredWidth(bottomValue))
        let width = ceil(horizontalPadding + badgeWidth + badgeGap + valueWidth + horizontalPadding)
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: width, height: height))
        // A template image lets macOS apply exactly the same foreground color as
        // the other menu bar items, including wallpaper-driven light/dark changes.
        image.isTemplate = true

        image.lockFocusFlipped(true)
        defer {
            image.unlockFocus()
        }

        drawRow(badge: "5H", value: topValue, y: 0, width: width, drawBadge: !topIsLow)
        drawRow(badge: "W", value: bottomValue, y: 10, width: width, drawBadge: !bottomIsLow)

        return image
    }

    private static func drawRow(badge: String, value: String, y: CGFloat, width: CGFloat, drawBadge shouldDrawBadge: Bool) {
        if shouldDrawBadge {
            let badgeRect = NSRect(x: horizontalPadding, y: y + 2, width: badgeWidth, height: badgeHeight)
            let path = NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2)
            NSColor.black.setFill()
            path.fill()

            // Clear the lettering out of the mask. The resulting template becomes
            // a filled system-colored pill with transparent lettering.
            NSGraphicsContext.current?.compositingOperation = .clear
            drawBadge(text: badge, in: NSRect(x: badgeRect.minX, y: y + 1.15, width: badgeRect.width, height: 9.5), color: .black)
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        let valueX = horizontalPadding + badgeWidth + badgeGap
        drawValue(
            text: value,
            in: NSRect(x: valueX, y: y, width: width - valueX, height: 9.5),
            color: .black
        )
    }

    private static func drawBadge(text: String, in rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private static func drawValue(text: String, in rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private static func measuredWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: valueFont
        ]
        return NSString(string: text).size(withAttributes: attributes).width
    }

}

private final class LowQuotaStatusOverlayView: NSView {
    var topIsLow = false { didSet { needsDisplay = true } }
    var bottomIsLow = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if topIsLow { drawBadge("5H", y: 2) }
        if bottomIsLow { drawBadge("W", y: 12) }
    }

    private func drawBadge(_ text: String, y: CGFloat) {
        let rect = NSRect(x: 5, y: y, width: 17, height: 8)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSString(string: text).draw(
            in: NSRect(x: rect.minX, y: y - 0.85, width: rect.width, height: 9.5),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
    }
}
