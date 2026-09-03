# Atobi article block shapes

Payload rules for `gcs_create_article` / `gcs_update_article`. Copied verbatim from
`ce-learning-article-creator` SKILL.md Step 7 on 2026-09-03 (spec D10). Until the
creator points here, keep the two in sync: any correction lands in both.

Read this whole file before building a payload. The gotchas at the end of "Task
blocks" (`correct` not `isCorrect`; question in `description` not `title`; `answer`
is a paragraph node) have each broken a real article.

## Top-level fields

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

## Block skeleton (all blocks)

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

## Uploading photos (operator-supplied files)

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

## Section dividers (REQUIRED for `shownAs: "training"` — Journey UX)

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

## Text block

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

## Image block

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

## Video block

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

## Task blocks (multi_choice, yes_no_task, open_question_task, simple_task)

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

## Pre-call checklist

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

