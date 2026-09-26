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
    private var countdownTimer: Timer?
    private var countdownRows: [(deadline: Date, expiredValue: String?, row: MenuInfoRowView)] = []
    private var isMenuOpen = false
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
                if let self, self.isMenuOpen, let menu = self.statusItem.menu {
                    self.populateMenu(menu)
                }
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
        countdownTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func updateStatusViewForEnvironmentChange() {
        updateStatusView()
    }

    private func updateStatusView(force: Bool = false) {
        let rows = store.snapshot.displayRows.map { row in
            StatusRenderRow(
                badge: row.badge,
                value: row.value,
                isLow: shouldHighlightLowQuota(row.remainingPercent)
            )
        }
        let renderState = StatusRenderState(
            rows: rows,
            toolTip: store.snapshot.menuTitle
        )

        guard force || renderState != lastRenderState else {
            return
        }

        let image = QuotaStatusImageRenderer.render(rows: renderState.rows)
        statusItem.button?.image = image
        statusItem.button?.toolTip = renderState.toolTip
        statusItem.length = image.size.width
        lowQuotaOverlay.rows = renderState.rows
        lastRenderState = renderState
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusView()

        Task {
            await store.refresh()
        }

        populateMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateCountdowns()
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            // This timer is registered only on the main run loop.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateCountdowns()
                Task { await self.store.refresh() }
            }
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdowns() {
        let now = Date()
        for entry in countdownRows {
            let value = entry.deadline <= now ? entry.expiredValue : nil
            entry.row.updateValue(value ?? QuotaCountdown.string(until: entry.deadline, at: now))
        }
    }

    private func populateMenu(_ menu: NSMenu) {
        countdownRows.removeAll()
        menu.removeAllItems()

        for row in store.snapshot.displayRows {
            if row.badge == "W", let deadline = store.snapshot.weeklyResetAt {
                let item = NSMenuItem()
                let view = MenuInfoRowView(label: "\(row.resetLabel)  \(row.resetValue)",
                                           value: QuotaCountdown.string(until: deadline))
                item.view = view
                countdownRows.append((deadline, nil, view))
                menu.addItem(item)
            } else {
                menu.addItem(alignedInfoItem(label: row.resetLabel, value: row.resetValue))
            }
        }

        menu.addItem(.separator())
        if let resets = store.snapshot.bankResets {
            menu.addItem(alignedInfoItem(label: "重置卡", value: "\(resets.availableCount) 次可用"))
            menu.addItem(.separator())
            let credits = resets.availableCredits()
            for credit in credits {
                let item = NSMenuItem()
                let row = MenuInfoRowView(label: credit.expirationValue,
                                          value: credit.countdownValue() ?? "")
                item.view = row
                if let expiresAt = credit.expiresAt {
                    countdownRows.append((Date(timeIntervalSince1970: expiresAt), "已到期", row))
                }
                item.toolTip = credit.title
                menu.addItem(item)
            }
            if resets.availableCount > credits.count {
                menu.addItem(alignedInfoItem(label: "到期明细", value: "另 \(resets.availableCount - credits.count) 次未提供"))
            } else if resets.availableCount == 0 {
                menu.addItem(alignedInfoItem(label: "", value: "暂无可用 重置卡"))
            }
        } else {
            menu.addItem(alignedInfoItem(label: "重置卡", value: "暂未获取"))
        }

        if let errorMessage = store.snapshot.errorMessage {
            menu.addItem(.separator())
            let error = NSMenuItem(title: "错误 \(errorMessage)", action: nil, keyEquivalent: "")
            error.isEnabled = false
            menu.addItem(error)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        let infoRows = menu.items.compactMap { $0.view as? MenuInfoRowView }
        let labelWidth = infoRows.map(\.measuredLabelWidth).max() ?? 0
        let valueWidth = infoRows.map(\.measuredValueWidth).max() ?? 0
        let menuWidth = max(280, labelWidth + valueWidth + 28 + 24)
        for row in infoRows {
            row.applyLayout(width: menuWidth, labelWidth: labelWidth)
        }
    }

    private func alignedInfoItem(label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuInfoRowView(label: label, value: value)
        return item
    }

    private func shouldHighlightLowQuota(_ remainingPercent: Int?) -> Bool {
        guard let remainingPercent else {
            return false
        }

        return remainingPercent <= 20
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct StatusRenderState: Equatable {
    let rows: [StatusRenderRow]
    let toolTip: String
}

private struct StatusRenderRow: Equatable {
    let badge: String
    let value: String
    let isLow: Bool
}

private final class MenuInfoRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

        configure(labelField, alignment: .left)
        configure(valueField, alignment: .right)

        labelField.stringValue = label
        valueField.stringValue = value

        applyLayout(width: 280, labelWidth: measuredLabelWidth)

        addSubview(labelField)
        addSubview(valueField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var measuredLabelWidth: CGFloat { measuredWidth(labelField) }
    var measuredValueWidth: CGFloat { measuredWidth(valueField) }

    private func measuredWidth(_ field: NSTextField) -> CGFloat {
        ceil(NSString(string: field.stringValue).size(withAttributes: [.font: field.font!]).width) + 4
    }

    func applyLayout(width: CGFloat, labelWidth: CGFloat) {
        setFrameSize(NSSize(width: width, height: 28))
        labelField.frame = NSRect(x: 14, y: 5, width: labelWidth, height: 18)
        let valueX = 14 + labelWidth + 24
        valueField.frame = NSRect(x: valueX, y: 5, width: max(0, width - valueX - 14), height: 18)
    }

    func updateValue(_ value: String) {
        valueField.stringValue = value
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

private enum QuotaStatusLayout {
    static let horizontalPadding: CGFloat = 2
    static let badgeGap: CGFloat = 4
    static let inlineBadgeSize = NSSize(width: 17, height: 8)
    static let stackedBadgeSize = NSSize(width: 17, height: 8)
    static let inlineValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    static let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let inlineBadgeFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    static let stackedBadgeFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)

    static func stackedBadgeRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: pixelAligned((bounds.width - stackedBadgeSize.width) / 2),
            y: 0.5,
            width: stackedBadgeSize.width,
            height: stackedBadgeSize.height
        )
    }

    static func inlineBadgeRect(rowY: CGFloat) -> NSRect {
        NSRect(
            x: horizontalPadding,
            y: rowY + 2,
            width: inlineBadgeSize.width,
            height: inlineBadgeSize.height
        )
    }

    static func rowYOffsets(count: Int) -> [CGFloat] {
        count == 1 ? [5] : Array(0..<count).map { CGFloat($0 * 10) }
    }

    private static func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

private enum QuotaStatusDrawing {
    static func drawBadge(
        text: String,
        in rect: NSRect,
        font: NSFont,
        fillColor: NSColor,
        textColor: NSColor,
        clearsText: Bool
    ) {
        fillColor.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        ).fill()

        if clearsText {
            NSGraphicsContext.current?.compositingOperation = .clear
        }

        drawText(text, in: rect, font: font, color: textColor, alignment: .center, verticallyCentered: true)

        if clearsText {
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
    }

    static func drawText(
        _ text: String,
        in bounds: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        verticallyCentered: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        var drawingRect = bounds

        if verticallyCentered {
            let textHeight = NSString(string: text).size(withAttributes: attributes).height
            drawingRect.origin.y = bounds.midY - textHeight / 2
            drawingRect.size.height = textHeight
        }

        NSString(string: text).draw(in: drawingRect, withAttributes: attributes)
    }

    static func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        NSString(string: text).size(withAttributes: [.font: font]).width
    }
}

private enum QuotaStatusImageRenderer {
    static func render(rows: [StatusRenderRow]) -> NSImage {
        if let row = rows.first, rows.count == 1 {
            return renderStacked(row: row)
        }

        let valueWidth = rows.map {
            QuotaStatusDrawing.measuredWidth($0.value, font: QuotaStatusLayout.inlineValueFont)
        }.max() ?? 0
        let width = ceil(
            QuotaStatusLayout.horizontalPadding
                + QuotaStatusLayout.inlineBadgeSize.width
                + QuotaStatusLayout.badgeGap
                + valueWidth
                + QuotaStatusLayout.horizontalPadding
        )
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: width, height: height))
        // A template image lets macOS apply exactly the same foreground color as
        // the other menu bar items, including wallpaper-driven light/dark changes.
        image.isTemplate = true

        image.lockFocusFlipped(true)
        defer {
            image.unlockFocus()
        }

        for (row, y) in zip(rows, QuotaStatusLayout.rowYOffsets(count: rows.count)) {
            drawInlineRow(row, y: y, width: width)
        }

        return image
    }

    private static func renderStacked(row: StatusRenderRow) -> NSImage {
        let valueWidth = QuotaStatusDrawing.measuredWidth(
            row.value,
            font: QuotaStatusLayout.stackedValueFont
        )
        let width = ceil(
            max(QuotaStatusLayout.stackedBadgeSize.width, valueWidth)
                + QuotaStatusLayout.horizontalPadding * 2
        )
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = true

        image.lockFocusFlipped(true)
        defer {
            image.unlockFocus()
        }

        let bounds = NSRect(origin: .zero, size: image.size)
        let badgeRect = QuotaStatusLayout.stackedBadgeRect(in: bounds)

        if !row.isLow {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: badgeRect,
                font: QuotaStatusLayout.stackedBadgeFont,
                fillColor: .black,
                textColor: .black,
                clearsText: true
            )
        }

        let valueBounds = NSRect(
            x: QuotaStatusLayout.horizontalPadding,
            y: badgeRect.maxY,
            width: width - QuotaStatusLayout.horizontalPadding * 2,
            height: height - badgeRect.maxY
        )
        QuotaStatusDrawing.drawText(
            row.value,
            in: valueBounds,
            font: QuotaStatusLayout.stackedValueFont,
            color: .black,
            alignment: .center,
            verticallyCentered: true
        )

        return image
    }

    private static func drawInlineRow(_ row: StatusRenderRow, y: CGFloat, width: CGFloat) {
        let badgeRect = QuotaStatusLayout.inlineBadgeRect(rowY: y)

        if !row.isLow {
            // Clear the lettering out of the mask. The resulting template becomes
            // a filled system-colored pill with transparent lettering.
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: badgeRect,
                font: QuotaStatusLayout.inlineBadgeFont,
                fillColor: .black,
                textColor: .black,
                clearsText: true
            )
        }

        let valueX = badgeRect.maxX + QuotaStatusLayout.badgeGap
        QuotaStatusDrawing.drawText(
            row.value,
            in: NSRect(x: valueX, y: y, width: width - valueX, height: 10),
            font: QuotaStatusLayout.inlineValueFont,
            color: .black,
            alignment: .left,
            verticallyCentered: true
        )
    }
}

private final class LowQuotaStatusOverlayView: NSView {
    var rows: [StatusRenderRow] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let row = rows.first, rows.count == 1, row.isLow {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: QuotaStatusLayout.stackedBadgeRect(in: bounds),
                font: QuotaStatusLayout.stackedBadgeFont,
                fillColor: .systemRed,
                textColor: .white,
                clearsText: false
            )
            return
        }

        for (row, y) in zip(rows, QuotaStatusLayout.rowYOffsets(count: rows.count)) where row.isLow {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: QuotaStatusLayout.inlineBadgeRect(rowY: y),
                font: QuotaStatusLayout.inlineBadgeFont,
                fillColor: .systemRed,
                textColor: .white,
                clearsText: false
            )
        }
    }
}
