import AppKit
import UniformTypeIdentifiers

/// Images go in as an "Uploading" line, and that line becomes the real one when the site has the file.
extension AppModel {
    func attachEditor(_ view: QuietTextView, for document: EditorDocument) {
        editorView = view
        editorDocumentID = document.localID
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        insertImages(panel.urls.map(ImageSource.file), at: nil)
    }

    /// `index` is a character position in the body, or nil for the caret.
    func insertImages(_ sources: [ImageSource], at index: Int?) {
        guard let document, !sources.isEmpty else { return }
        guard let client else {
            notice = "Connect to the site to add images."
            return
        }
        let jobs = sources.map(ImageJob.init)
        place(jobs.map(\.placeholder), at: index, in: document)
        for job in jobs {
            Task { await upload(job, into: document, client: client) }
        }
    }

    private func place(_ lines: [String], at index: Int?, in document: EditorDocument) {
        if let view = editor(for: document) {
            view.insertParagraphs(lines, at: index ?? view.selectedRange().location)
            return
        }
        var text = document.text
        text.body += (text.body.isEmpty ? "" : "\n\n") + lines.joined(separator: "\n\n")
        document.restore(text)
    }

    private func upload(_ job: ImageJob, into document: EditorDocument, client: EmDashClient) async {
        uploadsInFlight += 1
        defer { uploadsInFlight -= 1 }
        do {
            let source = job.source
            let prepared = try await Task.detached(priority: .userInitiated) { try PreparedImage.prepare(source) }.value
            let media = try await client.upload(prepared)
            swap(job.placeholder, for: PortableText.imageLine(media: media, alt: ""), in: document)
        } catch {
            removePlaceholder(job.placeholder, in: document)
            noteUploadFailure(error, name: job.source.name)
        }
    }

    private func removePlaceholder(_ placeholder: String, in document: EditorDocument) {
        for candidate in ["\n\n" + placeholder, placeholder + "\n\n", placeholder]
        where swap(candidate, for: "", in: document) {
            return
        }
    }

    /// Through the editor when the post is on screen, so it is one undoable edit. Otherwise in the text,
    /// journaled, since a post that is not open is rebuilt from the journal when it opens again.
    @discardableResult
    private func swap(_ old: String, for new: String, in document: EditorDocument) -> Bool {
        if let view = editor(for: document) { return view.replaceText(old, with: new) }
        guard document.body.contains(old) else { return false }
        var text = document.text
        text.body = text.body.replacingOccurrences(of: old, with: new)
        document.restore(text)
        journal(document)
        return true
    }

    private func editor(for document: EditorDocument) -> QuietTextView? {
        guard editorDocumentID == document.localID, let view = editorView, view.window != nil else { return nil }
        return view
    }

    private func noteUploadFailure(_ error: Error, name: String) {
        guard let api = error as? APIError, api.status == 403 || api.status == 401 else {
            notice = "“\(name)” did not upload. \(error.localizedDescription)"
            return
        }
        notice = "This token cannot upload images. In the EmDash admin, give it permission to upload media."
    }
}

private struct ImageJob {
    var source: ImageSource
    var placeholder: String

    init(_ source: ImageSource) {
        self.source = source
        let name = source.name.replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "\n", with: " ")
        placeholder = "![Uploading \(name)…](\(PortableText.uploadingScheme)\(UUID().uuidString))"
    }
}
