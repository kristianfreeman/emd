#if DEBUG
    import AppKit

    /// Typing, timed, in an offscreen copy of the editor. The live post is never touched and nothing saves.
    extension ProbeRoutes {
        /// `{"typed": "…", "seed": "…", "at": 120}`. `seed` defaults to the open post's text, `at` to its end.
        /// Each keystroke restyles its line and lays the column out, as a real one does.
        func replay(_ request: ProbeRequest) -> ProbeResponse {
            let object = request.body.object ?? [:]
            let seed = object["seed"]?.string ?? model.document?.body ?? ""
            let typed = object["typed"]?.string ?? "The quick brown fox jumps over the lazy dog. "
            let (scroll, column) = offscreenColumn(seed)
            let length = (seed as NSString).length
            column.bodyView.setSelectedRange(
                NSRange(location: min(Int(object["at"]?.number ?? Double(length)), length), length: 0))
            column.bodyView.scrollRangeToVisible(column.bodyView.selectedRange())
            Pace.reset()
            let keystrokes = typed.map { keystroke(String($0), in: column) }
            withExtendedLifetime(scroll) {}
            let breakdown = Dictionary(grouping: Pace.snapshot(), by: \.name).mapValues {
                Self.summary($0.map(\.milliseconds))
            }
            return .json(
                .object([
                    "keystroke": Self.summary(keystrokes), "breakdown": .object(breakdown),
                    "documentLength": .number(Double(length)), "typed": .number(Double(keystrokes.count)),
                ]))
        }

        private func keystroke(_ text: String, in column: ColumnView) -> Double {
            let view = column.bodyView
            let started = CFAbsoluteTimeGetCurrent()
            let location = view.selectedRange().location
            view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            view.restyle(around: NSRange(location: location, length: (text as NSString).length))
            column.noteTyping()
            column.layoutSubtreeIfNeeded()
            return (CFAbsoluteTimeGetCurrent() - started) * 1000
        }

        private func offscreenColumn(_ text: String) -> (NSScrollView, ColumnView) {
            let width = max(view?.superview?.bounds.width ?? 1000, 400)
            let column = ColumnView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
            // In a scroll view, as the real page is, so keystrokes lay out what is on screen.
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
            scroll.documentView = column
            let size = CGFloat(model.fontSize)
            let palette = Palette.resolve(.light)
            column.bodyView.configure(
                TextLook(
                    font: model.fontChoice.nsFont(size: size),
                    ink: TextInk(color: palette.nsInk, muted: palette.nsMuted, paper: palette.nsPaper),
                    lineHeight: 1.32, paragraphSpacing: size * 0.28))
            column.bodyView.focusMode = model.focusMode
            column.bodyView.focusDepth = model.focusDepth
            column.bodyView.siteURL = model.siteURL
            column.bodyView.string = text
            column.bodyView.restyle()
            column.layout()
            return (scroll, column)
        }
    }
#endif
