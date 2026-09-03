# Drop format — the contract for markdown drops

One definition, three readers. `ce-article-producer` writes a drop to this shape,
`ce-review` checks it against this shape, `ce-publish` parses it by this shape.
Design rationale: `specs/2026-09-03-ce-publish-design.md` §3.

## Folder

```
<engine_folder>/programs/<program>/drops/<slug>/
├── <slug>.md          ce-article-producer writes; humans read and review
├── review.md          ce-review writes; the ONLY audit in the drop
├── published.yaml     ce-publish writes; drop → article link + approval record
└── assets/            optional; images at review size, for human reviewers only
    └── CREDITS.md     provenance and rights per file
```

There is no `build.yaml` and no `knowledge-check.yaml`. The reviewed `<slug>.md`
is the single source of truth for content.

## Frontmatter

Exactly these nine fields. Any other field is a format error.

```yaml
---
brand: new-balance
publisher: sport2000
program: 1080v15-launch
slug: 01-1080v15-launch-module
archetype: product-launch        # product-launch | refresh | family-series | educational | campaign-awareness | compliance
shown_as: training               # training | article
cover: hero-1080v15.jpg          # filename; the operator supplies the file at publish time
voice_loaded: [brand/voice-profile.md, brand/glossary.md, publisher/voice-profile.md]
sources: [1080v15-tech-sheet.extract.md]
---
```

`voice_loaded` and `sources` record what shaped the piece. They are facts, not
assessments. No pass/fail, audit table, or self-assessment of any kind appears
anywhere in the drop except `review.md`.

`archetype`, `shown_as` and `cover` are required for publish. If the producer
could not determine one, it leaves the key out and `ce-publish` asks.

## Body

Top to bottom:

1. `## Status` — first heading in the body. Bullet list of open questions and
   unresolved items for the reviewer. May be an empty list. Never published.
2. `# Title` — exactly one H1. Becomes the article title.
3. `## Heading` — one per section. For `shown_as: training` each becomes a
   section-divider block (a Journey section). For `shown_as: article` each becomes
   an inline level-2 heading.
4. Paragraphs, bullet lists and `###` headings inside a section are text content.
   How they group into text blocks is `ce-publish`'s judgment, shown in its block plan.
5. Image — a markdown image alone on a line: `![alt text](filename.jpg)`. An optional
   caption follows on the next line in italics. `filename.jpg` must be among the files
   the operator supplies at publish. The frontmatter `cover` is NOT repeated in the body.
6. Knowledge check — see below. Placed inside the section it tests, so it gates
   that section in a Journey.

## Knowledge check syntax

```markdown
### Knowledge check

**Q:** A customer says the 1080 feels too soft. What do you say?
- [ ] Suggest a firmer model right away
- [x] Explain that Fresh Foam X is tuned for cushioning and ask about their running
- [ ] Offer a half size down
> Feedback: Soft is the design intent. Reassure first, then qualify.

**Poll:** Which feature do you think customers will ask about most?
- [ ] Fresh Foam X
- [ ] Hypoknit upper
- [ ] Weight

**Yes/No:** Have you tried the 1080v15 on yourself?
- [x] Yes
- [ ] No

**Open:** Write your one-sentence opener for a customer who ran the v14.
```

| Marker | Atobi block | Options | Correct markers | Gating (training) |
|---|---|---|---|---|
| `**Q:**` | `multi_choice` | 2–4 | ≥1 `- [x]` | `mandatory: true` |
| `**Poll:**` | `multi_choice`, every choice `correct: false`, `required: 0` | 2–5 | none | `mandatory: false` |
| `**Yes/No:**` | `yes_no_task` (no answer key on Atobi — the `[x]` is the expected answer, for reviewers) | exactly 2 | exactly 1 `- [x]` | `mandatory: true` |
| `**Open:**` | `open_question_task` | none | none | `mandatory: true` |

`> Feedback:` is optional on `**Q:**` and `**Yes/No:**`. Several questions may
follow one `### Knowledge check` heading. Option text, question text and feedback
are copy the reader sees in the brand's name — they are subject to voice review.

## Format errors

Any of these stops `ce-publish` before any write. All violations are reported at
once, then the run stops. `ce-publish` never edits `<slug>.md`; fixes go back
through the producer or the human reviewer.

- unknown frontmatter field, or a required field missing after the operator declined to supply it
- zero H1s, or more than one
- `## Status` absent, or not the first heading in the body
- a `**Q:**` with no `- [x]`, or with fewer than 2 or more than 4 options
- a `**Poll:**` with any `- [x]`, or fewer than 2 or more than 5 options
- a `**Yes/No:**` without exactly 2 options and exactly 1 `- [x]`
- an `**Open:**` followed by option lines
- an image filename not present among the supplied files (checked in the images step)
- a fenced code block or YAML anywhere in the body
