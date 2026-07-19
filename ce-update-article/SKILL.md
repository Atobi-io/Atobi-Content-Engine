---
name: ce-update-article
description: >
  Safely modify an existing Atobi article via the GCS API and capture the
  operator's change — and the reason behind it — to the memory event stream.
  The moment an operator says "change X" is the highest-signal moment to learn a
  brand preference, so this skill records it. Does a safe fetch -> merge -> write
  (gcs_update_article replaces the FULL block list, so it never rebuilds from
  scratch) with the updatedAt optimistic-concurrency token, and appends one or
  more `insight` rows phrased as general brand guidance. Use whenever an operator
  wants to edit, fix, rewrite, or adjust an article they already have — e.g.
  "update article 1234", "the Ghost 18 journey title is too salesy, fix it",
  "rewrite the intro to lead with the consumer profile", "add a knowledge check".
allowed-tools: gcs_list_articles, gcs_get_article, gcs_update_article, gdrive_find_by_path, gdrive_read_file, search_memory, store_memory
metadata:
  version: "0.1.1"
  phases: [delivery]
---

# Update article

Modify an existing Atobi article without losing anything, and turn the operator's
change into durable brand memory. This is the keystone feedback path of the
content-engine learning loop: every "change this" is a signal about what the
brand wants, captured here so future articles don't repeat the mistake.

*(This skill is self-contained — everything it needs to operate memory is inline
below. The repo's `specs/MEMORY-CONSOLIDATION.md` holds the full design rationale
but is **not** required at runtime and is absent when the skill is used outside
this repo.)*

## Outcome

An existing article updated in place on the Atobi platform, plus a memory record
of what changed and why.

- **Side effect**: the target article is modified (its full block list / metadata replaced with the merged version). One or more `insight` rows are appended to memory.
- **Returned**: the article id, a summary of what changed, and the captured brand-guidance insight(s).
- **Idempotency**: the article edit is naturally idempotent for a given instruction (re-running the same change is a no-op once applied). The memory capture is append-only — don't re-run just to re-capture; that duplicates insights.
- **What "success" looks like**: the requested change is live, **nothing else on the article was lost** (no blocks dropped, no metadata reset), and the operator's underlying preference is recorded as general brand guidance — not as a one-off article edit.

## Context needs

| Source | Load level | How it shapes this skill |
|--------|-----------|--------------------------|
| `gcs_get_article` (live) | required | The current full article — block list + `updatedAt` token. The merge baseline; the write replaces everything, so this is mandatory before any edit. |
| `search_memory` (substrate) | best-effort | Loads the brand `knowledge` playbook so the edit stays consistent with established brand preferences. Continue silently if absent. |
| `store_memory` (substrate) | required | Appends the change + reason as `insight` row(s) — the feedback firehose. |
| `foundation/brands/<brand>/voice-profile.md` (Drive) | best-effort | Re-loaded only for a voice-driven rewrite, so the new text matches the brand. Skip if absent or the change isn't voice-related. |
| `specs/MEMORY-CONSOLIDATION.md` | optional (repo only) | Full design rationale. Background only — not a runtime dependency. |

## Skill relationships

- **Phase**: delivery
- **Often follows**: `ce-learning-article-creator` (the article being edited was usually created there), or an operator reviewing a live article.
- **Often precedes**: nothing — this is a terminal edit step.
- **Related**:
  - `ce-learning-article-creator` — sibling/creator. Its Step 0b promotion pass is where the `insight` rows this skill captures get consolidated into the brand playbook. This skill is **capture-only**; it does not promote.
  - `ce-remember` — the manual backstop for feedback that doesn't flow through an edit. Same capture shape, different trigger.

## Step 1: Identify the article and fetch its current state

Resolve the target, then fetch it — **never edit blind.**

1. If `article_id` was given, use it. Otherwise resolve from `article_ref`:
   ```json
   gcs_list_articles({ "query": "<article_ref>", "perPage": 10 })
   ```
   Present matches and confirm with the operator before editing. **Never edit an ambiguous match silently** — if more than one plausible article comes back, ask.
2. Fetch the full current article — this is the merge baseline and the source of the concurrency token:
   ```json
   gcs_get_article({ "articleId": <id> })
   ```
   Capture from the response: the entire `blocks` list, all `variants` (titles, coverImage), `languages`, `audiences`, `channelId`, `status`, `shownAs`, and the **`updatedAt`** value.

> **Why this is mandatory:** `gcs_update_article` takes the *same full schema as create* and **replaces the article wholesale** — any field or block you omit is dropped. The only safe edit is fetch → modify the fetched object → resend the whole thing. There is no partial/patch update.

## Step 2: Load the brand playbook + voice (best-effort)

So the edit stays on-brand instead of drifting:

- Resolve the `brand` (from input, or infer from the article's content/title; ask if unclear).
- Load the brand playbook, read-only (quoted phrase — matches the playbook's marker line exactly; a bare AND-of-words query can hit another brand's playbook. Expect one hit; on 2+, use the newest and mention the duplicates):
  ```json
  search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
  ```
  Apply its **Locked** and **Tone / voice** bullets when making the change. If the playbook already records the very preference behind this change, the edit should bring the article into line with it.
- If the change is a **voice-driven rewrite** (tone, phrasing, headline), best-effort re-load `foundation/brands/<brand>/voice-profile.md` via `gdrive_find_by_path` then `gdrive_read_file`. Skip silently if absent or irrelevant to the change.

This step is best-effort — if memory or Drive errors, continue with the edit anyway.

## Step 3: Merge the change into the fetched article

Work **on the object you fetched in Step 1**, never a rebuilt-from-scratch payload.

- Locate the specific block(s) / variant field(s) the change touches and modify only those, leaving every other block byte-for-byte as fetched.
- Adding content → insert new block(s) at the right `position` and renumber following blocks if needed; keep all existing blocks.
- Editing text → change the `value` inside the existing block's `variants.<lang>.items`, preserving the node shape (`format: {}` required on every text node).
- Removing content → drop only the targeted block; confirm with the operator first if it's substantive.
- Keep `id`, `languages`, `audiences`, `channelId`, `status`, `shownAs`, `variants` titles + `coverImage` intact unless the change explicitly targets them. `coverImage` is required per variant — never drop it.

If the operator's instruction is vague ("make it better"), ask one clarifying question rather than guessing at a rewrite that risks the whole article.

## Step 4: Write back with optimistic concurrency

```json
gcs_update_article({
  "article": {
    "id": <id>,
    "updatedAt": "<the updatedAt from Step 1>",
    "blocks": [<full merged block list>],
    "variants": {<all variants>},
    "languages": [<as fetched>],
    "audiences": [<as fetched>],
    "channelId": <as fetched or changed>,
    "status": "<as fetched or changed>",
    "shownAs": "<as fetched>",
    "publishAt": <as fetched>,
    "archiveAt": <as fetched>,
    "users": [<as fetched>]
  }
})
```

- Pass **`updatedAt`** from Step 1 — this is the optimistic-concurrency token. A **409** means someone (or the operator in the UI) changed the article since you fetched it. **Do not force the write.** Re-run Step 1 (`gcs_get_article`), re-apply the change onto the fresh state, and write again. This is what prevents this skill from clobbering an in-flight UI edit.
- Send the **full** object (all required fields from the schema), not a partial.

## Step 5: Report

Print: the article id, a one-line summary of what changed, whether status/channel/audiences changed, and a note if a 409 retry occurred. If a block was removed, say which.

## Step 6: Capture to the event stream (memory)

**Append-only and judgment-free** — `store_memory` `insight` rows only. This skill does **not** consolidate into the brand playbook; promotion of these insights into `knowledge` happens lazily at `ce-learning-article-creator` Step 0b (or a future scheduled pass). Keeping capture cheap here, and judgment in one place there, is the design. Write **regardless** of whether the edit fully succeeded.

The high-value capture is **the preference behind the change**, phrased generally — as brand guidance, not an article-specific edit:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "user_explicit",
  "importance": 7,
  "content": "<brand> content preference (from edit to articleId <id>): <general statement>.\n\n- What changed: <e.g. 'rewrote the headline from a hype line to an informative one'>.\n- Why / preference: <reason — e.g. 'operator: our titles should inform, not sell'>."
})
```

Field notes:

- `function_id: "content-engine"` — exact, case-sensitive; the promotion pass reads back with this value.
- The **brand goes in the `content`** (first words), never in `customer_id` — `customer_id` is the Tier-3 tenant, not the brand. Set `customer_id` to the bound tenant slug only if reliably known; otherwise omit.
- `source_type: "user_explicit"` — the operator actually asked for this; it's a deliberate signal.
- `importance: 7` — edits are high-signal feedback; they should surface in the next promotion pass.
- Generalize. "Make THIS title shorter" → capture "operator wanted a shorter, less salesy title" (a candidate preference), not "shortened title of article 1234." One-off, truly article-specific tweaks (fixing a typo) aren't worth capturing.
- Capture once per distinct preference. If one edit reflects two preferences, write two rows; if it's one preference, write one. Don't re-run the skill just to re-capture.

If `store_memory` errors, report it in one line but treat the edit as successful — the article change already landed.

## Troubleshooting

- **Blocks disappeared after the update** — the write didn't include them. `gcs_update_article` replaces the full block list; Step 3 must merge into the *fetched* list, never send only the changed block. Re-fetch and restore from the article's history if needed.
- **409 Conflict on update** — the article changed since Step 1 (often a UI edit). Re-fetch with `gcs_get_article`, re-apply the change onto fresh state, write again. Never strip `updatedAt` to force the write — that's exactly the clobber this guards against.
- **Validation error on update** — same failure modes as create: missing `coverImage` on a variant, text node missing `format: {}`, multi_choice `choices`/`correct` shape, `shownAs` omitted, a `variants` language not declared in `languages[]`. Diff your payload against what `gcs_get_article` returned — the fetched shape is already valid, so keep its structure.
- **Can't find the article** — `gcs_list_articles` `query`/`title` returned nothing. Confirm the brand/tenant binding and try a broader query, or ask the operator for the id. Never edit a guessed match.
- **`store_memory` returns `Insufficient scope: atobi-mcp:admin required`** — memory writes need the admin scope (declared in the manifest). If it persists, the OAuth token lacks it — same failure mode as `foundation-memory-roundtrip`.
- **The captured preference never shaped a later article** — it's an `insight` awaiting promotion. Promotion runs at `ce-learning-article-creator` Step 0b for that brand. It promotes on recurrence (≥2) or a clear rule; a one-off may stay provisional under "Observed once" until it repeats.
- **Memory tool fails mid-run** — never fatal. Step 2 read failure: edit without the playbook. Step 6 write failure: report one line, treat the edit as successful.
