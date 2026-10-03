# Vord motion

Motion connects navigation, capture and recall. The interface stays monochrome, keyboard-first, and ready for the next action while animations are running.

| Moment | Behavior | Timing |
| --- | --- | --- |
| Sidebar navigation | One background pill travels between the selected rows, briefly compressing and settling | 300 ms |
| Sidebar / content expansion | Low-bounce native spring; the rail keeps a stable internal width during the resize | 380 ms |
| Page entry | Incoming content fades and moves 6 pt; old content is removed immediately so keyboard monitors are released | 160 ms |
| Buttons / input focus | Small press compression; focus border changes smoothly | 160–240 ms |
| Dictionary entry / candidate list | Short incoming reveal, without delaying lookup or save | 160 ms |
| Glass orb / Quick Add | A circular draggable shell with damped internal refraction, docking to either screen edge; expansion retains spring velocity when interrupted | Short damped springs |
| Word saved | Word-specific confirmation with a drawn check; input clears and regains focus immediately | 240 ms; confirmation remains 2.4 s |
| Review / dictation | Answers reveal softly, next cards replace promptly, real completed counts advance a spring progress indicator | 160–240 ms |
| Session completed | Drawn check and a completed progress line; results and next actions remain accessible | 240 ms |

Success feedback follows confirmed persistence. A failed save keeps the input/card and shows the error. “Again” acknowledges a saved review with “We'll revisit it.” and does not celebrate recall. Queued retries stay incomplete; after the existing retry limit, the session counts the card as processed while its next review remains due in 10 minutes. Dictation finishes acknowledge the round, with separate correct/missed results.

Capture fields acquire native keyboard focus after joining a key window, including when reopening the retained quick-add panel. Return confirms an active Chinese input-method composition before it can submit a word. Tab keeps the native editing behavior.

SwiftUI uses `accessibilityReduceMotion`; AppKit uses `accessibilityDisplayShouldReduceMotion`. Reduced motion disables movement, deformation, count transitions, animated resizing and press scaling while keeping all status text, focus and progress values. Animations use native rendering and finite event-driven sequences, with no external library, sounds, background particle loops or delay in the learning scheduler.

Implementation uses Apple's [keyframe animator](https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)) and [Reduce Motion environment](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).
