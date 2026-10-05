# Desktop product acceptance

The target is a dependable macOS vocabulary product: working features, clear layouts, useful learning motivation, smooth motion and convenient interaction. Android is paused. A build or a unit test does not establish visual or motion acceptance.

## Current evidence

| Area | Required outcome | Evidence | Remaining acceptance |
| --- | --- | --- | --- |
| Daily practice | Configurable 1–100 distinct words; imports and skipped answers excluded | StudyActivityTests: persistence, clamping, review/exam deduplication, future records, local dates and DST | Installed UI and practice navigation |
| Long-term activity | Activity survives the 100-round detailed exam limit and relaunch | StudyActivityTests: 101 completed rounds, reopen, all 101 word identities retained | Normal use over time |
| Review and dictation | Recall, repeated attempts and exam isolation still work | 33 selected tests passed in `build/practice-agent-tests.log`; includes LearningAgentTests, StudyActivityTests, DictationTests and LearningFlowTests | Native keyboard walkthrough without modifying the user's real review schedule |
| Library | Functional toolbar, dense table, search and unobscured dates | Separate scroller content margin; 4 focused tests cover removed/retained tags, time-based due filtering without schedule writes, and full-definition search | Current keyboard shortcuts and clear visual capture at regular, minimum and full-screen sizes |
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
- The Library follow-up passed 4 focused tests (`build/library-efficiency-tests.log`), built a universal Release (`build/library-efficiency-release.log`) and was installed with a verified signature. It adds Command+F search, Return to open the first nonempty search result, Escape to clear, and Command+[ to return from details (disabled while editing or saving).
- Finder accessibility and screenshot capture worked during the latest retry. Opening the installation directory then failed with `Sky Computer Use native pipe closed before response`. Resetting the connection allowed one Vord accessibility observation; Today exposed the daily goal (0/10), 2-day streak and practice action.
- The installed application was restarted through native UI; a new process at the installed executable path was confirmed. Subsequent window observations and keyboard walkthroughs failed with ScreenCaptureKit `-3812`. Shortcut behavior, visual layout and motion therefore remain open, despite the successful restart and model tests.


## October 4 desktop follow-up

Product direction is practical innovation: capture during reading, keep original context, and make recall easier. Decorative changes should serve that flow.

- Native Library walkthrough: Command+F searched `stagnant`, Return opened its detail, Command+[ returned, and Escape cleared the search. Clear regular and full-screen captures showed the dense table and dates without the scroller covering them. Full-screen automatically hid the sidebar and exposed its restore control. Minimum-size and dark-mode checks remain open.
- Native Add walkthrough: `plight` loaded offline bilingual definitions and an example; Chinese `缓解` produced candidates. The reverse lookup now resolves explicit, unambiguous inflections to base entries such as `alleviate` and `relieve`, retains the original matching gloss for ranking, and preserves independent entries such as `meeting`. Sixteen DictionaryFlowTests passed in `build/reverse-lookup-tests.log`. Long example input supports up to six visible lines; its latest multiline rendering remains to be checked.
- Native review walkthrough: entered practice, used Space to reveal an answer and its rating intervals, and paused with Escape. No rating or test word was written to the user's library.
- Thirty-three repository/dictionary/selection/sync/release tests passed in `build/desktop-core-acceptance.log`. Twenty-six capture/clipboard/orb/dictionary tests passed in `build/orb-capture-tests.log`; these ran before the final native glass and event-handoff changes. The final universal Release built in `build/liquid-orb-release.log`, was installed at `~/Applications/Vord.app`, and passed strict signature verification.
- Quick Add runtime: Option+Space exposed the input as focused; typing `plight` without clicking the field loaded bilingual definitions. Escape collapsed it. Clicking the collapsed orb and immediately typing `stagnant` preserved the complete word after the event-handoff fix. No entry was saved. Captures confirmed the compact result view and removal of the empty-state/footer guides.
- Orb runtime: the plus and drawn flow lines are removed. macOS 26+ uses public `NSGlassEffectView` with `.clear`, supplemented by broad spherical reflection and edge shading; earlier systems retain a material fallback. Two vertical eyes remain. The final collapsed-window screenshot was captured. Detailed motion/frame-rate and changing desktop-background behavior are not established by this still image.
- Earlier ScreenCaptureKit failures were intermittent; native observations worked for the walkthrough above. Do not treat those previous failures as current proof that all visual acceptance is blocked. The full product acceptance remains open for the outstanding items in the table.


## Capture refinement and softer orb edge

- Removed the supplementary dark/white concentric ring from the orb. A radial mask feathers only the outer 2.2 points of the native lens, with a lighter, broader contact shadow. The central native glass, moving light sources, eyes and fixed circular drag shape remain.
- Pointer proximity shifts the eyes and reflected light slightly; Reduce Motion disables this tracking displacement. Native tracking does not change the sphere silhouette.
- Quick Add includes the actual dictionary phonetic and a pronunciation button. Result height follows measured definition content (180–420 points, scrolling beyond the cap); an in-progress query retains the current height rather than repeatedly collapsing it.
- Chinese candidate selection supports Up/Down with a highlighted row that scrolls into view, and Return or Add selected explicitly saves that candidate. IME marked text retains its own Up/Down/Return handling. Normal editing retains arrows when there are no candidates. Merely selecting a candidate does not write to the repository.
- Nineteen focused tests passed in `build/capture-refinement-tests.log`, including isolated candidate selection/save, IME and normal-editing arrow handling. Final universal Release passed in `build/orb-soft-edge-release.log`; installed at `~/Applications/Vord.app`, strict signature verified.
- This installation's native visual check remains pending: ScreenCaptureKit returned `-3811` for Vord and subsequently Finder. The failures do not establish an application layout defect, nor do passing model tests prove the edge, adaptive layout or pointer response looks correct. The installed UI must still be inspected when capture is available.


## Live lens composition follow-up

- The supplementary edge feather mask has been removed in response to the frosted appearance. The native glass surface now sits outside the animated overlay's clip and the shell's clip/shadow passes. Only the decorative light and eyes are clipped; their artificial white reflections are reduced.
- macOS 27+ enables public `NSGlassEffectView.effectIsInteractive`, unless Reduce Motion is enabled. The native pointer view is now the glass's `contentView`, with decorative SwiftUI content ignoring input, so actual pointer events stay inside the interactive glass hierarchy. The panel host and pointer content explicitly report nonopaque backgrounds. macOS 26 keeps the native clear lens without this newer AppKit interaction property; earlier systems retain the visual material fallback.
- This uses the operating system's optical effect, not a custom desktop-capture shader. Public API does not expose an arbitrary refraction-strength/IOR setting; background distortion strength and material response still require direct desktop observation. No new screen-recording access is requested.
- Universal Release built successfully in `build/orb-live-glass-release.log`. Native observation again failed with ScreenCaptureKit `-3811` for both Vord and Finder, including after reconnect. Do not claim the user's desired dynamic lens strength has been visually accepted. A running older process requires relaunch to use the installed change.


## Orb contraction and expression follow-up

- Closing has its own transitional state: the expanded rounded surface follows actual native window dimensions, rounds into the final 56-point lens bounds and yields to the glass late in the contraction. The lens stays in the same view hierarchy when contraction completes. The opening spring remains unchanged; closing damping increases from 0.82 to 0.94 to reduce undershoot. Reopening replaces the previous completion callback, and repeated close requests do not restart the morph.
- The two eyes now use continuous stroked paths for natural double blinks, a brief return blink, slight drag squint/tilt and a short happy arch after a successful save. Reduce Motion keeps expressions static.
- Thirteen focused OrbGeometryTests and ClipboardCaptureTests passed in `build/orb-collapse-face-tests.log`. They cover morph endpoints and monotonicity, the shorter saved banner, bounded closing undershoot, expression timing and existing clipboard/spring behavior. Universal Release built in `build/orb-collapse-face-release.log`; installed at `~/Applications/Vord.app` with strict signature verification.
- The previous application exited through native UI and the newly installed executable was observed running. Its Today accessibility tree was retrieved. The keyboard walkthrough did not establish that Quick Add received the shortcut; screenshot capture returned unavailable, and the following native action failed with ScreenCaptureKit `-3812`. The contraction, expression appearance and interrupted reopening remain pending direct visual acceptance. No word or review rating was saved during this check.


## October 5 companion orb integration

- Enlarged the two eye strokes from 3.1 to 4.2 points and their neutral length from 8.8 to 11.6 points. The native lens keeps its 56-point diameter and circular drag silhouette.
- Companion now reserves a 72-point anchor beside its metrics. The same native panel, not a duplicate mascot, travels between this anchor and the saved desktop edge. Anchor screen coordinates update after layout and window move/resize notifications. Inactive, minimized, offscreen, hidden, occluded and sheet-covered anchors are excluded. Manual drag-out stays detached until a deliberate drop/rejoin or the next page visit. Desktop visibility still follows the existing setting.
- Travel uses the native spring and ignores mouse events while moving; it never activates the app or takes first responder. Explicitly clicking the embedded orb selects Conversation and requests composer focus. Existing Quick Add keyboard focus remains owned by the capture panel.
- Agent thinking/import state and Practice selection set subtle gaze poses. New assistant replies, actual imported-word increments and completed practice increments acknowledge success through the existing brief smile. No automatic messages, ratings or data writes were introduced. Reduce Motion keeps expression/gaze static and makes native placement immediate.
- Twenty-seven focused OrbGeometryTests, ClipboardCaptureTests and LearningAgentTests passed in `build/companion-orb-tests.log`; geometric tests cover translated/negative screen positions, fixed circle dimensions, near/far drop acceptance and bounded/static activity gaze. These tests do not establish actual native anchor alignment or keyboard focus. Universal Release built in `build/companion-orb-release.log`, was installed at `~/Applications/Vord.app` and passed strict signature verification.
- The previous collapsed orb's accessibility state and still screenshot were retrieved, then the old app exited through native UI. The newly installed executable was observed running. Reconnection timed out twice; after resetting the native bridge it failed with ScreenCaptureKit `-3811`. The new eye appearance, actual window/page handoff, composer click, sheet/minimize/full-screen behavior and motion observation remain unverified. No test message or word was submitted to the live application.


## Companion draft and sheet handoff follow-up

- Moved unfinished composer text from the transient conversation view into the shared LearningAgent session. Only accepted explicit sends clear it; oversized input and the following draft survive rejection/busy replies, profile refresh and plan preview. It remains excluded from persisted assistant history and unrelated request context. Twelve LearningAgentTests passed in `build/companion-draft-tests.log`, including the new rejection/next-draft regression test.
- Sheet notifications now latch the anchor's covered state at `willBeginSheet`, before AppKit necessarily sets attachedSheet, and release it at `didEndSheet`. This closes an ordering gap that could leave the floating orb above the import sheet.
- Finder accessibility worked during this follow-up. Opening the exact installed application through a fresh Finder window exposed the main Vord window; Companion navigation and a clear main-window screenshot were retrieved. The page kept its metrics, controls and composer. Its rejoin button was absent, consistent with the controller selecting the embedded state, but the separate orb panel was not present in the captured main-window image. This is insufficient evidence of actual orb alignment or successful handoff.
- Subsequent native window-menu actions returned stale element IDs, screenshots became unavailable, and the Finder reconnection ended with `Sky Computer Use native pipe closed before response`. Actual orb eye appearance, click-to-compose, travel, full-screen, drag and sheet handoff remain pending. No live word, review or AI message was submitted.
- Universal Release succeeded in `build/companion-draft-release.log`; installed at `~/Applications/Vord.app`, strict signature verified. The previously running process was retained because the native UI connection could not reliably quit/relaunch it. A normal application restart is still needed to load this latest draft/sheet patch.

## Continuous closing silhouette and expression refinement

- The closing lens now shares the paper surface's actual bounds and corner radius throughout contraction. The opaque surface yields to native glass over the same silhouette, rather than revealing a separate fixed-size sphere inside a shrinking rectangle. The native glass itself is no longer faded by SwiftUI in this handoff. Its end bounds remain 56 × 56 inside the 72-point panel. Geometry updates disable implicit SwiftUI animation so they follow the native frame spring directly; opening spring behavior is unchanged.
- Eyes appear late in the contraction. Closed eyes widen into short curved lids, with a 25 ms stagger between the two blinks. The success smile has smooth attack/release and a small 0.8-point lift; native pointer tracking also updates hover expression. Reduce Motion retains a neutral static face.
- Eighteen focused OrbGeometryTests and ClipboardCaptureTests passed in `build/orb-continuous-morph-tests.log`. Tests cover shared silhouette bounds, material handoff before settle, short success banners, expression continuity and reduced-motion behavior. Universal Release succeeded in `build/orb-continuous-morph-release.log` and was installed at `~/Applications/Vord.app` with strict signature verification. These checks do not establish visual fluidity or frame rate.
- The installed draft/sheet patch's earlier process was observed with a new start time (PID 43199, 02:20:41), confirming that the preceding app restart occurred. This latest morph installation still requires another application restart. Native capture returned ScreenCaptureKit `-3811` for Vord, again after resetting the computer-use session, and for Finder. Actual contraction, glass sampling and facial appearance remain pending direct observation; no live vocabulary or AI request was submitted.

## Passive edge docking and remaining goal gates

- After a released drag, the orb panel now passes mouse events through while the spring moves it to the desktop edge, restoring hit testing at completion. Automatic Companion travel already used the same behavior. Explicit opening or another drag cancels the old spring completion and restores interaction through the existing controller paths. No application activation or keyboard-focus request was added to passive docking.
- Universal Release succeeded in `build/orb-passive-dock-release.log`; the installed `~/Applications/Vord.app` passed strict signature verification. The existing focused geometry, clipboard and agent test results cover their respective logic, but do not prove native click-through, page alignment or visual appearance.
- Continued native observation again failed with ScreenCaptureKit `-3811`. App inventory confirms Vord is running; the observed PID 43199 predates the latest installations. Final goal acceptance still needs a relaunch plus direct observation of larger eyes, native page/desktop handoff (including minimize/sheet/full-screen), explicit click-to-compose focus, and noninterference during travel. Capturing only the main window or observing controller flags cannot close these gates.

## Enlarged eyes and face-mask correction

- The face/optics overlay previously applied a circular clip to its small intrinsic bounds, which cut the eyes into thin slivers. The overlay now takes the full lens bounds before clipping. Eye strokes increase from 4.2 to 6.2 points; neutral end-to-end height increases from 15.8 to 20.8 points, with a 34 × 24 face region, slightly wider spacing and proportionate closed/happy curves. Expression timing and the native lens itself are retained.
- Universal Release succeeded in `build/orb-face-mask-release.log`, installed at `~/Applications/Vord.app` and passed strict signature verification. The old app quit through its native Quit menu; a new installed process (PID 46087, 02:46:03) was observed. Native window capture recovered after an initial reconnect timeout.
- Temporarily minimizing the main window exposed the actual 144 × 144 collapsed-panel screenshot. It shows two complete, broad, rounded vertical eyes, rather than the clipped thin crescents in the preceding screenshot. The top optical highlight is also visible. The main Today window was restored through Finder opening the exact installed bundle. No vocabulary, rating or AI message was submitted. This directly verifies the larger-eye appearance; other Companion handoff/focus gates remain open.

## Fuller orb face and speaking materials

- Orb strokes increase from 6.2 to 8.4 points and neutral end-to-end height from 20.8 to 26 points. The face region is 38 × 30, with rounded caps and proportionate blink/smile curves. The previously corrected full-lens mask remains. Universal Release build succeeded and the bundle was installed at `~/Applications/Vord.app`. Native reconnection returned ScreenCaptureKit -3811 twice; no fresh screenshot proves this iteration's appearance or relaunch.
- Examples now contains Materials and Generate examples. The new local library includes 26 original offline examples, manual editing, TXT/Markdown/JSON preview import, optional selected-provider AI analysis, original-source retention, JSON export, question-first timed speaking practice, saved self-reports and explicit Companion draft handoff. Existing unfinished drafts are retained. Generated sentences can be collected separately from their vocabulary entry.
- Focused validation: the first 25 tests (10 speaking, 12 agent, 3 translation/registry) passed. A subsequent run with cancellation and grounded speaking-context/draft tests passed all 24 speaking/agent tests. No paid live AI request, vocabulary addition or real-user rating was made for acceptance. Native file/sheet/timer/layout/handoff checks remain pending while capture is unavailable.
- Final checks: 48 selected speaking/agent/short-round/learning-flow/activity tests passed, followed by all 14 speaking tests after adding source-document collision protection (49 distinct related tests across these runs). Final universal Release build succeeded, was signature-verified and installed. Old Vord exited via its native Quit menu; the installed executable was observed running as PID 70476 after restart. The earlier orb screenshot was taken before this final restart; it is not evidence of the 8.4-point eyes. Subsequent native connections timed out and Finder capture again returned -3811. Final new-version visual acceptance remains open.
