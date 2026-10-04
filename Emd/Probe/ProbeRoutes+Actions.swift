#if DEBUG
    import AppKit

    extension ProbeRoutes {
        /// Editor commands the probe may send, as the key bindings would. Anything else is refused.
        static let commands: Set<String> = [
            "insertNewline", "insertTab", "insertBacktab", "deleteBackward", "deleteForward", "deleteWordBackward",
            "moveUp", "moveDown", "moveLeft", "moveRight", "moveWordLeft", "moveWordRight",
            "moveToBeginningOfLine", "moveToEndOfLine", "moveToBeginningOfDocument", "moveToEndOfDocument",
            "moveUpAndModifySelection", "moveDownAndModifySelection", "moveLeftAndModifySelection",
            "moveRightAndModifySelection", "selectAll", "selectLine", "selectParagraph", "pageDown", "pageUp",
            "cancelOperation", "undo", "redo",
        ]

        /// `{"id": "…"}` opens a post from the list. It loads in the background; poll `GET /state`.
        /// `{"id": "…", "collection": "pages"}`. The collection, when given, is chosen first.
        func open(_ request: ProbeRequest) async -> ProbeResponse {
            guard let id = request.body.object?["id"]?.string, !id.isEmpty else {
                return Self.failure("Send {\"id\": …}.")
            }
            if let slug = request.body.object?["collection"]?.string, slug != model.collection?.slug {
                await model.chooseCollection(slug)
            }
            model.openFromList(id)
            return .json(.object(["opening": .string(id)]))
        }

        /// A local post that never saves or journals, for anything that edits. `{"text": "…"}` seeds it.
        func scratch(_ request: ProbeRequest) -> ProbeResponse {
            closeScratchDrafts()
            let draft = EditorDocument()
            draft.neverSaves = true
            draft.loaded = true
            draft.collectionSlug = model.collection?.slug
            draft.restore(
                DraftText(
                    title: "Probe scratch", body: request.body.object?["text"]?.string ?? "", excerpt: "", slug: ""))
            model.drafts.insert(draft, at: 0)
            model.document = draft
            model.editorFocusID = draft.localID
            return .json(.object(["document": Self.document(draft)]))
        }

        func closeScratch() -> ProbeResponse {
            let closed = closeScratchDrafts()
            return .json(.object(["closed": .number(Double(closed))]))
        }

        @discardableResult
        private func closeScratchDrafts() -> Int {
            let scratch = model.drafts.filter(\.neverSaves)
            model.drafts.removeAll(where: \.neverSaves)
            if model.document?.neverSaves == true { model.document = nil }
            return scratch.count
        }

        /// `{"location": 12, "length": 0}`, through the same snapping a click or an arrow key gets.
        func select(_ request: ProbeRequest) -> ProbeResponse {
            guard let view else { return Self.failure("No post is open in the editor.") }
            let object = request.body.object ?? [:]
            let location = Int(object["location"]?.number ?? 0)
            let length = Int(object["length"]?.number ?? 0)
            view.setSelectedRange(NSRange(location: min(location, (view.string as NSString).length), length: length))
            return .json(.object(["selection": Self.range(view.selectedRange()), "saves": .bool(!isScratch)]))
        }

        /// `{"text": "…"}` types at the selection, as the keyboard would.
        func type(_ request: ProbeRequest) -> ProbeResponse {
            guard let view else { return Self.failure("No post is open in the editor.") }
            let text = request.body.object?["text"]?.string ?? ""
            view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return .json(.object(["selection": Self.range(view.selectedRange()), "saves": .bool(!isScratch)]))
        }

        /// `{"name": "moveDown", "count": 3}`
        func command(_ request: ProbeRequest) -> ProbeResponse {
            guard let view else { return Self.failure("No post is open in the editor.") }
            let name = request.body.object?["name"]?.string ?? ""
            guard Self.commands.contains(name) else {
                return Self.failure("Unknown command. Allowed: \(Self.commands.sorted())")
            }
            for _ in 0..<max(1, Int(request.body.object?["count"]?.number ?? 1)) {
                perform(name, on: view)
            }
            return .json(
                .object([
                    "selection": Self.range(view.selectedRange()), "length": .number(Double(view.string.utf16.count)),
                ]))
        }

        private func perform(_ name: String, on view: QuietTextView) {
            if name == "undo" { return view.undoManager?.undo() ?? () }
            if name == "redo" { return view.undoManager?.redo() ?? () }
            view.doCommand(by: NSSelectorFromString(name + ":"))
        }

        /// `{"style": "bold" | "italic" | "code" | "footnote"}`, as the Format menu does.
        func format(_ request: ProbeRequest) -> ProbeResponse {
            let markers = ["bold": "**", "italic": "_", "code": "`", "footnote": ""]
            guard let view, let marker = markers[request.body.object?["style"]?.string ?? ""] else {
                return Self.failure(
                    "Open a post and send {\"style\": \"bold\" | \"italic\" | \"code\" | \"footnote\"}.")
            }
            if marker.isEmpty { view.insertFootnote() } else { view.toggleMarker(marker) }
            return .json(.object(["selection": Self.range(view.selectedRange())]))
        }

        /// `{"manifest": {…}, "regions": {"aside": "Aside"}}`: custom blocks as if the site's manifest declared
        /// them, and regions for the open post, so cards and dividers can be seen before a site has either.
        func objects(_ request: ProbeRequest) -> ProbeResponse {
            let body = request.body.object ?? [:]
            if let manifest = body["manifest"] { model.blockDefs = PageBlocks.definitions(fromManifest: manifest) }
            if let regions = body["regions"]?.object { model.probeRegions = regions.compactMapValues(\.string) }
            return .json(
                .object([
                    "blocks": .array(model.blockDefs.keys.sorted().map { .string($0) }),
                    "regions": .number(Double(model.probeRegions?.count ?? 0)),
                ]))
        }

        /// `{"at": 120}`: opens the details of the picture or card at a character, as a double-click does.
        func openObject(_ request: ProbeRequest) -> ProbeResponse {
            let at = Int(request.body.object?["at"]?.number ?? 0)
            guard let view, let object = view.imageContent(around: at) else { return Self.failure("No object there.") }
            view.showImageDetails(object)
            return .json(.object(["object": Self.range(object)]))
        }

        /// `{"type": "musicList"}`: Post › Insert at the caret, as the menu does.
        func insertObject(_ request: ProbeRequest) -> ProbeResponse {
            guard let view, let definition = model.blockDefs[request.body.object?["type"]?.string ?? ""] else {
                return Self.failure("Open a post, and send a type the site defines.")
            }
            view.insertBlock(definition)
            return .json(.object(["text": .string(view.string)]))
        }

        /// `{"target": "editor" | "sidebar" | "search"}`
        func focus(_ request: ProbeRequest) -> ProbeResponse {
            switch request.body.object?["target"]?.string {
            case "editor": model.focusEditor()
            case "sidebar": model.focusSidebar()
            case "search": model.searchToken += 1
            default: return Self.failure("Target is editor, sidebar, or search.")
            }
            return .json(.object(["ok": .bool(true)]))
        }

        /// Any of `focusMode`, `focusDepth` (0–4), `typewriter`, `fontSize`, `font`, `appearance`.
        func settings(_ request: ProbeRequest) -> ProbeResponse {
            let object = request.body.object ?? [:]
            applyViewToggles(object)
            applyTypeSettings(object)
            return .json(state())
        }

        private func applyViewToggles(_ object: [String: JSONValue]) {
            if let value = object["focusMode"]?.boolish { model.focusMode = value }
            if let value = object["focusDepth"]?.number {
                model.focusDepth = FocusDepth(rawValue: Int(value)) ?? .muted
            }
            if let value = object["typewriter"]?.boolish { model.typewriter = value }
        }

        private func applyTypeSettings(_ object: [String: JSONValue]) {
            if let value = object["fontSize"]?.number { model.setFontSize(value) }
            if let value = object["font"]?.string, let font = WriterFont(rawValue: value) { model.setFont(font) }
            if let value = object["appearance"]?.string, let look = AppearanceChoice(rawValue: value) {
                model.setAppearance(look)
            }
        }

        private var isScratch: Bool { model.document?.neverSaves == true }
    }
#endif
