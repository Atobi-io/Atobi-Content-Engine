[README.md](https://github.com/user-attachments/files/30165232/README.md)
# Atobi Content Engine

Claude skills that turn brand source material into published learning content on the Atobi platform — in each brand's own voice, with knowledge checks, ready for store staff.

This repository is the source of truth for the `ce-*` skill library and the operator documentation. Skills are authored here, packaged as zips, and installed by content managers in Claude Desktop.

---

## What's in here

```
skills/
├── ce-asset-intake/              Brand PDFs → structured, searchable extracts
├── ce-brand-voice/               Authors/refreshes the brand voice triplet
├── ce-learning-article-creator/  Creates training articles & journeys on-platform
├── ce-article-producer/          Writes markdown articles to Drive for review
├── ce-quiz-generator/            Knowledge checks and assessment actions
├── ce-feed-post-branded/         Composes and publishes brand-voiced feed posts
├── ce-feed-post/                 Bare wiring test for the MCP → backend path
├── ce-review/                    Independent brand-compliance audit before publish
├── ce-update-article/            Safe fetch → merge → write edits to live articles
├── ce-reporting/                 Post-publish performance report (the loop-closer)
└── ce-remember/                  Captures standing operator preferences to memory

docs/
└── content-engine-operator-guide.html   Operator guide v1.0 — start here if you're a content manager
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

Read `docs/content-engine-operator-guide.html` — it covers connecting the Atobi connector, installing the skills, the seven workflows, and troubleshooting.

Setup in short:

1. Claude Desktop → **Settings → Connectors** → connect the Atobi Production MCP Server, signing in on the tenant you manage.
2. Verify with `"Verify my Atobi connection"` and confirm the tenant in the reply before creating anything.
3. **Settings → Skills → Add → Upload a skill** for each `ce-*` zip.

## For maintainers

Each skill folder zips as-is — the zip root must contain `SKILL.md`, not a wrapper directory.

```bash
cd skills && for d in ce-*/; do zip -r "../dist/${d%/}.zip" "$d" -x '*.DS_Store'; done
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
