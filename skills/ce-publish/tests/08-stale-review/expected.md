# Expected

Setup (git does not keep mtimes): before running, make the markdown newer than the review:
`touch -t 202609010900 review.md && touch 08-stale-review.md`

- review.md present, verdict pass — but 08-stale-review.md is newer than review.md.
- Skill stops at the gate with the stale message, naming both timestamps.
- Message names the next step: re-run ce-review, then publish. Mentions `force: true` as the recorded override.
- Body is NOT parsed; no block plan; nothing written.
