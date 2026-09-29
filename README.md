# Emd

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

Debug and Release sign with the Apple Development identity in `project.yml`, so a build runs on this Mac. Release turns on the hardened runtime and a secure timestamp. Shipping to other Macs also needs a Developer ID Application certificate and notarization (`xcodebuild archive`, then `notarytool submit` and `stapler staple`).

## Probe

Debug builds run a control channel for scripted checks and for Claude: HTTP on `127.0.0.1`, a random port, and a random token, written to `~/Library/Application Support/EmDashWriter/probe.json` (mode 600). Release builds do not contain it (`#if DEBUG`). `scripts/probe` is the client.

```sh
scripts/probe GET /                    # the routes
scripts/probe GET /state               # model: post, dirty, notice, uploads, view settings, first responder
scripts/probe GET '/editor?text=0'     # selection, caret line, bullets, pictures, scroll
scripts/probe GET '/layout?from=0&to=400'   # line fragments
scripts/probe GET '/attributes?at=42'  # everything styled onto one character
scripts/probe render editor.png        # the page, drawn in the app (no screen-recording permission)
scripts/probe GET '/stats?reset=1'     # Pace timings (count, mean, p50, p95, max) and memory
scripts/probe POST /scratch '{"text": "- one\n- two"}'   # a post that never saves; use it for edits
scripts/probe POST /select '{"location": 5}'
scripts/probe POST /type '{"text": "hello"}'
scripts/probe POST /command '{"name": "moveDown", "count": 2}'
scripts/probe POST /settings '{"focusMode": true, "focusDepth": 3}'
scripts/probe POST /replay '{"typed": "abc", "at": 60000}'  # timed typing in an offscreen copy
```

Typing into a real post autosaves it like any edit, so experiments belong in `/scratch`. Publishing, unpublishing, discarding, and trashing are not on the probe.
