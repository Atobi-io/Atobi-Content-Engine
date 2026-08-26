---
name: ce-reporting
description: >
  Post-publish performance report for Atobi content — one article or a set
  (program / brand / timeframe). Publication check, reach and completion
  against the real audience denominator, knowledge-check pass rates with
  per-question analysis (distinguishing content gaps from badly-written
  questions), engagement signals mined from comments, and a
  feedback-to-next-brief section captured to memory so the next production
  run starts smarter. Aggregate numbers by default — individual staff data
  only on explicit request, chat-only. This is CaaS Step 8, the loop-closer.
  Use when asked "how did [article/journey] perform", "completion report for
  [brand]", "quiz pass rates for [program]", or after a campaign window ends.
allowed-tools: gcs_get_article, gcs_list_articles, gcs_get_action_instances, gcs_get_action_answers, gcs_get_action_answer_summary, gcs_list_comments, gcs_list_reactions, us_get_audience, us_list_audience_users, gdrive_find_by_path, gdrive_list_folder, gdrive_read_file, gdrive_create_folder, gdrive_upload_file, gdrive_trash_file, send_slack_message, search_memory, store_memory
metadata:
  version: "0.1.0"
  phases: [delivery]
---

# Reporting

Answer the question every published piece of content leaves hanging: did it work? This skill checks the content is actually live and reaching who it should, measures completion against the honest denominator, reads quiz results for what they say about *staff knowledge* and about *the content itself*, and converts all of it into feedback the next brief and production run can use. Without this step the engine publishes and forgets; with it, every campaign makes the next one smarter — it's the outermost loop the engine has.

## Outcome

A performance report, in chat always, saved to Drive by default:

- **Report sections**: publication check → reach & completion → knowledge-check performance → engagement → feedback to next brief (structure in Step 6)
- **Saved artefact**: single article whose drop folder is known → `programs/<program>/drops/<slug>/performance-<YYYY-MM-DD>.md`; multi-article or unknown drop → `programs/<program>/reports/` (or `programs/_adhoc/reports/`) as `report-<target>-<YYYY-MM-DD>.md`. A prior report for the same target and period is trashed (recoverable) before upload; reports for different periods coexist — trends live in the comparison.
- **Optional Slack summary**: only with an explicit channel and only after showing the exact message and getting a yes (Step 7)
- **Memory**: feedback insights captured to the event stream so producers and future briefs recall them (Step 8)
- **Privacy floor**: aggregates by default. Per-user lists (`include_individuals=true`) go to chat only — never into the Drive file or Slack. A cohort smaller than 5 is reported as "<5", not broken down further.
- **Never**: publish/unpublish actions, content edits, or numbers without a denominator ("64 completions" means nothing; "64 of 210 targeted (30%)" is a finding)

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| Target articles (`gcs_get_article`) | full | Publication state, channel, audience id, `shownAs`, action blocks — the skeleton every metric hangs on. |
| Audience (`us_get_audience` + `us_list_audience_users`) | count + scoped | The honest denominator. Completion % against the wrong population is fiction. |
| Action data (`gcs_get_action_answers`, `gcs_get_action_answer_summary`; `gcs_get_action_instances` for recurring actions) | full | Completion and quiz performance — the core measurements. |
| Comments + reactions | scoped | Engagement, and the qualitative gold: questions staff ask in comments are unmet content needs. |
| `search_memory` prior report insights | best-effort | Trend line: is this brand's completion drifting up or down vs earlier runs? Continue silently if absent. |
| `programs/<program>/drops/<slug>/` | if exists | Where a single-article report lands; links performance to the drop artefact trail (brief → content → review → performance). |

## Skill relationships

- **Phase**: delivery (CaaS Step 8 — Report & Follow-Up)
- **Often follows**: publish (via `ce-learning-article-creator` / `ce-feed-post-branded`) + a sensible measurement window; a campaign or training deadline passing
- **Often precedes**: the next brief (feedback section is its input); `ce-update-article` (fixing a badly-performing question); `ce-brand-voice` refresh (when engagement signals contradict the profile's assumptions)
- **Related**: `ce-review` (pre-publish quality gate; this is the post-publish counterpart — review predicts, reporting measures); planned `ce-brief` would read this skill's memory insights; CS Engine integration (health scoring / QBRs) depends on this skill's outputs per the overview doc

## Step 1: Resolve the targets

`target` forms: a numeric article id, a comma-separated list, `brand:<slug>`, or `program:<slug>`. If omitted, ask — never guess what to measure.

- **Ids** → use directly.
- **`brand:<slug>`** → `gcs_list_articles` filtered to the window (`since`, default 30d) and select the brand's content — confirm the resolved list with the operator before pulling data (name matching on titles/channels is heuristic, and a wrong article in the set pollutes every aggregate).
- **`program:<slug>`** → resolve the program's drops folder (`gdrive_find_by_path`), list its drops (`gdrive_list_folder`), and `gdrive_read_file` each drop's `published.yaml` — the backlink `ce-learning-article-creator` (v0.5+, `drop` input) writes at creation time with the `article_id`. Drops without a `published.yaml` are listed as unmeasurable so the operator can supply ids (or backfill the file by hand).

Echo the final article list + window before proceeding.

## Step 2: Publication check

`gcs_get_article` each target: published state, channel, audience, `shownAs`, publish date, and whether it has action blocks at all. Failures here are findings, not errors — "drop exists but was never published" or "published to a channel with a different audience than the brief intended" is exactly what CaaS Step 8's publication check exists to catch. Content with no actions gets reach/engagement sections only; say so rather than inventing a completion proxy.

## Step 3: Establish the denominator

`us_get_audience` + `us_list_audience_users` for each article's audience → the targeted population count. This number gates every percentage in the report. Where two articles in the set target different audiences, report them separately — averaging across different denominators produces a number that describes neither. If the audience can't be resolved (deleted, cross-tenant), report absolute numbers and flag that percentages are unavailable, rather than silently using a guessed base.

## Step 4: Completion and knowledge-check performance

**Completion**: measured from answers — `gcs_get_action_answers` per action (paged, 200/page), counting **distinct users who submitted**; the denominator is the Step 3 audience. The outstanding set is the audience list minus the submitters, computed here — there is no server-side "who hasn't completed" call (`gcs_get_uncompleted_actions` is scoped to the *calling* user, never use it for audience math). For recurring actions, pick the relevant instance via `gcs_get_action_instances` and filter answers by `actionInstanceId`. Report per-article completion rate, and for journeys (sequential sections) the **drop-off curve** — per-section distinct-submitter counts show which section loses people. A journey that loses 40% at section 3 has a section-3 problem, not a motivation problem.

**Knowledge checks**: `gcs_get_action_answer_summary` per `multi_choice` action. Per question: attempt count, pass rate, answer distribution. Then the diagnostic that makes this section worth reading — for every badly-performing question (pass rate meaningfully below the rest), classify:

- **Content gap** — wrong answers spread across distractors, or concentrated on a plausible misconception → staff genuinely don't know this; the content didn't teach it. Feedback: cover the topic more clearly next production run (and consider a follow-up post now).
- **Bad question** — wrong answers concentrated on ONE distractor that is arguably also correct, or the question tests trivia the content never covered → the question is broken, not the staff. Feedback: fix via `ce-update-article` (mind answer locking on published-with-answers articles).

Say which classification each weak question gets and why. This distinction is the difference between "retrain staff" and "fix the quiz" — collapsing them wastes someone's time either way.

**Privacy**: all of the above is aggregate. If `include_individuals=true` (manager follow-up use case), the uncompleted-users list goes in **chat only**, with a reminder it's for follow-up, not league tables. Cohorts under 5 are never broken down.

## Step 5: Engagement

`gcs_list_reactions` + `gcs_list_comments` per article: counts first (reactions, comments, per-capita against the denominator), then read the comments themselves — **questions staff ask in comments are unmet content needs**, the most direct brief-input this skill produces. Quote 2-3 representative ones (anonymized — role/store context only if relevant, never names). Note reaction patterns only when they say something actionable (e.g. high reactions + low completion = the hook works, the length doesn't).

## Step 6: Compose the report

```markdown
# Performance report: <target label>
_<YYYY-MM-DD> • window: <since> → <today> • audience: <name> (<n> staff) • generated by ce-reporting v0.1_

## Verdict
<2-3 sentences: the one thing to know. "Strong completion, one broken quiz question, staff asking for sizing guidance the content doesn't cover.">

## Publication check
| Article | State | Channel | Audience | Published |

## Reach & completion
<Per article: completed / targeted (%). Journeys: drop-off by section.>

## Knowledge checks
<Per action: pass rate; weak questions with content-gap vs bad-question classification and evidence.>

## Engagement
<Counts per capita; representative staff questions (anonymized); actionable patterns.>

## Feedback to next brief
<Numbered, concrete, each traceable to a section above. "1. Cover in-store fitting in the next Ghost drop — 3 staff comments asked; quiz Q4 (fit) had the lowest pass rate (41%)." This section is what memory captures and what the next brief reads.>
```

Save per the Outcome rules: `gdrive_list_folder` the destination to find a prior report for the same target and period (its filename carries an earlier date, so an exact-path lookup won't find it), trash it, then upload with `mime_type: "text/markdown"`. Numbers without denominators don't ship; percentages without absolute counts don't either.

## Step 7: Optional Slack summary

Only when a channel is provided (input or operator ask). Compose a 5-8 line summary — verdict, headline numbers, link/pointer to the full report — show it verbatim, and post via `send_slack_message` **only after an explicit yes**. Posting to Slack is outward-facing and unrecallable; no individual data, ever.

## Step 8: Capture to the event stream (memory)

Best-effort. Always the report event (`importance: 5`, same shape as sibling skills: what was measured, headline numbers, where the report lives). Additionally, **each item in "Feedback to next brief" becomes its own insight** (`importance: 6-7`, `source_type: "agent_extracted"`), phrased as forward guidance:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 7,
  "content": "<brand> content signal (from performance report <date>): quiz question on <topic> classified content-gap — 59% failure spread across distractors. Next <brand> production covering <topic> should teach it explicitly, not assume it."
})
```

These rows are the loop: `ce-article-producer`'s Step 2b promotion pass folds recurring signals into the brand playbook, and a future `ce-brief` reads them at brief time. If `store_memory` errors, one line in the report, run still succeeds.

## Troubleshooting

- **Completion rate looks absurdly low** — check the denominator first: the audience may include staff cohorts the content was never realistically for (head office in a floor-staff audience), or the window is too fresh. Report the number with the caveat rather than "correcting" it silently.
- **`gcs_get_action_answer_summary` returns nothing for an action** — the action may have no answers yet (too early) or not be a `multi_choice`. Distinguish "no data yet" from "no quiz" in the report; don't score an unanswered quiz as failing.
- **Audience can't be resolved** — deleted or restructured since publish. Absolute numbers only, flagged; suggest the operator confirm the intended audience so the next report has a denominator.
- **`brand:<slug>` resolution pulls in wrong articles** — title/channel matching is heuristic; that's why Step 1 confirms the list. Re-run with explicit ids; don't hand-prune the aggregates afterward.
- **Program drops have no `published.yaml`** — the article predates `ce-learning-article-creator` v0.5's `drop` input, or was created without it. List those drops as unmeasurable and ask for ids; measuring a guessed article is worse than a gap. Backfill: a hand-written `published.yaml` with just `article_id` is enough for the next run.
- **Operator asks for a leaderboard of individuals** — that's outside this skill's privacy floor for written artefacts; individual data stays chat-only and cohorts <5 are never broken down. Point managers at the uncompleted list (chat) for follow-up instead.
- **Slack post requested mid-run before the report is final** — post only after Step 6 is done and confirmed; a summary of an unfinished report is how wrong numbers escape.
- **`Insufficient scope: atobi-mcp:admin required`** — the OAuth token lacks the admin scope gating `us_*`/`gdrive_*`/memory tools; same failure mode as `foundation-memory-roundtrip`.
