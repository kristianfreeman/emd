import AppKit
import SwiftUI

struct ColumnChange {
    var title = false
    var body = false
    var style = false
}

struct WritingColumn: NSViewRepresentable {
    @Binding var title: String
    @Binding var bodyText: String
    var fontChoice: WriterFont
    var fontSize: CGFloat
    var palette: Palette
    var focusMode: Bool
    var typewriter: Bool
    var gutter: GutterCopy

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WriterScroll()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = palette.nsPaper
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let column = ColumnView()
        column.titleView.delegate = context.coordinator
        column.bodyView.delegate = context.coordinator
        context.coordinator.column = column
        context.coordinator.scroll = scroll
        column.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        scroll.documentView = column
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.watchClip(scroll)
        context.coordinator.apply(self, to: column)
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 680, height: 640))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let scroll = scroll as? WriterScroll, let column = scroll.documentView as? ColumnView else { return }
        scroll.backgroundColor = palette.nsPaper
        scroll.show(gutter)
        context.coordinator.apply(self, to: column)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingColumn
        weak var column: ColumnView?
        weak var scroll: NSScrollView?
        private var applying = false
        private var widthObserver: NSObjectProtocol?
        private var paintedKey = ""
        private var pendingEdit: NSRange?
        private var skipNextCaretRestyle = false

        init(_ parent: WritingColumn) {
            self.parent = parent
        }

        deinit {
            guard let widthObserver else { return }
            NotificationCenter.default.removeObserver(widthObserver)
        }

        func watchClip(_ scroll: NSScrollView) {
            guard widthObserver == nil else { return }
            widthObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.matchClipWidth()
            }
        }

        private func matchClipWidth() {
            column?.noteViewportChanged()
            (scroll as? WriterScroll)?.placeGutter()
        }

        func apply(_ parent: WritingColumn, to column: ColumnView) {
            self.parent = parent
            applying = true
            defer { applying = false }
            configureColumn(parent, column)
            let changed = syncText(parent, column)
            restyleIfNeeded(changed, column)
            layoutIfNeeded(changed, column)
        }

        private func configureColumn(_ parent: WritingColumn, _ column: ColumnView) {
            column.titleView.placeholder = "Title"
            column.titleView.configure(look(parent, size: parent.fontSize * 1.22, lineHeight: 1.12, spacing: 0))
            column.bodyView.accent = parent.palette.nsAccent
            column.bodyView.focusMode = parent.focusMode
            column.bodyView.typewriter = parent.typewriter
            column.bodyView.configure(
                look(parent, size: parent.fontSize, lineHeight: 1.32, spacing: parent.fontSize * 0.28))
        }

        private func look(_ parent: WritingColumn, size: CGFloat, lineHeight: CGFloat, spacing: CGFloat) -> TextLook {
            TextLook(
                font: parent.fontChoice.nsFont(size: size),
                ink: TextInk(color: parent.palette.nsInk, muted: parent.palette.nsMuted, paper: parent.palette.nsPaper),
                lineHeight: lineHeight,
                paragraphSpacing: spacing
            )
        }

        private func syncText(_ parent: WritingColumn, _ column: ColumnView) -> ColumnChange {
            var changed = ColumnChange()
            changed.title = column.titleView.string != parent.title
            changed.body = column.bodyView.string != parent.bodyText
            assignIfNeeded(changed.title, parent.title, column.titleView)
            assignIfNeeded(changed.body, parent.bodyText, column.bodyView)
            let styleKey =
                "\(parent.fontChoice.rawValue)|\(parent.fontSize)|\(parent.focusMode)|\(parent.palette.ink)|\(parent.palette.paper)"
            changed.style = paintedKey != styleKey
            paintedKey = styleKey
            return changed
        }

        private func assignIfNeeded(_ needed: Bool, _ text: String, _ view: NSTextView) {
            guard needed else { return }
            view.string = text
        }

        private func restyleIfNeeded(_ changed: ColumnChange, _ column: ColumnView) {
            guard changed.body || changed.style else { return }
            column.bodyView.restyle()
        }

        private func layoutIfNeeded(_ changed: ColumnChange, _ column: ColumnView) {
            guard changed.body || changed.title || changed.style || column.bounds.width < 2 else { return }
            column.needsLayout = true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?)
            -> Bool
        {
            guard !applying, textView === column?.bodyView else { return true }
            let length = (replacementString as NSString?)?.length ?? 0
            pendingEdit = NSRange(location: affectedCharRange.location, length: length)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !applying, let view = notification.object as? NSTextView, let column else { return }
            if view === column.titleView {
                parent.title = view.string
            } else if view === column.bodyView {
                parent.bodyText = view.string
                let edited = pendingEdit
                pendingEdit = nil
                skipNextCaretRestyle = true
                column.bodyView.restyle(around: edited)
            }
            column.needsLayout = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? QuietTextView, view === column?.bodyView else { return }
            if skipNextCaretRestyle {
                skipNextCaretRestyle = false
                view.noteCaretLine()
            } else {
                view.restyleCaretLine()
            }
            guard view.typewriter, let scroll, let column else { return }
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: view.selectedRange(), actualCharacterRange: nil)
            let caret = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            column.layoutSubtreeIfNeeded()
            let inColumn = view.convert(caret, to: column)
            let clipHeight = scroll.contentView.bounds.height
            var origin = scroll.contentView.bounds.origin
            let target = inColumn.midY - clipHeight * 0.42
            let limit = max(0, column.bounds.height - clipHeight)
            origin.y = min(max(0, target), limit)
            scroll.contentView.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

final class ColumnView: NSView {
    let titleView = QuietTextView.editor()
    let bodyView = QuietTextView.editor()

    func noteViewportChanged() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        guard !layingOut, abs(bounds.width - max(width, 1)) > 0.5 else { return }
        reflow()
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(bodyView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var layingOut = false

    override func layout() {
        super.layout()
        reflow()
    }

    private func reflow() {
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }

        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        let columnWidth = max(available, 1)
        let fitted = WritingMeasure(columnWidth: columnWidth)
        let textWidth = fitted.width
        let x = fitted.origin
        let span = Pace.begin("layout")
        let titleHeight = measure(titleView, width: textWidth)
        titleView.frame = NSRect(x: x, y: 72, width: textWidth, height: titleHeight)
        let bodyY = titleView.frame.maxY + 28
        let bodyHeight = measure(bodyView, width: textWidth)
        Pace.end(span, detail: "\(bodyView.string.utf16.count)")
        bodyView.frame = NSRect(x: x, y: bodyY, width: textWidth, height: bodyHeight)
        let height = bodyView.frame.maxY + 120
        if abs(frame.width - columnWidth) > 0.5 || abs(frame.height - height) > 0.5 {
            frame = NSRect(x: 0, y: 0, width: columnWidth, height: height)
        }
    }

    private func measure(_ view: QuietTextView, width: CGFloat) -> CGFloat {
        let inset = view.textContainerInset.width * 2
        let textWidth = max(1, width - inset)
        // Assigning the container size invalidates every line. Skip it when the column width has not changed.
        if let container = view.textContainer, abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        guard let layout = view.layoutManager, let container = view.textContainer else { return 36 }
        layout.ensureLayout(for: container)
        return max(36, ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2 + 8))
    }
}

private struct WritingMeasure {
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
