---
name: ce-quiz-generator
description: >
  Generate quiz questions, knowledge checks, and assessment actions for Atobi
  content. Reads source material (articles, journeys, PDFs, product sheets) and
  the brand-voice profile to create scenario-based, role-appropriate questions
  that test product knowledge and selling skill. Use when adding quizzes to any
  content, when asked "add quizzes to [content]", "create knowledge check for
  [topic]", or auto-called by ce-article-producer and ce-journey-producer during
  production.
metadata:
  version: "0.1.0"
  phases: [delivery]
---

# Quiz generator

Generate scenario-based knowledge checks for Atobi content that test whether store staff can sell — not whether they can memorise bullet points. Bad quiz: "What technology is in the Mercurial sole plate?" Good quiz: "A customer is worried about playing on a wet pitch. Which Mercurial feature solves their concern?" Invoke directly, or auto-called by `ce-article-producer` / `ce-journey-producer` during production.

## Outcome

A set of quiz actions embedded in the article/journey payload, ready to publish through the Atobi platform.

- **Format**: YAML blocks describing one action each — `quiz`, `open_question`, `yes_no`, or `poll`.
- **Distribution**: 1–3 actions per section for journeys (required for unlock), 1–2 actions total for articles.
- **Difficulty curve**: easy → medium → hard across sections in journeys.
- **Feedback**: every quiz answer carries a teaching feedback line.
- **Voice**: matches the brand-voice profile passed in (e.g. `nike-football`: direct, coach-like).

## Context needs

| File | Load level | How it shapes this skill |
|------|-----------|--------------------------|
| Source content (article / journey / PDF / product sheet) | full | The material being quizzed — every question must trace back to a section, fact, or scenario in it |
| Brand-voice profile | reference | Drives tone, vocabulary, and question framing (e.g. `nike-football` → direct, scenario-based) |
| Atobi platform action schema | reference | Defines the allowed action types (`quiz`, `open_question`, `yes_no`, `poll`) and field shape the output must conform to |
| Atobi AI Quiz Generator output | if used | Accelerator: AI-generated questions to review and refine, never publish blindly |

## Skill relationships

- **Phase**: delivery
- **Often follows**: `ce-article-producer`, `ce-journey-producer`, `ce-campaign-producer` — auto-called during content production
- **Often precedes**: publishing the article/journey through the Atobi platform
- **Related**: the sibling producer skills embed quiz output into their final payloads

## Step 1: Analyse the source content

Read the content being quizzed and extract three layers:

- **Key facts** — specs, features, dates, prices → recall questions.
- **Key concepts** — benefits, differentiators, positioning → understanding questions.
- **Key scenarios** — customer situations, selling moments, objection handling → application questions.

Note section / anchor references against each extracted item so questions can carry a `section_reference` back to the source.

## Step 2: Pick the right question type

| Type | Best for | Platform action |
|------|----------|-----------------|
| **Quiz (multiple choice)** | Knowledge verification, scenario-based selling | Quiz action — select correct option(s) |
| **Open Question** | Creative responses, pitch practice, personal reflection | Open Question action — short text answer |
| **Yes/No** | Quick comprehension checks, policy acknowledgement | Yes/No action |
| **Poll** | Opinion gathering, engagement (no correct answer) | Poll action — 2–5 options |

Default to **quiz** for facts and selling scenarios; **open question** for pitch practice; **poll** when you want engagement with no correct answer; **yes/no** sparingly, only for explicit policy acknowledgement.

## Step 3: Generate questions across the difficulty curve

Mix recall, understanding, application, and scenario questions. For journeys, run easy → medium → hard across sections; for articles, keep it light.

```yaml
quiz_generation:
  source: "Mercurial Superfly 10 training journey — Section 2: Technology"
  brand_voice: "nike-football"

  questions:
    # RECALL — did they read it?
    - type: "quiz"
      difficulty: "easy"
      question: "What does Anti-Clog Traction do?"
      options:
        - "Prevents mud build-up for consistent grip" # correct
        - "Provides extra ankle support"
        - "Makes the boot waterproof"
      correct: 0
      section_reference: "section_2"

    # UNDERSTANDING — do they get why it matters?
    - type: "quiz"
      difficulty: "medium"
      question: "Why is Zoom Air in the forefoot specifically — not the heel?"
      options:
        - "Because sprinters push off from the forefoot" # correct
        - "Because there isn't room in the heel"
        - "Because the forefoot needs more cushioning"
      correct: 0
      feedback: "Speed boots are about acceleration — and acceleration starts at the forefoot."

    # APPLICATION — can they use it on the floor?
    - type: "quiz"
      difficulty: "hard"
      question: "A customer tries on the Mercurial and says 'it feels tight.' What do you say?"
      options:
        - "I can get you a half size up"
        - "The Flyknit is designed to fit snug — it will break in after 2-3 wears for the perfect lockdown feel" # correct
        - "That means it's the wrong boot for you"
      correct: 1
      feedback: "Lockdown IS the selling point. Tight = working as designed. Reassure and educate."

    # SCENARIO — real selling moment
    - type: "open_question"
      difficulty: "hard"
      question: "A customer is choosing between the Mercurial Superfly 10 (€275) and the adidas X Crazyfast (€250). Write what you'd say to close the sale."
      visibility: "public"
      section_reference: "section_3"

    # ENGAGEMENT — opinion, no wrong answer
    - type: "poll"
      question: "Which Mercurial colourway will sell best in your store this season?"
      options: ["Volt/Black", "Black/Chrome", "Bright Crimson"]
      section_reference: "section_1"
```

Always include `feedback` on quiz answers — that's the teaching moment.

## Step 4: Apply the brand voice

Rewrite each question and feedback line so it matches the brand-voice profile:

- **Nike-style**: direct, coach-like, scenario-based, conversational.
- **Avoid**: academic, test-like, formal, corporate.

If the profile is missing or ambiguous, default to second-person scenario framing ("A customer says…") and reject any question that reads like a textbook prompt.

## Step 5: Apply the distribution rules

| Container | Action count | Mix |
|-----------|--------------|-----|
| Journey section | 1–3 actions per section (required for unlock) | quiz + open question |
| Article | 1–2 actions total | keep light — reference articles should not feel like exams |

Difficulty curve across journey sections runs easy → medium → hard. Every quiz answer carries a `feedback` line. Verify every AI-accelerated question before handing back to the producer skill.

## Troubleshooting

- **AI-generated questions feel generic** — the Atobi AI Quiz Generator is an accelerator, not a publisher. Every question must trace to a specific section, fact, or scenario in the source; rewrite the ones that don't.
- **All questions are recall-only** — you skipped scenario extraction in Step 1. Re-read the source for selling moments and objection handling, then regenerate the hard tier.
- **Brand voice drift** — questions sound like the writer, not the brand. Re-apply Step 4 with the voice profile in front of you; cut anything that doesn't sound like a coach talking to floor staff.
- **Section reference missing** — quizzes embedded in a journey need `section_reference` to gate unlock. Add it before handing back to the producer skill.
