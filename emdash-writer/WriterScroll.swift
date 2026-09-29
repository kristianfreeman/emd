import AppKit
import SwiftUI

/// The column's measure, and the scroll view that holds it with the properties gutter.
struct WritingMeasure {
    var origin: CGFloat
    var width: CGFloat
    var right: CGFloat { origin + width }

    init(columnWidth: CGFloat) {
        width = min(680, max(240, columnWidth - 72))
        origin = max(36, (columnWidth - width) / 2)
    }
}

final class WriterScroll: NSScrollView {
    let gutter = PassThroughBox()
    private var placing = false
    private var shown = GutterCopy.empty
    /// Measured once per change of copy. Scrolling moves nothing inside the gutter.
    private var measuredHeight: CGFloat?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installGutter()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installGutter()
    }

    override func tile() {
        super.tile()
        followViewport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        followViewport()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        followViewport()
    }

    private func followViewport() {
        (documentView as? ColumnView)?.noteViewportChanged()
        placeGutter()
    }

    func show(_ copy: GutterCopy) {
        guard shown != copy else { return }
        shown = copy
        measuredHeight = nil
        gutter.host.rootView = PropertiesText(copy: copy)
        gutter.host.invalidateIntrinsicContentSize()
        placeGutter()
    }

    func placeGutter() {
        guard !placing, bounds.width > 80, bounds.height > 80 else { return }
        placing = true
        defer { placing = false }
        let width: CGFloat = 200
        let frame = pinned(width: width, height: gutterHeight(width))
        gutter.isHidden = coversText(frame)
        guard !gutter.isHidden else { return }
        gutter.frame = frame
    }

    private func coversText(_ frame: NSRect) -> Bool {
        let measure = WritingMeasure(columnWidth: contentSize.width)
        return measure.right + 24 > frame.minX
    }

    private func gutterHeight(_ width: CGFloat) -> CGFloat {
        if let measuredHeight { return measuredHeight }
        let height = measureGutter(width)
        measuredHeight = height
        return height
    }

    private func measureGutter(_ width: CGFloat) -> CGFloat {
        let host = gutter.host
        host.setFrameSize(NSSize(width: width, height: 1))
        host.layoutSubtreeIfNeeded()
        let intrinsic = host.intrinsicContentSize.height
        guard intrinsic > 1, intrinsic < 360 else { return 96 }
        return ceil(intrinsic)
    }

    private func pinned(width: CGFloat, height: CGFloat) -> NSRect {
        let x = bounds.maxX - width - 36
        let y = isFlipped ? bounds.minY + 28 : bounds.maxY - height - 28
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func installGutter() {
        gutter.translatesAutoresizingMaskIntoConstraints = true
        gutter.host.sizingOptions = .intrinsicContentSize
        addSubview(gutter)
    }
}

final class PassThroughBox: NSView {
    let host = NSHostingView(rootView: PropertiesText(copy: .empty))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        host.frame = bounds
    }
}
