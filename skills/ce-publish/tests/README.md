# ce-publish golden drops

Each folder is a drop as it would sit in Drive. `expected.md` states what
`ce-publish` must do when pointed at it — a block plan, or an error list.

How to run one (Claude Code, no platform writes happen for 03–06 by design;
01, 02, 07 stop at the block-plan confirmation — answer "no"):

1. Copy the fixture folder into a scratch Drive drop path, or point the skill
   at the local folder (the skill accepts a local path for dry-runs).
2. Invoke: `/ce-publish drop=<path>`.
3. Compare the skill's output with `expected.md`. Pass = every line of
   `expected.md` is satisfied.

Fixture 07 references article id `999999`; in a dry-run the skill will report
"id not found → create mode" — that is the expected outcome offline.
