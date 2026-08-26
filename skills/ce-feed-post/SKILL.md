---
name: ce-feed-post
description: >
  Post a feed post into a specific Atobi tenant via the atobi-mcp server.
  Test skill for validating the Claude Code → atobi-mcp → backend wiring with
  a real write. Use when you want to confirm tenant auth + the post_feed_post
  tool are working before building richer content skills. Triggers on phrases
  like "post a feed post", "test feed post", "/ce-feed-post".
allowed-tools: post_feed_post
metadata:
  version: "0.1.0"
  phases: [meta]
---

# Feed post (test)

Post a single feed post into a specific Atobi tenant through the atobi-mcp server. The point is to exercise the full wiring — auth → MCP → backend — with a real (visible) write, not to be a production content-publishing skill.

## Outcome

A feed post is created in the target tenant's feed.

- **Side effect**: one new post visible in the tenant's Atobi feed.
- **Returned**: the post id (or the raw MCP tool response) so the operator can verify it landed.
- **Idempotency**: none. Re-running creates another post. Don't loop this.

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| Atobi MCP Server connector | reference | The MCP connection this skill calls into — connect it in your client first (Claude: Settings → Connectors or `claude mcp`; other agents: their MCP config) |
| User-supplied `tenant_id` | input | Which tenant the post lands in — required, no default |
| User-supplied post `body` (and optional `title`) | input | The actual content posted |

## Skill relationships

- **Phase**: meta (substrate test, not a production content skill)
- **Often follows**: `/foundation-memory-roundtrip` — verifies memory wiring; this verifies write-side wiring to a real backend
- **Often precedes**: any production content skill that posts into tenants (e.g. a future `ce-article-publish`)
- **Related**: `foundation-memory-roundtrip` is the read+write-memory POC; this is its action-side counterpart

## Step 1: Gather inputs

You need three things before calling the tool:

- `tenant_id` — the target tenant. Ask the user if not provided. Refuse to default — posting into the wrong tenant is a real-world mistake to avoid.
- `body` — what the post says. Ask the user if not provided.
- `title` — optional. Skip if the user doesn't supply one.

Echo the resolved inputs back to the user once before calling the tool. This is a write; confirmation matters.

## Step 2: Call the MCP tool

Invoke the `post_feed_post` tool exposed by atobi-mcp with:

```json
{
  "tenant_id": "<from input>",
  "body": "<from input>",
  "title": "<optional, omit if not supplied>"
}
```

The atobi-mcp server forwards this to the backend's feed-post endpoint, using a token scoped to `tenant_id` (either directly, or via admin → tenant token exchange — depends on which auth path is live).

## Step 3: Report the result

Print:

- The post id returned by the tool, if any.
- The raw MCP tool response (or its salient fields) so the operator can spot-check.
- A reminder that this was a real write — the post is now visible in that tenant's feed.

If the tool fails, do not retry automatically. Surface the error to the user with the tenant_id used.

## Troubleshooting

- **`tool not found: post_feed_post`** — the MCP tool name in this skill's manifest may not match what atobi-mcp actually exposes. Run an MCP tools/list against the server, find the real name, update `manifest.yaml` and the `allowed-tools` line in this file's frontmatter.
- **401 / 403 from the backend** — auth path isn't ready for this tenant. Either you don't have a valid tenant-scoped token, or the admin → tenant exchange isn't wired in atobi-mcp yet. Stop and resolve before retrying — don't paper over it with a different tenant.
- **Post created but in the wrong tenant** — the token was bound to a different tenant than `tenant_id`. This is the highest-risk failure mode of this skill; treat it as a security incident, delete the post from the wrong tenant, and root-cause the token binding before running again.
- **Tool succeeds but no post appears in the feed** — backend accepted the write but didn't publish (visibility/draft state?). Check the returned object for a `published` / `status` field; the post may be a draft awaiting approval.
