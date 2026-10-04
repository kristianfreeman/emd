#if DEBUG
    import AppKit

    extension ProbeRoutes {
        /// Line fragments: `?from=0&to=400` in characters, at most 400 fragments.
        func layout(_ request: ProbeRequest) -> ProbeResponse {
            guard let view, let layout = view.layoutManager, let container = view.textContainer else {
                return Self.failure("No post is open in the editor.")
            }
            let ns = view.string as NSString
            let from = min(Int(request.query["from"] ?? "") ?? 0, ns.length)
            let to = min(Int(request.query["to"] ?? "") ?? ns.length, ns.length)
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: from, length: max(0, to - from)), actualCharacterRange: nil)
            var fragments: [JSONValue] = []
            var glyph = glyphs.location
            while glyph < NSMaxRange(glyphs), fragments.count < 400 {
                var range = NSRange()
                let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
                fragments.append(fragment(range, rect: rect, layout: layout, ns: ns))
                glyph = max(NSMaxRange(range), glyph + 1)
            }
            let used = layout.usedRect(for: container)
            return .json(.object(["used": Self.rect(used), "fragments": .array(fragments)]))
        }

        private func fragment(_ glyphs: NSRange, rect: NSRect, layout: NSLayoutManager, ns: NSString) -> JSONValue {
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let used = layout.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let text = ns.substring(with: characters)
            return .object([
                "characters": Self.range(characters), "rect": Self.rect(rect), "used": Self.rect(used),
                "text": .string(String(text.prefix(80))),
            ])
        }

        /// Everything styled onto one character: `?at=12`.
        func attributes(_ request: ProbeRequest) -> ProbeResponse {
            guard let view, let storage = view.textStorage, storage.length > 0 else { return Self.failure("No text.") }
            let index = min(Int(request.query["at"] ?? "") ?? 0, storage.length - 1)
            let found = storage.attributes(at: index, effectiveRange: nil)
            var fields: [String: JSONValue] = [
                "at": .number(Double(index)), "hidden": .bool(view.hiddenCharacters.contains(index)),
                "bullet": .bool(view.bulletCharacters.contains(index)),
            ]
            for (key, value) in found {
                fields[key.rawValue] = .string(String(describing: value).prefix(400).description)
            }
            return .json(.object(fields))
        }

        /// The editor as PNG, drawn in the app, so no screen-recording permission is needed. It is the visible
        /// page with its paper and gutter.
        /// `?what=window` draws the whole window instead; SwiftUI toolbar parts may come out blank that way.
        /// `?what=frame` is the window as the screen shows it, title bar and toolbar too. An app may image its own
        /// windows without screen-recording permission.
        func render(_ request: ProbeRequest) -> ProbeResponse {
            if request.query["what"] == "frame" { return framed() }
            let target = request.query["what"] == "window" ? view?.window?.contentView : view?.enclosingScrollView
            guard let target, target.bounds.width > 0 else { return Self.failure("Nothing to draw.") }
            let bounds = target.bounds
            guard let rep = target.bitmapImageRepForCachingDisplay(in: bounds) else {
                return Self.failure("Could not draw.")
            }
            target.cacheDisplay(in: bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                return Self.failure("Could not encode.")
            }
            return .png(png)
        }

        /// The main window's area with whatever of this app is on screen there, popovers and sheets included.
        private func framed() -> ProbeResponse {
            guard let window = view?.window ?? NSApp.mainWindow, let screen = window.screen ?? NSScreen.screens.first,
                let image = CGWindowListCreateImage(
                    Self.flipped(window.frame, in: screen), .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return Self.failure("Could not image the window.") }
            return .png(png)
        }

        /// AppKit counts up from the bottom of the main screen; Core Graphics counts down from its top.
        private static func flipped(_ frame: NSRect, in screen: NSScreen) -> CGRect {
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        }

        /// Timings by name from `Pace`, memory, and counts. `?reset=1` clears the timings after reading.
        func stats(_ request: ProbeRequest) -> ProbeResponse {
            let samples = Pace.snapshot()
            if request.query["reset"] == "1" { Pace.reset() }
            let grouped = Dictionary(grouping: samples, by: \.name).mapValues { Self.summary($0.map(\.milliseconds)) }
            return .json(
                .object([
                    "timings": .object(grouped), "memoryMB": .number(Self.footprintMB()),
                    "samples": .number(Double(samples.count)),
                ]))
        }

        static func summary(_ values: [Double]) -> JSONValue {
            let sorted = values.sorted()
            func at(_ share: Double) -> Double {
                sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))]
            }
            let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
            return .object([
                "count": .number(Double(sorted.count)), "mean": .number(mean), "p50": .number(at(0.5)),
                "p95": .number(at(0.95)), "max": .number(sorted.last ?? 0),
            ])
        }

        /// What Activity Monitor calls Memory.
        static func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
        }
    }
    extension ProbeRoutes {
        /// A GET against the site's API with the app's token: `?path=/schema/collections`. Read-only by design.
        func api(_ request: ProbeRequest) async -> ProbeResponse {
            guard let client = model.client, let path = request.query["path"], path.hasPrefix("/") else {
                return Self.failure("Connect first, and send ?path=/…")
            }
            do {
                return .json(try await client.send("GET", path))
            } catch {
                return Self.failure(error.localizedDescription)
            }
        }
    }
#endif
