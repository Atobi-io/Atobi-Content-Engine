# Atobi Content Engine

Claude skills that turn brand source material into published learning content on the Atobi platform — in each brand's own voice, with knowledge checks, ready for store staff.

> [!IMPORTANT]
> These skills write to live Atobi tenants. Content is a draft until a human operator reviews it — skills that publish always confirm the channel and audience first, and never infer them. Everything here requires an **Atobi tenant** and the **Atobi MCP Server** connected in your client (see [MCP integration](#mcp-integration)); without those, the skills install but have nothing to act on.

## What's in the repo

- **One plugin, eleven skills** covering the full content pipeline: intake → voice → create → review → publish → report.
- A **plugin marketplace** manifest, so Claude Code users install and update with two commands.
- Skills in the open [Agent Skills](https://agentskills.io) `SKILL.md` format, so they also work in OpenAI Codex CLI, Cursor, Gemini CLI, and other agents that adopted the standard.

## The golden path

```
1 · Intake  →  2 · Voice profile  →  3 · Create  →  4 · Review  →  5 · Publish  →  6 · Report
```

Steps 1–2 run once per brand and whenever new material arrives. For a brand already onboarded, operators start at step 3.

Two things make the output trustworthy: content is grounded in extracted source material rather than model recall, and every brand has an approved voice profile before anything is produced — the producer skills refuse to guess a brand's voice.

## Repository layout

```
.claude-plugin/
  marketplace.json    Marketplace manifest — /plugin marketplace add points here
  plugin.json         The content-engine plugin manifest (version lives here)
skills/
  ce-<skill>/         One folder per skill: SKILL.md (the instructions Claude
                      follows) + manifest.yaml (internal docs: scopes, tools,
                      inputs — not read by Claude)
```

## Getting started

### Claude Code

```bash
claude plugin marketplace add atobi-io/Atobi-Content-Engine
claude plugin install content-engine@atobi-content-engine
```

Updates arrive automatically when a new version is published — nothing to clone, no background jobs.

### Claude Desktop / claude.ai

Paste the repo URL (`https://github.com/atobi-io/Atobi-Content-Engine`) into the plugin picker, or upload a zip of any folder under `skills/` (with `SKILL.md` at the zip root) via **Settings → Skills → Add**. Team/Enterprise workspaces can distribute it through the organization plugin directory.

### Other agents (open Agent Skills standard)

The skills follow the open [Agent Skills](https://agentskills.io/specification) `SKILL.md` format, so any agent that adopted the standard can run them. The quickest cross-agent path is [Vercel's skills.sh installer](https://github.com/vercel-labs/skills), which discovers everything under `skills/` and fans out into each agent's own skills directory:

```bash
npx skills add atobi-io/Atobi-Content-Engine                    # all detected agents
npx skills add atobi-io/Atobi-Content-Engine -a codex -a cursor # target specific agents
npx skills add atobi-io/Atobi-Content-Engine -l                 # list skills without installing
```

Whichever agent you use, you also need the Atobi MCP Server connected in it — the per-agent snippets below show where. Ask jul@atobi.io for the server URL for your tenant.

#### OpenAI Codex CLI

Skills live in `~/.agents/skills/` (global) or `.agents/skills/` (project) — `npx skills add … -a codex` puts them there, or copy the folders manually. Connect the Atobi MCP server in `~/.codex/config.toml`, then sign in:

```toml
[mcp_servers.atobi]
url = "<atobi-mcp-server-url>"
```

```bash
codex mcp login atobi   # runs the OAuth flow
```

Docs: [Codex skills](https://developers.openai.com/codex/skills) · [Codex MCP](https://developers.openai.com/codex/mcp)

#### Cursor

Skills live in `~/.cursor/skills/` (global) or `.agents/skills/` / `.cursor/skills/` (project); Cursor also auto-loads `.claude/skills/`. Install via `npx skills add … -a cursor` or drop the folders in manually. Connect the Atobi MCP server in `~/.cursor/mcp.json` — Cursor opens the OAuth flow in your browser automatically:

```json
{
  "mcpServers": {
    "atobi": { "url": "<atobi-mcp-server-url>" }
  }
}
```

Docs: [Cursor skills](https://cursor.com/docs/skills) · [Cursor MCP](https://cursor.com/docs/context/mcp)

#### Gemini CLI

Gemini CLI has a native skills installer:

```bash
gemini skills install https://github.com/atobi-io/Atobi-Content-Engine.git
# or a single skill:
gemini skills install https://github.com/atobi-io/Atobi-Content-Engine.git --path skills/ce-review
```

Connect the Atobi MCP server in `~/.gemini/settings.json` (OAuth is discovered automatically for `httpUrl` servers):

```json
{
  "mcpServers": {
    "atobi": { "httpUrl": "<atobi-mcp-server-url>" }
  }
}
```

Docs: [Gemini CLI skills](https://geminicli.com/docs/cli/skills/) · [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/)

> [!NOTE]
> The skills reference Atobi MCP tool names (`gdrive_*`, `gcs_*`, `rc_*`, …) — they work identically in any agent as long as the Atobi server is connected. A few skills also mention Claude conveniences (Drive connector, memory tools); on other agents those steps degrade gracefully to the MCP equivalents or are skipped.

## MCP integration

Every skill talks to Atobi through the **Atobi Production MCP Server**. Connect it once per client, then verify:

| Client | How to connect |
|--------|----------------|
| Claude Desktop / claude.ai | **Settings → Connectors** → add the Atobi Production MCP Server, sign in on the tenant you manage |
| Claude Code | `claude mcp add` with the Atobi server URL (or inherit the connector from claude.ai) |
| Other agents | Add the Atobi server to that agent's MCP config — see the per-agent notes above |

Then ask: **"Verify my Atobi connection"** and confirm the tenant named in the reply before creating anything.

## Skill & command reference

| Skill | Command | Phase | What it does |
|-------|---------|-------|--------------|
| [ce-asset-intake](skills/ce-asset-intake) | `/ce-asset-intake` | Intake | Brand PDFs → structured, searchable extracts |
| [ce-brand-voice](skills/ce-brand-voice) | `/ce-brand-voice` | Intake | Authors/refreshes the brand voice triplet |
| [ce-learning-article-creator](skills/ce-learning-article-creator) | `/ce-learning-article-creator` | Delivery | Creates training articles & journeys on-platform |
| [ce-article-producer](skills/ce-article-producer) | `/ce-article-producer` | Delivery | Writes markdown articles to Drive for review |
| [ce-quiz-generator](skills/ce-quiz-generator) | `/ce-quiz-generator` | Delivery | Knowledge checks and assessment actions |
| [ce-feed-post-branded](skills/ce-feed-post-branded) | `/ce-feed-post-branded` | Delivery | Composes and publishes brand-voiced feed posts |
| [ce-review](skills/ce-review) | `/ce-review` | Delivery | Independent brand-compliance audit before publish |
| [ce-update-article](skills/ce-update-article) | `/ce-update-article` | Delivery | Safe fetch → merge → write edits to live articles |
| [ce-reporting](skills/ce-reporting) | `/ce-reporting` | Delivery | Post-publish performance report (the loop-closer) |
| [ce-remember](skills/ce-remember) | `/ce-remember` | Delivery | Captures standing operator preferences to memory |
| [ce-feed-post](skills/ce-feed-post) | `/ce-feed-post` | Meta | Bare wiring test for the MCP → backend path |

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

## Brand onboarding

Create `foundation/brands/<brand>/source-material/`, drop the brand's PDFs, then run intake followed by the voice-profile workflow.

## For maintainers

Authoring is git: edit a skill, commit, push. Installed plugins pick up the change when you publish a new version.

- **Releasing:** bump `version` in **both** `.claude-plugin/plugin.json` and the plugin entry in `.claude-plugin/marketplace.json` on any behavioural change, then push. Claude Code offers the update to installed users.
- **Before pushing:** run `claude plugin validate .` — it must pass.
- Each skill's `manifest.yaml` is internal documentation (scopes, tools, inputs). Claude does not read it; keep it in sync with what the skill actually calls. `atobi-mcp:admin` gates the `gdrive_*` and memory tools; `atobi-mcp:write` gates publishing.
- Skills that write to the platform must confirm channel and audience with the operator before publishing — never infer them.
- Reporting stays aggregate by default; individual staff data is chat-only and never written to Drive or Slack.

## Migrating from the old symlink sync

Earlier versions installed via `install.sh`, which symlinked skills into `~/.claude/skills/` and scheduled a background `git pull`. That system is gone. If you used it, clean up once:

```bash
# macOS: remove the scheduled job
launchctl unload ~/Library/LaunchAgents/io.atobi.content-engine-sync.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/io.atobi.content-engine-sync.plist

# Linux: remove the crontab line tagged "# io.atobi.content-engine-sync"
crontab -l | grep -v "# io.atobi.content-engine-sync" | crontab -

# Both: remove the old skill symlinks (only removes symlinks, not real folders)
find ~/.claude/skills -maxdepth 1 -name 'ce-*' -type l -delete
```

Then install via the marketplace ([Getting started](#getting-started)). Your old clone can be deleted.

## License

Licensing is being decided — until a LICENSE file lands, all rights are reserved. If you want to use these skills outside an Atobi engagement, contact us first.

## Contact

Questions on the engine or skill distribution: jul@atobi.io
