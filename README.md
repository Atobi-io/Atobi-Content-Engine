# Atobi Content Engine

Claude skills that turn brand source material into published learning content on the Atobi platform — in each brand's own voice, with knowledge checks, ready for store staff.

This repository is the source of truth for the `ce-*` skill library. Skills are authored here and sync straight from GitHub into each operator's Claude skills folder (`~/.claude/skills/`) — clone once, and an automatic pull keeps them current. See **[Automatic sync](#automatic-sync)** below.

---

## What's in here

Each `ce-*` skill lives at the repo root:

```
ce-asset-intake/              Brand PDFs → structured, searchable extracts
ce-brand-voice/               Authors/refreshes the brand voice triplet
ce-learning-article-creator/  Creates training articles & journeys on-platform
ce-article-producer/          Writes markdown articles to Drive for review
ce-quiz-generator/            Knowledge checks and assessment actions
ce-feed-post-branded/         Composes and publishes brand-voiced feed posts
ce-feed-post/                 Bare wiring test for the MCP → backend path
ce-review/                    Independent brand-compliance audit before publish
ce-update-article/            Safe fetch → merge → write edits to live articles
ce-reporting/                 Post-publish performance report (the loop-closer)
ce-remember/                  Captures standing operator preferences to memory

install.sh · sync.sh · uninstall.sh   Git-based sync into ~/.claude/skills
```

Every skill folder contains a `SKILL.md` (the instructions Claude follows) and a `manifest.yaml` (id, version, required scopes, MCP tools, inputs).

## The golden path

```
1 · Intake  →  2 · Voice profile  →  3 · Create  →  4 · Review  →  5 · Publish  →  6 · Report
```

Steps 1–2 run once per brand and whenever new material arrives. For a brand already onboarded, operators start at step 3.

Two things make the output trustworthy: content is grounded in extracted source material rather than model recall, and every brand has an approved voice profile before anything is produced — the producer skills refuse to guess a brand's voice.

## Where brand context lives

Skills read and write a single Drive tree at the Shared Drive root, shared across workspace engines:

```
foundation/
├── publisher/          How we talk to our own staff
└── brands/
    └── <brand>/
        ├── voice-profile.md     Required for production
        ├── glossary.md          Locked product names & tech terms
        ├── fidelity-rules.md    Banned phrases, claim rules
        └── source-material/     Brand PDFs + generated extracts

programs/<program>/drops/<slug>/   Article artefacts, reviews, published.yaml backlinks
```

## For operators

Two things to set up: the Atobi connector, and the skills.

1. **Connect the tenant.** In Claude (Desktop → **Settings → Connectors**, or Claude Code via `claude mcp`), connect the Atobi Production MCP Server, signing in on the tenant you manage.
2. **Verify** with `"Verify my Atobi connection"` and confirm the tenant in the reply before creating anything.
3. **Install the skills** — clone once and run the installer; they link in and stay synced automatically:

   ```bash
   gh repo clone atobi-io/Atobi-Content-Engine ~/.claude/atobi-content-engine
   ~/.claude/atobi-content-engine/install.sh
   ```

Then work the golden path above.

## Automatic sync

The skills sync straight from this repo into `~/.claude/skills/` — no zip upload, no manual copy. Clone once and run the installer:

```bash
gh repo clone atobi-io/Atobi-Content-Engine ~/.claude/atobi-content-engine
~/.claude/atobi-content-engine/install.sh
```

That symlinks every `ce-*` skill into your Claude skills folder and schedules a background pull (launchd on macOS, cron on Linux) so new and updated skills appear automatically. Default interval is 30 min; override with `SYNC_INTERVAL=3600 ./install.sh` (seconds).

- `sync.sh` — pulls latest and re-links skills. Runs on the schedule; safe to run by hand any time.
- `install.sh` — one-time setup: initial sync + schedule the job.
- `uninstall.sh` — removes the schedule and the `ce-*` symlinks (leaves your clone in place).

The sync only ever touches `ce-*` symlinks that point into this repo — it never clobbers a real folder or another skill. Logs go to `.sync.log` in the clone.

> Sync requires Claude Code (it reads `~/.claude/skills/`). Claude Desktop can't pull from GitHub; if you're on Desktop, upload each `ce-*` folder as a skill zip (`SKILL.md` at the zip root) via **Settings → Skills → Add**.

## For maintainers

Authoring is git: edit a skill, commit, push. Every operator's scheduled `sync.sh` picks up the change on its next pull — nothing to package or redistribute.

```bash
# in your clone
git pull
# edit ce-<skill>/SKILL.md (and manifest.yaml), then:
git add ce-<skill> && git commit -m "…" && git push
```

Conventions:

- Bump `version` in `manifest.yaml` on any behavioural change to `SKILL.md`.
- Keep `scopes` and `tools` in the manifest in sync with what the skill actually calls. `atobi-mcp:admin` gates the `gdrive_*` and memory tools; `atobi-mcp:write` gates publishing.
- Skills that write to the platform must confirm channel and audience with the operator before publishing — never infer them.
- Reporting stays aggregate by default; individual staff data is chat-only and never written to Drive or Slack.

## Brand onboarding

Create `foundation/brands/<brand>/source-material/`, drop the brand's PDFs, then run intake followed by the voice-profile workflow.

## Contact

Questions on the engine or skill distribution: jul@atobi.io
