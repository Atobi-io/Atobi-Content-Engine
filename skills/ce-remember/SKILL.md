---
name: ce-remember
description: >
  Manual backstop for the content-engine learning loop — fold an operator's
  explicitly-stated content preference into brand memory, any time, any session.
  Covers feedback that never flowed through an article edit: a chat grumble, a
  next-day "the last one was too long", a standing rule ("for Hoka, titles inform,
  don't sell"). Takes an explicit statement or extracts candidates from the recent
  conversation, ALWAYS confirms before writing, appends an `insight` (history) and
  promotes directly into the brand `knowledge` playbook. Use when the operator
  says "remember that ...", "for a brand, always/never ...", "note this preference",
  or invokes "/ce-remember".
allowed-tools: search_memory, store_memory, update_memory
metadata:
  version: "0.1.1"
  phases: [delivery]
---

# Remember (content preference)

The deliberate way to teach the content engine a brand preference, decoupled from
creating or editing an article. The create skill learns from recurrence; the edit
skill learns from changes; this skill learns from the operator **saying so**.

*(Self-contained — everything needed to operate memory is inline below. The repo's
`specs/MEMORY-CONSOLIDATION.md` holds the full rationale but is **not** required at
runtime and is absent when the skill is used outside this repo.)*

## Outcome

A brand content preference recorded in memory, after the operator confirms it.

- **Side effect**: one `insight` row appended (history), and the brand `knowledge` playbook created or updated with the preference.
- **Returned**: a confirmation of exactly what was remembered, for which brand, and the relevant playbook section after the merge.
- **Idempotency**: re-remembering the same preference is a no-op on the playbook (dedup), though it appends another `insight`. Don't re-run to re-state the same thing.
- **What "success" looks like**: the next article for that brand (via the create skill's Step 0 playbook read) reflects this preference without the operator restating it.

## Why this skill promotes directly

The two-layer memory model (see below) normally keeps **capture** cheap (append an
`insight`) and concentrates **promotion** (folding into the `knowledge` playbook)
in one lazy pass at `ce-learning-article-creator` Step 0b, where *frequency* is the
durability signal. This skill is the deliberate exception: when an operator
explicitly states a preference, **the operator is the durability signal** — it
needn't wait to recur. So `ce-remember` both appends the `insight` *and* promotes
into the playbook in the same run. It uses the identical merge discipline as Step
0b, so there's no divergence — only the trigger differs (explicit vs frequency).

## Context needs

| Source | Load level | How it shapes this skill |
|--------|-----------|--------------------------|
| recent conversation | required when `feedback` omitted | The skill extracts candidate preferences from what the operator just said, then confirms. |
| `search_memory` (substrate) | required | Loads the current brand playbook so the new preference merges in (and contradictions are caught) rather than overwriting. |
| `store_memory` / `update_memory` (substrate) | required | Append the `insight`; create or merge the `knowledge` playbook. |
| `specs/MEMORY-CONSOLIDATION.md` | optional (repo only) | Full design rationale. Background only — not a runtime dependency. |

## Skill relationships

- **Phase**: delivery
- **Often follows**: an operator reviewing a published article and reacting to it; a conversation where preferences surfaced.
- **Often precedes**: the next `ce-learning-article-creator` run, which reads the playbook this skill just updated.
- **Related**:
  - `ce-learning-article-creator` — consumer of the playbook (Step 0) and home of the frequency-based promotion pass (Step 0b).
  - `ce-update-article` — captures preferences *implied by an edit*; this skill captures preferences the operator *states outright*.

## The two-layer memory model (inline reference)

- **`insight`** (`store_memory`, append-only) — the raw event/preference stream; the history.
- **`knowledge`** (`update_memory` to merge, `store_memory` to seed) — **one playbook row per brand**, the consolidated guidance the create skill reads.

**Scoping**: `function_id: "content-engine"` (exact, case-sensitive). The brand is **not** a substrate column — encode it as the first line of the playbook `content` (`# Content playbook: <brand>`) and find it via a **quoted-phrase** search: `search_memory(query: "\"Content playbook: <brand>\"")`. `customer_id` is the Tier-3 tenant, not the brand — omit unless the bound tenant is reliably known.

**Playbook schema** — fixed sections, never free prose (because `update_memory` replaces the whole body). Every bullet ends with a provenance stamp `(YYYY-MM-DD, <source>)`; re-confirming a rule bumps its date in place. Section caps: Locked 7 each, Structural/Tone 5 each, Observed once 10.

```markdown
# Content playbook: <brand>
_function: content-engine • updated: <YYYY-MM-DD> (<source skill>)_

## Locked — always do
## Locked — never do
## Structural defaults (per archetype)
## Tone / voice
## Observed once — not yet confirmed
```

## Step 1: Determine what to remember

- If `feedback` was supplied, use it as the candidate preference.
- If not, scan the recent conversation for preferences the operator expressed (dislikes, corrections, "always/never" statements). Summarize them as a short bulleted list of candidate preferences.
- **Always confirm before writing** — this is a deliberate memory edit. Show the operator the exact wording you intend to store and which brand it applies to. Proceed only on confirmation. If nothing clear surfaced and none was supplied, say so and stop; don't invent a preference.

## Step 2: Resolve the brand

- From `brand` input, else infer from context, else ask.
- If the preference is engine-wide (applies across all brands, not one), treat it as **house style**: use a playbook keyed `# Content playbook: house` (same schema, `function_id: "content-engine"`). Confirm with the operator whether a stated preference is brand-specific or house-wide when ambiguous.

## Step 3: Load the current playbook

```json
search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
```

The quoted phrase matches the playbook's marker line exactly; a bare AND-of-words query can hit another brand's playbook when names share words. `limit: 5` makes duplicates visible: expect one hit — on 2+, use the most recently updated and tell the operator the duplicates should be merged.

Capture the row `id` + `content` if found. If a near-identical or **contradicting** preference already exists, surface it to the operator: supersede the old one (newer wins), or keep both if they're compatible. Don't blindly append a duplicate.

## Step 4: Append the raw insight (history)

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "user_explicit",
  "importance": 8,
  "content": "<brand> content preference (stated via ce-remember): <the confirmed preference, verbatim-ish>."
})
```

`importance: 8` — an explicitly stated preference is among the strongest signals; rank it above inferred ones (edits are 7, creation events 5).

## Step 5: Promote into the playbook

Merge the confirmed preference into the right section — **Locked** for a clear standing rule ("always/never"), **Observed once** only if the operator hedged ("maybe we should…"). Stamp the bullet `(YYYY-MM-DD, ce-remember)`; if the preference re-confirms an existing bullet, bump that bullet's date instead of adding a line. Apply the merge discipline: dedup, supersede contradictions (newer wins), respect the section caps (Locked 7, Structural/Tone 5, Observed once 10) and generalize rather than grow.

- Playbook exists → send the **full merged body** (existing + new), never just the new line:
  ```json
  update_memory({ "id": "<playbook id>", "content": "<full merged playbook>", "importance": 7 })
  ```
- No playbook yet → seed it:
  ```json
  store_memory({ "tier": "knowledge", "function_id": "content-engine", "importance": 7, "content": "<seeded playbook with this preference>" })
  ```

> `update_memory` **replaces the entire row body**. Re-read in Step 3, merge in memory, send the whole thing. Sending only the new bullet wipes the playbook.

## Step 6: Report

Confirm: what was remembered (the exact stored wording), which brand (or "house"), which section it landed in, and that the next article for that brand will pick it up via the create skill's Step 0. If you superseded an older preference, say which.

## Troubleshooting

- **Playbook got wiped to one line** — `update_memory` replaces the full body. Step 5 must send the merged playbook (Step 3's content + the new preference), not just the new bullet. Re-read and re-merge.
- **Operator's statement was vague** — don't store a guess. Ask one clarifying question or decline. A noisy playbook is worse than a missing line.
- **Can't tell if it's brand-specific or house-wide** — ask. Storing a one-brand quirk as house style pollutes every brand's output.
- **`store_memory` / `update_memory` returns `Insufficient scope: atobi-mcp:admin required`** — memory writes need the admin scope (declared in the manifest). If it persists, the OAuth token lacks it — same failure mode as `foundation-memory-roundtrip`.
- **The remembered preference didn't shape the next article** — confirm it actually landed in the `knowledge` playbook (not just an `insight`), and that `function_id` is exactly `"content-engine"` and the brand marker matches what the create skill's Step 0 queries. Casing/marker drift means Step 0 won't find it.
- **Memory tool fails mid-run** — report it; nothing else to undo (this skill only writes memory). Retry once the substrate is reachable.
