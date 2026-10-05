# Speaking materials

Examples has two sections: **Materials** and **Generate examples**. Materials contains 26 original offline starter examples. These cover direct answer/reason/detail, adaptable stories, comparison and cause/effect, useful collocations, paraphrasing and targeted corrections. They are learning examples, not official model answers or score guarantees.

- Add/edit a phrase, sentence, story, argument angle or correction with its topic, question, Chinese meaning and usage notes. Editing a starter creates a local override.
- Import UTF-8 TXT/Markdown (English first line, optional Chinese below, blank line between blocks; `English = Chinese` also works), or a JSON material pack. Preview and edit candidates before saving.
- **Analyse with AI** sends the entered source to the currently selected provider. Long notes up to 60,000 characters are processed in chunks, up to 20 candidates per chunk. Cancellation or a failed chunk never saves partial items. Saving is explicit. Exact supporting excerpts are checked against the source; corrected examples are labelled AI adapted. Original uploads remain local.
- Collect a generated example into Materials without replacing the word's existing sentence. A material's selectable English also uses the existing in-app dictionary/add-selection interaction.
- Practise from the question before revealing the reference. Part 2 offers 60 seconds preparation and 120 seconds speaking; other parts use shorter exercises. The countdown does not record anything automatically. Explicit Recalled / To revisit controls store a self-report, answer/note, elapsed exercise time and whether the reference was viewed. No microphone capture or inferred pronunciation score.
- Discuss moves a question or answer into Companion's draft while retaining any existing unfinished draft. Sending remains explicit. Companion receives a bounded sample of real materials and recent speaking self-reports; these are kept distinct from vocabulary ratings.
- Export a portable JSON pack containing materials and original documents. Practice history remains local and is not imported as new practice evidence.

Storage: Application Support/Vord/speaking-materials.json, with atomic saves and a fail-closed warning for unreadable existing files. This is separate from vocabulary SQLite and the current vocabulary-only sync contract. Personal lesson transcripts are not bundled in public source.

## Validation

Focused tests cover offline starter identity, bilingual import/export with original text, duplicate prevention, ID collisions, edited starter persistence, failed/corrupt storage, source-reference integrity, schema validation, AI source verification, long-source chunking, cancelled analysis, Companion context/draft preservation and unchanged vocabulary review schedules.

Native runtime acceptance still needs: installed-app relaunch, wide/narrow Materials layout, file chooser and editable preview, timer/reference/save controls, existing generation screen, and Companion draft handoff. ScreenCaptureKit failure is not visual acceptance.
