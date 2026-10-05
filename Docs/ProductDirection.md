# Vord product direction

Vord should make a word encountered in everyday reading easier to capture,
understand, recall and use. Keep the desktop app light: each feature must remove
an existing obstacle or create a useful reason to return to learning.

## Product rules

- Start useful practice in one action. Offer small rounds alongside full review.
- Ground encouragement in recorded learning: attempts, recalled words and real
  improvements. Distinguish completing a round from remembering every word.
- Keep dictionary capture and ordinary practice local. AI is for chosen tasks
  such as contextual explanation, material extraction and conversational recall.
- Keep the monochrome interface quiet. Put optional explanations in help, use
  existing controls, and avoid extra dashboards or rewards with no learning value.
- Make progress visible without punishment for missed days. The daily goal and
  learning calendar describe activity; they do not claim mastery.
- Preserve the normal scheduler and explicit save/rating boundaries. A game,
  preview, conversation or animation cannot silently change learning history.

## Implemented iteration: short review rounds

Today’s daily-practice action offers up to five distinct, eligible due words.
Words not yet practiced on the current local day come first; within that group,
recorded weakness and overdue dates determine priority. If the daily target has
only one or two words left, the round is correspondingly shorter. After reaching
the goal, more practice remains voluntary. When no eligible word is due, the
action leads to Dictation rather than advancing a future review.

Selection refreshes against current library data on click. Review loading checks
for removed, archived, incomplete and no-longer-due entries again. A short round
asks one due direction per word. Again keeps the existing bounded in-session
retries and scheduler behavior. Only explicit ratings write review logs.

At completion, the app reports distinct words practiced, answer count, recalled
words and words still needing another look. The latest saved answer for each
asked direction determines the result. If either asked direction is still Again,
that word stays in the revisit list. These are self-reported recall outcomes, not
an automatic measurement of mastery. Choosing a new short round replaces the
current in-memory session queue; already-saved answers remain in the library.

## Next product opportunities

1. **Recall in context:** use a saved example as a short cloze exercise, retain
   its source and explanation, and keep independent practice separate from
   scheduled ratings. Give missed words a concrete place to be used again.
2. **Recover difficult words:** show recurring trouble from real review and
   dictation evidence, with a small targeted practice action. A later successful
   recall should be visible without erasing the earlier attempt.
3. **A useful weekly recap:** show unique words practiced, days of activity and
   resolved difficulties. Lead to an optional next session; avoid generic AI
   encouragement or counters inflated by repeated taps.
4. **Learn from real material:** improve the passage/word-list import preview,
   preserve useful context, and make the route from import to a manageable first
   session clear. External-source extraction remains an explicit AI action.

Deliver each as a working, tested desktop flow before expanding the surface area.
Android work remains deferred. The continuing product goal stays open; shipping
one iteration does not complete it.
