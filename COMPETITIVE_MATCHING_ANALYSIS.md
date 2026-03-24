# Competitive Matching Analysis: Your System vs Teal vs Jobscan vs Resume Worded

## Executive Summary

**Your system does not have a "matching layer" in the way Teal, Jobscan, and Resume Worded do.** What you have is fundamentally different — and that difference is both your biggest gap and your biggest potential advantage. This document breaks down exactly what each system does, what yours outputs, and where that leaves you strategically.

---

## Part 1: What Your System Actually Outputs When You Run a Resume Against a JD

### The Honest Answer

Your system does not score a resume against a JD. It does not output a match percentage. It does not produce a gap analysis. It generates a *new* resume tailored to the JD.

Here is the exact pipeline:

**Input:** Job description + ATS keywords + technologies + your project portfolio (from `ResumeConfig`)

**Processing (8 LLM calls per job via OpenAI `gpt-5-mini`):**

1. `produce_resume_statements` — Generates bullet points from your project portfolio, aligned to the JD's keywords and technologies
2. `enhance_resume_statements` — Intertwines ATS keywords and technologies into the bullets
3. `format_resume_statements` — Cleans formatting (with retry/validation loops)
4. `generate_technical_skills_list` — Produces a comma-separated skills line based on the JD
5. `extract_user_experience_themes` — Identifies 2-4 transferable competencies bridging your background to the target role
6. `create_resume_summary` — Writes a professional summary tailored to the role's seniority, function area, and your experience themes
7. `generate_similar_titles` — Produces 5 related role titles ranked by seniority
8. Various fallback generators for edge cases

**Output per job (stored in MongoDB `resumes` collection):**

```
{
  jobTitle, company, jobDescription, location, jobUrl,
  atsKeywords, technologies, qualifications, duties,
  resumeStatements: [{ statement, jobIndex, statementIndex }],
  technicalSkillsList: "comma, separated, skills",
  resumeSummary: '{"ResumeSummary": "..."}',
  similarTitles: ["Title 1", "Title 2", ...],
  resumeConfigId, resumeConfigName, status, generatedBy
}
```

**What is NOT in the output:**
- No match score (0-100%)
- No gap analysis ("you're missing X, Y, Z")
- No fit assessment ("strong fit" / "weak fit")
- No keyword coverage report
- No recommendation list ("add certification X")
- No recruiter-aligned reasoning about why you are or aren't a fit

### The Job Filter (Separate System in dejdash)

Your dejdash backend has a separate **AI job filter** (`jobFilterService.js`) that does something closer to "matching" — but it's binary, not scored:

**Input:** Scraped job listing + FilterProfile (candidate preferences: IC/management, seniority range, work arrangement, excluded companies/industries, custom rules)

**Processing:** OpenAI `gpt-4o-mini` with structured JSON output

**Output per job:**
```json
{
  "keep": true/false,
  "reason": "one sentence explanation",
  "tags": ["seniority_too_low", "industry_mismatch", ...]
}
```

This is a **preference filter**, not a **fit scorer**. It answers "does this job match what I'm looking for?" not "how well does my resume match this job?"

---

## Part 2: What Teal, Jobscan, and Resume Worded Actually Do

### Teal

**Matching approach:** AI-powered comparison running 15+ checks across structure, keywords, impact metrics, and completeness.

**What it outputs:**
- A real-time **Match Score** (percentage) comparing your resume against a specific JD
- Visual breakdown of what's **aligned** (green), what's **missing** (red), what to **adjust** (yellow)
- Keyword and skills gap identification
- Specific suggestions for tailoring bullets, summary, and skills sections
- Pre-match Resume Analyzer for baseline quality (formatting, structure, measurable results)

**How it reasons:** Semantic similarity + keyword extraction from JD + structural quality checks. It identifies which specific skills, phrases, and keywords the hiring team uses, then checks whether your resume reflects them.

**Limitation:** Primarily surface-layer semantic matching. It tells you "add this keyword" but doesn't deeply reason about whether your 3 years of project management experience actually qualifies you for a Director-level PM role.

### Jobscan

**Matching approach:** Keyword frequency analysis weighted by importance, plus ATS formatting checks.

**What it outputs:**
- A **Match Rate** (0-100%) based on keyword overlap
- Per-keyword breakdown showing: how many times the keyword appears in the JD vs your resume
- Priority ranking of keywords by importance
- Hard skills vs soft skills separation
- Formatting/ATS compatibility score
- Synonym detection and grouping

**How it reasons:** Primarily keyword frequency matching with weighting. It counts occurrences, checks for synonyms, and produces a score. The recommended target is 80%+ match rate.

**Limitation:** Heavy keyword orientation. A resume that mentions "Python" 5 times might score higher than one that demonstrates deep Python expertise through project descriptions. It optimizes for ATS pass-through, not recruiter judgment.

### Resume Worded

**Matching approach:** AI-powered keyword scan + relevancy scoring against specific JDs.

**What it outputs:**
- A **Relevancy Score** (target: 80+)
- Missing keywords identified from the JD
- AI-generated suggestions for writing bullet points that incorporate missing skills
- "Score My Resume" general quality check (separate from JD matching)

**How it reasons:** Keyword extraction from JD → comparison against resume → gap identification → AI-generated suggestions for rewriting bullets.

**Limitation:** Similar to Jobscan but with more AI-generated rewrite suggestions. Still fundamentally keyword-gap oriented.

---

## Part 3: The Three-Axis Comparison

### Axis 1: Accuracy of Match Scoring

| System | What It Scores | Scoring Mechanism | Calibrated to Recruiter Judgment? |
|--------|---------------|-------------------|-----------------------------------|
| **Your System** | Does not score. Generates new resume content. | N/A | N/A |
| **Your Job Filter** | Binary keep/reject with reason | LLM reasoning against preferences | Partially — it reasons about fit to preferences, not skills-to-requirements |
| **Teal** | % match against JD | Semantic similarity + keyword + structure checks | Loosely — better than pure keyword but still surface-level |
| **Jobscan** | % match rate | Weighted keyword frequency | No — optimizes for ATS algorithms, not human reviewers |
| **Resume Worded** | Relevancy score | Keyword gap + AI analysis | Loosely — keyword-centric with AI enhancement |

**Your gap:** You have no match score at all. You can't tell a user "this job is a 40% fit, don't bother" or "this is a 92% fit, apply now." The job filter gives a binary keep/reject for preference-based filtering, but it doesn't evaluate skills-to-requirements fit.

**Your potential advantage:** The competitors all essentially do keyword matching with varying levels of sophistication. None of them do genuine reasoning about role requirements vs candidate experience. Your LLM pipeline already reasons deeply about how to position experience against a JD (see `extract_user_experience_themes`) — that reasoning just isn't surfaced as a score or assessment.

### Axis 2: Quality of Gap Analysis

| System | Gap Analysis Output | Specificity | Actionability |
|--------|-------------------|-------------|---------------|
| **Your System** | None. Implicitly addressed by generating tailored content. | N/A | The generated resume IS the action |
| **Teal** | "Missing" keywords/skills highlighted, sections to adjust identified | Medium-high — tells you which specific skills are absent | Medium — shows what's missing but you write the fix |
| **Jobscan** | Per-keyword frequency comparison, missing keywords listed | High for keywords — exact counts and priorities | Low-medium — shows the gap, you figure out how to fill it |
| **Resume Worded** | Missing keywords + AI-generated bullet suggestions | Medium — keyword-level gaps with AI suggestions | Medium-high — gives you rewrite suggestions |

**Your gap:** Users can't see what's missing because you skip straight to generating the solution. That sounds good in theory, but it means users can't evaluate whether they should even apply. They can't see "you're missing 4 of the 6 required technologies" before you generate a resume that papers over those gaps.

**Your potential advantage:** Your `extract_user_experience_themes` prompt already identifies transferable competencies between the candidate's background and the target job. This is actual reasoning about fit — not keyword matching. If you surfaced this analysis as a visible gap report before generating the resume, it would be more insightful than what Teal/Jobscan/Resume Worded produce.

### Axis 3: Actionability of Output

| System | Primary Output | Does It Help Improve the Resume? | Does It Help Decide Where to Apply? |
|--------|---------------|----------------------------------|-------------------------------------|
| **Your System** | Complete tailored resume content (bullets, summary, skills) | Yes — it IS the improved resume | No — no signal on fit quality |
| **Your Job Filter** | Keep/reject + reason | No — only filters jobs | Yes — but binary, no nuance |
| **Teal** | Match score + gaps + suggestions | Partially — shows what to fix | Partially — score indicates fit |
| **Jobscan** | Match rate + keyword breakdown | Partially — shows keyword gaps | Partially — match rate as proxy |
| **Resume Worded** | Relevancy score + missing keywords + suggested bullets | Yes — gives rewrite suggestions | Partially — score indicates fit |

**Your gap:** You generate content but don't help users decide whether to apply in the first place.

**Your potential advantage:** You're the only system that produces a complete, ready-to-use tailored resume. Every competitor stops at "here's what's wrong with your resume" and leaves the user to fix it. You skip to the finished product. That's genuinely differentiated — if you pair it with fit assessment.

---

## Part 4: The Recruiter Alignment Question

The user's question frames the key distinction perfectly: most tools optimize for making users feel good (high scores, green checkmarks) rather than for calibration to recruiter judgment.

### What Recruiters Actually Evaluate

A senior recruiter screening resumes evaluates:

1. **Role-level fit** — Is this person at the right seniority for this role? (Not "do they mention the word 'senior'")
2. **Progression logic** — Does their career trajectory make sense for this role?
3. **Domain depth** — Do they have real experience in this domain, or just adjacent keywords?
4. **Impact evidence** — Do they show outcomes at the scale this role requires?
5. **Skills criticality** — Do they have the 2-3 non-negotiable skills, not just 80% keyword overlap?
6. **Red flags** — Job hopping, title inflation, buzzword stuffing

### How Each System Maps to Recruiter Thinking

| Recruiter Criterion | Your System | Teal | Jobscan | Resume Worded |
|---------------------|-------------|------|---------|---------------|
| Role-level fit | Job filter checks seniority range (binary) | Score adjusts somewhat for level | Not addressed | Not addressed |
| Progression logic | Not addressed | Not addressed | Not addressed | Not addressed |
| Domain depth | `extract_user_experience_themes` identifies transferable competencies | Keyword presence only | Keyword frequency only | Keyword presence only |
| Impact evidence | Prompts require statistical impacts in N% of statements | Checks for measurable results | Not specifically | Not specifically |
| Skills criticality | Not distinguished from nice-to-haves | Not distinguished | All keywords weighted equally-ish | Not distinguished |
| Red flags | Not addressed | Some structural checks | ATS formatting flags | Some structural checks |

**Key insight:** None of these tools — including yours — genuinely replicate recruiter judgment. They're all operating at the keyword/semantic layer. The recruiter is operating at the reasoning layer. This is the gap the user identified, and it's real.

---

## Part 5: Where Your System Stands — The Honest Assessment

### What You Have That's Differentiated

1. **End-to-end generation** — You don't just score; you produce the finished resume. No other tool in this comparison does that at the same depth.
2. **LLM-based reasoning about experience transfer** — `extract_user_experience_themes` does genuine reasoning about how a candidate's background connects to a target role. This is closer to recruiter thinking than keyword matching.
3. **Integrated pipeline** — Scrape → filter → generate → submit is a full stack that competitors can't replicate by bolting on a single feature.
4. **Job filtering with reasoning** — The `jobFilterService` gives explanatory verdicts, not just scores. "Title is a management role — IC only" is more useful than "72% match."

### What You're Missing

1. **No explicit match scoring** — You can't answer "should I apply to this job?" You only answer "here's a resume for this job."
2. **No visible gap analysis** — The reasoning exists inside your LLM prompts but is never surfaced to the user.
3. **No pre-generation assessment** — Users can't evaluate fit before you spend compute generating a full resume.
4. **No calibration data** — You have no feedback loop from recruiters, interviews, or applications to calibrate whether your generated resumes actually perform better.
5. **No must-have vs nice-to-have distinction** — Your keyword weaving treats all JD requirements equally.

### The Competitive Positioning Matrix

```
                    MATCHING DEPTH
                    (Low)  ────────────────  (High)
                      │
           Jobscan    │
 ACTION-   (keyword   │
 ABILITY   counting)  │
 (Low)                │
   │      Resume      │    Teal
   │      Worded      │    (semantic +
   │      (keywords   │    structure)
   │      + AI tips)  │
   │                  │
   │                  │          ┌─────────────────┐
   │                  │          │  YOUR SYSTEM     │
   │                  │          │  (generates the  │
   │                  │          │  whole resume,   │
(High)                │          │  but no scoring) │
                      │          └─────────────────┘
```

You're high on actionability (you produce the finished product) but effectively absent on matching depth (you don't tell the user whether they should bother).

---

## Part 6: Strategic Recommendations

### If You Want to Add Matching (the "better" path)

Build a **pre-generation fit assessment** that runs before the resume generation pipeline. It should:

1. **Score overall fit** (0-100) calibrated to recruiter judgment, not keyword overlap
2. **Identify must-have vs nice-to-have gaps** — distinguish "you don't have the required 5 years of Kubernetes experience" from "it'd be nice if you knew Terraform too"
3. **Assess seniority alignment** — is this a stretch role, a lateral move, or a step down?
4. **Surface the `extract_user_experience_themes` reasoning** — show users the competency bridges your LLM already identifies
5. **Recommend apply/skip/stretch** — not just a number, but a verdict with reasoning

This would be genuinely differentiated from Teal/Jobscan/Resume Worded because it would reason about fit rather than just counting keywords.

**Implementation hint:** You already have the LLM infrastructure and prompting patterns. A new endpoint that takes a resume + JD, calls a structured LLM prompt asking for fit assessment (with JSON schema output), and returns the analysis before triggering generation would be relatively straightforward.

### If Your Matching Is Roughly Equivalent After Testing

Sell the generation + submission pipeline as the product. Don't compete on matching. Let Teal keep their match score UI. Your value prop becomes: "We don't just tell you what's wrong with your resume — we fix it and submit it."

### If Your Matching Would Be Worse

Don't build it yet. The job filter (keep/reject) is sufficient for now. Focus on generation quality and submission reliability. Come back to scoring when you have user feedback data to calibrate against.

---

## Part 7: The 2-Hour Competitive Test Protocol

Here's the exact test to run, adapted for your system:

### Setup (15 min)
1. Sign up for Teal free tier
2. Sign up for Resume Worded free tier
3. Sign up for Jobscan free tier
4. Have your system running locally or via API

### Select Test Data (15 min)
Pick 5 real JDs across different levels:
- 1 entry-level role in your domain
- 1 mid-level role that's a strong fit for your background
- 1 senior role that's a genuine stretch
- 1 role in an adjacent domain (close but not exact)
- 1 role that's a genuinely poor fit (different function entirely)

Use a single real resume (yours or a test candidate's).

### Run the Tests (60 min)

**For each JD, capture:**

| Tool | What to Record |
|------|----------------|
| **Teal** | Match score %, list of gaps identified, suggestions given |
| **Jobscan** | Match rate %, per-keyword breakdown, priority keywords missed |
| **Resume Worded** | Relevancy score, missing keywords, AI-suggested bullets |
| **Your Job Filter** | keep/reject verdict, reason, tags |
| **Your Resume Generator** | Generated bullets quality, skills relevance, summary alignment |

### Evaluate (30 min)

For each JD, answer:
1. Which tool correctly identified the strong fit (JD #2) vs the weak fit (JD #5)?
2. Which tool's gap analysis was most specific and actionable?
3. Did any tool give misleadingly high scores for the poor-fit JD?
4. How do your generated resume bullets compare to Resume Worded's suggested bullets?
5. Would a recruiter agree with each tool's assessment?

### What You're Looking For

- **If Teal/Jobscan give 80%+ scores on the poor-fit JD:** That's the "engagement optimization" problem. If your job filter correctly rejects it, you're already more honest.
- **If your generated bullets for the stretch JD are better than Resume Worded's suggestions:** Your generation quality is a real differentiator.
- **If all tools including yours miss the seniority mismatch:** That's the recruiter-reasoning gap none of you have solved yet.

---

## Part 8: What Your Matching Layer Currently Outputs — Direct Answer

**Resume Generator (`resume_api.py`):**
When you run a resume against a JD, you get generated resume content — not a score or assessment. The output is tailored bullets, a skills list, a summary, and similar titles. There is no match percentage, no gap report, no fit verdict.

**Job Filter (`jobFilterService.js`):**
When you run a job through the filter, you get a binary keep/reject with a one-sentence reason and categorized tags. This is preference-based filtering, not skills-to-requirements matching.

**The gap:** You have generation without assessment. You can produce a great tailored resume for a job you shouldn't apply to. The competitors have assessment without generation. They can tell you the job's a 40% fit but leave you to fix the resume yourself.

**The opportunity:** Combine both. Assessment + generation in one pipeline is what none of the competitors offer. That's the full-stack story.
