---
name: ce-publish
description: >
  Take a reviewed markdown drop from Drive and create (or update, while still a
  draft) the article on Atobi. Gate on review.md (pass / pass-with-notes);
  running the skill is the human approval, recorded in published.yaml. Parses the
  drop per references/drop-format.md, shows the block plan and stops for
  confirmation, uploads operator-supplied images, asks status/channel/audience,
  writes the article, writes published.yaml. Never edits the drop. Use when asked
  to "publish the [slug] drop" or "push the approved drop to Atobi".
allowed-tools: gdrive_find_by_path, gdrive_list_folder, gdrive_read_file, gdrive_upload_file, gdrive_trash_file, gcs_get_article, gcs_create_article, gcs_update_article, gcs_create_file_slot, gcs_list_channels, gcs_get_channel, us_list_audiences, search_memory, store_memory, verify_connection
metadata:
  version: "0.1.0"
  phases: [delivery]
---

# Publish

Take a drop that `ce-article-producer` wrote, `ce-review` passed, and a human approved, and make it an article on the Atobi platform. This is the only skill that writes *drops* to the platform; `ce-learning-article-creator` is the separate short flow that drafts directly on the platform without a drop.

Two references are load-bearing. **`references/drop-format.md`** is the contract for what a drop looks like — read it before parsing. **`references/block-shapes.md`** is the payload contract for `gcs_create_article` — read it before building. Do not build from memory of either.

Drive layout: the drop lives under the resolved Publisher's engine folder at `<engine_folder>/programs/<program>/drops/<slug>/`. Publisher config lives at `foundation/publishers/<publisher>/config.yaml` at the Shared Drive root (`GDRIVE_DEFAULT_ROOT_ID`). For dry-runs against `tests/`, `drop` may be a local folder path; read files with the shell instead of `gdrive_*` and skip every Drive write.

## Outcome

- **Platform**: one article created (create mode) or its block list replaced (update mode, draft only), as `draft` or `published`.
- **Drive**: `published.yaml` in the drop folder (prior one trashed, recoverable):

```yaml
# published.yaml — written by ce-publish v0.1; read by ce-reporting (program: mode)
article_id: <id>
title: "<title>"
shown_as: <training|article>
status: <draft|published>
channel_id: <id, omit for drafts>
channel_name: "<name, omit for drafts>"
audience_ids: [<ids, omit for drafts>]
published_at: "<YYYY-MM-DD>"
published_by: ce-publish v0.1
approved_by: "<email from verify_connection>"
approved_at: "<YYYY-MM-DD>"
approved_on_behalf_of: "<optional free text the operator gives, e.g. 'NB brand team, SPORT 2000 L&D'>"
review_verdict: <pass|pass-with-notes|forced>
```

- **Returned**: article id, web link (`https://<tenant>.atobi.io/articles/<id>`), status, mode (create/update), drop path, warnings.
- **Memory**: one `insight` row per run; one extra `user_explicit` row when `force` was used.
- **Never**: edits to `<slug>.md`, a second `gcs_create_article` call in the same run, a publish past a `fail` or stale verdict without `force`, or an update to an article that is already published.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `references/drop-format.md` | **full** | The parse rules. Every format error in Step 3 cites a section of this file. |
| `references/block-shapes.md` | **full** | The payload rules for Step 7. |
| `<drop>/<slug>.md` | full | The content. Frontmatter + body. |
| `<drop>/review.md` | full | The gate. Verdict line decides Step 2. |
| `<drop>/published.yaml` | if exists | Decides create vs update mode. |
| `foundation/publishers/<publisher>/config.yaml` | required | `engine_folder` (to expand shorthand paths) and the tenant (for `coverImage.tenantId` and the web link). Missing → ask, never guess. |
| `search_memory` playbook | best-effort | Only to echo the playbook date in the report header. Never blocks. |
| Operator-supplied image files | required if the drop references any | Uploaded in Step 5. |

## Skill relationships

- **Phase**: delivery
- **Often follows**: `ce-review` (its `review.md` is the gate), which follows `ce-article-producer`
- **Often precedes**: `ce-reporting` (reads `published.yaml` by `article_id`), `ce-update-article` (any change after the article is live)
- **Related**: `ce-learning-article-creator` — the *short flow*: drafts a topic straight onto the platform, no drop, no gate. Use that for internal or low-stakes content; use the drop flow (producer → review → this skill) for anything a brand or retailer signs off before it exists on the platform.

## Step 1: Resolve the drop and the publisher

`drop` is required. Accept three forms:

- Full Drive path `<engine_folder>/programs/<program>/drops/<slug>/`.
- Shorthand `<program>/<slug>` — expand with the publisher's `engine_folder`.
- A local folder path (dry-run). Detect by the path existing on disk. Read with the shell; skip every Drive write; say "dry-run: no Drive writes" in the report. In a dry-run, take `publisher` from the drop's frontmatter, skip the publisher config lookup, and use `0` as the tenant placeholder (the drop carries no tenant; it comes from `config.yaml` in a real run).

Resolve the publisher exactly as the other content-engine skills do: explicit `publisher` input → else the publisher already chosen this session → else `gdrive_find_by_path({ path: "foundation/publishers" })` + `gdrive_list_folder`, filter to folders; 1 → use it and echo; 2+ → ask and remember for the session; 0 → the drop path's engine folder is the only hint, ask the operator to confirm which publisher it belongs to.

Read `foundation/publishers/<publisher>/config.yaml`. Need `engine_folder` and the tenant binding (the key the feed-post skill reads for its tenant). Either missing → stop and ask; suggest adding the key so future runs don't ask.

Resolve the drop folder id via `gdrive_find_by_path`. Not found → stop: "drop not found at <path>". Don't create it — a typo'd slug must not mint a folder.

`verify_connection` once; keep the email for `approved_by`. If it fails, ask the operator for their name once and reuse it this session.

## Step 2: Gate — review verdict and existing article

**Review.** `gdrive_list_folder` the drop; look for `review.md`.

- Absent → stop. Say: "No review.md in <drop>. Run `ce-review` on this drop first. To publish anyway pass `force: true`; the override is recorded to memory."
- Present → read it; find the `**Verdict:**` line. `pass` / `pass-with-notes` → continue. `fail` → stop; echo every Critical and High finding's first line; say: "Fix through `ce-article-producer`, re-run `ce-review`, then publish."
- **Stale check.** Compare `modifiedTime` of `review.md` and `<slug>.md` from the `gdrive_list_folder` result (local dry-run: file mtimes). If `<slug>.md` is newer than `review.md`, the review describes text that no longer exists → stop: "review.md (<time>) is older than <slug>.md (<time>): the markdown changed after the last review. Re-run `ce-review`, then publish. To publish anyway pass `force: true`; the override is recorded to memory." A pass on old text is not a pass.
- `force: true` with any of the three stop conditions (absent, fail, stale) → ask the operator for a one-line reason, then continue. Immediately `store_memory({ tier: "insight", function_id: "content-engine", source_type: "user_explicit", importance: 7, content: "Forced publish of <drop> for <brand> past review (<absent|fail|stale>). Reason: <reason>. Approved by <email>." })`. `review_verdict` in `published.yaml` becomes `forced`.

**Existing article.** Look for `published.yaml`.

- Absent → **create mode**.
- Present → read `article_id`; `gcs_get_article({ id })`.
  - Not found → say "article <id> from published.yaml not found → create mode" and continue in create mode.
  - Found, status draft → **update mode**. Keep the fetched article (its `updatedAt` and current block count are needed in Step 7).
  - Found, published → stop: "Article <id> is live. Changes to a live article go through `ce-update-article`, which respects answer locking." Do not offer `force` here; there is no override for this.

## Step 3: Parse the drop

Read `<slug>.md`. Re-read `references/drop-format.md`, then validate in this order, collecting every violation before stopping:

1. **Frontmatter.** Exactly the nine allowed keys. Unknown key → violation "unknown frontmatter field: <key>". Missing `brand`, `publisher`, `program`, `slug` → violation. Missing `archetype`, `shown_as`, or `cover` → not a violation yet; ask the operator for each missing one (`AskUserQuestion`, archetype from the six options, shown_as from two, cover as a filename). Declined → violation.
2. **Body order.** First heading must be `## Status`. Exactly one `# ` H1 after it. Otherwise violations.
3. **Sections.** Each `## ` after the H1 opens a section. Content before the first `## ` (in an article with no sections) is one implicit section.
4. **Images.** Lines matching `![...](filename)` alone on a line. Collect filenames. An italic line immediately after is its caption.
5. **Knowledge checks.** Under each `### Knowledge check`, parse questions by marker (`**Q:**`, `**Poll:**`, `**Yes/No:**`, `**Open:**`), options by `- [ ]` / `- [x]`, feedback by `> Feedback:`. A marker may also appear directly in a section body without the `### Knowledge check` heading (flat articles); treat it the same. Apply the table in `drop-format.md § Knowledge check syntax`. Each rule breach is one violation quoting the question text.
6. **Forbidden content.** Any fenced code block or YAML block in the body → violation "YAML/code in body — drop-format.md forbids it".

Any violation → print all of them as a numbered list, each with the `drop-format.md` section it breaks, then stop: "Fix in the drop via `ce-article-producer` or by hand, re-run `ce-review`, then publish. This skill never edits the drop."

## Step 4: Block plan — the approval moment

Build the plan from the parse, using judgment only for text grouping within a section (a paragraph followed by a list may be one text block or two; a very long section may split at a `###`).

- `shown_as: training`: each `## ` section → a **section divider** text block (single level-1 heading item) followed by its content blocks. `### ` headings inside a section → level-2 headings inside text blocks, **except** `### Knowledge check`, which is a syntax marker and emits no heading block.
- No `## ` sections (flat article) → one implicit section, shown as `(none)` in the plan's Section column.
- `shown_as: article`: `## ` headings → level-2 heading items inside text blocks; no dividers.
- Image → image block (internal media, slot id filled in Step 5). Caption → a text block with an italic paragraph directly after.
- `**Q:**` → `multi_choice`, `mandatory: true` for training. `**Poll:**` → `multi_choice`, all `correct: false`, `required: 0`, `mandatory: false`. `**Yes/No:**` → `yes_no_task`; Atobi's yes/no block has no answer key, so the `[x]` marks the expected answer for reviewers only and is not sent in the payload. `**Open:**` → `open_question_task`.
- `> Feedback:` → the block shapes carry no feedback field, so feedback becomes a text block with one italic paragraph directly after its question block. Show it as its own row in the plan.

Print:

```
Title:      <H1>
Type:       <shown_as> · archetype <archetype> · <create|update (replaces N blocks)>
Cover:      <cover filename>
Images:     <list of inline filenames, or none>

Pos  Block            Section                    Detail
0    text (divider)   Who walks in asking for it
1    text             "                          "A runner who already owns…"
2    image            "                          side-profile.jpg
3    multi_choice     "                          3 options, correct [1], mandatory
4    text (feedback)  "                          "Soft is the design intent…"
...
```

Then **stop** with `AskUserQuestion`: "Publish this plan? Running past this point is recorded as your approval in published.yaml." Options: Yes / No. Also ask, optional free text: "Approved on behalf of anyone else (brand, retailer)? Leave blank if not." No → end the run; nothing written; say so.

## Step 5: Images

Every filename from Step 3 (cover + inline) must resolve to a local file. Look in `images` if given; otherwise ask for a path per file. Any file missing → stop: "Missing image file(s): <list>. Nothing was created." Do this BEFORE any platform write.

For each file, following `references/block-shapes.md § Uploading photos`:

1. If width > 1200 px: `sips -Z 1200 -s formatOptions 85 <in> --out <scratch>/<name>`.
2. `gcs_create_file_slot({ name: "<filename>", mimeType: "<image/jpeg|image/png>" })` → `{ id, uploadUrl, headers }`.
3. `curl -X PUT -H "x-ms-meta-__status: uploaded" <each header from the response> --data-binary @<file> "<uploadUrl>"` → expect HTTP 201.
4. Keep `filename → slot id`.

Any slot or PUT failure → stop; name the file; list slot ids already created (harmless orphans). Nothing else to undo.

## Step 6: Status, channel, audiences

`status` given → use it. Else ask: draft (default) or published.

Published only (skip entirely for draft):

1. `gcs_list_channels` → present names, ask which one.
2. `us_list_audiences` → present, ask (multi-select, at least one; refuse to continue on empty).
3. `gcs_get_channel({ channelId })` → if it is a feed channel, check `viewerAudiences ∩ chosen audiences` is non-empty. Empty → ask to change channel or widen audiences. Never fix silently.
4. Echo title, `shown_as`, channel, audiences before writing. Wrong channel + audience is the highest-risk failure of a published article.

## Step 7: Write the article and published.yaml

Build the payload per `references/block-shapes.md`, exactly:

- `variants.en.title` = H1; `translationStatus` = `draft` for draft, `approved` for published, mirrored on every block.
- `coverImage` = `{ type: "internal", id: <slot id for cover>, tenantId: <tenant> }`.
- Blocks in plan order with `position` 0..n, `parentId: null`, `version: 1`.
- Task blocks: `required: -1` (or `0` for polls), `public: false`, `audiences: []` for draft / the chosen ids for published, `deadline: null`, the one-year `schedule`, `mandatory` per Step 4. Question text in `variants.en.description`. Choices at block top level with `position`, `correct: true|false` (**never `isCorrect`**), `answerType: "string"`, `variants.en.answer` as a paragraph node. Feedback is the following text block from Step 4.
- Run the `## Pre-call checklist` in `block-shapes.md` — **payload-shape items only** (`format: {}`, `coverImage`, `schedule`/`required`/`mandatory`, choice fields, heading `level`, flat media, dividers, `translationStatus`, nullable and required fields, `languages[]`, publish fields). Skip its content-design items (title verb, hook, paragraph length, image position, quiz per section, benefit-first, interactive count, read time): those were the producer's job and `ce-review` already judged them. A drop that passed review is published as written.

**Create mode**: `gcs_create_article({ article: <payload> })`. Capture the id.

**Update mode**: use the article fetched in Step 2; replace its `blocks` with the new list, set the new `variants.en`, keep every other top-level field as fetched, pass its `updatedAt`. `gcs_update_article`. On 409: re-fetch once, re-apply, retry once; a second 409 → stop and report.

Then `published.yaml`: `gdrive_trash_file` any existing one, `gdrive_upload_file({ parent_id: <drop id>, name: "published.yaml", content, mime_type: "text/yaml" })` with the shape in Outcome. `approved_at` = today; `approved_by` = the Step 1 email; `approved_on_behalf_of` = the Step 4 answer or omitted; `review_verdict` from Step 2.

## Step 8: Report and capture

Print: article id · web link · status · mode · drop path · "published.yaml written" or the failure · warnings (dry-run notice, forced override, orphan slots).

`store_memory({ tier: "insight", function_id: "content-engine", source_type: "agent_extracted", importance: 5, content: "Published drop <program>/<slug> as article <id> for <brand>: <status>, <create|update>, review <verdict>, approved by <email><, on behalf of …>. Blocks: <counts by type>." })`.

If the `published.yaml` upload failed: print the full YAML block verbatim for a manual save, say the article exists, and **do not** call the article write again — a retry mints a duplicate. If `store_memory` fails: one line, run still counts as successful.

## Troubleshooting

- **"No review.md"** — the drop was never reviewed. Run `ce-review` first. `force: true` bypasses and is recorded; use it knowingly.
- **Review says fail but the findings were already fixed in the .md** — `review.md` is stale. Re-run `ce-review` so the file reflects the current markdown; don't `force` past a stale fail.
- **"review.md is older than <slug>.md"** — the markdown was edited (by the producer or by hand) after the last review. This is the loop working: re-run `ce-review`, then publish. If Drive shows a newer `modifiedTime` on the .md but nothing changed (e.g. a re-upload of identical content), re-review anyway — it is cheap and the trail stays honest.
- **Format errors on a drop the producer just wrote** — the producer is on a version before 0.4.0 and still embeds YAML / lacks the frontmatter cap. Upgrade the producer, regenerate, or fix the markdown by hand.
- **"unknown frontmatter field"** — the drop carries a field the contract doesn't allow (often a self-audit). Remove it; assessments belong in `review.md` only.
- **Article <id> is live** — no override. Use `ce-update-article`, which knows about answer locking.
- **Image upload 403 / expired** — the `uploadUrl` is valid ~1 hour; re-create the slot and PUT again. Never fall back to `gcs_upload_file_to_slot` for large files (base64 in the tool payload).
- **`coverImage` rejected** — `tenantId` missing or wrong. It comes from the publisher `config.yaml`; check the binding.
- **Feed channel with empty audience intersection** — the server will reject. Pick a non-feed channel for training content, or widen audiences.
- **409 on update twice** — someone is editing the article in the UI. Coordinate, then re-run.
- **`published.yaml` upload failed** — the article exists; save the printed YAML by hand. Never re-run the whole skill (duplicate article).
- **Wrong publisher inferred from the path** — multi-publisher drives make engine-folder inference unreliable; confirm the publisher before Step 7, re-run if wrong.
- **`Insufficient scope: atobi-mcp:admin required`** — the token lacks the admin scope gating `gdrive_*`/memory tools; same failure mode as `foundation-memory-roundtrip`.
