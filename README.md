# emdash writer

A native Mac app for writing on an [EmDash](https://emdashcms.com/) site. It is a text window, not the admin panel: the sidebar holds the library, the post, and the type, and the page is only the writing.

Connect with the site address and a personal access token from the EmDash admin (Settings → API tokens). The token needs to read and write content. It is stored in the Keychain. The app then loads the site name, collections, and posts through `/_emdash/api/`.

Posts are edited as Markdown. A Portable Text field is converted on the way in and out, in the same shapes EmDash’s own client uses for headings, lists, emphasis, links, and code. Image and other blocks are kept as fenced lines so a save does not drop them. Save writes a draft. Publish, unpublish, discard draft, and trash are separate.

Type choices are Geist Sans, Geist Mono, the system sans, New York, SF Mono, Charter, and Georgia. Appearance follows the system, or stays light or dark. Geist is bundled under the SIL Open Font License; see `emdash-writer/Resources/Fonts/OFL.txt`.

## Run

```sh
xcodegen generate
xcodebuild -scheme EmDashWriter -destination 'platform=macOS' test
open EmDashWriter.xcodeproj
```

The project is signed ad hoc so it runs locally without an Apple team.
