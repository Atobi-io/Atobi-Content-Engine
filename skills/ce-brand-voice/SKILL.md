---
name: ce-brand-voice
description: >
  Author or refresh the brand voice triplet in foundation/brands/[brand]/ —
  voice-profile.md (required, using the 10-section template in
  references/), fidelity-rules.md and glossary.md (when the
  evidence supports them). Researches the brand's live Atobi tenant
  (read-only), website, and social media, plus Drive source material and
  accumulated memory corrections, then fills the template with a short
  operator interview covering only the gaps — every entry carries a
  provenance stamp, and nothing uploads without operator sign-off. This is
  the onboarding gate for new brands: producers refuse to write without a
  voice profile. Use when asked to "onboard [brand]'s voice", "create a
  voice profile for [brand]", "refresh the [brand] voice profile", or when
  a producer run stopped because the profile is missing.
allowed-tools: gdrive_find_by_path, gdrive_list_folder, gdrive_search_files, gdrive_read_file, gdrive_create_folder, gdrive_upload_file, gdrive_trash_file, verify_connection, gcs_list_channels, gcs_list_articles, gcs_get_article, gcs_list_comments, rc_list_achievements, search_memory, store_memory, WebFetch, WebSearch
metadata:
  version: "0.2.0"
  phases: [intake]
---

# Brand voice

Author (or refresh) the voice profile every producer skill loads before writing a word for a brand. Today these are hand-seeded; this skill derives them from evidence — the brand's live Atobi tenant, its website and socials, its own guideline documents, and the corrections operators have already made — then gets explicit sign-off before anything lands in `foundation/brands/<brand>/`. A voice profile steers **every future article, journey, and feed post** for the brand: this is the highest-blast-radius artefact in the content engine, which is why sign-off is mandatory, not optional.

## Outcome

Up to three files in `foundation/brands/<brand>/`, uploaded only after operator sign-off:

- **`voice-profile.md`** — always produced, structured by `references/voice-profile-template.md` (10 sections: Brand Identity, Staff Personas, Tone of Voice, Vocabulary Guide, Product Universe, Partners, Content Patterns, Cultural & Seasonal Calendar, Do's and Don'ts, Sample Copy). The file `ce-article-producer` / `ce-feed-post-branded` refuse to run without.
- **`fidelity-rules.md`** — produced only when the evidence supports it (locked phrases, banned phrases, claim rules, competitor policy). **An invented fidelity file is worse than none**: producers skip an absent file silently, but a wrong one actively misleads every run.
- **`glossary.md`** — produced only when locked product names / multi-language forms are actually known from sources or the operator.
- **Returned**: file ids + web view links, an evidence summary (what each section was derived from), and the list of entries marked `inferred — confirm` that the operator accepted provisionally.
- **Naming note**: the canonical path is `foundation/brands/<brand>/voice-profile.md` — producers hardcode it. The older `[customer-name]_voice-profile.md` convention from the template's original prompt is superseded by this path.
- **Idempotency / refresh**: if the triplet already exists, the skill runs in refresh mode — it proposes a **diff with reasons**, never a silent rewrite. Prior versions are trashed (recoverable) before re-upload.
- **Side effects**: may create `foundation/brands/<brand>/` for a brand-new brand (explicitly confirmed first); appends one `insight` memory row per run. **Never writes to the Atobi tenant** — tenant research is strictly read-only.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `references/voice-profile-template.md` | full | The authoritative profile structure. Fill it; don't invent a parallel format. |
| `foundation/brands/<brand>/voice-profile.md` + siblings | if exists | Existing triplet → refresh mode; its signed-off entries are preserved unless newer evidence contradicts them. |
| Live Atobi tenant (`gcs_*`, `rc_*`, read-only) | scoped | Existing articles, feed posts, channel names, achievement names, named series — the most direct signal of what already works (template §7). |
| Brand website + social media (`WebFetch`/`WebSearch`) | scoped | Brand copy, headline style, product lines, collaborations, tone in the wild (template §1, §3–§6, §8). |
| `source-material/` guideline docs + `*.extract.md` | full / section | Brand book / tone-of-voice docs (strongest tier) and `ce-asset-intake` extracts — how the brand talks about itself. |
| `search_memory` playbook + insights | best-effort | Operator corrections ("stop saying game-changer for Hoka") are voice mistakes already paid for once. |
| `foundation/publishers/<publisher>/voice-profile.md` | reference | Defines the layering boundary — what NOT to put in the brand file (Step 6). Resolve the publisher like the brand (session-sticky; reuse this session's choice, list `foundation/publishers/` and ask when 2+, skip the layer when 0). Skip silently if absent. |

## Skill relationships

- **Phase**: intake
- **Often follows**: `ce-asset-intake` (extracts double as voice evidence — run intake first when the brand folder has unprocessed PDFs); a new brand landing in the engine
- **Often precedes**: `ce-article-producer`, `ce-learning-article-creator`, `ce-feed-post-branded` — all load this skill's outputs; unblocks the "voice profile missing" refusal path in each
- **Related**: `ce-remember` (its `insight` corrections feed refresh runs); planned `ce-blueprint` (new-brand onboarding would call this as its voice step)

## Step 1: Validate inputs

No input is strictly required. Optional: `brand` (resolved in Step 2), `sources` (comma-separated name fragments pointing at the brand's own voice documents), `refresh_focus` (scope a refresh to one template section instead of the whole triplet).

Useful but optional context to ask for in one breath if the operator hasn't given it: the brand's website URL, social handles, and — when researching tenant content — which Atobi tenant to read. Missing pieces just mean that evidence tier is skipped.

## Step 2: Resolve the brand

Same discovery pattern as the producers: if `brand` was supplied, verify `foundation/brands/<brand>/` via `gdrive_find_by_path`; if omitted, list `foundation/` and branch on count (0: stop; 1: use it and say so; 2+: ask). Never fuzzy-match.

**Brand-new brand** (folder doesn't exist and the operator confirms it's a genuinely new onboarding, not a typo): ask explicitly before `gdrive_create_folder`-ing `foundation/brands/<brand>/`. Creating a folder for a mistyped slug pollutes the brand list every future discovery run sees.

## Step 3: Detect mode — create vs refresh

Check for the three triplet files. Any of them present → **refresh mode**: load what exists, and treat it as the baseline the operator already approved. Nothing present → **create mode**.

In refresh mode with a `refresh_focus`, scope evidence-gathering and drafting to that focus; leave the rest of the file byte-identical.

## Step 4: Gather the evidence

Load `references/voice-profile-template.md` first — it defines what you're looking for (each template section names its data sources in brackets). Collect evidence per tier below, and track **where every candidate entry came from** — provenance stamps are written into the files in Step 6. The template's filter applies throughout: *only include information that changes how content is written*; background trivia doesn't survive into the profile.

**4a — The live Atobi tenant (read-only — hard rule: no actions, no comments, no reactions, no interaction of any kind).** The most direct signal of what already works (template §7, plus names for §5/§6):

- `gcs_list_channels` → channel names and what content lives where
- `gcs_list_articles` (+ `gcs_get_article` for a representative handful) → article titles, headline patterns, format preferences, named content series
- Feed posts → post style, length, emoji use, CTA patterns; `gcs_list_comments` on a few high-engagement pieces → what triggers engagement
- `rc_list_achievements` → achievement/badge naming style, reward mechanics

Real titles, post lines, and badge names collected here feed template §10 (Sample Copy) — actual copy trains voice better than any description.

**4b — Website and social media (`WebFetch` / `WebSearch`).** Capture brand copy and headline style (§3), taglines and positioning (§1), product lines, categories, named programmes and hero products (§5), active collaborations and league affiliations (§6), seasonal moments (§8), and the tone/vocabulary they use in the wild (§4). Note what they amplify on social and any recurring formats.

**4c — The brand's own guideline documents (strongest tier when present).** Search `source-material/` for the brand speaking about its own voice:

```
gdrive_search_files: '<source-material-id>' in parents and
  (name contains 'brand' or name contains 'voice' or name contains 'tone'
   or name contains 'guideline' or name contains 'style') and trashed = false
```

If `sources` was supplied, resolve those fragments instead. Mine for stated tone words, explicit do/don't lists, banned vocabulary, audience definitions, claim policies, locked taglines.

**4d — How the brand writes in its materials.** Load available `*.extract.md` files (or up to 3 raw marketing-copy assets if no extracts exist — suggest running `ce-asset-intake` first when the folder is full of unprocessed PDFs). Mine "Selling points & claims" for phrasing, rhythm, vocabulary. Locked product spellings feed the glossary.

**4e — Operator corrections (memory).** Best-effort, never blocking:

```json
search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
search_memory({ "query": "<brand>", "tier": "insight", "function_id": "content-engine", "limit": 20 })
```

Playbook **Locked** / **Tone / voice** bullets and voiced-preference insights are corrections already paid for once — a profile that omits them guarantees the same correction gets made again. Fold them in at high confidence (mostly into §9 Do's and Don'ts and §4 Avoid).

**4f — The publisher layer (boundary, not content).** Resolve the publisher (same routine as brand discovery, against `foundation/publishers/`; reuse the session's choice, ask when 2+, skip when 0) and read `foundation/publishers/<publisher>/voice-profile.md` if present — not to copy from, but to know what to leave OUT (see Step 6's layering rule).

If the evidence is thin across 4a–4e (no tenant presence yet, no guideline docs, few extracts), say so plainly and lean harder on Step 5 — a profile derived from two spec sheets is mostly guesswork and must be marked as such.

## Step 5: Interview the operator — gaps only

Ask **one batched round** of questions covering only the template fields the evidence didn't answer. §2 (Staff Personas) usually needs the operator most — it's the template's own "most important section" and rarely derivable from public sources: who the staff are, what blocks them, what motivates them, what device/context they read on. Other typical gaps: forbidden words the brand cares about, competitor naming policy, claim-substantiation rules, internal milestones (§8). Skip anything already evidenced — re-asking what the brand book states wastes the operator's attention and signals the sources weren't read.

Operator answers are provenance tier `(operator, YYYY-MM-DD)` — equal in authority to the brand's own documents.

## Step 6: Fill the template

Produce `voice-profile.md` by filling `references/voice-profile-template.md` section by section. Discipline:

- **Every entry ends with a provenance stamp** — `(tenant: article titles)`, `(website)`, `(instagram)`, `(brand-book.pdf)`, `(extract: ghost-18)`, `(playbook)`, `(operator, 2026-07-16)`, or `(inferred — confirm)`. **Never write brand voice from category stereotype** ("running brands sound energetic") — anything not traceable is either dropped or explicitly stamped `inferred — confirm` for the operator to accept or kill in Step 7.
- **The template's own filter is law**: a field that doesn't change how content is written stays blank or gets deleted. A short profile of load-bearing entries beats a complete-looking one padded with trivia.
- **§10 Sample Copy uses real copy** collected in 4a/4b wherever possible — paste actual feed posts, article titles, badge names (marked as real); write ideal ones only where nothing real exists (marked as ideal).
- **Layering rule:** the brand file carries only **brand-distinctive** rules. Per the engine's conflict-resolution (claims & product language → brand wins; tone, structure, writing discipline → publisher wins), generic writing discipline the publisher layer already imposes doesn't belong here.
- Fill the footer: last-updated date, `ce-brand-voice v0.1 + <operator>`, and the actual data sources used.

**`fidelity-rules.md`** (only with real signal): `## Locked phrases` (verbatim, with source), `## Banned phrases`, `## Claim rules` (what performance/regulated claims are allowed and what substantiation they need), `## Competitor policy`. Overlap with the profile's §4 Avoid table is fine — fidelity is the enforcement-grade subset producers treat as hard constraints.

**`glossary.md`** (only with real signal): a table — `| Product / term | Locked form | Notes / languages |`.

**Refresh mode:** produce a **proposed diff, not a new file** — per change: what, and the evidence that motivated it. An operator-signed entry is only removed/weakened when newer evidence contradicts it, and the diff says so explicitly. Bump the footer stamp; keep untouched sections byte-identical.

## Step 7: Operator sign-off — mandatory

Present the full drafts (or the diff, in refresh mode) plus the list of `inferred — confirm` stamps. Iterate until the operator approves. **No upload without explicit approval** — unlike a drop article, these files silently steer every future run for the brand; a bad rule here is a systemic error, not a one-off. If the operator goes quiet, stop with the drafts in the response — don't upload "provisionally".

Record which fidelity/glossary files the operator agreed to *omit* (thin evidence) so the report doesn't read as a failure.

## Step 8: Save to Drive

For each approved file: if a prior version exists, `gdrive_trash_file` it first (recoverable history), then `gdrive_upload_file` into `foundation/brands/<brand>/` with `mime_type: "text/markdown"`. Use ids from responses directly — don't re-resolve fresh items via path (Drive index lag).

## Step 9: Report

Print: file names + ids + web view links; evidence summary per template section (which sources shaped it); accepted `inferred — confirm` entries (these are the ones to watch in the first few production runs); omitted files and why; and the suggested next step — run a producer against the brand and see if the output sounds right, because the profile's real test is its first article.

## Step 10: Capture to the event stream (memory)

Best-effort, one row:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 6,
  "content": "Voice triplet <authored|refreshed> for <brand>: <files written>. Evidence: <tenant / website / socials / guideline docs / extracts / playbook / operator interview>. Inferred-confirm entries accepted: <n>. Omitted: <files + reason>. Notes: <anything unusual>."
})
```

Preferences the operator voiced *about the process itself* ("never ask me about competitor policy, we have one global rule") → separate `insight`, `source_type: "user_explicit"`, `importance: 7`. If `store_memory` errors, report one line and treat the run as successful.

## Troubleshooting

- **No tenant presence, no guideline docs, almost no source material** — the profile would be interview-only. Say so and offer: (a) proceed operator-interview-only with everything stamped `(operator, ...)`, (b) pause until the brand supplies material, or (c) run `ce-asset-intake` first if there are unprocessed PDFs. Don't quietly produce a stereotype profile.
- **Tenant research tools return another tenant's content or nothing** — the MCP session is bound to one tenant; confirm with `verify_connection` which tenant the token belongs to before assuming the brand has no content. Never widen the search by interacting with the platform.
- **Producers still write off-voice after the profile landed** — check the failing rules are *auditable* (concrete phrases, not "be bold"), and that the violated rule is in **§9 Do's and Don'ts** or **§4 Avoid** (which producers audit line-by-line) rather than buried in §1 positioning prose.
- **Profile conflicts with the publisher voice** — expected for claims/product language (brand wins); a conflict on tone/structure means the brand file overstepped the layering rule — move that rule out or mark it as a deliberate brand override.
- **Operator wants to hand-edit the files directly in Drive** — fine; that's why they're Markdown. On the next refresh run, treat hand edits as operator-tier evidence to preserve, not drift to revert.
- **Refresh wiped entries the operator liked** — refresh mode must diff against the existing file, never regenerate from scratch. Restore from Drive trash (prior version was soft-deleted, not destroyed) and re-run with the diff discipline.
- **Two brands share a parent company style guide** — author each brand's file separately anyway; stamp shared rules with the shared source. "See other brand" references break producers, which load exactly one brand's files.
- **`Insufficient scope: atobi-mcp:admin required`** — the OAuth token lacks the admin scope gating `gdrive_*`/memory tools; same failure mode as `foundation-memory-roundtrip`.
