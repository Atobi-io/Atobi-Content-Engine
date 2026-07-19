---
name: ce-learning-article-creator
description: >
  Create a single, highly engaging training or learning article directly on the
  Atobi platform via the GCS API. Decides between a Journey (shownAs: training)
  and a regular article (shownAs: article), loads brand voice + publisher voice
  from Drive when present, and assembles a block-tree payload. If publishing
  immediately, fetches channels and audiences and asks the operator to pick the
  exact channel + audience set before writing. Use whenever the user wants to
  build a learning module, training article, knowledge check, onboarding piece,
  or any Atobi content whose primary purpose is to teach something to staff —
  e.g. "create a training article on X", "build a learning module about Y",
  "make a journey on Z", "create a knowledge check for staff on W".
allowed-tools: gdrive_find_by_path, gdrive_read_file, gdrive_list_folder, gdrive_create_folder, gdrive_upload_file, gdrive_trash_file, gcs_list_channels, gcs_get_channel, us_list_audiences, gcs_create_article, search_memory, store_memory, update_memory, list_memory
metadata:
  version: "0.5.0"
  phases: [delivery]
---

# Learning article creator

Turn a learning topic into a single, highly engaging article that delivers real skill uplift — not just information — and publish (or draft) it directly on the Atobi platform via the GCS API. Use when the user wants a training module, knowledge check, onboarding piece, or any content whose primary goal is teaching.

Drive layout: brand foundation files live at the **Shared Drive root** under `foundation/brands/<brand>/` — shared across workspace engines (content engine, gtm-engine, …), which is why they sit outside any single engine folder. `GDRIVE_DEFAULT_ROOT_ID` points at the Shared Drive root, so `foundation/...` paths resolve directly. Publisher-level voice/audience profiles live beside the brands at `foundation/publisher/`. Engine-specific files (`programs/`) live under this Publisher's content-engine folder (`atobiv2-content-engine/`). The skill never sees `customers/<tenant>/` in paths.

## Outcome

An article created on the Atobi platform — either as a `draft` (default) or `published` directly into a channel for one or more audiences.

- **Side effect**: one new article visible in the Atobi platform (draft list, or live in-feed if published). When the `drop` input is given, a `published.yaml` backlink is written into that drop folder (Step 7b) — the drop → article-id link `ce-reporting`'s `program:` mode reads. Memory side effects: the brand `knowledge` playbook may be promoted/seeded at Step 0b, and one or more `insight` rows are appended at Step 9.
- **Returned**: the article id, the resolved `shownAs` type (`training` vs `article`), the channel + audience ids if published, the drop backlink path if written, and the Drive paths of any voice profiles that shaped the body (so the operator can audit "what voice did this end up in").
- **Idempotency**: none. Re-running creates another article. Don't loop this.
- **What "success" looks like**: the article reads like a senior colleague coaching floor staff on how to **sell and serve** — not a textbook or spec sheet. For product/retail content it gives concrete customer-facing moves (how to approach, what to ask, which need to uncover, what to say) with product features attached as the *reason the move works*, not as standalone trivia. The block structure matches the Journey/Article decision in Step 2.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `foundation/brands/<brand>/voice-profile.md` | best-effort | If present, drives voice / tone / vocabulary. Loaded only when the file exists — the skill does not refuse without it for learning content (instructional design rules still apply), but it WILL surface its absence in Step 7 so the operator knows what voice shaped the output. |
| `foundation/brands/<brand>/fidelity-rules.md` | best-effort | Locked phrases, banned phrases, claim rules. Load if present; skip silently if not. |
| `foundation/brands/<brand>/glossary.md` | best-effort | Locked product names + multi-language forms. Load if present; skip silently if not. |
| `foundation/publisher/voice-profile.md` | best-effort | Publisher voice (Layer 1 of voice stacking). Layers under the brand voice. Load if present; skip silently if not. |
| `foundation/publisher/audience-profile.md` | best-effort | Floor-staff segments, languages, devices. Informs register. Skip if absent. |
| `gcs_list_channels` (live) | required when publishing | Channel ids to publish into. Called in Step 6 only if `status="published"`. |
| `us_list_audiences` (live) | required when publishing | Audience ids the article is visible to. Called in Step 6 only if `status="published"`. |
| `search_memory` (substrate) | best-effort, Step 0 | Loads the brand `knowledge` playbook (0a) and pulls recent `insight` rows for the promotion pass (0b). Shapes defaults + drafting; never overrides the operator. Continue silently on error. |
| `update_memory` (substrate) | best-effort, Step 0b | Merges promoted signal into the existing brand playbook in place (replaces the full row body — fixed-section schema, dedup, supersede). |
| `store_memory` (substrate) | required, Steps 0b + 9 | Seeds a new brand playbook (`knowledge`) when none exists, and appends `insight` rows at Step 9 (creation event + any voiced preferences). |
| `list_memory` (substrate) | optional, Step 0b | Alternative to `search_memory` for browsing recent brand insights when a text query is too narrow. |
| `specs/MEMORY-CONSOLIDATION.md` | optional (repo only) | Full design rationale for the learning loop. Background reading — **not** a runtime dependency; the skill is self-contained. Absent when the skill is used outside this repo. |
| `ce-quiz-generator` | downstream (optional) | For learning articles, knowledge checks are built inline as block-tree `multi_choice` / `open_question_task` / `yes_no_task` blocks rather than YAML. The block-shape design here is informed by `ce-quiz-generator`'s distribution rules. |

## Skill relationships

- **Phase**: delivery
- **Often follows**: a higher-level learning-plan or campaign skill (not built yet); manual operator request for a training piece
- **Often precedes**: `ce-review` (post-creation compliance check); `ce-reporting` (reads the Step 7b `published.yaml` backlink to measure program drops)
- **Related**:
  - `ce-article-producer` — sibling. Produces brand-voiced **markdown** in Google Drive for human review. This skill produces **live Atobi articles** via the GCS API. Use `ce-article-producer` when the output is a Drive drop for review; use this skill when the output is the platform itself and the goal is learning.
  - `ce-quiz-generator` — sibling. Generates YAML quiz blocks for content saved elsewhere. This skill embeds knowledge checks **inline** as native Atobi block-tree task blocks instead.

## Step 0: Recall the brand playbook (memory)

Memory is two layers: an append-only `insight` event stream (raw corrections/events — the history) and **one curated `knowledge` row per brand — the "content playbook"**. Recall reads the *playbook*, not the event log. The playbook is what carries the operator's accumulated preferences and dislikes so they don't have to re-correct the same things on every article. *(Everything this skill needs to operate memory is inline below — it is self-contained. The repo's `specs/MEMORY-CONSOLIDATION.md` holds the full design rationale but is **not** required at runtime.)*

**This whole step is best-effort: if any memory tool errors or returns nothing, continue silently. Never block the run on memory.** The playbook *shapes* the run (smarter defaults, duplicate guard, voice continuity) — it never *overrides* an explicit operator instruction.

**Brand timing.** The playbook is keyed by brand. If `brand` was supplied as an input, run this whole step now — its output informs the Step 1 questions. If `brand` is not yet known, run only the duplicate-guard read now and **re-run the playbook load + promotion immediately after Step 2 resolves the brand**, before Step 3.

### 0a — Load the playbook

```json
search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
```

The query is a **quoted phrase** — it matches the playbook's marker line (`# Content playbook: <brand>`) as consecutive words. Don't drop the quotes: a bare `<brand> content playbook` query is an AND-of-words that can rank a *different* brand's playbook first when brand names share words or are common words ("On").

`limit: 5` so duplicates are visible. Expect exactly one hit:

- **0** — this brand has no playbook yet; that's fine, one gets seeded in 0b.
- **1** — capture the row's `id` and `content`.
- **2+** — duplicate playbooks exist. Read the most recently updated one for this run, and tell the operator ("found N playbooks for <brand> — using the newest; the others should be merged/deleted"). Don't silently pick.

### 0b — Promotion pass (lazy consolidation)

This is the curated step that turns raw feedback into durable guidance. **Frequency is the durability signal** — a correction stated once is provisional; one that recurs (or was stated as a standing rule) is durable.

1. Pull recent raw signal for this brand:
   ```json
   search_memory({ "query": "<brand>", "tier": "insight", "function_id": "content-engine", "limit": 20 })
   ```
2. Scan those insights for corrections / preferences **not already reflected in the playbook**. For each:
   - Recurs across ≥2 insights, or was stated as a rule → fold into a **Locked** section.
   - Seen once → put under **Observed once — not yet confirmed**.
   - One-off edits specific to a single article (not generalizable) → ignore; they age out of the insight stream on their own.
3. If anything changed, write the merged playbook back:
   - Playbook exists → `update_memory({ "id": "<playbook id>", "content": "<full merged body>" })` (this **replaces** the whole body — merge in place, dedup, supersede contradictions, don't append duplicates).
   - No playbook yet → `store_memory({ "tier": "knowledge", "function_id": "content-engine", "importance": 7, "content": "<seeded playbook>" })`.

Merging the same signal twice is a no-op (dedup), so this pass is safe to run every time without a hard watermark.

**Playbook schema** — a fixed-section template, never free prose (because `update_memory` replaces the entire body):

```markdown
# Content playbook: <brand>
_function: content-engine • updated: <YYYY-MM-DD> (<source skill>)_

## Locked — always do
## Locked — never do
## Structural defaults (per archetype)
## Tone / voice
## Observed once — not yet confirmed
```

**Every bullet ends with a provenance stamp** `(YYYY-MM-DD, <source>)` — the date the rule was last confirmed and the capture path that recorded it (`ce-remember`, `edit`, `promotion`). Re-confirming an existing rule bumps its date in place; it never appends a duplicate. **Section caps**: Locked sections 7 bullets each; Structural defaults and Tone / voice 5 each; Observed once 10 (when over, drop the oldest unconfirmed entries). When a Locked/Tone section is over cap, generalize two bullets into one rather than growing the list.

### 0c — Apply the playbook to this run

- **Duplicate guard** — if the playbook (or a recent insight) shows an article already exists on a near-identical topic for this brand, surface it in Step 1 ("we already have *<title>* on this — extend it, supersede it, or proceed anyway?").
- **Smarter defaults** — offer the playbook's archetype / channel / audience patterns as the *suggested default* in Step 1 / Step 6 instead of asking blind. The operator can still change it.
- **Voice + structure continuity** — apply the Locked and Structural-defaults bullets when drafting in Steps 4–5, and prefer the same voice files in Step 3.

## Step 1: Gather requirements

Use `AskUserQuestion` for each missing input below. Skip questions where the input was already supplied or the answer is obvious from context.

1. **Topic** (`topic`) — what should staff learn or be able to do after reading this? One clear skill or knowledge area. If the answer covers multiple things, ask which is most important, or suggest building several articles.
2. **Archetype** (`archetype`) — what KIND of article is this? This determines the section template, formatting density, quiz role, and `shownAs`. Required when foundation/publisher/voice-profile.md is present (it has different templates per archetype). One of:
   - `product-launch` — new product hits the store **with a campaign / Early-Access window**. Journey, 5 sections including a dedicated Introduction. (e.g. Ghost 18 at Intersport)
   - `refresh` — new generation of an existing product, no campaign event. Journey, 4 sections, Consumer Profile is the entry point (no separate Intro). (e.g. Adrenaline GTS 25)
   - `family-series` — overview of a product family / line. Journey, 1 family-overview section + 1 per product variant. Heavy on video blocks; quizzes per-product, no dedicated Recap. (e.g. Brooks Glycerin Series)
   - `educational` — upskill on a non-product concept (gait fitting, support vs neutral, how-to). Journey, verb-forward title.
   - `campaign-awareness` — partnership / community / seasonal moment. `shownAs: "article"` (not training), no completion gating.
   - `compliance` — mandatory policy / process training. Journey, mandatory completion.

   **How to distinguish launch vs refresh**: campaign / Early-Access / event window present → `product-launch`. Just a new version dropping with no campaign moment → `refresh`.
3. **Audience description** (`audience_description`) — who is this for (role, experience level, context)? Defaults to `"retail staff"`. This shapes register and examples — it is **not** the same as the platform audience ids picked at publish time.
4. **Format** (`format`) — usually **derived from archetype** (launch/refresh/educational/compliance → `training`; campaign-awareness → `article`). Only ask if the operator wants to override. Options: `training` (Journey, sequential), `article` (any-order reading), `auto`.
5. **Status** (`status`) — `draft` (default) or `published` (live immediately).
6. **Brand** (`brand`) — optional. Resolved in Step 2 if missing.

**Channel and audiences are NOT asked here.** They are required if and only if `status="published"`, and they are resolved against live platform data in Step 6 (not free-form text input).

## Step 2: Resolve the brand (best-effort)

If `brand` was supplied, verify the folder `foundation/brands/<brand>/` exists via `gdrive_find_by_path`. If not found, fall through to the discovery flow.

**Discovery (when `brand` is missing or the supplied slug doesn't exist):**

```
gdrive_find_by_path({ path: "foundation/brands" })
gdrive_list_folder({ folder_id: <brands-folder-id> })
```

**No path-prefix retry here**: `foundation/` lives at the Shared Drive root, which is exactly where `GDRIVE_DEFAULT_ROOT_ID` points — so there is no engine prefix to retry with. If `found: false`, the foundation tree genuinely doesn't exist in this workspace.

Filter to `mimeType == 'application/vnd.google-apps.folder'`. Branch on count:

| Count | What to do |
|---|---|
| 0 | Continue without a brand. Tell the operator no brands are seeded — the article will be written using generic instructional-design voice and Step 7's report will flag this. |
| 1 | Use that brand. Echo it before continuing. |
| 2+ | Present the list to the operator and ask which to use. Wait for an answer. |

Unlike `ce-article-producer`, this skill **does not refuse without a brand**. Learning content has its own instructional-design rules that produce a usable article even without a brand voice; the brand voice is an enhancement, not a precondition.

**Deferred playbook load.** If Step 0 was skipped because the brand wasn't known yet, run Step 0a–0c now that the brand has resolved — before Step 3 — so the playbook can still inform voice loading, drafting, and channel/audience defaults. If a brand could not be resolved at all, there is no playbook to load; continue without one.

## Step 3: Load voice profiles (best-effort, only if files exist)

For each of the files below, call `gdrive_find_by_path` FIRST. Only `gdrive_read_file` if `found: true`. Never assume — always check. Keep track of which files were loaded so Step 7 can list them in the report.

**Brand layer (if a brand was resolved in Step 2):**
- `foundation/brands/<brand>/voice-profile.md`
- `foundation/brands/<brand>/fidelity-rules.md`
- `foundation/brands/<brand>/glossary.md`

**Publisher layer:**
- `foundation/publisher/voice-profile.md`
- `foundation/publisher/audience-profile.md`

**Path-prefix retry (publisher layer only)**: if a `foundation/publisher/` path returns `found: false` on the first attempt, retry once with the engine prefix (`atobiv2-content-engine/<path>`) before declaring it absent — publisher files are engine-relative. `foundation/` paths live at the Shared Drive root and take no prefix; a miss there means the file genuinely doesn't exist.

**Conflict resolution** (when Publisher + brand voice disagree):
- Claims & product language → **brand** wins (fidelity / glossary).
- Tone, structure, writing discipline, formatting conventions, section template → **Publisher** wins.
- If a layer is absent, the other layer fills in.

**When publisher-voice IS present** (changes how Steps 4, 5, and 7 behave):
- Use the publisher voice's **section template for the resolved archetype** verbatim instead of inventing structure. The template will specify section count, section titles (with emoji prefixes), section order, and what goes in each.
- Apply publisher-voice **formatting conventions**: heavy inline bold on key phrases, italic emoji-bookended intro paragraphs, emoji-prefixed section titles, callout patterns like "💡 In short:", list patterns (numbered for ranked content, bulleted with emoji prefixes for use cases).
- Apply publisher-voice **quiz role per section position**: engagement (no correct answer) in early sections, assessment in later sections, dedicated Recap Quiz cluster if specified.
- Apply publisher-voice **image-role taxonomy**: cover ≠ campaign creative; cover = lifestyle action; campaign creative goes inline in Section 1 as banner; annotated/infographic image goes in Features & Benefits; etc.
- The publisher voice's interactive-block count for the archetype **overrides** the generic "2–4 interactive blocks" guidance in Step 5.

If NO voice files are found at all, fall back to generic instructional-design voice — direct, scenario-based, second-person, coach-like. Put the reader inside a live customer interaction and lead with the selling move, not the spec (see "Persona & selling skill" in Step 5). Step 7 will flag the absence. Output will look generic (one-section feel, no emoji conventions, evenly-distributed knowledge checks).

## Step 4: Decide Journey vs Article

**Terminology**: in Atobi, what users call a "Journey" maps to `shownAs: "training"` in the GCS API. A regular evergreen article maps to `shownAs: "article"`. These are the two `shownAs` values this skill produces. (The server also supports `post`, `checklist`, and `competition`, but `post` is for feed-channel announcements without task blocks — out of scope for learning content — and the others aren't relevant here.)

**Archetype → shownAs mapping** (derive automatically; only fall through to the decision table below if archetype is `auto` or absent):

| Archetype | shownAs | Why |
|---|---|---|
| `product-launch` | `training` | Sequential completion matters — staff must be floor-ready before customers ask |
| `refresh` | `training` | Same sequential pattern, lighter content, no Intro section |
| `family-series` | `training` | One section per product, sequential through the lineup |
| `educational` | `training` | Skill-building benefits from gated progression |
| `campaign-awareness` | `article` | Reference / awareness only — no completion requirement |
| `compliance` | `training` | Mandatory completion is the entire point |

| Use `shownAs: "training"` (Journey) when... | Use `shownAs: "article"` when... |
|---|---|
| The content has a clear sequence that must be followed | Content can be consumed in any order |
| Staff must complete actions/sections to progress | Reading is exploratory or optional |
| Knowledge checks gate progression | No pass/fail or completion requirement |
| It's a structured skill-building or compliance piece | It's reference material or awareness content |
| You'd describe it as "a course" or "a training" | You'd describe it as "a guide" or "an update" |

**UX difference**: `training` renders one section at a time — users must complete each block before advancing. `article` renders everything on one page and lets users jump around. Choose based on whether sequential completion is meaningful for the objective. If `format="auto"`, pick using this table.

## Step 5: Draft the content blueprint

**If publisher-voice was loaded in Step 3**: use its **section template for the resolved archetype** as the literal blueprint structure. Don't invent. The template will tell you exactly how many sections, what each section title is (with emoji prefix), and what role each section plays. The blueprint is then a "fill-the-template" exercise, not a "design-from-scratch" exercise. The "Content structure rules" below act as backup guidance — apply only where the publisher voice doesn't speak.

**If publisher-voice was NOT loaded**: invent the structure using the rules below.

Produce a short blueprint and echo it to the operator before writing the full body:

```
Title: [Punchy, action-oriented — starts with a verb or outcome]
Type: Journey (shownAs: training) / Article (shownAs: article)
Learning objective: By the end, the reader can [specific action]
Sections: (max 4-5)
  1. [Hook — why this matters]
  2. [Core concept A]
  3. [Core concept B]
  4. [Apply / commit]
Sections (Journey only — each starts with a level-1 heading-only divider block):
  1. [Section A title] → blocks 1..n
  2. [Section B title] → blocks n+1..m
  3. [Section C title] → blocks m+1..end
Blocks planned: section-divider ×3, text, image, multi_choice ×2, yes_no_task
Voice loaded: [list of voice files actually loaded in Step 3, or "none — generic"]
Estimated read time: ~4 min
```

### Content structure rules

These reflect how adult learners actually retain information in a mobile-first, deskless-worker context.

**Persona & selling skill (apply first — governs everything below for product / retail content)**
- Write to the reader as the person on the floor, not as a student. Where it sharpens the framing, name the role out loud: *"You're a sales associate. A customer walks in holding the [product] and asks…"* Open the body — and ideally each product section — by dropping them into their own shift.
- **Lead with the sell, not the spec.** The reader doesn't need to recite a feature list; they need to know what to *do* with a customer. For any product or customer-facing topic, structure the teaching as:
  - **The customer** — the need, doubt, or signal to listen for. *"Knees ache on long runs → they need cushioning + support."*
  - **The move** — how to approach, what to ask, what to say. Give them actual words: *"Try: 'How many miles a week are you running?'"*
  - **The proof** — THEN attach the product feature as the *reason* the recommendation works: *"…point them to the 1080 — its Fresh Foam X soaks up impact, so it's the one for high-mileage knees."*
- **Convert every spec into a customer benefit and, where useful, a line they can say.** A feature with no selling action attached is trivia — cut it or convert it. Aim for "to sell this, do X · approach the customer like Y · uncover need Z," never a bare "this shoe has feature W."
- **Benefit first, feature second — at the sentence level, every time.** A technology name means nothing to the reader until they know what the customer *feels*. State what the product does for the customer, then name the technology as the reason it works. The reader should never have to memorize tech vocabulary to follow the article; after every product mention they should be able to answer "why would a customer choose this?"
  - ❌ Spec-first: *"Every shoe here runs on FuelCell, a springy, propulsive energy-return foam, and the top models add a carbon fiber plate."* — explains the technology, not why it matters.
  - ✅ Benefit-first: *"Every shoe in this collection gives a soft, bouncy, propulsive ride that helps runners feel faster and more efficient — that's FuelCell, the brand's high-energy cushioning. The top racing models feel even more responsive on race day thanks to a carbon plate."*
- Soft skills are the lesson; product facts are the evidence. When in doubt, keep the customer-handling guidance and trim the technical depth.

**Text**
- Paragraphs: max 3 sentences. No walls of text.
- Sections: max 4–5. More = cognitive overload. **Exception — multi-product content**: when several products appear, every product gets its own dedicated section, even if that pushes past the cap. Grouping two models into one section makes the content harder to scan and robs each model of its own "why would a customer choose this one" explanation — the exact thing the article exists to teach. If the lineup is long, trim depth per section rather than merging products (this is the `family-series` shape: one overview section + one per variant).
- Total body: aim for a 3–7 minute read (~300–600 words for `standard`).
- Headings are navigation, not decoration.
- Opening paragraph (hook): about the **reader's world**, not the topic. "You've probably seen this happen…" beats "In this article we will cover…"

**Visuals**
- Every article needs at least one image. Place the first one within the first 2–3 blocks.
- Use images for: real-world examples, before/after comparisons, process steps, "what good looks like."
- Videos: only if a real URL is supplied. Keep under 6 minutes.

**Interactivity**
- For Journey (`shownAs: "training"`): place a `multi_choice` block after each major content section, not just at the end. Journey renders one section at a time — the testing effect kicks in naturally.
- `open_question_task`: when the learner should apply the concept to their own context. Forces deeper processing than recall.
- `yes_no_task`: self-assessments, readiness checks, commitment moments.
- `simple_task`: action items the learner must physically complete.
- `media_task`: only when there's a real reason to collect photo evidence.
- **Don't over-quiz** (generic default): 2–4 interactive blocks total is the sweet spot. More than 5 feels like an exam.
- **Override**: when publisher-voice is loaded and specifies a different interactive-block count for the resolved archetype, use the publisher voice's count. Example: the atobiv2 publisher voice specifies 6–7 interactive blocks for `product-launch` (engagement S1 + engagement-poll S2 + assessment in mid-sections + 3-quiz Recap Quiz cluster). That's higher than the generic rule because retention before customer contact is the whole point of a launch Journey.

## Step 6: Resolve channel + audiences (only when status="published")

Skip this entire step if `status="draft"`. Drafts do not need a channel or audiences.

**If `status="published"`, both are required.** The skill MUST NOT publish to a guessed channel or empty audience list. Resolution is against live platform data:

1. **Channel** — if `channel_id` was supplied as input, use it. Otherwise:
   ```
   gcs_list_channels()
   ```
   Present the returned channels (id + name) to the operator via `AskUserQuestion` and ask which one to publish into. Do not auto-pick — channel placement is visible and editorial.

2. **Audiences** — if `audience_ids` was supplied (non-empty array), use it. Otherwise:
   ```
   us_list_audiences()
   ```
   Present the returned audiences to the operator via `AskUserQuestion` (`multiSelect: true`) and ask which audiences this article should be visible to. **At least one is required**; refuse to proceed with an empty selection.

3. **Feed-channel audience intersection** — if the resolved channel turns out to be a feed channel, the server requires the article's `audiences` to intersect the channel's `viewerAudiences`. Call `gcs_get_channel({ channelId })` once after channel selection, inspect `viewerAudiences`, and confirm the intersection. If empty, surface this to the operator and ask them to either pick a different channel or widen the audience selection — don't try to "fix" it silently. (This rule rarely bites training content because Journeys typically land in non-feed channels, but `shownAs: "article"` published into a feed channel hits it.)

Echo the resolved `channel_id` and `audience_ids` back to the operator alongside the title and `shownAs` type before calling `gcs_create_article`. Wrong channel + audience is the highest-risk failure mode for a published article.

## Step 7: Build the payload and call gcs_create_article

The tool takes a wrapper: `gcs_create_article({ article: <payload> })`. The fields below describe the `<payload>` object inside that wrapper.

### Top-level fields

- `variants`: `{ "en": { title, translationStatus, coverImage: {...} } }`
  - `translationStatus`: `"draft"` when article `status="draft"`, `"approved"` when `status="published"`. Mirror this on every block's `variants.en.translationStatus` as well.
- `coverImage`: REQUIRED on every language variant. Two valid shapes:
  - **External (URL)**: `{ "type": "external", "url": "https://...", "name": "Cover image" }` — `name` REQUIRED. Use for stock photos (Unsplash) or any publicly-reachable URL.
  - **Internal (uploaded file)**: `{ "type": "internal", "id": "<file-slot-id>", "tenantId": <tenant> }` — no `name` field. The file must be uploaded first via the file-slot flow (see "Uploading photos" subsection below). `tenantId` is technically optional but recommended (e.g. `78` for atobiv2).
  - For brand-supplied campaign assets, prefer internal — the photos live inside the tenant, render with proper small/medium/large variants the server auto-generates, and don't break if external URLs rot.
- `shownAs`: `"training"` for Journey, `"article"` for regular article. **Always set explicitly** — do not rely on defaults.
- `status`: `"draft"` or `"published"`.
- `publishAt`: `null` unless scheduling. **Must be present even when null** — don't omit.
- `archiveAt`: `null` unless scheduling. **Must be present even when null** — don't omit.
- `blocks`: array of block objects (see skeletons below). **Required even when empty** (`[]`).
- `audiences`: `[]` for draft; the array of ids resolved in Step 6 if publishing. **Required even when empty**.
- `users`: `[]` (required, even when empty).
- `languages`: `[{ "language": "en", "isDefault": true }]`. Exactly ONE entry has `isDefault: true`. Do **not** add `translationStatus` here — it belongs on `variants.en`, not on the language entry. Every key in `variants{}`, `block.variants{}`, and `multi_choice choice.variants{}` MUST appear in `languages[]`.
- `channelId`: the id resolved in Step 6 if publishing. **`null` for draft, present, never omitted.**

### Block skeleton (all blocks)

```json
{
  "type": "<block-type>",
  "version": 1,
  "position": 0,
  "parentId": null,
  "variants": {
    "en": {
      "translationStatus": "draft"
    }
  }
}
```

### Uploading photos (operator-supplied campaign assets)

When the operator provides photos (campaign hero, product shots, etc.) rather than pointing at a stock URL, use the internal file-slot flow:

1. **Create a slot** per image:
   ```
   gcs_create_file_slot({ name: "ghost18-hero.jpg", mimeType: "image/jpeg" })
   ```
   Returns `{ id, uploadUrl, headers, instructions }`. The `id` is what you reference in articles. The `uploadUrl` is a pre-signed Azure Blob URL valid for ~1 hour.

2. **Upload the bytes** via direct `PUT` to that URL — DON'T pipe the file through `gcs_upload_file_to_slot` for non-trivial images. That tool base64-encodes the content and embeds it in the tool-call payload, which inflates size ~33% and burns context fast (a 350 KB jpg becomes ~470 KB of text). Direct PUT bypasses both. Pattern:
   ```bash
   curl -sS -X PUT \
     -H "x-ms-blob-type: BlockBlob" \
     -H "x-ms-meta-__name: <name>" \
     -H "x-ms-meta-__status: uploaded" \
     -H "x-ms-meta-__mimeType: <mime>" \
     -H "Content-Type: <mime>" \
     --data-binary @<local-path> \
     "<uploadUrl>"
   ```
   Expect HTTP 201 on success. The headers map 1:1 to the `headers` returned by `gcs_create_file_slot` — pass them through verbatim.

3. **Resize first if the source is big.** macOS `sips -Z 1200 -s formatOptions 85 <in> --out <out>` caps width at 1200px and re-encodes at JPEG q=85 — typically gets a campaign-shot jpg under 200 KB without visible quality loss. Atobi auto-generates small/medium/large webp variants from whatever you upload, so giving it a 4000px original wastes bandwidth.

4. **Reference by id** in `coverImage` (article-level) or in image-block variants (see "Image block" below). The server fills in `name`, `url`, and the `directUrls` map on response — you only send `{type, id, tenantId}`.

Use `gcs_upload_file_to_slot` (the MCP wrapper) only as a fallback when you don't have shell access or PUT capability. For everything else, direct PUT.

### Section dividers (REQUIRED for `shownAs: "training"` — Journey UX)

In Atobi, a Journey renders one **section** at a time and gates progression on completing the section's mandatory tasks. Sections are NOT a separate API entity — they're inferred from the block list using this rule:

**A section divider is a `text` block whose `variants.en.items` is EXACTLY one node — a `heading` with `level: 1` — and nothing else.** The text in that heading becomes the section title. Every block that follows belongs to that section, until the next divider (or end of article).

Pattern:

```
position 0  → text { items: [ heading level:1 "Section A" ] }   ← divider only, no body
position 1  → text { items: [ paragraph, paragraph, ... ] }     ← body of Section A
position 2  → image                                              ← still Section A
position 3  → multi_choice                                       ← still Section A (gates A's completion)
position 4  → text { items: [ heading level:1 "Section B" ] }   ← divider only
position 5  → text { items: [ paragraph, ... ] }                ← body of Section B
...
```

Rules:
- For Journeys (`shownAs: "training"`): the article's first block SHOULD be a level-1 divider. Without one, all content lands in an implicit "Untitled" section.
- One divider per section. Don't put body content in the divider block — anything beyond the single heading-level-1 node breaks the divider behavior.
- For in-section sub-headings, use `heading` with `level: 2` (or higher) inside text blocks alongside paragraphs — those render inline, not as section breaks.
- For `shownAs: "article"`: dividers are optional. The Article UX doesn't gate or paginate by section, so a flat structure is fine.

Aim for **3–5 sections** for a Journey. Fewer than 3 feels like an article that lied about being a Journey; more than 5 turns the unlock UX into a slog. **Exception**: multi-product content takes one divider per product — never bundle two products under one divider, even when that exceeds 5 sections (keep each product's section lean instead).

### Text block

```json
{
  "type": "text", "version": 1, "position": 0, "parentId": null,
  "variants": { "en": {
    "translationStatus": "draft",
    "items": [
      { "type": "paragraph", "children": [
        { "type": "text", "value": "Your paragraph text.", "format": {} }
      ]}
    ]
  }}
}
```

`format` is REQUIRED on every text node — `{}` for plain, `{ "bold": true }` etc.
Heading: `{ "type": "heading", "level": 2, "children": [{ "type": "text", "value": "...", "format": {} }] }` — note `level` (number), NOT `tag: "h2"`.
List: `{ "type": "list", "listType": "bullet", "children": [ { "type": "listitem", "children": [...] } ] }`.

### Image block

The media object is **flat inside `variants.en`** — NOT wrapped in an inner `"image"` key. Same external/internal discriminator pattern as the article `coverImage`.

**External (URL):**
```json
{
  "type": "image", "version": 1, "position": 1, "parentId": null,
  "variants": { "en": {
    "translationStatus": "draft",
    "type": "external",
    "url": "https://...",
    "name": "Description"
  }}
}
```

**Internal (uploaded file)** — after the file-slot upload in "Uploading photos" above, reference the returned `id`:
```json
{
  "type": "image", "version": 1, "position": 1, "parentId": null,
  "variants": { "en": {
    "translationStatus": "draft",
    "type": "internal",
    "id": "<file-slot-id>",
    "tenantId": 78
  }}
}
```

No `name` field on the internal variant — the server uses the name supplied at slot creation. `tenantId` is optional but recommended. On response, the server fills in `name`, `url`, and a `directUrls` map with auto-generated small/medium/large webp variants.

### Video block

Same external/internal pattern as image — media fields are flat inside `variants.en`.

**External:**
```json
{
  "type": "video", "version": 1, "position": 2, "parentId": null,
  "variants": { "en": {
    "translationStatus": "draft",
    "type": "external",
    "url": "https://...",
    "name": "Video title"
  }}
}
```

**Internal** (uploaded via `gcs_create_file_slot` with a `video/*` mime type, then PUT to the pre-signed URL):
```json
{
  "type": "video", "version": 1, "position": 2, "parentId": null,
  "variants": { "en": {
    "translationStatus": "draft",
    "type": "internal",
    "id": "<file-slot-id>",
    "tenantId": 78
  }}
}
```

### Task blocks (multi_choice, yes_no_task, open_question_task, simple_task)

All task blocks require these extra top-level fields (alongside `type`, `version`, `position`, `parentId`, `variants`):

```json
{
  "required": -1,
  "public": false,
  "audiences": [<audience-id>],
  "deadline": null,
  "schedule": {
    "frequency": "once",
    "start": { "time": "<ISO-8601-now>" },
    "end": { "time": "<ISO-8601-one-year-from-now>" },
    "exceptions": []
  }
}
```

Field semantics — read carefully, the two flags are NOT synonyms:

- `required`: `-1` = no answer requirement, `0` = optional, `1` = required-to-submit-an-answer.
- `mandatory` (training only): `true` = must complete to progress in the Journey, `false`/omitted = doesn't gate progression. For `shownAs: "training"` task blocks that gate the journey, set `mandatory: true`. The minimal-pattern from the server example uses `required: -1` + `mandatory: true` together — the action doesn't force an answer shape, but the trainee can't advance without completing it.

For draft articles, use `[]` for the inner `audiences` field on task blocks. For published articles, mirror the audience ids resolved in Step 6.

**multi_choice** — the question text goes in `variants.en.description`. An optional `variants.en.title` adds a short label rendered ABOVE the question (the editor's "Title (optional)" field); omit it or set `""` for no title. **`choices` is a top-level field on the BLOCK** (not inside `variants`), and each choice is its own object with `position`, `correct`, `answerType`, and a per-language `variants` map where the answer text is a paragraph node:

```json
{
  "type": "multi_choice", "version": 1, "position": 3, "parentId": null,
  "required": -1, "public": false, "audiences": [<id>], "deadline": null,
  "schedule": { "frequency": "once", "start": { "time": "..." }, "end": { "time": "..." }, "exceptions": [] },
  "mandatory": true,
  "variants": { "en": {
    "translationStatus": "draft",
    "title": "Optional short label (or omit)",
    "description": "Question text?"
  }},
  "choices": [
    {
      "position": 0,
      "correct": true,
      "answerType": "string",
      "variants": { "en": {
        "translationStatus": "draft",
        "answer": { "type": "paragraph", "children": [{ "type": "text", "value": "Correct answer", "format": {} }] }
      }}
    },
    {
      "position": 1,
      "correct": false,
      "answerType": "string",
      "variants": { "en": {
        "translationStatus": "draft",
        "answer": { "type": "paragraph", "children": [{ "type": "text", "value": "Plausible wrong answer", "format": {} }] }
      }}
    }
  ]
}
```

Critical naming gotchas the tool description gets wrong:
- The correct-answer flag is **`correct: true|false`**, NOT `isCorrect`. Sending `isCorrect` is silently dropped — the choice stores `correct: null` and grading breaks.
- `answer` is a **paragraph node** (`{type: "paragraph", children: [{type: "text", value, format: {}}]}`), not a flat string.
- The **question** goes in `description`, not `title`. `title` is a SEPARATE optional field — a short label rendered above the question. Put the actual question in `description`; use `title` only when you want a heading on top of it.

Use 2–4 choices. Wrong answers must be plausible. Test application, not rote recall.

For all three below, the prompt goes in `description`; `title` is an optional short label rendered above it (omit it for no title).

**yes_no_task**:
```json
{ "translationStatus": "draft", "title": "Optional label (or omit)", "description": "Statement the learner agrees/disagrees with." }
```

**open_question_task**:
```json
{ "translationStatus": "draft", "title": "Optional label (or omit)", "description": "Open prompt that asks for application or reflection." }
```

**simple_task**:
```json
{ "translationStatus": "draft", "title": "Optional label (or omit)", "description": "Concrete action the learner must take or confirm." }
```

### Pre-call checklist

Before calling `gcs_create_article`, verify:

- [ ] Title is action-oriented (starts with a verb or names the outcome)
- [ ] Opening hook is about the reader's world, not the topic
- [ ] No paragraph longer than 3 sentences
- [ ] At least one image in the first 3 blocks
- [ ] For `shownAs: "training"`: every content section has a following knowledge check
- [ ] `shownAs` is explicitly set
- [ ] Knowledge-check questions test application, not memorization
- [ ] Every technology/feature mention is preceded by the customer benefit it delivers (benefit → feature order); no bare spec sentences, no tech names the reader must memorize before knowing what they do for the customer
- [ ] Multi-product content: exactly one product per section — no section covers two or more models
- [ ] Total interactive blocks: 2–4
- [ ] Estimated read + interaction time: 3–7 minutes
- [ ] `format: {}` present on every text node
- [ ] `coverImage.name` is set on every language variant
- [ ] `schedule` set on all task blocks; `required` is one of `-1 | 0 | 1`; for `shownAs: "training"` task blocks that gate progression, `mandatory: true`
- [ ] multi_choice: question text is `variants.en.description`; `title` only if a short label above the question is wanted (else omit); `choices` is at block top level; each choice has `position`, `correct: true|false` (not `isCorrect` — server silently drops that), `answerType`, and `variants.en.answer` is a paragraph node
- [ ] yes_no_task / open_question_task / simple_task: prompt text is `variants.en.description`; optional `variants.en.title` for a label above it (else omit)
- [ ] Headings in text-block items use `level: <number>` (not `tag: "h2"`)
- [ ] Image/video block media is flat inside `variants.en` (`type` + `url` + `name`), not wrapped in an inner `image`/`video` key
- [ ] For `shownAs: "training"`: 3–5 section-divider text blocks (each a text block whose `items` is exactly one `heading level: 1` node, nothing else); divider precedes the section's content; sub-headings inside sections use `level: 2`+
- [ ] `translationStatus` matches `status` (`"draft"` ↔ `"draft"`, `"published"` ↔ `"approved"`) on the article variant AND every block variant
- [ ] Nullable fields PRESENT (don't omit): `publishAt`, `archiveAt`, `channelId` (null when draft)
- [ ] Required arrays PRESENT (don't omit, even when empty): `blocks`, `audiences`, `users`
- [ ] Every language key in `variants` and `block.variants` appears in `languages[]` (with one `isDefault: true`)
- [ ] If `status="published"`: `channelId` is set and `audiences` is non-empty (verified against Step 6's resolutions, not guessed); if the channel is a feed channel, audiences intersect `viewerAudiences`

Then call:

```
gcs_create_article({ article: <assembled payload> })
```

Note the `article` wrapper — the tool input is `{ article: {...} }`, not the payload flat.

## Step 7b: Record the drop backlink (only when `drop` is given)

Skip entirely when the `drop` input is absent — no Drive write happens (previous behaviour). When present, this step links the Drive artefact trail to the live article: the one moment both ids are known is right after `gcs_create_article` returns, so the link is written here or lost.

Resolve the drop folder: `drop` is either the full `programs/<program>/drops/<slug>/` path or the `<program>/<slug>` shorthand (expand to the full path). `gdrive_find_by_path` it; if the folder doesn't exist, confirm with the operator before `gdrive_create_folder`-ing the chain (`programs/` → `<program>/` → `drops/` → `<slug>/`) — a typo'd slug otherwise mints a stray drop. Use ids from each create response directly (Drive index lag on fresh folders).

Trash any existing `published.yaml` in the folder (recoverable history — re-publish and draft→published transitions overwrite), then upload:

```yaml
# published.yaml — written by ce-learning-article-creator v0.5; read by ce-reporting (program: mode)
article_id: <id from gcs_create_article>
title: "<article title>"
shown_as: <training|article>
status: <draft|published>
channel_id: <id, or omit for drafts>
channel_name: "<name, or omit for drafts>"
audience_ids: [<ids, or omit for drafts>]
published_at: "<YYYY-MM-DD>"
published_by: ce-learning-article-creator v0.5
```

Drafts get the backlink too (`status: draft`, channel/audience fields omitted) — the id link is what matters; `ce-reporting`'s publication check reads live state anyway.

**Failure here is non-fatal but loud**: the article already exists, so never roll back or retry the whole run. Report the write failure in Step 8 and print the YAML block verbatim so the operator can drop it into the folder by hand — a manual copy beats a lost link.

## Step 8: Report the result

Print, in order:

- The article id returned by `gcs_create_article`
- The chosen `shownAs` type (`training` or `article`) and the one-line reason
- The block structure used (brief list — e.g. "text ×4, image ×2, multi_choice ×2, yes_no_task ×1")
- The voice files actually loaded in Step 3 (or "none — generic instructional-design voice")
- If published: the channel id + name and the audience ids that were applied
- If draft: a note that the article is a draft and won't be visible to staff until published
- If `drop` was given: the drop path and whether `published.yaml` was written (on failure: the YAML block to save by hand, per Step 7b)
- A direct link if available: `https://[tenant].atobi.io/articles/[id]`
- A follow-up offer if the topic clearly warrants more articles (e.g. a multi-part journey)

## Step 9: Capture to the event stream (memory)

This step is **append-only and judgment-free** — `store_memory` `insight` rows only. It does **not** touch the brand playbook: consolidation into `knowledge` is the promotion pass's job, and it runs lazily at Step 0b of the *next* run. Keeping capture cheap here, and judgment concentrated in one place there, is the whole design. Write **regardless of outcome** — a publish, a draft, or a publish that fell back to draft after an error all belong in the history.

**9a — the creation event** (always):

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 5,
  "content": "Created learning content: \"<title>\" (articleId <id>) for <brand>.\n\n- Type: <shownAs: training|article>, archetype <archetype>. Status: <draft|published>.\n- If published: channel <id + name>, audiences <ids>.\n- Block structure: <e.g. 'text ×4, image ×2, multi_choice ×2'>. Voice files: <list, or 'none'>.\n- Drop: <programs/.../drops/<slug>/ with published.yaml written, or 'none'>.\n- Link: https://[tenant].atobi.io/articles/<id>.\n- Notes: <anything unusual — e.g. 'published failed on channel/audience mismatch, saved as draft'>."
})
```

**9b — operator corrections / preferences voiced *this session*** (only if any): if, while drafting, the operator rejected a section, asked to change tone/structure, or stated a preference ("make titles less salesy", "lead with the consumer profile"), capture each as a **separate** insight phrased *generally* — as brand guidance, not as an article-specific edit. These are the high-value rows the next run's promotion pass weighs for the playbook.

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "user_explicit",
  "importance": 7,
  "content": "<brand> content preference (voiced while creating articleId <id>): <general statement, e.g. 'titles should be informative, not salesy — operator rewrote a hype headline'>."
})
```

Field notes:

- `function_id: "content-engine"` — exact, case-sensitive; Step 0 reads back with this value.
- `customer_id` — set to the bound tenant slug **only if reliably known**; otherwise omit. Never put the brand here — `customer_id` is the Tier-3 tenant, not the brand. The brand goes in `content` (first words), so the promotion pass's `search_memory(query:"<brand>")` finds it.
- `source_type` — `"agent_extracted"` for the 9a event; `"user_explicit"` for 9b corrections the operator actually voiced.
- `importance` — 9a creation events 5 (routine); 9b voiced preferences 7 (these should surface in promotion).
- Do **not** call `update_memory` here. Promotion to the playbook happens at the next run's Step 0b.

If `store_memory` errors, report it in one line but treat the run as successful — the article already exists; a missed capture degrades future learning, it doesn't undo the work.

## Troubleshooting

- **No brands seeded in this workspace** — `gdrive_list_folder` returned zero folders at `foundation/brands/`. Continue without a brand; the article will use generic instructional-design voice and Step 7's report flags the absence.
- **Voice profile files not found** — expected. They are best-effort for learning content. Step 7's report MUST list which files were loaded so the operator knows what shaped the output.
- **Paths look wrong (e.g. `foundation/` not found)** — the deployment's `GDRIVE_DEFAULT_ROOT_ID` must point at the Shared Drive root, where `foundation/` and the engine folders (`atobiv2-content-engine/`, `gtm-engine/`) live. If it points at a single engine folder or a different drive, the shared `foundation/` tree is unreachable — fix the env var.
- **`gcs_list_channels` returned zero channels** — the tenant has no channels configured. Publishing is impossible. Stop and tell the operator; offer to save as draft instead.
- **Operator picked zero audiences when publishing** — refuse. A published article with no audiences is invisible. Re-prompt; require at least one.
- **`gcs_create_article` failed with a validation error** — most common causes, in order of frequency: missing `article` wrapper (tool input must be `{ article: {...} }`), heading using `tag: "h2"` instead of `level: 2`, image/video block wrapping media in an inner `"image"`/`"video"` key (must be flat inside `variants.en`), multi_choice question in `title` instead of `description`, multi_choice `choices` nested inside `variants.en` instead of at block top level, choice fields flat (`value` + `isCorrect`) instead of the real shape (`position` + `correct` + `answerType` + `variants.en.answer` as paragraph node), missing `format: {}` on a text node, missing `name` on `coverImage`, missing `schedule` on a task block, `shownAs` not set, nullable field omitted instead of being `null`, `translationStatus` on a `languages[]` entry instead of on `variants.en`, language key in `variants` not declared in `languages[]`, or `translationStatus` mismatched with `status`. Run the Step 7 pre-call checklist and re-submit.
- **Article published but quizzes don't grade** — choices stored `correct: null`. You sent `isCorrect: true|false` (per the older tool description) — the real server field is `correct`. The choice payload is accepted but silently degrades to "no correct answer." Re-update the article with `correct` instead of `isCorrect`.
- **`gcs_update_article` wiped manual edits on a live article** — the update endpoint replaces the FULL block list with whatever you send. Any block you don't include in the payload is dropped, including in-flight UI edits the operator made between your last fetch and this write. Before calling `gcs_update_article` on an article that may have been touched in the editor: (a) `gcs_get_article` to fetch the current block list, (b) merge your additions into that list rather than rebuilding from your in-memory model, (c) pass `updatedAt` from the fetched response as the optimistic-concurrency token — the server returns 409 if the article changed since your fetch and you re-fetch + re-merge. Skipping this is fine for "I just created this article 10 seconds ago and nothing else touched it"; mandatory for anything else.
- **Journey renders as one giant scroll instead of unlock-gated sections** — Section dividers are missing. In the Atobi article model, a **section divider** is a `text` block whose `variants.en.items` contains **exactly one node**: a `heading` with `level: 1`. Every block after a divider belongs to that section until the next divider (or end of article). To get N sections, insert N divider blocks at the start of each section's content. See Step 7's "Section dividers" subsection.
- **`gcs_create_article` rejected with "audiences must intersect channel viewerAudiences"** — Step 6's intersection check was skipped or the channel changed between check and write. Re-run `gcs_get_channel({ channelId })`, surface `viewerAudiences` to the operator, and either narrow the channel choice or widen the audience selection.
- **Published to the wrong channel / audience** — same incident pattern as `ce-feed-post`'s tenant mismatch. Don't try to "patch" the article; surface the mistake to the operator and let them decide whether to archive it.
- **Article doesn't sound like the brand** — Step 3 loaded files but Step 5/7 didn't audit against them. Re-load the voice content, audit line-by-line, regenerate the offending sections.
- **`gdrive_find_by_path` returns `[dev mode]`** — the deployed mcp-server doesn't have `GDRIVE_SA_KEY_JSON` configured. Server-side, not a skill bug. Voice loading is impossible until that's fixed; continue with generic voice and flag in Step 7.
- **Step 7b backlink write failed (folder unresolvable, upload error)** — never fatal and never a reason to re-run `gcs_create_article` (the article exists; a retry mints a duplicate). Print the `published.yaml` content verbatim in Step 8 for a manual save, and name the failure. If the drop path was a typo, the operator can re-point: trash the stray folder if one was created, save the YAML into the right drop.
- **`drop` given but the article was re-created after a failed first attempt** — make sure `published.yaml` carries the id of the article that actually survived; a stale id sends ce-reporting to a dead draft. Trash-then-upload (Step 7b) exists precisely so the file always reflects the latest write.
- **`store_memory` / `search_memory` returns `Insufficient scope: atobi-mcp:admin required`** — memory writes need the admin scope. The manifest declares `atobi-mcp:admin`; if the error persists, the OAuth token granted to Claude Code lacks it. Confirm the `mcp-atobi` client may request `atobi-mcp:admin` and the account has it granted (same failure mode as `foundation-memory-roundtrip`).
- **Step 0 recall returns nothing on a brand you know you've used** — `search_memory` does an exact `function_id` match with no normalisation. Confirm earlier runs wrote `function_id: "content-engine"` (not `"content_engine"` or a tenant-specific value). If casing drifted in an older run, those rows won't surface — fix the write side going forward. Also check the marker line: the quoted-phrase query only matches playbooks whose first line is exactly `# Content playbook: <brand>` — if an older playbook used a different marker wording, re-title it via `update_memory`.
- **Memory tool fails mid-run** — never fatal. Step 0 read failures: continue with no recall. Step 9 write failure: report one line, treat the run as successful — the article exists regardless.
- **Playbook got wiped down to one bullet after promotion** — `update_memory` **replaces the entire row body**, it does not append. Step 0b must send the *full merged playbook* (existing content + new signal), never just the new bullet. If you only have the new line, you've lost the rest. Re-read the playbook (`search_memory`/`get_memory`), merge, then write the whole thing.
- **Playbook keeps growing / starts contradicting itself** — promotion isn't deduping or superseding. Sections are capped (Locked 7, Structural/Tone 5, Observed once 10); when over, generalize two bullets into one. A newer preference that contradicts an older one replaces it (newer wins) — don't keep both. One-off article-specific edits should never reach the playbook; they stay as `insight` rows and age out. The per-bullet `(YYYY-MM-DD, <source>)` stamps show which rules are stale.
- **A correction the operator voiced last session didn't shape this article** — it was captured as an `insight` (Step 9b) but not yet promoted. Promotion is lazy: it runs at Step 0b of the *next* run for that brand. If it recurred (≥2 insights) or was a clear rule it should have promoted — check that 0b actually ran (it's skipped if the brand wasn't resolved; see the deferred-load note after Step 2).
