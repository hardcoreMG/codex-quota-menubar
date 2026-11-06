import AppKit

struct StatusRenderState: Equatable {
    let groups: [StatusRenderGroup]
    let toolTip: String
}

struct StatusRenderGroup: Equatable {
    let provider: QuotaProvider
    let rows: [StatusRenderRow]
}

enum QuotaProvider {
    case codex, grok

    var icon: NSImage { self == .codex ? Self.codexIcon : Self.grokIcon }

    private static let codexIcon = loadIcon("CodexProvider", extension: "png")
    private static let grokIcon = loadIcon("GrokProvider", extension: "icns")

    private static func loadIcon(_ name: String, extension ext: String) -> NSImage {
        NSImage(contentsOf: Bundle.module.url(forResource: name, withExtension: ext)!)!
    }
}

struct StatusRenderRow: Equatable {
    let badge: String
    let value: String
    let tint: StatusRowTint
    var colorsValue = false
}

enum StatusRowTint {
    case normal, red, green

    static func daily(_ remainingPercent: Int?) -> StatusRowTint {
        guard let remainingPercent else { return .normal }
        if remainingPercent > 50 { return .green }
        if remainingPercent < 20 { return .red }
        return .normal
    }

    var color: NSColor {
        switch self {
        case .normal: return .labelColor
        case .red: return .systemRed
        case .green: return .systemGreen
        }
    }
}

enum QuotaStatusLayout {
    static let horizontalPadding: CGFloat = 2
    static let badgeGap: CGFloat = 4
    static let inlineBadgeSize = NSSize(width: 17, height: 8)
    static let stackedBadgeSize = NSSize(width: 17, height: 8)
    static let inlineValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    static let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let inlineBadgeFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    static let stackedBadgeFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    static let providerIconSize: CGFloat = 16
    static let providerGap: CGFloat = 4
    static let groupGap: CGFloat = 12

    struct GroupLayout {
        let iconRect: NSRect
        let quotaRect: NSRect
    }

    static func groups(_ groups: [StatusRenderGroup]) -> [GroupLayout] {
        var x: CGFloat = horizontalPadding
        return groups.map { group in
            let height = NSStatusBar.system.thickness
            let iconRect = NSRect(x: x, y: (height - providerIconSize) / 2,
                                  width: providerIconSize, height: providerIconSize)
            let quotaRect = NSRect(x: iconRect.maxX + providerGap, y: 0,
                                   width: quotaWidth(rows: group.rows), height: height)
            x = quotaRect.maxX + groupGap
            return GroupLayout(iconRect: iconRect, quotaRect: quotaRect)
        }
    }

    static func quotaWidth(rows: [StatusRenderRow]) -> CGFloat {
        if let row = rows.first, rows.count == 1 {
            return ceil(max(stackedBadgeSize.width,
                            QuotaStatusDrawing.measuredWidth(row.value, font: stackedValueFont)) + horizontalPadding * 2)
        }
        let valueWidth = rows.map { QuotaStatusDrawing.measuredWidth($0.value, font: inlineValueFont) }.max() ?? 0
        return ceil(horizontalPadding * 2 + inlineBadgeSize.width + badgeGap + valueWidth)
    }

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

    static func inlineValueBounds(rowY: CGFloat, width: CGFloat) -> NSRect {
        let valueX = inlineBadgeRect(rowY: rowY).maxX + badgeGap
        return NSRect(x: valueX, y: rowY, width: width - valueX, height: 10)
    }

    static func stackedValueBounds(in bounds: NSRect) -> NSRect {
        let badge = stackedBadgeRect(in: bounds)
        return NSRect(x: horizontalPadding, y: badge.maxY,
                      width: bounds.width - horizontalPadding * 2, height: bounds.height - badge.maxY)
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

enum QuotaStatusImageRenderer {
    static func render(groups: [StatusRenderGroup]) -> NSImage {
        let layouts = QuotaStatusLayout.groups(groups)
        let images = groups.map { render(rows: $0.rows) }
        let size = NSSize(width: (layouts.last?.quotaRect.maxX ?? 0) + QuotaStatusLayout.horizontalPadding,
                          height: NSStatusBar.system.thickness)
        let image = NSImage(size: size)
        image.isTemplate = true
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }
        for (index, layout) in layouts.enumerated() {
            images[index].draw(in: layout.quotaRect, from: .zero, operation: .sourceOver,
                               fraction: 1, respectFlipped: true, hints: nil)
            if index > 0 {
                NSColor.black.withAlphaComponent(0.3).setFill()
                NSRect(x: layout.iconRect.minX - QuotaStatusLayout.groupGap / 2,
                       y: 4, width: 0.5, height: size.height - 8).fill()
            }
        }
        return image
    }

    static func render(rows: [StatusRenderRow]) -> NSImage {
        if let row = rows.first, rows.count == 1 {
            return renderStacked(row: row)
        }

        let width = QuotaStatusLayout.quotaWidth(rows: rows)
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
        let width = QuotaStatusLayout.quotaWidth(rows: [row])
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = true

        image.lockFocusFlipped(true)
        defer {
            image.unlockFocus()
        }

        let bounds = NSRect(origin: .zero, size: image.size)
        let badgeRect = QuotaStatusLayout.stackedBadgeRect(in: bounds)

        if row.tint == .normal {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: badgeRect,
                font: QuotaStatusLayout.stackedBadgeFont,
                fillColor: .black,
                textColor: .black,
                clearsText: true
            )
        }

        if !row.colorsValue || row.tint == .normal {
            QuotaStatusDrawing.drawText(
                row.value,
                in: QuotaStatusLayout.stackedValueBounds(in: bounds),
                font: QuotaStatusLayout.stackedValueFont,
                color: .black,
                alignment: .center,
                verticallyCentered: true
            )
        }

        return image
    }

    private static func drawInlineRow(_ row: StatusRenderRow, y: CGFloat, width: CGFloat) {
        let badgeRect = QuotaStatusLayout.inlineBadgeRect(rowY: y)

        if row.tint == .normal {
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

        if !row.colorsValue || row.tint == .normal {
            QuotaStatusDrawing.drawText(
                row.value,
                in: QuotaStatusLayout.inlineValueBounds(rowY: y, width: width),
                font: QuotaStatusLayout.inlineValueFont,
                color: .black,
                alignment: .left,
                verticallyCentered: true
            )
        }
    }
}

final class QuotaStatusOverlayView: NSView {
    var groups: [StatusRenderGroup] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (group, layout) in zip(groups, QuotaStatusLayout.groups(groups)) {
            group.provider.icon.draw(in: layout.iconRect, from: .zero, operation: .sourceOver,
                                     fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: layout.quotaRect.minX, yBy: 0)
            transform.concat()
            drawTints(rows: group.rows, bounds: NSRect(origin: .zero, size: layout.quotaRect.size))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawTints(rows: [StatusRenderRow], bounds: NSRect) {

        if let row = rows.first, rows.count == 1, row.tint != .normal {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: QuotaStatusLayout.stackedBadgeRect(in: bounds),
                font: QuotaStatusLayout.stackedBadgeFont,
                fillColor: row.tint.color,
                textColor: .white,
                clearsText: false
            )
            if row.colorsValue {
                QuotaStatusDrawing.drawText(row.value, in: QuotaStatusLayout.stackedValueBounds(in: bounds),
                                             font: QuotaStatusLayout.stackedValueFont, color: row.tint.color,
                                             alignment: .center, verticallyCentered: true)
            }
            return
        }

        for (row, y) in zip(rows, QuotaStatusLayout.rowYOffsets(count: rows.count)) where row.tint != .normal {
            QuotaStatusDrawing.drawBadge(
                text: row.badge,
                in: QuotaStatusLayout.inlineBadgeRect(rowY: y),
                font: QuotaStatusLayout.inlineBadgeFont,
                fillColor: row.tint.color,
                textColor: .white,
                clearsText: false
            )
            if row.colorsValue {
                QuotaStatusDrawing.drawText(row.value,
                                             in: QuotaStatusLayout.inlineValueBounds(rowY: y, width: bounds.width),
                                             font: QuotaStatusLayout.inlineValueFont, color: row.tint.color,
                                             alignment: .left, verticallyCentered: true)
            }
        }
    }
}
