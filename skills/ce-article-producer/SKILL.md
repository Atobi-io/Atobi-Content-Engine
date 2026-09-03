---
name: ce-article-producer
description: >
  Produce a brand-voiced markdown article for a specific brand and Publisher.
  Resolves the Publisher like the brand (explicit input, or discovery + ask;
  session-sticky), loads the brand voice profile from the brand's foundation
  folder, generates the article in the loaded voice, and saves it to the
  drops folder under the Publisher's engine folder. Optionally auto-calls
  ce-quiz-generator. Use when asked "write an article about X for a brand".
allowed-tools: gdrive_find_by_path, gdrive_read_file, gdrive_search_files, gdrive_list_folder, gdrive_create_folder, gdrive_upload_file, search_memory, store_memory, update_memory
metadata:
  version: "0.4.0"
  phases: [delivery]
---

# Article producer

Produce a brand-voiced markdown article for a specific brand and Publisher. Resolves the Publisher (like the brand: explicit input, or discovery + ask), loads the brand voice profile (and any seeded fidelity / glossary) from `foundation/brands/<brand>/`, generates the article in the loaded voice, and saves the output as a drop under the Publisher's engine folder. Invoke when asked "write an article about X for `<brand>`", or auto-call from a higher-level campaign skill.

Drive layout: brand foundation files live at the **Shared Drive root** under `foundation/brands/<brand>/` — shared across workspace engines and Publishers (INTERSPORT and a brand engine can share one Brooks profile), which is why they sit outside any single engine folder. `GDRIVE_DEFAULT_ROOT_ID` points at the Shared Drive root, so `foundation/...` paths resolve directly. Publisher-level files live beside the brands at `foundation/publishers/<publisher>/` — one sub-folder per Publisher, resolved in Step 1b the same way brands are in Step 2. Engine-specific files (`programs/`) live under the resolved Publisher's engine folder (declared in that Publisher's `config.yaml`). The skill never sees `customers/` in paths.

## Outcome

A markdown article saved to the resolved Publisher's `programs/` tree.

- **Output path**: `<engine_folder>/programs/<program>/drops/<slug>/<slug>.md`
  - `<engine_folder>` from the resolved Publisher's `config.yaml` (Step 1b), e.g. `atobiv2-content-engine`
  - `<program>` from the `program` input; defaults to `_adhoc` for one-off articles not part of a coordinated arc
  - `<slug>` derived from the topic (lowercase, hyphen-separated, ≤60 chars)
  - The drop follows the contract in `../ce-publish/references/drop-format.md`: `<slug>.md` (this skill), `review.md` (`ce-review`), `published.yaml` (`ce-publish`), optional `assets/` + `CREDITS.md`. This skill writes only `<slug>.md`. No `build.yaml`, no `knowledge-check.yaml`, no self-audit anywhere in the drop.
- **Returned**: the Drive file id, web view link, and the in-Drive path so the caller (human or upstream skill) can locate it
- **Side effects**: may create intermediate folders (`programs/`, `<program>/`, `drops/`, `<slug>/`) if missing
- **Idempotency**: re-running with the same `topic` (same slug) overwrites the existing article (prior one is soft-deleted before upload). The response includes the prior version's id so the caller can recover from trash if needed.
- **Downstream**: the drop is consumed by `ce-review` (gate) and then `ce-publish` (platform write). Content that needs no sign-off before it exists on the platform should use `ce-learning-article-creator` instead — the short flow.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `foundation/brands/<brand>/voice-profile.md` | **full** | Drives voice, tone, vocabulary. Without this, the skill refuses — generic AI prose defeats the purpose. |
| `foundation/brands/<brand>/fidelity-rules.md` | best-effort | Locked phrases, banned phrases, claim rules. Per the doc, this is a required brand artefact; until skills like `ce-fidelity` exist to author it, skip silently if absent. |
| `foundation/brands/<brand>/glossary.md` | best-effort | Locked product names + multi-language forms. Same status as fidelity — load if present, skip if not. |
| `foundation/brands/<brand>/source-material/*` | scoped to topic | Raw brand inputs (product PDFs, spec sheets). `gdrive_search_files` under that folder for files whose name or content references the topic; load matching ones. |
| `foundation/publishers/<publisher>/config.yaml` | best-effort | Declares the Publisher's `engine_folder` (where outputs go) and, later, the tenant binding. If absent, ask where outputs should go. |
| `foundation/publishers/<publisher>/voice-profile.md` | reference | The Publisher voice (Layer 1 of voice stacking per the doc). Layer with the brand voice. Skip silently if absent — most Publishers don't have it seeded yet. |
| `foundation/publishers/<publisher>/audience-profile.md` | reference | Floor-staff segments, languages, devices. Informs register. Skip if absent. |
| `search_memory` (substrate) | best-effort | Loads the brand `knowledge` playbook (accumulated operator preferences) so the article doesn't repeat corrected mistakes. Continue silently if absent — never block on memory. |
| ce-quiz-generator | downstream | Called in Step 8 if `include_quizzes=true`. Pass the produced article as source content and the same voice context. |

## Skill relationships

- **Phase**: delivery
- **Often follows**: a higher-level campaign or content-plan skill (not built yet)
- **Often precedes**: `ce-quiz-generator` (auto-called when `include_quizzes=true`), human review, eventual publish to the Atobi feed
- **Related**: `ce-quiz-generator` (sibling, auto-called); `ce-feed-post` (publish path); `ce-remember` / `ce-learning-article-creator` (share the brand-playbook memory this skill reads in Step 2b and feeds in Step 11); future `ce-journey-producer`

## Step 1: Validate inputs

Required input: `topic`. If empty, stop and ask the user — do not guess.

`publisher` is optional and is resolved in Step 1b; `brand` is optional and is resolved in Step 2. Other optional inputs: `program` (defaults to `_adhoc`), `audience` (defaults to `"retail staff"`), `length` (defaults to `"standard"`), `include_quizzes` (defaults to `false`).

## Step 1b: Resolve the publisher

Same shape as brand resolution (Step 2), with two differences: a session-sticky choice, and zero publishers is not an error.

**Session stickiness first:** if a publisher was already resolved earlier in this session, reuse it without re-asking. An explicit `publisher` input on this invocation, or the user asking to switch, overrides the session choice.

If `publisher` was supplied, verify the folder `foundation/publishers/<publisher>/` exists via `gdrive_find_by_path`. If it doesn't, fall through to discovery and ask the user which publisher they meant — don't fuzzy-match.

**Discovery (when `publisher` is missing or the supplied slug doesn't exist):**

```
gdrive_find_by_path({ path: "foundation/publishers" })
→ get the publishers folder id
gdrive_list_folder({ folder_id: <publishers-folder-id> })
→ list of publisher sub-folders
```

Filter to `mimeType == 'application/vnd.google-apps.folder'`. Branch on count:

| Count | What to do |
|---|---|
| 0 | Not an error. Proceed with no Publisher layer (brand-only voice) and note it in the Step 10 response. Ask the user where outputs should go, since there's no `config.yaml` to name the engine folder. |
| 1 | Use that publisher. Surface it in the response so the user can catch a mistake. |
| 2+ | Present the list to the user and ask which to use — for this article or for the whole session. Remember the answer for the rest of the session. |

**Then load the publisher config (best-effort):** `foundation/publishers/<publisher>/config.yaml`. Its `engine_folder` key names the Publisher's engine folder (e.g. `atobiv2-content-engine`) — Step 9 saves outputs under it. If the config or the `engine_folder` key is missing, ask the user where outputs should go rather than guessing.

## Step 2: Resolve the brand

If `brand` was supplied as an input, verify the folder `foundation/brands/<brand>/` exists via `gdrive_find_by_path`. If it doesn't, fall through to the discovery flow below and ask the user which brand they meant — don't fuzzy-match.

**Discovery (when `brand` is missing or the supplied slug doesn't exist):**

```
gdrive_find_by_path({ path: "foundation/brands" })
→ get the brands folder id
gdrive_list_folder({ folder_id: <brands-folder-id> })
→ list of brand sub-folders
```

Filter to `mimeType == 'application/vnd.google-apps.folder'`. Branch on count:

| Count | What to do |
|---|---|
| 0 | Stop. Tell the user no brands are seeded under `foundation/brands/` in this workspace. Brand onboarding is a separate Setup-mode flow. |
| 1 | Use that brand. Surface it in the response so the user can catch a mistake before the article gets written. |
| 2+ | Present the list to the user and ask which to use. Wait for an answer. |

Echo the resolved publisher and brand (and `program`, defaulting to `_adhoc`) back before doing the rest of the work — this is a multi-call sequence and confirmation saves cycles.

## Step 2b: Recall the brand playbook (memory)

Memory is two layers: an append-only `insight` event stream (raw corrections/events — the history) and **one curated `knowledge` row per brand — the "content playbook"** carrying the operator's accumulated preferences so they don't re-correct the same things on every article. This step reads the playbook and runs the lazy promotion pass; Step 11 feeds the stream. *(Self-contained — the repo's `specs/MEMORY-CONSOLIDATION.md` holds the rationale but is **not** required at runtime.)*

**This whole step is best-effort: if any memory tool errors or returns nothing, continue silently. Never block the run on memory.** The playbook *shapes* the run — it never *overrides* an explicit operator instruction.

**2b-i — Load the playbook:**

```json
search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
```

The query is a **quoted phrase** — it matches the playbook's marker line (`# Content playbook: <brand>`) as consecutive words; a bare AND-of-words query can rank a different brand's playbook first. `limit: 5` so duplicates are visible: 0 hits → no playbook yet (fine — one gets seeded in 2b-ii if there's signal); 1 → capture `id` + `content`; 2+ → use the most recently updated and tell the operator the duplicates should be merged.

**2b-ii — Promotion pass (lazy consolidation):** pull recent raw signal for this brand — `search_memory({ "query": "<brand>", "tier": "insight", "function_id": "content-engine", "limit": 20 })` — and fold anything not already in the playbook: recurs across ≥2 insights or stated as a rule → a **Locked** section; seen once → **Observed once**; one-off article-specific edits → ignore. If anything changed, write the **full merged body** back (`update_memory` on the existing row, or `store_memory({ "tier": "knowledge", "function_id": "content-engine", "importance": 7, ... })` to seed). **`update_memory` replaces the entire row body — never send just the new bullet.**

The playbook is a fixed-section template, never free prose (identical across every writer — `ce-learning-article-creator`, `ce-remember`, and this skill — so promotion dedups cleanly):

```markdown
# Content playbook: <brand>
_function: content-engine • updated: <YYYY-MM-DD> (<source skill>)_

## Locked — always do
## Locked — never do
## Structural defaults (per archetype)
## Tone / voice
## Observed once — not yet confirmed
```

**Every bullet ends with a provenance stamp** `(YYYY-MM-DD, <source>)` — the date the rule was last confirmed and the capture path that recorded it (`ce-remember`, `edit`, `promotion`). Re-confirming an existing rule bumps its date in place; it never appends a duplicate. **Section caps**: Locked sections 7 bullets each; Structural defaults and Tone / voice 5 each; Observed once 10 (when over, drop the oldest unconfirmed entries). When a Locked/Tone section is over cap, generalize two bullets into one rather than growing the list. A newer preference that contradicts an older one replaces it (newer wins).

**2b-iii — Apply to this run:** treat the playbook's **Locked** and **Tone / voice** bullets as drafting constraints in Steps 6–7 (alongside the voice profile); use **Structural defaults** for the article shape when the operator didn't specify one; if the playbook or a recent insight shows a near-identical topic was already produced for this brand, surface it before drafting ("we already have *<title>* on this — extend, supersede, or proceed?").

## Step 3: Load the brand voice (+ optional fidelity / glossary)

**Required:**
```
gdrive_find_by_path({ path: "foundation/brands/<brand>/voice-profile.md" })
```

If `found: false`:

- Tell the user the voice profile is missing at the expected path.
- Ask whether to (a) abort, (b) proceed with a generic voice (mark the article output with a `_no-voice-profile` suffix so reviewers know), or (c) supply a voice description inline.
- **Do not silently fall back to a generic voice.** The whole point of this skill is brand fidelity; producing without a voice and not flagging it is the worst failure mode.

If found, `gdrive_read_file` the content. Keep it in working memory — primary instruction for Steps 6-7.

**Best-effort (skip silently if absent):**
- `foundation/brands/<brand>/fidelity-rules.md` — locked phrases, claim rules, banned phrases
- `foundation/brands/<brand>/glossary.md` — product names, locked multi-language forms

Per the doc, these are required brand artefacts. Until `ce-fidelity` / `ce-glossary` Setup skills exist to author them, they often won't be present. Load if found; the article still ships if not.

**Publisher voice layer (Layer 1 of voice stacking — best-effort, skip silently if absent):**
- `foundation/publishers/<publisher>/voice-profile.md` — the resolved Publisher's own voice
- `foundation/publishers/<publisher>/audience-profile.md` — who reads this

(Skip both lookups entirely if Step 1b resolved no publisher.)

These layer *under* the brand voice. Conflict resolution (per the doc): claims and product language → brand wins; tone, structure, activation, writing discipline → Publisher wins. If the Publisher layer is absent, you're effectively writing brand-only voice — note it in Step 10's response so the reviewer knows what was loaded.

## Step 4: Discover and load brand source material (if topic implies it)

If `topic` references something product-shaped (a model name, a feature, a category), search the brand's source material:

```
gdrive_find_by_path({ path: "foundation/brands/<brand>/source-material" })
→ if found, gdrive_search_files with `'<id>' in parents and (name contains '<topic-keyword>' or fullText contains '<topic-keyword>') and trashed = false`
```

Load up to 3 matching files via `gdrive_read_file`. More than 3 → too much noise; ask the user which to prioritise.

If the source-material folder doesn't exist, or `topic` is non-product (a season, a campaign concept), skip and rely on the voice profile alone.

## Step 5: Load Publisher-shared context (optional, situational)

If the brand corpus is thin (no source material loaded, no fidelity / glossary) and a publisher was resolved, pull more from `foundation/publishers/<publisher>/` — particularly:

```
gdrive_find_by_path({ path: "foundation/publishers/<publisher>" }) → list contents
```

Useful candidates: `audience-profile.md`, `content-style.md`, `fidelity-rules.md`, `glossary.md`. Skip if brand-specific context was already sufficient — adding more on top of rich brand context just dilutes.

## Step 6: Draft the article

Write the drop as markdown to the contract in `../ce-publish/references/drop-format.md` — read that file now; the shape below is a summary, the reference is authoritative.

**Frontmatter** — exactly these nine keys, nothing else:

```yaml
---
brand: <brand>
publisher: <publisher>
program: <program>
slug: <slug>
archetype: <product-launch | refresh | family-series | educational | campaign-awareness | compliance>
shown_as: <training | article>
cover: <filename.jpg>           # the image the operator will supply as cover
voice_loaded: [<relative paths of every voice/fidelity/glossary file loaded in Step 3>]
sources: [<extract filenames loaded in Step 4>]
---
```

Pick `archetype` from the topic (campaign window → `product-launch`; new generation, no campaign → `refresh`; family overview → `family-series`; non-product skill → `educational`; partnership/seasonal → `campaign-awareness`; policy → `compliance`). `shown_as` follows: `campaign-awareness` → `article`; everything else → `training`. If either is genuinely undecidable, leave the key out — `ce-publish` will ask. `voice_loaded` and `sources` are facts about inputs, never assessments.

**Body**, in this order:

1. `## Status` — first. Bullet list of open questions the reviewer must resolve (unconfirmed facts, missing assets, claims needing sign-off). Empty list if none. This is the first thing a reviewer reads.
2. `# Title` — one H1, in the brand's voice (voice rules apply to titles too).
3. Lede — 1–2 sentences leading with the reader's situation.
4. `## Section` × 3–5 — each grounded in a product fact, a customer scenario, or a strategic point from the loaded context. In a Journey each becomes a section; keep them self-contained.
5. Images — `![alt](filename.jpg)` alone on a line where an image belongs; italic caption on the next line. Name files descriptively; the operator supplies them at publish.
6. Close — a concrete next action for the reader's job.

Target length per `length`: `short` ~300 words, `standard` ~600, `long` ~1000. A target, not a quota.

**Never in the body**: YAML, fenced code, tables of rules, audit results. The drop is the deliverable; the reviewer must be able to read it top to bottom as prose.

## Step 7: Apply the voice layers — audit line-by-line

Re-read the voice profile loaded in Step 3 (plus fidelity / glossary / Publisher voice if loaded) and audit the draft against every rule. Common audit items (the actual files may have more):

- Forbidden phrases removed (e.g. "game-changer", "unleash", "next-level")
- Required phrases / structures present
- Audience register matches `audience` input
- Concrete numbers favoured over vague claims
- Tone matches the voice profile's "Do's"
- Every **Locked** bullet from the brand playbook (Step 2b) holds — these are corrections the operator already made once; violating one is the exact failure memory exists to prevent

**Conflict resolution** (when Publisher voice + brand voice disagree, per the architecture doc):

- **Claims & product language** — brand fidelity / glossary wins
- **Tone, structure, writing discipline** — Publisher voice wins (if loaded; otherwise brand voice fills in)
- **Attribution** — creator signature wins (Layer 3 — not yet wired; placeholder for when operator declarations land)

This is the step most likely to drift on a first pass — be explicit, list each rule, and verify line-by-line.

**This audit is internal.** It shapes the draft; it never appears in the drop — not as a table, not as frontmatter, not as a checklist. The only audit in a drop is `review.md`, written independently by `ce-review`. A producer marking its own homework in the deliverable competes with the real review for the reader's trust.

## Step 8: (Optional) Knowledge checks

If `include_quizzes=true`, call `ce-quiz-generator` with:

- `source` = the article markdown produced in Step 6
- `brand_voice` = the brand voice profile content
- distribution = "article" (1–2 actions total per the quiz skill's distribution rules)

The generator returns YAML. **Do not embed the YAML.** Render each question into the readable syntax in `../ce-publish/references/drop-format.md § Knowledge check syntax`, inside the section it tests, under a `### Knowledge check` heading:

```markdown
### Knowledge check

**Q:** <question text>
- [ ] <distractor>
- [x] <correct option>
- [ ] <distractor>
> Feedback: <feedback, if the generator supplied one>
```

Mapping from the generator's YAML: `type: quiz` → `**Q:**`; `type: poll` → `**Poll:**` (no `[x]`); `type: yes_no` → `**Yes/No:**`; `type: open_question` → `**Open:**` (no options). `correct: <index>` marks that option `[x]`. `feedback:` → `> Feedback:`.

Option text, question text and feedback are copy the reader sees in the brand's name. Run Step 7's voice audit over them too — a first-person slip in a distractor is the same failure as one in a paragraph.

## Step 9: Save the article

Resolve (or create) the output folder chain step by step under the Publisher's engine folder (`<engine_folder>` from Step 1b's config), using the id returned from each `gdrive_create_folder` directly (don't re-resolve via path — avoids Drive's search-index lag on freshly-created items):

```
<engine_folder>/programs/ → .../programs/<program>/ → .../drops/ → .../drops/<slug>/
```

Never create `programs/` at the Shared Drive root — outputs always live inside an engine folder. If Step 1b left `<engine_folder>` unresolved, this step must not proceed until the user has named a destination.

Check for an existing file at `<slug>.md` in the final drop folder. If present, soft-delete it via `gdrive_trash_file` before uploading the new version (preserves a recoverable history in Drive trash).

Upload:

```
gdrive_upload_file({
  parent_id: <drop folder id>,
  name: "<slug>.md",
  content: <article markdown>,
  mime_type: "text/markdown"
})
```

## Step 10: Return the artefact details

Print, in order:

- The Drive file id
- The `webViewLink` from the upload response (so the operator can click through)
- The in-Drive path (the human-readable one, not the id)
- Whether quizzes were embedded
- If a prior version was trashed: its id, so the operator can restore it if Step 6/7 went sideways

## Step 11: Capture to the event stream (memory)

Append-only and judgment-free — `store_memory` `insight` rows only. Do **not** touch the playbook here; consolidation happens in the promotion pass (Step 2b-ii of a later run). Write regardless of outcome.

**11a — the creation event** (always):

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 5,
  "content": "Produced markdown article: \"<title>\" for <brand> (drop: programs/<program>/drops/<slug>/<slug>.md).\n\n- Length: <short|standard|long>, audience: <audience>. Quizzes: <yes|no>.\n- Voice files loaded: <list, or 'none'>.\n- Notes: <anything unusual — e.g. 'no voice profile, operator approved generic voice'>."
})
```

**11b — operator corrections / preferences voiced *this session*** (only if any): if the operator rejected a section, changed tone/structure, or stated a preference while drafting, capture each as a **separate** insight phrased *generally* — brand guidance, not an article-specific edit:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "user_explicit",
  "importance": 7,
  "content": "<brand> content preference (voiced while producing <slug>): <general statement, e.g. 'ledes should open with the customer scenario, not the product'>."
})
```

Field notes: `function_id` exact and case-sensitive — Step 2b reads it back. The brand goes in the first words of `content` (never in `customer_id` — that's the Tier-3 tenant; omit unless reliably known). If `store_memory` errors, report it in one line and treat the run as successful — the article exists; a missed capture only degrades future learning.

## Troubleshooting

- **No brands seeded in this workspace** — `gdrive_list_folder` returned zero folders at `foundation/brands/`. Brand onboarding is a separate Setup-mode flow; escalate rather than auto-creating.
- **User picked a publisher that doesn't appear in the discovery list** — re-present the list from `foundation/publishers/` and ask again. Don't fuzzy-match or proceed on an unconfirmed publisher; onboarding a new Publisher (folder + `config.yaml`) is a Setup-mode task, not something to auto-create mid-run.
- **`foundation/publishers/<publisher>/config.yaml` missing or lacks `engine_folder`** — the voice layer still loads, but outputs have no destination. Ask the user where drops should go; suggest adding the key to `config.yaml` so future runs don't ask.
- **User picked a brand that doesn't appear in the discovery list** — brands are shared across Publishers at `foundation/brands/`; the brand may simply not be onboarded yet. Re-present the list and ask again. Don't proceed on an unconfirmed brand.
- **Voice profile not found at `foundation/brands/<brand>/voice-profile.md`** — the brand folder exists but the voice file is missing. See Step 3's fallback options.
- **Paths look wrong (e.g. `foundation/` not found)** — the deployment's `GDRIVE_DEFAULT_ROOT_ID` must point at the Shared Drive root, where `foundation/` and the engine folders (`atobiv2-content-engine/`, `gtm-engine/`) live. If it points at a single engine folder or a different drive, the shared `foundation/` tree is unreachable — fix the env var.
- **Article doesn't sound like the brand** — Step 7 was skipped or rushed. Re-load the voice profile content (don't rely on memory), re-audit each rule line-by-line, regenerate sections that fail. If the Publisher voice was also loaded, double-check the conflict-resolution rules in Step 7 — claims/glossary from brand, tone/structure from Publisher.
- **Output overwrites the wrong file** — `<slug>` collided with another topic. Disambiguate by including a date or qualifier in the slug, or refuse to overwrite and surface the collision to the user.
- **`gdrive_create_folder` succeeded but `gdrive_find_by_path` for the new folder returns null immediately after** — Drive's search index has eventual-consistency lag on newly-created items in Shared Drives. Use the id from the `gdrive_create_folder` response directly instead of re-resolving via path.
- **`include_quizzes=true` but quiz generator failed** — the article itself is still produced and saved. Return the article + note that quizzes failed, don't roll back the save. Operator can re-invoke ce-quiz-generator manually against the saved article.
- **Memory tool fails mid-run** — never fatal. Step 2b read failure: continue with no recall. Step 11 write failure: report one line, treat the run as successful — the article exists regardless.
- **Playbook got wiped down to one bullet after promotion** — `update_memory` **replaces the entire row body**. Step 2b-ii must send the full merged playbook (existing content + new signal), never just the new bullet. Re-read the playbook, merge, write the whole thing.
- **`store_memory` / `search_memory` returns `Insufficient scope: atobi-mcp:admin required`** — memory tools need the admin scope (declared in the manifest). If it persists, the OAuth token lacks it — same failure mode as `foundation-memory-roundtrip`.
- **Wrong workspace in `GDRIVE_DEFAULT_ROOT_ID`** — folder names under `foundation/` don't match what you expect because the env var points at a different workspace's Shared Drive root. Confirm which workspace the deployment is bound to before assuming the data is wrong.
