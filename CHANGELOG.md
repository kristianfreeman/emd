# Changelog

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
