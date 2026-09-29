# emdash writer

A native Mac app for writing on an [EmDash](https://emdashcms.com/) site. It is a text window, not the admin panel: the sidebar holds the library, the post, and the type, and the page is only the writing.

Connect with the site address and a personal access token from the EmDash admin (Settings → API tokens). The token needs to read and write content. It is stored in the Keychain. The app then loads the site name, collections, and posts through `/_emdash/api/`.

Posts are edited as Markdown. A Portable Text field is converted on the way in and out, in the same shapes EmDash’s own client uses for headings, lists, emphasis, links, and code. A picture on its own line (`![alt](url)`) is an image block. An image that also has a library id, caption, or size stays on a fenced line so a save does not drop it, as do other blocks the editor does not edit. Save writes a draft. Publish, unpublish, discard draft, and trash are separate.

Type choices are Geist Sans, Geist Mono, the system sans, New York, SF Mono, Charter, and Georgia. Appearance follows the system, or stays light or dark. Geist is bundled under the SIL Open Font License; see `emdash-writer/Resources/Fonts/OFL.txt`.

## Lint

`scripts/lint` checks formatting with `swift-format`, then structure with SwiftLint and a branching-depth check. SwiftLint is `brew install swiftlint`. `swift-format` comes with Xcode.

Complexity warns at 5 and errors at 8. An `if` inside an `if` warns; a third level errors. Function bodies warn at 40 lines and error at 60. Files warn at 400 lines and error at 600.

## Run

```sh
xcodegen generate
xcodebuild -scheme EmDashWriter -destination 'platform=macOS' test
open EmDashWriter.xcodeproj
```

The project is signed ad hoc so it runs locally without an Apple team.
