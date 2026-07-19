---
name: ce-asset-intake
description: >
  Normalize raw brand assets (PDF product sheets, campaign decks, spec docs)
  from foundation/brands/[brand]/source-material/ into structured, searchable
  markdown extracts saved next to the originals, plus an intake index tracking
  what has been processed. Extracts are what the producer skills actually find
  and load — raw image-heavy PDFs often aren't fullText-searchable in Drive.
  Binary formats (PDF, docx, pptx) can't be read via gdrive_read_file
  (metadata only) — the primary read path is an operator-supplied copy of the
  file (attachment in Claude Desktop, local path in Claude Code) read with
  Claude's native document processing; a same-named Google-Docs conversion
  copy in Drive is the fallback. The skill flags what it can't source rather
  than guessing at content.
  Idempotent: re-runs only process new or changed source files. Use when asked
  to "process the new [brand] PDFs", "intake the assets for [brand]", "ingest
  brand source material", or before a production run against fresh uploads.
allowed-tools: gdrive_find_by_path, gdrive_list_folder, gdrive_search_files, gdrive_read_file, gdrive_create_folder, gdrive_upload_file, gdrive_trash_file, search_memory, store_memory, Read, Agent
metadata:
  version: "0.2.0"
  phases: [intake]
---

# Asset intake

Turn raw brand uploads in `foundation/brands/<brand>/source-material/` into normalized markdown extracts the production skills can reliably discover and load. This is the first mile of Mode 1 ("PDF in, Journey out"): today producers search source material by `name contains` / `fullText contains`, which silently misses image-heavy PDFs and decks — an extract is plain markdown, so it always indexes. Invoke when new assets land, or before a production run against a brand whose material hasn't been processed.

## Outcome

One extract per raw asset, plus an index, all inside the brand's existing source-material folder:

- **Extracts**: `foundation/brands/<brand>/source-material/<asset-slug>.extract.md`
  - `<asset-slug>` derived from the source file name (lowercase, hyphen-separated, extension dropped, ≤60 chars)
  - Saved as a **direct child** of `source-material/` — deliberately, so the producers' existing `'<folder-id>' in parents` search finds extracts with zero changes to those skills
  - Format: YAML frontmatter (source id, modified time, asset type, products, topics, season, language) + normalized body — see Step 5
- **Index**: `foundation/brands/<brand>/source-material/_intake-index.md` — one table row per source asset: name, source id, source `modifiedTime`, extract name, processed date, status (`extracted` / `needs-source` / `unreadable` / `skipped`)
- **Returned**: a run summary table (asset → status → topics found), and the list of anything unreadable so the operator can supply text another way
- **Idempotency**: a source file whose Drive `modifiedTime` matches its index row is skipped unless `force=true`. Re-extracting soft-deletes the prior extract (recoverable from Drive trash) before uploading the new one.
- **Side effects**: may create `source-material/` if the brand folder exists but has no source-material folder yet; appends one `insight` memory row per run.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `foundation/brands/<brand>/source-material/` | enumerate | The work queue — every non-extract file here is a candidate asset. |
| Each candidate asset | full, batched | The content being extracted. Loaded one at a time in Step 5. |
| `source-material/_intake-index.md` | if exists | Prior-run ledger; drives the new/changed/unchanged diff in Step 4. Absent on first run — that's fine. |
| `foundation/brands/<brand>/glossary.md` | best-effort | Locked product names and multi-language forms — extracts must use the locked spellings so downstream search hits them. Skip silently if absent. |
| `search_memory` (substrate) | best-effort | Recent intake insights for this brand (e.g. "the SS26 deck is superseded"). Continue silently if absent — never block on memory. |

## Skill relationships

- **Phase**: intake
- **Often follows**: a brand dropping new files in Drive; brand onboarding (folder seeded by hand today; `ce-brand-voice` / `ce-blueprint` when they exist)
- **Often precedes**: `ce-article-producer`, `ce-learning-article-creator`, `ce-quiz-generator` — all of which discover source material by searching `source-material/` and now find extracts first
- **Related**: `ce-remember` (shares the memory event stream); planned `ce-brief` / `ce-blueprint` would consume the same extracts

## Step 1: Validate inputs

No input is strictly required. Optional inputs: `brand` (resolved in Step 2), `files` (comma-separated names or fragments to restrict the run), `force` (defaults to `false`).

If `files` is given, treat each entry as a name fragment to match in Step 4 — don't require exact names; surface what matched before processing so a too-loose fragment gets caught.

## Step 2: Resolve the brand

Same discovery pattern as `ce-article-producer`: if `brand` was supplied, verify `foundation/brands/<brand>/` exists via `gdrive_find_by_path`; if it doesn't, or if `brand` was omitted, list the folders under `foundation/brands/` and branch on count — 0: stop and say no brands are seeded; 1: use it and surface the choice; 2+: ask the user which one. Never fuzzy-match a brand.

Then resolve `foundation/brands/<brand>/source-material/`. If the brand folder exists but the source-material folder doesn't, ask before creating it — an empty folder means there is nothing to intake, and the user may have uploaded assets somewhere else by mistake.

## Step 3: Load the intake index and glossary

`gdrive_read_file` on `source-material/_intake-index.md` if it exists. Parse the table into a map keyed by source file id: `{ name, modifiedTime, extractName, status }`. First run → empty map.

Best-effort, skip silently if absent:

- `foundation/brands/<brand>/glossary.md` — locked product names; extracts must spell products exactly as the glossary locks them.
- `search_memory({ "query": "<brand> intake", "tier": "insight", "function_id": "content-engine", "limit": 10 })` — recent intake context (superseded decks, known-bad files). Shapes judgment; never blocks.

## Step 4: Enumerate and diff the assets

`gdrive_list_folder` on `source-material/`. Partition the children:

- **Skip outright**: `*.extract.md`, `_intake-index.md`, sub-folders (v0 does not recurse — say so in the report if sub-folders exist and contain files)
- **Readable candidates**: Google-native files (Docs, Slides, Sheets — `gdrive_read_file` auto-exports them) and textual formats (plain text, markdown, CSV, JSON)
- **Needs conversion**: binary formats — PDFs, docx/pptx, images. `gdrive_read_file` returns metadata only for these (that's the tool's contract, not a property of the file), so they can't be extracted directly — see the conversion flow below

Diff each candidate against the index map:

| Condition | Classification |
|---|---|
| Not in index | **new** |
| In index, Drive `modifiedTime` differs | **changed** |
| In index, `modifiedTime` matches | **unchanged** — skip unless `force=true` |
| Index row exists but the source file is gone from Drive | **orphaned** — flag; ask whether to trash the stale extract |

If `files` was given, further restrict to candidates matching a fragment.

**Binary assets — the operator-supplied source flow (primary).** `gdrive_read_file` returns metadata only for binary formats, but Claude reads PDFs/documents natively and with high fidelity — layout, tables, and design-heavy pages included. So for each binary asset, ask the operator for a copy of the file: an **attachment** (Claude Desktop / claude.ai) or a **local path** (Claude Code — often already in `~/Downloads`, since the operator usually uploaded the Drive original themselves). Read that copy natively and stamp the extract's frontmatter with the **original Drive asset's** name/id/modifiedTime plus `read_via: "operator-supplied copy"` — idempotency keys on the Drive original, and the local copy is plumbing. The operator only confirms the copy matches the Drive file (same name/version); if unsure, treat it as not supplied.

**Large documents — parallel page-range readers.** Native reads are paged (~20 pages per call). Past ~40 pages, don't serially read in one context: split the page range across parallel subagents (e.g. 1–40 / 41–80 / 81–end), each returning compact spec-dense notes under the Step 5 discipline, then merge into ONE extract. Check the real PDF page count first — dealer copies are often composites (catalog pages interleaved with annotation pages and sell sheets), so printed folios ≠ PDF pages; if a section isn't where the TOC says, keep reading past it rather than declaring it missing.

**Fallbacks, in order**: (1) a same-named Google-Docs conversion copy already in Drive (Drive's "Open with Google Docs"; OCRs scans) — extract from it, record `converted_copy_id`, stamp the original's id; (2) neither copy nor conversion available → record the asset as `needs-source` in the index and the report, and ask the operator to supply the file, then re-run. Never infer a binary file's content from its name.

**Present the plan and wait**: list new / changed / unchanged(skipped) / needs-source / orphaned, and the batch you intend to process. If the batch exceeds ~10 files, propose processing the 10 most recently modified first and ask how to handle the rest — a 40-file first-time intake is better run in confirmed chunks than one silent marathon.

## Step 5: Extract each asset

For each asset in the confirmed batch, read it — `gdrive_read_file` for Google-native/textual files; for binary assets, the operator-supplied copy read natively (or the conversion-copy fallback) per Step 4 — then write an extract in this exact shape:

```markdown
---
source_name: "<original file name>"
source_id: "<drive file id>"
source_modified: "<Drive modifiedTime, verbatim>"
read_via: "<operator-supplied copy | conversion copy | gdrive_read_file — how the content was actually read>"
converted_copy_id: "<Google-Docs copy id — only when read via a conversion copy>"
extracted: "<YYYY-MM-DD>"
asset_type: product-sheet | campaign-deck | spec-doc | vm-guide | lookbook | glossary | other
brand: <brand>
products: [<locked product names, per glossary if loaded>]
topics: [<5-12 lowercase keywords a producer would search for>]
season: "<e.g. SS26, or omit>"
language: "<primary language of the source>"
---

# <Asset title — from the document, not invented>

## Summary
<3-5 sentences: what this asset is, who it's for, what it covers.>

## Products & specs
<One sub-section per product. Specs, materials, sizes, prices, tech names — numbers and units verbatim from the source.>

## Selling points & claims
<Claims the brand itself makes, quoted or closely paraphrased. Mark anything that looks like a regulated/performance claim with ⚠ so fidelity review can check it.>

## Audience & usage notes
<Who the brand says this is for; retail-relevant guidance (fit advice, comparison points, FAQ answers).>

## Assets referenced
<Images, videos, other documents the source points at — name + where they live, so a producer knows visual material exists.>

## Open questions
<Anything unreadable, ambiguous, contradictory, or missing. Empty section is fine.>
```

Extraction discipline — this is the step that determines whether downstream articles are grounded or hallucinated:

- **Facts only.** Every spec, number, and claim comes from the source. Never fill a gap from general product knowledge — a missing weight is an Open question, not a guess.
- **Numbers verbatim.** Units, prices, percentages exactly as written, currency symbols included.
- **Locked names win.** If the glossary locks a product spelling, use it even when the source itself is inconsistent.
- **Uncertain → flagged.** Garbled OCR, ambiguous tables, contradictions between pages: quote what's there and put the doubt in Open questions with a `(?)`.
- **Topics are for search.** Pick the words an operator would actually type ("ghost 18", "cushioning", "ss26 launch"), not marketing abstractions.

If the read yields nothing usable (e.g. a conversion copy of a scan whose OCR produced garbage), do not fabricate an extract. Record the asset as `unreadable` in the index and the report; suggest the operator export a text version or paste key content inline.

## Step 6: Save extracts and update the index

For each produced extract: if the index says a prior extract exists, `gdrive_trash_file` it first (recoverable history), then `gdrive_upload_file` the new one into `source-material/` with `mime_type: "text/markdown"`. Use folder/file ids returned by earlier calls directly — don't re-resolve via path (Drive's search index lags on fresh items).

Then regenerate `_intake-index.md` **in full** — header note ("maintained by ce-asset-intake — do not hand-edit"), run date, and one row per known source asset (including unchanged and unreadable ones). Trash the old index file, upload the new one. Regenerating whole beats patching rows — the index must mirror reality, and partial edits are how it drifts.

## Step 7: Report

Print, in order:

- Run summary table: asset name → status (`extracted` / `skipped (unchanged)` / `needs-source` / `unreadable` / `orphaned`) → products/topics found
- Extract file names and the index's `webViewLink` so the operator can click through
- Anything that needs a human: unreadable files, orphaned extracts awaiting a decision, sub-folders that were not recursed into

## Step 8: Capture to the event stream (memory)

Best-effort, one row, regardless of partial failures upstream:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 5,
  "content": "Asset intake for <brand>: <n> extracted, <n> skipped (unchanged), <n> needs-source, <n> unreadable (<names>). Read paths used: <gdrive / operator-supplied / conversion copy>. Products covered: <list>. Notes: <anything unusual — superseded deck, glossary conflicts, operator decisions>."
})
```

If any operator preference was voiced during the run (e.g. "always treat lookbooks as campaign-decks", "ignore the archive folder"), capture each as a separate `insight` with `source_type: "user_explicit"`, `importance: 7`, phrased as general brand/intake guidance. If `store_memory` errors, report it in one line and treat the run as successful — the extracts exist; a missed capture only degrades future learning.

## Troubleshooting

- **`source-material/` not found under an existing brand** — assets were probably uploaded elsewhere (brand root, a personal folder). `gdrive_list_folder` the brand folder and show the user what's actually there before creating anything.
- **A PDF (or docx/pptx) comes back as metadata + webViewLink only** — that's `gdrive_read_file`'s contract for binary types, not a damaged file. Route it through Step 4's operator-supplied source flow (primary) or the conversion-copy fallback. The long-term fix is PDF text extraction in atobi-mcp itself (service-account `files.get alt=media` + text extraction, or automated `files.copy` → Google Doc → export → trash).
- **A huge catalog PDF blows up the reading context** — don't read 100+ pages serially in one context. Split page ranges across parallel subagents per Step 4, each returning compact notes; merge into one extract. Verified live: a 142-page composite dealer catalog extracted cleanly via 4 parallel readers.
- **Sections aren't where the TOC says** — the PDF is a composite (dealer annotations, sell sheets, analytics slides interleaved with catalog pages), so printed folios drift from PDF pages. Keep reading past the expected location; check the file's real page count before assuming a section is missing.
- **Operator-supplied copy might not match the Drive original** — confirm name/version with the operator before extracting; if they're unsure, treat the asset as `needs-source`. The extract stamps the Drive original's id/modifiedTime, so a mismatched copy would poison idempotency silently.
- **Producer still can't find an extract by topic** — check the extract's `topics` frontmatter and body use the operator's actual search words, and that the extract sits directly in `source-material/` (not a sub-folder — the producers' search is `'<id>' in parents`, non-recursive).
- **Two source files slug to the same `<asset-slug>`** — e.g. `Ghost 18.pdf` and `ghost-18.pptx`. Disambiguate with the extension or a qualifier in the slug (`ghost-18-pdf.extract.md`); never let one extract silently overwrite another's.
- **Index says `extracted` but the extract file is missing** — someone hand-deleted it. Treat the source as **changed** (re-extract) and regenerate the index; the index is a cache of reality, not the authority.
- **Freshly-uploaded extract not visible via `gdrive_find_by_path`** — Shared-Drive search-index lag on new items. Use ids from the upload responses directly instead of re-resolving paths.
- **`Insufficient scope: atobi-mcp:admin required`** — the OAuth token lacks the admin scope that gates `gdrive_*` and memory tools; same failure mode as `foundation-memory-roundtrip`.
