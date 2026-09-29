import AppKit
import SwiftUI

struct ColumnChange {
    var body = false
    var style = false
}

struct WritingColumn: NSViewRepresentable {
    @Binding var bodyText: String
    /// `EditorDocument.textRevision`. The body is only pushed into the view when this moves.
    var bodyRevision: Int
    var fontChoice: WriterFont
    var fontSize: CGFloat
    var palette: Palette
    var focusMode: Bool
    var focusDepth: FocusDepth
    var typewriter: Bool
    var gutter: GutterCopy
    /// `CaretMemory` key for this post.
    var caretKey: String
    var wantsFocus: Bool
    var onFocus: () -> Void
    var onEscape: () -> Void
    var onImages: ([ImageSource], Int) -> Void
    /// Hands the model the page, so an upload can land as an edit on it.
    var onReady: (QuietTextView) -> Void
    var site: URL?

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
        column.bodyView.delegate = context.coordinator
        column.onWindow = { [weak coordinator = context.coordinator] in coordinator?.windowReady() }
        column.bodyView.onEscape = { [weak coordinator = context.coordinator] in coordinator?.parent.onEscape() }
        column.bodyView.onImages = { [weak coordinator = context.coordinator] sources, index in
            coordinator?.parent.onImages(sources, index)
        }
        context.coordinator.column = column
        context.coordinator.scroll = scroll
        column.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        scroll.documentView = column
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.watchClip(scroll)
        context.coordinator.watchQuit()
        context.coordinator.apply(self, to: column)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.rememberSpot()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 680, height: 640))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let scroll = scroll as? WriterScroll, let column = scroll.documentView as? ColumnView else { return }
        scroll.backgroundColor = palette.nsPaper
        scroll.show(gutter, color: palette.muted)
        context.coordinator.apply(self, to: column)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingColumn
        weak var column: ColumnView?
        weak var scroll: NSScrollView?
        private var applying = false
        private var observers: [NSObjectProtocol] = []
        /// Set once the remembered caret is back. Until then there is nothing worth remembering.
        var restored = false
        private var paintedKey = ""
        private var syncedRevision = -1
        private var pendingEdit: NSRange?
        private var skipNextCaretRestyle = false

        init(_ parent: WritingColumn) {
            self.parent = parent
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func watchQuit() {
            let quit = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rememberSpot()
            }
            observers.append(quit)
        }

        func watchClip(_ scroll: NSScrollView) {
            let width = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.matchClipWidth()
            }
            observers.append(width)
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
            parent.onReady(column.bodyView)
            focusIfWanted()
        }

        private func configureColumn(_ parent: WritingColumn, _ column: ColumnView) {
            column.bodyView.placeholder = "Start writing…"
            column.bodyView.siteURL = parent.site
            column.bodyView.accent = parent.palette.nsAccent
            column.bodyView.focusMode = parent.focusMode
            column.bodyView.focusDepth = parent.focusDepth
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
            changed.body = parent.bodyRevision != syncedRevision
            syncedRevision = parent.bodyRevision
            if changed.body { assignKeepingCaret(parent.bodyText, column.bodyView) }
            let styleKey =
                "\(parent.fontChoice.rawValue)|\(parent.fontSize)|\(parent.focusMode)|\(parent.focusDepth.rawValue)|\(parent.palette.ink)|\(parent.palette.paper)"
            changed.style = paintedKey != styleKey
            paintedKey = styleKey
            return changed
        }

        /// New text from the site keeps the caret where it was, not at the end.
        private func assignKeepingCaret(_ text: String, _ view: NSTextView) {
            guard view.string != text else { return }
            let caret = view.selectedRange().location
            view.string = text
            view.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
            // Undo steps recorded against the old text would land in the wrong places now.
            view.undoManager?.removeAllActions(withTarget: view)
            if let storage = view.textStorage { view.undoManager?.removeAllActions(withTarget: storage) }
        }

        private func restyleIfNeeded(_ changed: ColumnChange, _ column: ColumnView) {
            guard changed.body || changed.style else { return }
            column.bodyView.restyle()
        }

        private func layoutIfNeeded(_ changed: ColumnChange, _ column: ColumnView) {
            guard changed.body || changed.style || column.bounds.width < 2 else { return }
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

        /// No spelling marks on pictures: their folded Markdown would show one as a stray dot.
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange)
            -> Int
        {
            guard let view = textView as? QuietTextView, !view.allowsSpelling(in: affectedCharRange) else {
                return value
            }
            return 0
        }

        func textDidChange(_ notification: Notification) {
            guard !applying, let view = notification.object as? NSTextView, let column else { return }
            if view === column.bodyView {
                parent.bodyText = view.string
                let edited = pendingEdit
                pendingEdit = nil
                skipNextCaretRestyle = true
                column.bodyView.restyle(around: edited)
            }
            column.noteTyping()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? QuietTextView, view === column?.bodyView else { return }
            if skipNextCaretRestyle {
                skipNextCaretRestyle = false
                view.noteCaretLine()
            } else {
                view.restyleCaretLine()
            }
            guard view.typewriter else { return }
            centerCaret(view)
        }
    }
}

final class ColumnView: NSView {
    let bodyView = QuietTextView.editor()
    var onWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onWindow?()
        onWindow = nil
    }

    func noteViewportChanged() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        guard !layingOut, abs(bounds.width - max(width, 1)) > 0.5 else { return }
        reflow()
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(bodyView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var layingOut = false
    /// Set by a keystroke: the next layout covers what is on screen instead of the whole post.
    private var typing = false
    private var settle: DispatchWorkItem?

    /// A keystroke lays out only down to the bottom of the screen. Everything after the edit point would
    /// otherwise lay out again on every key: 40ms at 120,000 characters. The whole post settles once typing
    /// pauses, which fixes the exact height.
    func noteTyping() {
        typing = true
        needsLayout = true
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.typing = false
            self?.needsLayout = true
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

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
        let bodyY: CGFloat = 72
        // Pictures run past the text by up to 140pt a side, and stay inside the window.
        bodyView.imageFullWidth = columnWidth - 48
        bodyView.imageWidthLimit = min(columnWidth - 48, textWidth + 280)
        let bodyHeight = typing ? measureVisible(bodyView, width: textWidth) : measure(bodyView, width: textWidth)
        Pace.end(span, detail: "\(bodyView.string.utf16.count)")
        bodyView.frame = NSRect(x: x, y: bodyY, width: textWidth, height: bodyHeight)
        let height = bodyView.frame.maxY + 120
        if abs(frame.width - columnWidth) > 0.5 || abs(frame.height - height) > 0.5 {
            frame = NSRect(x: 0, y: 0, width: columnWidth, height: height)
        }
    }

    /// Pictures from image lines, centered on the text. The text view draws no background, so they show.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let local = convert(dirtyRect, to: bodyView).insetBy(dx: 0, dy: -1)
        for item in bodyView.previews(
            in: NSRect(x: 0, y: local.minY, width: bodyView.bounds.width, height: local.height))
        {
            let top = convert(NSPoint(x: 0, y: item.top), from: bodyView).y
            let frame = item.preview.frame(top: top, text: bodyView.frame)
            item.preview.draw(in: frame, placeholder: bodyView.mutedColor)
            let captionFont = NSFont.systemFont(ofSize: (bodyView.baseFont?.pointSize ?? 15) * 0.8)
            item.preview.drawCaption(under: frame, color: bodyView.mutedColor, font: captionFont)
            drawSelection(of: item.range, around: frame)
        }
    }

    /// A ring when the picture is the selected object, a wash when a longer selection covers it.
    private func drawSelection(of range: NSRange, around frame: NSRect) {
        let accent = bodyView.accent
        if bodyView.isImageObjectSelected(range) {
            let ring = NSBezierPath(roundedRect: frame.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10)
            ring.lineWidth = 3
            accent.setStroke()
            ring.stroke()
        } else if range.length > 0, NSIntersectionRange(bodyView.selectedRange(), range).length == range.length {
            accent.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        }
    }

    /// Lays out through one screen past the visible part. The height only grows until the post settles,
    /// so the scroll position never jumps while typing.
    private func measureVisible(_ view: QuietTextView, width: CGFloat) -> CGFloat {
        guard let scroll = enclosingScrollView, let layout = view.layoutManager, let container = view.textContainer,
            abs(container.containerSize.width - max(1, width - view.textContainerInset.width * 2)) <= 0.5
        else { return measure(view, width: width) }
        var visible = view.convert(scroll.contentView.bounds, from: scroll.contentView)
        visible.origin.y -= view.textContainerOrigin.y
        visible.size.height += scroll.contentView.bounds.height
        layout.ensureLayout(forBoundingRect: visible, in: container)
        let laidOut = ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2 + 8)
        return max(36, laidOut, view.frame.height)
    }

    private func measure(_ view: QuietTextView, width: CGFloat) -> CGFloat {
        let inset = view.textContainerInset.width * 2
        let textWidth = max(1, width - inset)
        // Assigning the container size invalidates every line. Skip it when the column width has not changed.
        if let container = view.textContainer, abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
            view.noteColumnWidthChanged()
        }
        guard let layout = view.layoutManager, let container = view.textContainer else { return 36 }
        layout.ensureLayout(for: container)
        return max(36, ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2 + 8))
    }
}
