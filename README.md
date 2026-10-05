# Vord

A native macOS vocabulary notebook built with SwiftUI and local SQLite. Requires macOS 15 or later. Build with Xcode 26 or later.

## Learning flow

- **Today**: short rounds of up to five due words, due words, actual library statistics, a selectable week/month/year learning calendar, a configurable daily practice goal, an actual practice streak, and links into learning.
- **Companion**: grounded conversation using the selected AI service, actual daily practice/goal/streak context (including answered dictation), native seven-day plan previews, and explicit recall practice. Words and reviews sync; chats and adopted plans stay on their device. See [study companion](Docs/StudyCompanion.md).
- **AI vocabulary import (macOS)**: paste a word list or passage in Companion, or use Library → Import words. Review editable Chinese/English definitions, then add selected words in one action. Existing entries and review progress are preserved; new entries use normal sync.
- **Speaking materials**: collect phrases, sentences, stories and useful answer angles in Speaking (⌘5). Includes 26 offline starter examples, editable text/Markdown/JSON import, optional AI analysis with preview, question-first timed speaking practice and Companion draft handoff. Today and vocabulary review link into speaking questions; individual word-use assessments update productive review through the existing scheduler. Materials and speaking history stay local. See [speaking materials](Docs/SpeakingMaterials.md).
- **Floating capture**: Option + Space expands a draggable screen-edge glass orb into a compact dictionary window. The input takes focus immediately, including when reopening; early native typing events are retained while the field attaches. The orb uses native clear Liquid Glass on macOS 26+, with a material fallback on earlier systems, two broad rounded eyes and a fixed circular silhouette. Closing keeps the rounded surface synchronized with the shrinking native window, then reveals the lens; its return spring has stronger damping. Larger eyes blink naturally, soften during dragging and briefly smile after a successful addition. The same orb joins a reserved place in Companion while that page is active, follows the window, and returns to the desktop edge when leaving. A click there focuses the conversation; thinking, replies and recorded practice have subtle expression feedback. Manual drag-out is respected and travel never takes keyboard focus. There is no added concentric outline or mask over the native lens. On macOS 27+, native interactive glass is enabled (except with Reduce Motion); pointer input lives inside the glass content hierarchy. Quick Add shows pronunciation playback and phonetics, sizes definitions to their content within a scrolling limit, and supports Up/Down plus Return to explicitly add a highlighted Chinese reverse-lookup result. Settings → Capture optionally enables single-word clipboard suggestions; this is off by default and never auto-saves.
- **In-app dictionary**: select or right-click a word in an example sentence to read its English/Chinese definitions and explicitly add it with that sentence. Existing library words are preserved; multiword selection still supports Copy.
- **Add word**: type English or Chinese, preview a translation, enter a meaning manually, and attach tags and a source. Option + Space opens Quick Add anywhere; the shortcut is configurable.
- **Library**: a compact 52-point word table with pronunciation, Chinese meaning, review state and dates; search words, full definitions, and tags; filter by due words, missing meanings, or archived words. Details include pronunciation playback, installed macOS dictionary definitions, editing, translation refresh, and archive/restore.
- **Review**: independent schedules for both translation directions. Again returns forgotten cards later in the session, up to twice; persistently missed cards stay due in ten minutes. Rating buttons show the next interval. Switching pages pauses the session; a completed session can be followed by another set. There are at most 80 starting cards per session.
- **Dictation**: random tag-filtered exams in either direction or mixed mode; skip questions, inspect attempts, and retry only missed words. Completed results are stored locally. Answered words count toward the daily practice goal; skipped questions do not. Compact practice records remain after the 100-round results limit, so calendar activity does not disappear. Exams never update the review schedule. Unfinished rounds stay available while the app remains open.
- **Examples**: select up to eight bilingual entries, a topic, and an English level. Generate sentences, Chinese translations, and explanations in a reading column beside your word selection. Hide words for recall, reveal each answer, toggle Chinese, listen, copy, or save an example to its word. Replacing an existing example requires confirmation. New sentences use a different situation from the current set. The latest 100 generated sets and completed exams are saved on this Mac.

Keyboard shortcuts: Command + N adds a word; Command + 1–5 opens Today, Library, Review, Dictation, and Examples; Command + comma opens Settings. In Review, Space reveals, 1–4 rates, Return selects Good, and Escape pauses.

## AI configuration

In Settings → AI services, add a preset, enter an API key in the secure field, and test the connection. Saving keys uses macOS Keychain. Configurations contain a key reference, never a plaintext key. Provider selection is explicit; requests do not automatically fail over to another service.

MiniMax is the first preset, with domestic and global variants of both protocols:

| Protocol | Domestic base URL | Global base URL |
| --- | --- | --- |
| Anthropic Messages | `https://api.minimax.cn/anthropic/v1` | `https://api.minimax.io/anthropic/v1` |
| OpenAI Chat Completions | `https://api.minimax.cn/v1` | `https://api.minimax.io/v1` |

These presets use `MiniMax-M3`, a 90-second timeout, and an 8,192-token output budget to accommodate thinking models. The model menu also includes `MiniMax-M2.7` and `MiniMax-M2.5`; model IDs and URLs remain editable to match the account. Other supported formats are OpenAI Responses, Gemini Native, and Ollama. An exact endpoint option supports custom gateways. HTTP is allowed only for loopback services. Requests have configurable timeouts and output limits, with cancellation and actionable HTTP error messages. Generation uses non-streaming responses; thinking blocks are excluded from displayed text.

Selected headwords, meanings, topic, level, and the current examples for those words (when generating a new set) are sent. If example validation fails, one correction request includes the failed response and validation feedback. Authentication, network, and output-budget errors are never automatically retried. The word library, review logs, source notes, and credentials from other apps are not sent. A connection test sends a short prompt. Returned examples are checked for one complete item per selected word and the actual occurrence of that word or a normal English inflection in its sentence, using macOS Natural Language lemmas. Phrases are matched exactly. Partial responses are rejected; usage and elapsed time are shown when available. Content quality still depends on the configured model.

References: [MiniMax model invocation](https://platform.minimax.cn/docs/guides/text-generation), [MiniMax Anthropic compatibility](https://platform.minimax.cn/docs/api-reference/text-anthropic-api), [CC Switch provider configuration](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/2-providers/2.1-add.md).

## Translation and dictionaries

Vord includes a read-only [ECDICT](https://github.com/skywind3000/ECDICT) SQLite dictionary: 768,739 bilingual headwords, 159,012 English definitions, and 56,927 inflection aliases. English input automatically loads the full dictionary entry; Chinese meaning keywords search a local full-text index and present English candidates to choose before saving. Unambiguous dictionary inflections resolve to their base word in Chinese searches, while independent entries and English exact lookups remain intact. The Add page previews both definitions. Option+Space also supports selecting Chinese reverse-lookup results. Saving waits for a resolved entry rather than silently creating a word without its meaning.

Known words use the dictionary first, regardless of the fallback translation setting. Apple Translation uses installed English/Chinese resources for words outside the dictionary and can ask macOS to download them. English definition coverage varies by word; installed macOS dictionaries supplement missing definitions when available. A translation-only result is not presented as an English definition.

The bundled database is approximately 168 MB and requires no separate download or internet connection at runtime. Its source version and checksums are recorded in `Vord/Resources/dictionary-info.json`; the MIT attribution is included as `ECDICT-LICENSE.txt`. Rebuild it with `python3 Scripts/build_dictionary.py` (network needed only to fetch the pinned source and license). Custom imported entries override matching built-in headwords.

Import a JSON array in Settings → Dictionary → Offline dictionary. See [Examples/dictionary.json](Examples/dictionary.json). Each object needs `english` and `chinese`; phonetic, part of speech, English definition, and example sentence are optional. Imports merge by normalized English headword, persist atomically, and invalidate lookup caches. Duplicate headwords inside a file or missing bilingual fields reject the import without changing the installed dictionary. Limits: 50 MB / 100,000 entries. macOS Dictionary definitions are read separately from dictionaries enabled in Apple's Dictionary app; they are not automatically treated as Chinese translations.

Words with missing bilingual meanings are retained in Library → Needs meaning and excluded from review/exams. Add a meaning manually or use Refresh Translation in the detail page.

## Selected-word integration

Vord advertises the macOS service **快速添加到 Vord** and registers `vord://capture?text=...&source=...`. Install the application in `Applications` (including `~/Applications`) and open it once. In an app that supports macOS text services, select a short English word/phrase, then use Services → 快速添加到 Vord (often also under the right-click menu). If hidden, enable it in System Settings → Keyboard → Keyboard Shortcuts → Services → Text. Services cannot add the same menu to apps that do not participate in macOS Services.

For a direct Chrome/Edge page context-menu entry, use **Settings → Capture → Selection & browser**, choose Chrome or Edge, then click **Set up browser**. This installs an exact-origin native messaging manifest for this extension and copies its files to `~/Library/Application Support/Vord/BrowserExtension`. Load that folder through `chrome://extensions` or `edge://extensions` → Developer mode → Load unpacked. This is a local development extension, not a Web Store listing. The fixed public manifest key keeps its ID stable across updates; the native host accepts only that origin. If Vord is moved, run Set up browser again to update its location.

The extension requires `contextMenus`, `nativeMessaging`, and `storage`, with no host permissions or content script. It receives a selection only when the menu is clicked and passes that word and its source URL to a helper inside Vord.app. The helper bounds inputs, uses framed native messaging, and explicitly opens its owning app; it cannot execute arbitrary commands or read the library. Source URL query parameters and fragments are removed. The word opens in Quick add with definitions; Return saves and Escape closes. Saving records the source and retains normal duplicate-headword merging.

Builds compile a universal native helper and include the extension folder automatically via `Scripts/build_integrations.sh`. The protocol is defined in `ExternalCaptureRequest.swift`. Run `node Scripts/test_browser_extension.cjs` for worker, identity and error-feedback checks.

References: [Apple Services](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html), [Chrome context menus](https://developer.chrome.com/docs/extensions/reference/api/contextMenus), [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

## Optional library sync

Settings → Sync & backup can connect this Mac to a compatible Vord sync server using a private pairing JSON or server URL and sync code. Credentials remain in Keychain. The app stays fully usable offline; configuration does not connect until pairing is supplied. Changes queue durably, synchronize after edits and foreground activation, and poll every three seconds while active / every minute in the background. Words, definitions, archives, both review directions and review logs sync; dictionaries, AI keys, appearance and assistant conversations stay local. See [protocol](Docs/SyncProtocol.md).

## Appearance and updates

Settings → Learning → Daily practice sets a goal of 1–100 different words per day (default 10). Review and answered questions in completed dictation rounds count once per word; adding or importing words does not fill the goal. The daily goal and streak are calculated from real records, with no lost-streak penalty before today is finished. Exam activity stays local with learning history.

Settings → Appearance → Sidebar icons switches between textured cream-paper/graphite Sculpted icons and the original Outline icons. The Icon size slider continuously adjusts either style from 12 to 36 points, updates immediately and remembers its value. Transparent icon bodies use native silhouette shadows that react gently to hover and selection, with separate light/dark rendering. The optional Subtle wood grain background adds stationary, very low-contrast irregular fibres to the outer window background without changing its colour; the content panel remains plain; it is off by default. Reduce Motion and Reduce Transparency are respected.

Settings → About shows the installed version and checks [GitHub Releases](https://github.com/Yhazrin/Vord/releases). Automatic checks run at most once daily; Check now is always available. A newer stable release offers its macOS download. This version does not replace its own application bundle automatically. Release packages currently use local ad-hoc signing, not Developer ID signing or notarization.

## Local data and backup

Files in `~/Library/Application Support/Vord/`:

- `library.sqlite`: words, per-direction review schedules, and review logs; SQLite WAL transactions protect related writes.
- `dictionary.json`: imported offline dictionary.
- `learning-history.json`: generated context sets and completed exam results.
- `speaking-materials.json`: personal speaking materials, original text uploads and speaking self-reports. Materials has its own JSON export.

Settings → Export Library creates `vocabulary.json` containing words (including archives), review states, and review logs. Import Library Backup adds missing entries and their schedules/history in one transaction. Existing IDs or matching English headwords are skipped, so re-imports are safe and existing learning progress is retained. This library export does not include AI configurations, API keys, dictionaries, or the separate context/exam history files; back up those files separately if needed.

## Build and validation

```sh
python3 Scripts/build_dictionary.py
xcodebuild -project Vord.xcodeproj -scheme Vord -configuration Debug -derivedDataPath build build
xcodebuild -project Vord.xcodeproj -scheme Vord -destination 'platform=macOS' -derivedDataPath build test -skip-testing:VordTests/SyncHTTPIntegrationTests
xcodebuild -project Vord.xcodeproj -scheme Vord -configuration Release -derivedDataPath build build
```

If Xcode is not the active developer directory, prefix with `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

Tests cover protocol payloads/authentication/endpoints, HTTP transport, response parsing, AI example validation, scheduler behavior, precise due dates, repeated recall, failed saves, atomic rollback, exam isolation, dictionary imports, history persistence, and idempotent library restoration. Opt-in live checks on 2026-10-02: M3 passed both domestic Anthropic and OpenAI-compatible generation, including eight words with Anthropic; M2.7 and M2.5 passed three-word Anthropic generation. These checks do not establish availability of all models or global endpoints. Routine tests use fixtures and make no paid API calls.

For a universal package, build Release with `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`, then run `bash Scripts/package_release.sh`. Release output: `build/Build/Products/Release.noindex/Vord.app`. This development build is locally signed; public distribution still needs Developer ID signing and notarization.
