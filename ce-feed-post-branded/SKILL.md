---
name: ce-feed-post-branded
description: >
  Compose and publish a feed post in a brand's voice. Given a brand + topic,
  looks up the brand voice profile at foundation/brands/[brand]/, generates
  the post body in
  that voice, then posts via post_feed_post. Differs from ce-feed-post (the
  bare wiring-test skill) by composing branded content end-to-end. Use when
  asked "post about X for a brand", "publish a feed update for a brand".
allowed-tools: gdrive_find_by_path, gdrive_list_folder, gdrive_read_file, post_feed_post, search_memory, store_memory
metadata:
  version: "0.2.0"
  phases: [delivery]
---

# Branded feed post

Compose and publish a feed post in a brand's voice. Given a `brand + topic`, the skill loads the brand voice profile from the engine's Drive, composes the post in that voice, and publishes to the Atobi tenant via `post_feed_post`. Use when asked "post about X for `<brand>`" or "publish a feed update for `<brand>`". Differs from `ce-feed-post` (the bare wiring-test skill) by composing branded content end-to-end rather than relaying a user-supplied body verbatim.

Drive layout: brand foundation files live at the **Shared Drive root** under `foundation/brands/<brand>/` — shared across workspace engines (content engine, gtm-engine, …), which is why they sit outside any single engine folder. `GDRIVE_DEFAULT_ROOT_ID` points at the Shared Drive root, so `foundation/...` paths resolve directly. Publisher-level voice/audience profiles live beside the brands at `foundation/publisher/`. Engine-specific files (`programs/`) live under this Publisher's content-engine folder (`atobiv2-content-engine/`). The skill never sees `customers/<tenant>/` in paths.

## Outcome

A feed post published into the target tenant's feed, composed in the brand's documented voice.

- **Side effect**: one new post visible in the tenant's Atobi feed.
- **Returned**: the post id, the composed body, and the path of the style guide that shaped it — so the operator can audit "what voice did this end up in".
- **Idempotency**: none. Re-running creates another post. Don't loop this.
- **What "success" looks like**: the post body reads like it was written by someone who has internalised the brand's style guide — not like a generic AI assistant.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| `foundation/brands/<brand>/voice-profile.md` | **full** | Drives voice, tone, vocabulary. Without this, the skill refuses by default (see Step 3 fallback policy). Eventually the doc also mandates `fidelity-rules.md` and `glossary.md` per brand — load if present, skip if not. |
| `plugins/atobi-foundation/.mcp.json` | reference | Declares the atobi-mcp connection this skill calls into |
| `search_memory` (substrate) | best-effort | Loads the brand `knowledge` playbook (accumulated operator preferences) so the post doesn't repeat corrected mistakes. Continue silently if absent — never block a post on memory. |
| User-supplied `tenant`, `brand`, `topic` | input | Required — no defaults. Posting to the wrong tenant is the highest-risk failure mode (same guard as `ce-feed-post`). |

## Skill relationships

- **Phase**: delivery
- **Often follows**: a content-planning skill that decides what to post (not built yet); manual invocation by a content operator
- **Often precedes**: (nothing — this is the publish step)
- **Related**:
  - `ce-feed-post` — the bare wiring-test sibling. Bypass this skill and go to `ce-feed-post` when you want to publish a known body without style processing, or when debugging "is it MCP or is it the style logic?"
  - `ce-article-producer` — same brand-voice loading pattern, different output medium (article in Drive vs feed post in Atobi)

## Step 1: Validate inputs

Required: `tenant`, `topic`. If either is empty, stop and ask the user — do not guess defaults. **Tenant especially**: posting into the wrong tenant is a real-world incident; treat the input as load-bearing.

(Eventually `tenant` will come from `foundation/publisher/publisher-commercial-config.yaml` — until that artefact exists, the skill still takes it as input.)

`brand` is optional and is resolved in Step 2. `length` defaults to `"standard"`. `title` is omitted if not supplied.

## Step 2: Resolve the brand

If `brand` was supplied as an input, jump to the verification check below.

**Otherwise, discover the brands available in this engine:**

```
gdrive_find_by_path({ path: "foundation/brands" })
→ get the brands folder id
gdrive_list_folder({ folder_id: <brands-folder-id> })
→ list of brand sub-folders
```

Filter results to `mimeType == 'application/vnd.google-apps.folder'` — ignore stray files. Then branch on the count:

| Count | What to do |
|---|---|
| 0 | Stop. Tell the user no brands are seeded under `foundation/brands/` in this workspace. Do not auto-create — brand onboarding is a separate Setup-mode flow. |
| 1 | Use that brand. Show its name in Step 5's confirmation echo (the user gets one chance to catch a mistake). |
| 2+ | Present the list to the user and ask which to use. Wait for an answer; do not pick. |

**Verification (when `brand` was supplied):** confirm the folder `foundation/brands/<brand>/` exists via `gdrive_find_by_path`. If it doesn't, list available brands (same `gdrive_list_folder` call as above) and ask the user which they meant. Don't fuzzy-match — brand slugs should match exactly.

## Step 3: Load the brand voice profile

```
gdrive_find_by_path({
  path: "foundation/brands/<brand>/voice-profile.md"
})
```

**If `found: true`**: `gdrive_read_file` the content. Keep the full text in working memory — Step 4 will compose against it.

**If `found: false`**: by default, refuse. Tell the user the voice profile is missing at the expected path and ask whether to:
- abort,
- proceed with a generic neutral voice (require the user to confirm explicitly — silently falling back defeats the purpose of this skill),
- supply a voice description inline.

Do not just paste the generic-voice path. If a brand has no voice profile yet, that's a signal the brand isn't ready for autonomous posting; surfacing it is the correct outcome.

**Also try (best-effort)**: `foundation/brands/<brand>/fidelity-rules.md` and `foundation/brands/<brand>/glossary.md`. These are part of the doc's three-file brand reference but may not be seeded yet. If found, layer them on top of the voice profile (fidelity rules constrain claims; glossary locks product names). If absent, continue silently — the voice profile alone is enough for v0.

## Step 3b: Recall the brand playbook (memory, read-only)

The brand `knowledge` playbook is one curated memory row per brand carrying the operator's accumulated content preferences (learned via `ce-remember`, article edits, and past creation sessions). Load it so this post doesn't repeat a mistake the operator already corrected elsewhere:

```json
search_memory({ "query": "\"Content playbook: <brand>\"", "tier": "knowledge", "function_id": "content-engine", "limit": 5 })
```

The query is a **quoted phrase** — it matches the playbook's marker line (`# Content playbook: <brand>`) as consecutive words; a bare AND-of-words query can rank a different brand's playbook first. `limit: 5` so duplicates are visible: expect one hit; on 2+, use the most recently updated and mention the duplicates to the operator.

**Read-only, and best-effort** — this skill does *not* run the promotion pass or write the playbook (that's the create skills' and `ce-remember`'s job; a feed post should stay fast). If the tool errors or nothing is found, continue silently. Apply the playbook's **Locked** and **Tone / voice** bullets as composition constraints in Step 4 — they never override an explicit operator instruction in `topic`.

## Step 4: Compose the post body

Write the post in the loaded voice. Feed posts are short by design — target lengths:

| `length` | Words | Shape |
|---|---|---|
| `short` | ~50 | 1-2 sentences. One concrete hook. |
| `standard` (default) | ~120 | 2-4 sentences. Setup + payoff. |
| `long` | ~250 | 3-5 sentences. Setup + body + close. |

Source material is the `topic` argument. If the topic is product-shaped, lean on facts the style guide implies are important (concrete numbers, model names). If the topic is conceptual (a season, a campaign idea), lean on voice over facts.

After drafting, **audit against the style guide line-by-line**:
- Forbidden phrases removed
- Required phrases / structures present where applicable
- Tone matches the guide's "Do's"
- Concrete over generic
- Every **Locked** bullet from the brand playbook (Step 3b) holds — these are corrections the operator already made once; violating one in a *public feed post* is the most visible way to repeat a corrected mistake

The audit step is what differentiates this from `ce-feed-post`. Don't skip it.

## Step 5: Echo for confirmation

Show the user:
- Resolved tenant + brand (and, if Step 2 auto-picked the brand because only one was available, say so explicitly — "using the only brand under this tenant: `<brand>`")
- The style guide path that shaped the post
- The composed body (and title, if supplied)

Ask for an OK before publishing. Feed posts are visible; a wrong post is harder to recover than a wrong Drive write.

## Step 6: Publish

On confirmation, call:

```
post_feed_post({
  tenant_id: "<tenant>",
  body: "<composed body>",
  title: "<title or omitted>"
})
```

Don't retry automatically on failure. If it fails, surface the error with the tenant_id used so the operator can diagnose.

## Step 7: Report the result

Print, in order:

- The post id returned by the tool
- The composed body (so it's in the session log for audit)
- The style guide path that shaped it
- A reminder this was a real write — the post is now visible in that tenant's feed

## Step 8: Capture to the event stream (memory)

Append-only and judgment-free — `store_memory` `insight` rows only. Do **not** touch the playbook here (this skill is read-only on `knowledge`; consolidation happens in the create skills' promotion pass and `ce-remember`). Write after a successful publish; skip if the operator aborted at Step 5.

**8a — the publish event** (always after a publish):

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "agent_extracted",
  "importance": 5,
  "content": "Published feed post for <brand> (tenant <tenant>, post id <id>): \"<first ~10 words of body>…\"\n\n- Length: <short|standard|long>. Voice files: <list, or 'none'>.\n- Notes: <anything unusual>."
})
```

**8b — operator corrections / preferences voiced *this session*** (only if any): if the operator rejected a draft, changed tone, or stated a preference before approving ("shorter", "no exclamation marks", "don't open with a question"), capture each as a **separate** insight phrased *generally* — brand guidance, not post-specific:

```json
store_memory({
  "tier": "insight",
  "function_id": "content-engine",
  "source_type": "user_explicit",
  "importance": 7,
  "content": "<brand> content preference (voiced while composing a feed post): <general statement, e.g. 'feed posts should not open with a rhetorical question'>."
})
```

Field notes: `function_id` exact and case-sensitive. The brand goes in the first words of `content` (never in `customer_id`). If `store_memory` errors, report it in one line and treat the run as successful — the post is live; a missed capture only degrades future learning.

## Troubleshooting

- **No brands seeded in this engine** — `gdrive_list_folder` returned zero folders at `foundation/brands/`. The engine is new and hasn't been seeded with any brand yet. This is a Setup-mode gap, not a runtime bug — escalate to whoever runs Setup (operator or Atobi).
- **User picked a brand that doesn't appear in the list** — they may be confusing engines (atobiv2 vs another Publisher). Re-present the list scoped to *this* engine and ask again. Don't proceed on a brand the lookup doesn't confirm.
- **Voice profile not found at `foundation/brands/<brand>/voice-profile.md`** — the brand folder exists but the voice file is missing. The brand isn't ready for autonomous posting yet — escalate per Step 3's fallback policy rather than silently proceeding.
- **Paths look wrong (e.g. `foundation/` not found)** — the deployment's `GDRIVE_DEFAULT_ROOT_ID` must point at the Shared Drive root, where `foundation/` and the engine folders (`atobiv2-content-engine/`, `gtm-engine/`) live. If it points at a single engine folder or a different drive, the shared `foundation/` tree is unreachable — fix the env var.
- **Post sounds generic / not on-brand** — Step 3's audit was skipped or rushed. Re-load the style guide content (don't rely on memory), re-audit each rule, regenerate. Don't publish until the audit passes.
- **Tool fails: `post_feed_post not found`** — the MCP tool name in this skill's manifest may not match what atobi-mcp exposes. Run an MCP `tools/list`, find the real name, update `manifest.yaml`.
- **401 / 403 from the backend on publish** — auth path isn't ready for this tenant. Either the token isn't scoped for it, or admin → tenant exchange isn't wired. Stop and resolve rather than papering over with a different tenant.
- **Post created but in the wrong tenant** — same incident pattern as `ce-feed-post`'s tenant mismatch. Treat as a security incident, delete the post, root-cause the token binding before re-running.
- **`gdrive_find_by_path` returns `[dev mode]`** — the deployed mcp-server doesn't have `GDRIVE_SA_KEY_JSON` configured. Server-side, not a skill bug. Check Azure App Service settings.
- **Memory tool fails mid-run** — never fatal. Step 3b read failure: compose without the playbook. Step 8 write failure: report one line, treat the run as successful — the post is live regardless.
- **Post violated a known brand rule** — Step 3b was skipped or its Locked bullets weren't in the Step 4 audit. The playbook is where past corrections live; re-run the audit against it before any re-post. Consider `ce-remember` if the rule isn't in the playbook yet.
- **`store_memory` / `search_memory` returns `Insufficient scope: atobi-mcp:admin required`** — memory tools need the admin scope (declared in the manifest). If it persists, the OAuth token lacks it — same failure mode as `foundation-memory-roundtrip`.
