#if DEBUG
    import AppKit

    /// What the probe can read and do. Everything runs on the main thread against the live app.
    /// Nothing here publishes, unpublishes, trashes, or discards: those reach the site and stay manual.
    /// Typing into a real post autosaves it like any edit, so experiments go in `POST /scratch`, which never saves.
    @MainActor
    final class ProbeRoutes {
        let model: AppModel
        private var table: [String: (ProbeRequest) async -> ProbeResponse] = [:]

        init(model: AppModel) {
            self.model = model
            table = [
                "GET /": { _ in .json(.object(["routes": .array(self.table.keys.sorted().map(JSONValue.string))])) },
                "GET /state": { _ in .json(self.state()) },
                "GET /editor": { self.editor($0) },
                "GET /layout": { self.layout($0) },
                "GET /attributes": { self.attributes($0) },
                "GET /render": { self.render($0) },
                "GET /stats": { self.stats($0) },
                "GET /api": { await self.api($0) },
                "POST /open": { self.open($0) },
                "POST /scratch": { self.scratch($0) },
                "POST /scratch/close": { _ in self.closeScratch() },
                "POST /select": { self.select($0) },
                "POST /type": { self.type($0) },
                "POST /command": { self.command($0) },
                "POST /format": { self.format($0) },
                "POST /focus": { self.focus($0) },
                "POST /settings": { self.settings($0) },
                "POST /replay": { self.replay($0) },
            ]
        }

        func handle(_ request: ProbeRequest) async -> ProbeResponse {
            guard let route = table["\(request.method) \(request.path)"] else {
                return .json(
                    .object(["error": .string("No route \(request.method) \(request.path). GET / lists them.")]),
                    status: 404)
            }
            return await route(request)
        }

        var view: QuietTextView? { model.editorView }

        static func failure(_ message: String) -> ProbeResponse {
            .json(.object(["error": .string(message)]), status: 400)
        }

        // MARK: Reading

        func state() -> JSONValue {
            .object([
                "site": .string(model.siteURL?.absoluteString ?? ""), "connected": .bool(model.isConnected),
                "offline": .bool(model.offline), "warming": .bool(model.warming), "busy": .bool(model.busy),
                "saving": .bool(model.saving), "conflicted": .bool(model.conflicted), "notice": .string(model.notice),
                "flash": .string(model.flashText), "uploads": .number(Double(model.uploadsInFlight)),
                "collection": .string(model.collection?.slug ?? ""), "entries": .number(Double(model.entries.count)),
                "visible": .number(Double(model.visibleEntries.count)), "drafts": .number(Double(model.drafts.count)),
                "query": .string(model.query), "filter": .string(model.filter.rawValue),
                "document": model.document.map(Self.document) ?? .null, "view": viewSettings(),
                "firstResponder": .string(Self.responder()),
            ])
        }

        /// Which view has the keyboard in the main window: `QuietTextView`, a search field, the list.
        static func responder() -> String {
            let window = NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
            guard let responder = window?.firstResponder else { return "" }
            let name = String(describing: Swift.type(of: responder))
            guard let editor = responder as? NSTextView, !(editor is QuietTextView) else { return name }
            let field = (editor.delegate as? NSView).map { String(describing: Swift.type(of: $0)) } ?? "field editor"
            return "\(name) for \(field)"
        }

        static func document(_ document: EditorDocument) -> JSONValue {
            .object([
                "localID": .string(document.localID), "remoteID": .string(document.remoteID ?? ""),
                "title": .string(document.title), "status": .string(document.status), "dirty": .bool(document.dirty),
                "loaded": .bool(document.loaded), "words": .number(Double(document.words)),
                "loadError": .string(document.loadError ?? ""), "rev": .string(document.rev ?? ""),
                "pendingDraft": .bool(document.draftRevisionID != nil),
                "textRevision": .number(Double(document.textRevision)),
                "bodyLength": .number(Double((document.body as NSString).length)),
                "neverSaves": .bool(document.neverSaves),
            ])
        }

        private func viewSettings() -> JSONValue {
            .object([
                "focusMode": .bool(model.focusMode), "focusDepth": .number(Double(model.focusDepth.rawValue)),
                "typewriter": .bool(model.typewriter), "fontSize": .number(model.fontSize),
                "font": .string(model.fontChoice.rawValue), "appearance": .string(model.appearance.rawValue),
            ])
        }

        private func editor(_ request: ProbeRequest) -> ProbeResponse {
            guard let view else { return Self.failure("No post is open in the editor.") }
            let ns = view.string as NSString
            let selection = view.selectedRange()
            let caretLine = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
            var fields: [String: JSONValue] = [
                "length": .number(Double(ns.length)), "selection": Self.range(selection),
                "caretLine": .object(["range": Self.range(caretLine), "text": .string(ns.substring(with: caretLine))]),
                "hidden": .number(Double(view.hiddenCharacters.count)),
                "bullets": .array(view.bulletCharacters.map { .number(Double($0)) }),
                "revealedImage": view.revealedImage.map { .number(Double($0)) } ?? .null,
                "firstResponder": .bool(view.window?.firstResponder === view),
                "scrollY": .number(Double(view.enclosingScrollView?.contentView.bounds.origin.y ?? 0)),
                "pictures": .array(view.previews(in: view.bounds).map(Self.picture)),
            ]
            if request.query["text"] != "0" { fields["text"] = .string(view.string) }
            return .json(.object(fields))
        }

        static func picture(_ placed: PlacedPreview) -> JSONValue {
            .object([
                "range": range(placed.range), "url": .string(placed.preview.url.absoluteString),
                "width": .number(placed.preview.size.width), "height": .number(placed.preview.size.height),
                "top": .number(placed.top), "loaded": .bool(InlineImages.shared.image(placed.preview.url) != nil),
            ])
        }

        static func range(_ range: NSRange) -> JSONValue {
            .object(["location": .number(Double(range.location)), "length": .number(Double(range.length))])
        }

        static func rect(_ rect: NSRect) -> JSONValue {
            .array([rect.origin.x, rect.origin.y, rect.width, rect.height].map { .number(Double($0)) })
        }
    }
#endif
