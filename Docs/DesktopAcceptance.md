# Desktop product acceptance

The target is a dependable macOS vocabulary product: working features, clear layouts, useful learning motivation, smooth motion and convenient interaction. Android is paused. A build or a unit test does not establish visual or motion acceptance.

## Current evidence

| Area | Required outcome | Evidence | Remaining acceptance |
| --- | --- | --- | --- |
| Daily practice | Configurable 1–100 distinct words; imports and skipped answers excluded | StudyActivityTests: persistence, clamping, review/exam deduplication, future records, local dates and DST | Installed UI and practice navigation |
| Long-term activity | Activity survives the 100-round detailed exam limit and relaunch | StudyActivityTests: 101 completed rounds, reopen, all 101 word identities retained | Normal use over time |
| Review and dictation | Recall, repeated attempts and exam isolation still work | 33 selected tests passed in `build/practice-agent-tests.log`; includes LearningAgentTests, StudyActivityTests, DictationTests and LearningFlowTests | Native keyboard walkthrough without modifying the user's real review schedule |
| Library | Functional toolbar, dense table, search and unobscured dates | Current source reserves a separate scroller content margin; running UI exposes 25 word rows, search, filters and import | Clear visual capture at regular, minimum and full-screen sizes |
| Navigation | Redundant page names removed; active location and meaningful controls remain | Native Library → detail → Library and Command+1 navigation observed | All destinations, collapsed rail and full-screen sidebar |
| Dictionary/capture | Offline bilingual lookup, Chinese candidates, in-app selection and compact shortcut window | Existing implementation and test suites remain in the tree | Current installed application walkthrough |
| AI/import | Selected provider, grounded study context, editable import preview and explicit write action | LearningAgentTests confirms that real dictation activity and the current goal reach the context without sending AI requests or changing reviews | Current configured provider and import walkthrough |
| Appearance/motion | Quiet monochrome, grain on outer chrome, plain content panel, configurable icons, reduced-motion support | Existing design tokens and spring implementations; shared expanded-page inset protects the sidebar control | Light/dark rendering and motion observation on the installed app |
| Data/update | No data loss; export/restore, immediate sync and release checks remain usable | Existing repository, sync and release-check suites | Focused current verification and installed version confirmation |

## Evidence limits

- Native accessibility observations establish exposed controls and their actions, not frame rate or visual alignment.
- A captured window thumbnail that is distorted or too small is insufficient visual evidence.
- No test should add disposable words or submit review ratings into the user's live library. Use isolated repositories for writes.
- Full acceptance remains open until the remaining checks above have direct evidence; a successful build alone must not close it.

## Latest installation and runtime

- The daily-practice universal Release built successfully and was installed at `~/Applications/Vord.app`; the bundle passed `codesign --verify --deep --strict`.
- After installation the exact installed executable was observed running.
- The native capture connection failed with ScreenCaptureKit `-3811` even after the user confirmed the Mac was unlocked and the computer-use session was reset. The new daily-goal interface, full-screen layout and motion remain unverified at runtime. Do not describe them as visually accepted.
