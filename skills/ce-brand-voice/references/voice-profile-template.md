# Voice Profile Template
## For the Atobi Content Engine

**Version:** 1.1 (adopted from the operator's VOICE_PROFILE_TEMPLATE.md v1.0; "hockey" knowledge-level field genericized to product knowledge)
**Purpose:** This reference file is called by content skills to personalise articles, posts, achievements, training, checklists, and notifications for a specific customer. Skills do not contain brand logic — all brand context lives here.

---

> **How to use this template**
> Fill in each section using the data sources listed in *[brackets]*. Only include information that changes how content is written or structured. If a field doesn't improve output quality, leave it blank or delete it. The goal is a file a skill can read and immediately produce on-brand, relevant content — not a marketing brief.

---

## 1. Brand Identity

**Customer name:** [Official brand name as used in communications]

**Tagline / brand position:** [The line they lead with — website, packaging, campaigns]

**One-sentence brand description:** [What they sell, who to, why it matters to their staff]

**Brand heritage notes:** [Only include if heritage actively shapes the tone — e.g., "90+ year legacy brand" changes how authority is expressed]

**Market scope:** [Global / Regional. List key markets with flags if localisation matters to content routing]

---

## 2. Staff Persona(s)

> *This is the most important section. If you only fill in one thing, make it this. Every piece of content should feel like it was written FOR this person.*

For each persona:

**Persona name:** [Give it a descriptive label, e.g., "Floor Sales Associate" or "Certified Fit Specialist"]

- **Role:** [Job title(s) this persona covers]
- **Where they work:** [Retail floor / warehouse / distribution / field / head office]
- **Product knowledge level:** [Enthusiast / Expert / Novice — calibrates technical depth]
- **Primary goal at work:** [What success looks like for them day-to-day]
- **What blocks them:** [Time pressure, high turnover, language barrier, seasonal surges, etc.]
- **What motivates engagement:** [Rewards, competition with peers, career growth, love of the sport, etc.]
- **How they talk to customers:** [Casual + technical / advisory / transactional]
- **Device / context they consume content on:** [Phone on the floor / desktop in back office / etc.]

---

## 3. Tone of Voice

**Three to five tone adjectives:** [e.g., Bold. Direct. Sport-literate. Rewarding. Human.]

> These are the filter. Before publishing, ask: does this sentence sound like all five of these? If not, revise it.

**Formal–informal scale:** [1 = corporate report / 5 = locker room chat] — score + one sentence explaining where the dial sits

**Technical–accessible scale:** [1 = specs sheet / 5 = complete beginner] — score + where it sits

**Serious–playful scale:** [1 = safety manual / 5 = brand Twitter] — score + where it sits

**Headline formula:** [Describe how headlines are written. E.g., "SHORT. ALL CAPS. Verb-forward. Often a single punchy sentence with a period for impact."]

**Sentence length:** [Short and punchy / Mixed / Long and explanatory]

**Person:** [Second person "you" / First person plural "we" / Third person descriptive]

---

## 4. Vocabulary Guide

### Use freely
[List brand-specific vocabulary, sport terminology, product line names, and insider language that the brand owns and uses naturally. These words make content feel authentic.]

| Word / Phrase | Why it works |
|---|---|
| [term] | [reason] |

### Use carefully
[Words that exist in this brand's world but need context or should only appear in certain content types]

| Word / Phrase | When to use |
|---|---|
| [term] | [context] |

### Avoid
[Generic language that sounds off-brand, competitor names, outdated product names, tones that contradict the brand personality]

| Avoid | Reason |
|---|---|
| [term or pattern] | [why] |

---

## 5. Product Universe

> *Ensures articles and training reference real product lines correctly and proportionally.*

**Core product categories:** [List in order of business importance to this customer's staff]

**Product line / collection names:** [The named lines staff need to know — used in training articles and achievements]

**Hero products (current):** [2–5 products currently being prioritised by the brand — these should feature in examples and CTAs]

**Technology / programme names:** [Proprietary tech, fitting systems, loyalty programmes, custom builders — if staff need to explain these, they appear in training content]

**Seasonal focus:** [Does product emphasis shift by season? Note it here so content is timed correctly]

---

## 6. Brand Partners & Collaborators

> *Prevents content from accidentally contradicting partnerships or missing co-brand opportunities.*

**Active collaborations:** [Brand x Brand partnerships that are current and relevant to staff]

**Affiliated leagues / organisations:** [Leagues, teams, or governing bodies the brand sponsors or is associated with]

**Key retailer context:** [If this is a B2B2C setup — who are the retailers? What type of store? Independent vs. chain?]

---

## 7. Content Patterns (from existing Atobi content)

> *The most direct signal of what works. Drawn from existing articles, feed posts, and engagement data.*

**Feed post style:** [How do they write social feed posts? Length, structure, emoji use, CTA style]

**Article format preferences:** [Long-form explainer / step-by-step / video + text / quiz-gated / etc.]

**Named content series:** [Any recurring formats with established names — maintain these names exactly]

**Reward mechanics used:** [What incentives drive completion? Discount codes, physical rewards, badges, leaderboard points?]

**Engagement triggers observed:** [What topics, formats, or frames historically drive comments and reactions]

---

## 8. Cultural & Seasonal Calendar

> *Makes content feel timely without the skill needing to know the calendar.*

**Key seasonal moments:** [Season start/end, major tournaments, product launch windows, off-season training period]

**Sport calendar landmarks:** [Playoffs, drafts, All-Star events, international competitions relevant to this brand's markets]

**Internal milestones:** [Training deadlines, new product drops, certification windows]

---

## 9. Content Do's and Don'ts

A quick-scan checklist the skill can use before finalising any piece of content.

**Do:**
- [Specific positive instruction relevant to this brand]
- [...]

**Don't:**
- [Specific thing to avoid — generic, off-brand, legally sensitive, or factually wrong]
- [...]

---

## 10. Sample Copy

> *Two or three real examples of on-brand content. These train the model's intuition faster than any description.*

**Feed post example:**
> [Paste a real or ideal short post — 2–4 sentences, written in brand voice]

**Article headline example:**
> [Paste 2–3 real or ideal article titles]

**Achievement / badge name example:**
> [Paste 1–2 real or ideal badge names with their description]

**Notification / alert copy example:**
> [Paste 1–2 short push notification-style lines]

---

*Last updated: [date]*
*Updated by: [name / team]*
*Data sources used: Atobi tenant content, [customer website], [social media], [retailer brief], [Drive source material], [memory playbook]*
