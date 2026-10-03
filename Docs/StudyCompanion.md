# Study companion and global capture

The macOS Companion uses the same local vocabulary and recorded review data as the main learning screens.

## macOS

- **Option + Space**: morph the draggable screen-edge glass orb into Quick Add. Dictionary definitions appear immediately under the word, and long definitions scroll. Return saves; Escape closes. A successful save briefly displays confirmation and returns focus to the previous app.
- **Settings → Capture**: show or hide the glass orb, and opt into clipboard suggestions. Clipboard suggestions are off by default. Vord examines only new clipboard changes after enabling the setting, accepts a single English lexical form and validates it in the offline dictionary. It skips password/transient markers, URLs, paragraphs and existing words. A suggestion never saves automatically or calls an AI provider. Dismissal is remembered until the clipboard changes again.

The panel transitions use damped physical springs with a fixed anchor, short settling times and a small overshoot. The small capture panel retains velocity when a transition reverses. Reduce Motion skips frame morphs and simplifies content feedback. Compact panels do not take keyboard focus; opening an input is an explicit action.

## Grounded conversation

The selected AI service in Settings powers both contextual examples and the companion. MiniMax remains supported through the existing OpenAI/Anthropic-compatible adapters. Each message refreshes the local SQLite snapshot first; synced Mac/Android reviews are included once they reach that device.

The context includes exact whole-library counts, distinct due words, due directions, today's reviewed words, recorded mistakes, recent ratings and a bounded sample of relevant words and their independent direction states. The sample limit is explicit. The companion is instructed to distinguish recorded self-assessment from evidence of mastery, and to treat definitions, draft answers and notes as study data. It can explain meanings, compare words, create short contextual material and conduct conversational recall practice.

An AI's textual grade or suggested plan does not record a review or change the schedule. Stop cancels a pending response; failed questions remain available to retry. Provider credentials remain in the platform's protected credential store and are not sent as study context or synced.

## Importing vocabulary on macOS

Use **Library → Import words** or **Companion → Import words** to paste a word list or an English passage, or open a UTF-8 text/CSV/Markdown/JSON file. Alternatively, paste the material directly into the conversation and ask to add it, including words discussed in earlier messages. A message supports up to 16,000 characters; the import sheet supports 15,000. The configured AI service receives the supplied text and returns up to 50 proposed words with Chinese and English definitions. The offline dictionary enriches pronunciation, word class and definitions without another AI request.

The assistant reply includes a native editable list. Select the words to keep, correct English or Chinese fields and click **Add N words**. Only that action writes entries. Original sentences are retained only if they occur in the supplied conversation material. Existing words, including archives, are skipped without overwriting personal notes or review history. Checking duplicates and inserting a new entry share a database transaction; successful additions trigger normal library sync. Each result is stored in the conversation, so failed rows can be retried without duplicating completed rows. Extraction failures do not write anything.

## Plans and practice

The Plan tab builds a seven-day preview locally, without requiring AI. It assigns eligible active words on or after their earliest due day, prioritises overdue and recorded weak words, and caps each day at the chosen target (5–60 words). It schedules each word once within that preview, rather than pretending to forecast how the user will rate future answers. Words beyond the week's capacity remain due in the normal review flow.

Adopting the preview saves a local plan without rewriting the memory curve. Today's Start action reviews its remaining eligible words. An explicit Again rating keeps that word unfinished; successful recall marks it completed for the planned day. Archived/deleted words are excluded. Unfinished words carry into the next planned day within the daily target; Again does not mark completion. Starting a plan refreshes the word states and excludes reviews that are not due yet. A new preview uses current review data rather than recycling stale completion statistics.

Companion’s Practice tab draws random eligible words, preferring due words and avoiding the immediately preceding word when there is a choice. Drawing, skipping, typing and revealing are practice actions. Only the four explicit rating buttons record a review, using the same scheduler and repository as the main review screen. The model checks that the word still exists and has not changed before saving, and prevents duplicate ratings for the same direction in that draw.

## Looking up words inside examples

In Examples, Review sentences and Library examples, select a single English word to open a native dictionary popover. Right-click selects the word under the pointer before showing its meaning. English contractions, hyphenated words and Unicode apostrophes are handled in UTF-16 coordinates, including sentences containing emoji. Multiple-word selection retains standard Copy. Keyboard users can select a word and press Return to look it up.

The popover shows Chinese and English definitions, with scrolling for long entries and an explicit Add word button. Saving retains both definitions and the source sentence. Existing library words are indicated and not overwritten. Looking up a word does not add it or grade a review. Closing or replacing a lookup invalidates stale results. Main review shortcuts yield to reading selections and the dictionary popover.

## Persistence boundaries

Words, definitions, both review directions and review logs continue to sync through the existing private library server. Assistant conversation and adopted plans are currently saved **on each device**, not shared between Mac and Android. The macOS Companion stores `~/Library/Application Support/Vord/assistant.json` (up to 60 recent messages, import previews/results and the adopted plan). Library JSON backup does not include this file.

## Validation

Deterministic tests cover full counts versus bounded context, archived and missing-meaning exclusions, priority/due-date planning, capacity, unchanged schedules from chat/planning, explicit review writes, duplicate and stale-word protection, conversation/plan reopening, cancellation/retry paths, clipboard gating and interrupted spring behaviour. The opt-in macOS `AgentLiveIntegrationTests` calls the configured provider with a disposable in-memory word; ordinary tests do not consume AI tokens.

The former camera-notch study panel has been removed; global capture is provided by the screen-edge orb.
