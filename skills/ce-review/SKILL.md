---
name: ce-review
description: >
  Independent brand-compliance review of produced content — a Drive drop
  article or a live Atobi article — before human review or publish. Re-loads
  the brand's voice profile, fidelity rules, glossary, and memory playbook
  from source (never trusting the producer's own summary) and audits the
  content line-by-line across five dimensions: fidelity, factual grounding,
  voice, audience fit, and structure/quiz quality. Produces a severity-tagged
  findings report (Critical/High/Medium/Low/Info) with an overall
  pass / pass-with-notes / fail verdict. Report-only: fixes go back through
  the producer or ce-update-article. Use when asked to "review the [slug]
  drop", "check article [id] against the [brand] voice", "run brand
  compliance on this before it ships", or as the check step after any
  producer run.
allowed-tools: gdrive_find_by_path, gdrive_list_folder, gdrive_search_files, gdrive_read_file, gdrive_upload_file, gdrive_trash_file, gcs_get_article, search_memory, store_memory
metadata:
  version: "0.3.0"
  phases: [quality]
---

# Review

Audit a produced piece of content against everything the brand's rules actually say — before a human reviewer or a publish step sees it. This is the engine's adversarial-verification step: the reviewer **re-derives the criteria from source** (voice triplet, extracts, playbook) and checks the content cold, exactly because the producer already believes its output complies. A review that trusts the producer's own voice-audit is theater; this skill exists to be the second, independent pair of eyes.

Report-only by design: findings go to the operator (and a `review.md` next to Drive drops), and fixes flow back through the producer or `ce-update-article` — keeping who-changed-what clean.

## Outcome

A severity-tagged findings report with an overall verdict:

- **Verdict**: `pass` (no findings above Low) / `pass-with-notes` (Mediums worth a human glance) / `fail` (any Critical or High — don't publish as-is)
- **Findings**, most severe first. Each carries: severity (`Critical / High / Medium / Low / Info`), dimension, **location** (quote the offending line or name the block/action), **the rule violated with its source** (`fidelity: banned phrase (fidelity-rules.md)`, `playbook Locked bullet, 2026-05-12`), and a concrete suggested fix
- **Saved artefact** (Drive drops, `save_report` true): `programs/<program>/drops/<slug>/review.md` — verdict, findings, criteria versions used (which files, their last-updated stamps), review date. A prior `review.md` is trashed (recoverable) before upload — the file always reflects the latest review.
- **Returned**: the report (chat always; file id + link when saved), plus recurring-violation signals if this brand keeps failing the same rule (see Step 8)
- **Never**: edits to the content under review, publishes, or fidelity checks against rules the reviewer invented — no finding without a sourced rule behind it

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| The content under review (drop `.md` or `gcs_get_article`) | full | The subject. For live articles, includes blocks and `multi_choice` actions (quizzes). |
| `foundation/brands/<brand>/voice-profile.md` | full | Criteria for voice, audience, structure dimensions (§2–§4, §7, §9 especially). Without it the review degrades — see Step 3. |
| `foundation/brands/<brand>/fidelity-rules.md` | if exists | Hard constraints: locked/banned phrases, claim rules, competitor policy. Absent → fidelity dimension runs on glossary + playbook only, noted in the report. |
| `foundation/brands/<brand>/glossary.md` | if exists | Locked product spellings — every product mention is checked against it. |
| `source-material/*.extract.md` | scoped | Grounding evidence: every spec/number/claim in the content must trace to an extract (or other loaded source). |
| `search_memory` playbook | best-effort | **Locked** bullets are review criteria equal to fidelity rules — they're corrections the operator already made once. |
| `foundation/publishers/<publisher>/voice-profile.md` | reference | Layering: tone/structure findings defer to the resolved Publisher's rules when the brand file is silent. Skip if no publisher resolved or the file is absent. |

## Skill relationships

- **Phase**: quality
- **Often follows**: `ce-article-producer`, `ce-learning-article-creator`, `ce-feed-post-branded` — review their output before it moves on; also `ce-update-article` (re-review after a fix)
- **Often precedes**: human approval (CaaS Step 5), `ce-publish` (reads this skill's `review.md` verdict as its gate — `pass` / `pass-with-notes` proceed, `fail` blocks), `ce-update-article` (applying accepted findings to a live article)
- **Related**: `ce-brand-voice` (authors the criteria this skill enforces; recurring violations feed its refresh mode); `ce-quiz-generator` (its conventions are the quiz-quality criteria); `ce-asset-intake` (extracts are the grounding evidence)

## Step 1: Resolve the target

`target` can be a drop (slug or `programs/.../drops/<slug>/` path) or a live article (numeric id). If omitted, ask — never guess which content the operator means, and never review "the latest drop" without confirming which one that is.

- **Drop**: resolve the folder, `gdrive_read_file` the `<slug>.md`. If the folder holds drafts/translations, review the main `<slug>.md` unless told otherwise.
- **Live article**: `gcs_get_article` with the id — blocks, actions, and metadata (`shownAs`, channel) all included. Note whether the article is already published with answers (relevant to how urgent a `fail` is).

## Step 2: Resolve the brand

Infer from the drop's path/front matter or the article's content, then **confirm the inference with the operator** — auditing against the wrong brand's rules produces confidently wrong findings, the worst failure mode this skill has. If nothing is inferable, ask. Verify `foundation/brands/<brand>/` exists (same discovery pattern as the producers).

**Also resolve the publisher** (best-effort, same routine as the producers): reuse the publisher already chosen this session, or take the `publisher` input, or discover under `foundation/publishers/` (0 → review without the publisher layer, noted in the report header; 1 → use it; 2+ → ask, and the answer sticks for the session). A drop's path is a strong hint — its engine folder usually maps to one publisher's `config.yaml` `engine_folder`; confirm rather than assume.

## Step 3: Load the criteria — fresh, from source

Load the voice triplet (`voice-profile.md` full; fidelity/glossary if present), the playbook (`search_memory`, quoted-phrase query, `tier: "knowledge"`, best-effort), and the resolved Publisher's voice profile at `foundation/publishers/<publisher>/voice-profile.md` (reference, best-effort). **Independence rule: never accept the producer's summary of the rules, a cached version from earlier in the session, or "I remember this brand's voice" — re-read the files.** The whole value of this skill is that its copy of the criteria is authoritative and current.

Degraded modes, always disclosed in the report header:

- No voice profile → only fidelity/glossary/playbook and generic mobile-readability checks can run; the report says so and recommends `ce-brand-voice` before relying on the verdict.
- No fidelity file → fidelity dimension runs on glossary + playbook Locked bullets only.
- No extracts/source material → the grounding dimension can only flag *unverifiable* claims, not *wrong* ones — a much weaker guarantee; say so.

## Step 4: Audit — five dimensions

Work through the content line-by-line (blocks and actions included, for live articles). Every finding must cite a sourced rule; a reviewer hunch without a rule behind it is at most an `Info` note. Run all five dimensions unless `dimensions` narrows the set.

**4a — Fidelity (findings are Critical by default).** Locked phrases present and verbatim; banned phrases absent; claim rules respected — every performance/regulated claim (and everything an extract flagged with ⚠) has the required substantiation; competitor policy respected; glossary spellings exact (casing included).

**4b — Factual grounding (Critical for contradictions, High for unsourced).** Every spec, number, price, and product fact traces to a loaded source: `gdrive_search_files` the brand's source material for the products the content mentions and load the matching extracts. A fact that **contradicts** a source is Critical; a fact with **no source** is High ("unverifiable — confirm or cut"); prices and dated claims deserve extra suspicion. This dimension is why `ce-asset-intake` extracts matter — with no sources loaded, say plainly that grounding could not be verified.

**4c — Voice (High for Don't violations, Medium for drift).** Audit against the profile: §9 Do's and Don'ts line-by-line (each Don't violated is a High); §4 Vocabulary (Avoid terms present → High; "use carefully" terms outside their context → Medium); §3 tone dials, headline formula, person, sentence length (drift → Medium); playbook **Locked** bullets (violation → High — the operator already corrected this once). Layering: where the brand file is silent on tone/structure, the publisher profile's rules apply. **Quiz and poll copy is in scope**: question text, every option (correct and distractor), and feedback lines are copy the reader sees in the brand's name. Audit them under this dimension line by line — never read a knowledge check only as an answer key. A first-person slip in a distractor is a High, same as in a paragraph.

**4d — Audience fit (Medium).** Against §2 Staff Personas: register and technical depth match the persona's knowledge level; content answers what *blocks* them and speaks to what *motivates* them; mobile-readability — scannable paragraphs, front-loaded value, length justified for phone-on-the-floor reading. Includes knowledge-check copy: an option that assumes the reader works for the brand, or uses register the persona wouldn't, is an audience finding.

**4e — Structure & quiz quality (severity varies).** Format matches intent (`shownAs`, archetype conventions for live articles; drop template for markdown). Quizzes/knowledge checks: **every answer key verifiably correct against the loaded sources (wrong answer key = Critical — it trains staff wrong at scale)**; distractors plausible; questions scenario-based per `ce-quiz-generator` conventions rather than trivia recall. **Markdown drops are also checked against the drop contract** in `../ce-publish/references/drop-format.md`: frontmatter is exactly the nine allowed fields (an extra field — especially any self-audit — is a Medium: "assessments belong in review.md"), `## Status` is first in the body, one H1, knowledge checks use the readable marker syntax with valid option counts and correct markers, no YAML or code in the body. Each breach is a Medium; `ce-publish` will refuse the drop until fixed, so catching it here saves a round-trip.

## Step 5: Compose the report

Order findings most-severe-first, then by position in the content. Format each as:

```
[High] voice — Don't violated: "never open with the product name" (voice-profile.md §9)
  Where: lede, first sentence — "The Ghost 18 is Brooks' most..."
  Fix: open with the customer scenario, e.g. "A runner walks in asking for..."
```

Header: target, brand, verdict, dimensions run, criteria versions (file names + last-updated stamps + playbook date), degraded-mode disclosures. Footer: one-line recommended next action (publish / fix-then-re-review via producer or `ce-update-article` / escalate to operator).

Severity → verdict: any Critical or High → `fail`; Mediums only → `pass-with-notes`; Low/Info only → `pass`.

## Step 6: Save the report (Drive drops)

When the target is a drop and `save_report` isn't false: trash any existing `review.md` in the drop folder, upload the new one (`mime_type: "text/markdown"`). This is the approval-trail artefact for CaaS Step 5 — a reviewer opening the drop folder sees the content and its latest review side by side. Live articles: chat report only (there's no natural Drive home; don't invent one).

## Step 7: Deliver the verdict

Print the report in chat even when saved to Drive. Do not soften: a `fail` with three Criticals is a `fail`, stated first, findings after. If the operator disputes a finding and the rule genuinely supports their reading, downgrade it and say why — but a finding backed by a Locked playbook bullet or a fidelity rule stands unless the operator explicitly overrules it (that overrule is itself a memory-worthy event; see Step 8).

## Step 8: Capture to the event stream (memory)

Best-effort. Always the review event:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 5,
  "content": "Reviewed <target> for <brand>: <verdict>. <n> findings (<n> Critical / <n> High / <n> Medium). Top finding: <one line>. Criteria: <files + dates used>. Dimensions: <run/skipped>."
})
```

Plus, when they occur (separate rows, `importance: 7`):

- **Recurring violation** — this review found the same rule violated as ≥1 prior review insight for the brand: phrase it as a signal — "Producer output for <brand> keeps violating <rule> (seen in <slug1>, <slug2>). Voice profile §9 or producer prompts may need strengthening — candidate for ce-brand-voice refresh." Also surface it in the chat report; this loop-closing signal is how review findings compound instead of repeating.
- **Operator overrule** (`source_type: "user_explicit"`) — the operator rejected a sourced finding: capture the rule, the overrule, and the reasoning, phrased generally. Next `ce-brand-voice` refresh folds it in.

If `store_memory` errors, one line in the report, run still succeeds.

## Troubleshooting

- **Every voice finding feels subjective / operator pushes back on most of them** — the profile's rules aren't auditable (adjectives instead of concrete phrases). Downgrade unenforceable findings to Info, and recommend a `ce-brand-voice` refresh to make §9 concrete — that's a criteria defect, not a content defect.
- **Grounding dimension finds nothing to check against** — no extracts exist for the products mentioned. Run `ce-asset-intake` first, or accept the disclosed weaker guarantee (unverifiable ≠ verified).
- **Wrong brand inferred from a shared program folder** — multi-brand programs make path inference unreliable; that's why Step 2 confirms. Re-run with the right brand; discard the report, don't hand-patch it.
- **`gcs_get_article` returns published-with-answers** — the article is live and staff have answered its actions. A `fail` here needs the operator to weigh unpublishing vs fixing forward via `ce-update-article` (which respects answer locking) — flag it prominently, don't just file findings.
- **The review contradicts a prior review of the same drop** — criteria moved (profile refreshed, playbook grew) between runs. The header's criteria versions show what changed; the newer review stands, and the delta is worth a line in chat.
- **Report upload fails but the review ran** — deliver the full report in chat, note the save failure, don't re-run the audit just to retry an upload.
- **`Insufficient scope: atobi-mcp:admin required`** — the OAuth token lacks the admin scope gating `gdrive_*`/memory tools; same failure mode as `foundation-memory-roundtrip`.
