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
    private let statusOverlay = QuotaStatusOverlayView()
    private var cancellable: AnyCancellable?
    private var countdownTimer: Timer?
    private var countdownRows: [(deadline: Date, expiredValue: String?, credit: RateLimitResetCredit?, row: MenuInfoRowView)] = []
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
            statusOverlay.frame = button.bounds
            statusOverlay.autoresizingMask = [.width, .height]
            button.addSubview(statusOverlay)
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
        let now = Date()
        let groups = store.installedProviders.map { provider in
            StatusRenderGroup(provider: provider, rows: provider == .codex
                ? QuotaStatusPresentation.codexRows(store.snapshot, at: now)
                : QuotaStatusPresentation.grokRows(store.grokSnapshot, at: now))
        }
        let toolTip = groups.map { group in
            let title = group.provider == .codex ? "Codex \(store.snapshot.menuTitle)" : store.grokSnapshot.menuTitle
            return title + (group.rows.first(where: { $0.badge == "D" }).map { " | 今日 \($0.value)" } ?? "")
        }.joined(separator: "\n")
        let renderState = StatusRenderState(groups: groups, toolTip: toolTip)
        statusItem.isVisible = !groups.isEmpty
        guard !groups.isEmpty else {
            lastRenderState = renderState
            return
        }

        guard force || renderState != lastRenderState else {
            return
        }

        let image = QuotaStatusImageRenderer.render(groups: renderState.groups)
        statusItem.button?.image = image
        statusItem.button?.toolTip = renderState.toolTip
        statusItem.button?.setAccessibilityLabel(renderState.toolTip)
        statusItem.length = image.size.width
        statusOverlay.groups = renderState.groups
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
            if let credit = entry.credit {
                entry.row.updateWarning(credit.expiresWithinThreeDays(at: now))
            }
        }
    }

    private func populateMenu(_ menu: NSMenu) {
        countdownRows.removeAll()
        menu.removeAllItems()

        if store.installedProviders.contains(.codex) {
            for row in store.snapshot.displayRows {
                if row.badge == "W", let deadline = store.snapshot.weeklyResetAt {
                    let item = NSMenuItem()
                    let view = MenuInfoRowView(label: "\(row.resetLabel)  \(row.resetValue)",
                                               value: QuotaCountdown.string(until: deadline))
                    item.view = view
                    countdownRows.append((deadline, nil, nil, view))
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
                                              value: credit.countdownValue() ?? "",
                                              isWarning: credit.expiresWithinThreeDays())
                    item.view = row
                    if let expiresAt = credit.expiresAt {
                        countdownRows.append((Date(timeIntervalSince1970: expiresAt), "已到期", credit, row))
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
        }

        if store.installedProviders.contains(.grok) {
            if !menu.items.isEmpty {
                let separator = NSMenuItem()
                separator.view = ProviderSeparatorView(frame: NSRect(x: 0, y: 0, width: 280, height: 12))
                menu.addItem(separator)
            }
            let grok = store.grokSnapshot
            if let deadline = grok.resetAt {
                let item = NSMenuItem()
                let row = MenuInfoRowView(label: "Grok \(grok.displayRow.resetLabel)  \(grok.displayRow.resetValue)",
                                          value: QuotaCountdown.string(until: deadline))
                item.view = row
                countdownRows.append((deadline, nil, nil, row))
                menu.addItem(item)
            } else {
                menu.addItem(alignedInfoItem(label: "Grok \(grok.displayRow.resetLabel)", value: "--"))
            }
            menu.addItem(alignedInfoItem(label: "Grok 上次刷新", value: grok.updatedAt.map {
                DateFormatter.quotaHour.string(from: $0)
            } ?? "--"))
            if let errorMessage = grok.errorMessage {
                let error = NSMenuItem(title: "Grok 错误 \(errorMessage)", action: nil, keyEquivalent: "")
                error.isEnabled = false
                menu.addItem(error)
            }
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
        for separator in menu.items.compactMap({ $0.view as? ProviderSeparatorView }) {
            separator.setFrameSize(NSSize(width: menuWidth, height: 12))
        }
    }

    private func alignedInfoItem(label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuInfoRowView(label: label, value: value)
        return item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class ProviderSeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 14, y: 5, width: bounds.width - 28, height: 2).fill()
    }
}

private final class MenuInfoRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init(label: String, value: String, isWarning: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

        configure(labelField, alignment: .left)
        configure(valueField, alignment: .right)

        labelField.stringValue = label
        valueField.stringValue = value
        updateWarning(isWarning)

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

    func updateWarning(_ isWarning: Bool) {
        labelField.textColor = isWarning ? .systemRed : .labelColor
        valueField.textColor = isWarning ? .systemRed : .labelColor
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
