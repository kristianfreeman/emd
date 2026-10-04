# Changelog

## 0.2.0

### Writing
- Footnotes: `[^1]` in the text and `[^1]: The note.` below. References draw small and raised, notes draw as notes, and Format › Footnote (⌥⌘N) adds the next one and its note at the end of the post; from a note it goes back to the text.
- On the site a reference is a superscript linked to its note, and the notes are one block at that spot, so any EmDash site draws them and the admin editor still opens the post.
- Typing never waits on the length of the post: every keystroke stays under 2ms, even one that wraps a line at the top of 120,000 characters, which used to take 130ms.

### Toolbar
- Publish is an icon: a paper plane to publish, an arrow to update, and a quiet check or clock when there is nothing to send.
- Publishing and uploading show an animated progress symbol in their own button's icon, so nothing in the toolbar shifts or clips while they run.

### For developers
- The Debug build is its own app, **Emd Debug**: bundle ID `com.kristianfreeman.emd.debug`, a yellow icon with caution stripes, and its own settings, Keychain items, saved text (`~/Library/Application Support/Emd Debug`), and logs. It runs beside the installed Emd without touching what is being written there, and connects to the site on its own.
- Unit tests run in Emd Debug and open nothing: no post, no site connection.
- `scripts/probe render out.png frame` draws the whole window, toolbar included, and the probe's format route takes `footnote`.

## 0.1.0

The first release of Emd, a native Mac app for writing on an EmDash site.

### Writing
- A quiet Markdown editor: headings, bold, italic, code, links, quotes, and code blocks style as you type, with the markers showing only where the caret is.
- Lists read as lists: bullets, hanging indents, nesting with Tab, and Return that continues or ends a list.
- Pictures: drop, paste, or Insert Image… (⇧⌘I) to upload to the site's media library. Pictures draw inline, act as one object, and a double-click edits alt text, caption, and alignment.
- Links keep their Markdown out of the way; ⌘K adds or edits one, and pasting an address over words links them.
- Format menu: Bold ⌘B, Italic ⌘I, Code, Link ⌘K.
- Focus mode (⇧⌘F) with five depths from muted to blurred, Typewriter mode (⇧⌘T), text size ⌘+ ⌘− ⌘0, seven typefaces, light and dark.
- Each post remembers its caret and scroll, and launch reopens the last post.

### Saving and publishing
- Autosave a moment after you stop typing, journaled on this Mac first: a quit, crash, or dropped connection keeps your words, and offline launches keep the library open.
- A post that changed on the site while you wrote keeps your text, with Keep My Version or Use Site Version.
- Portable Text round-trips exactly: anything the editor does not edit stays as it was.
- Publish, Update, Unpublish, Schedule…, Discard Unpublished Changes, and Preview in Browser (⌥⌘P) in the Post menu.
- Post Details (⌃⌘I): title, slug, excerpt, tags, and categories.
- In a collection without revisions, a published post is never autosaved, since every save there is live.

### Library
- Search posts (⌥⌘F), filter by status, switch collections, rename, trash, and see which posts hold edits not yet on the site.

### For developers
- `scripts/lint`, `scripts/smoke` (drives the running Debug app through a local probe), and `scripts/release` (archive, Developer ID signing, notarization, stapling).
