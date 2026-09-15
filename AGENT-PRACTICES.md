# Agent working standard — Furlough

**Adapted to this repo 2026-09-14, solo mode.**

**What this is.** The working standard for agent-driven development here: how work is scoped
and decided, how it is sized to a model's context, which model runs what, how several sessions
run against one checkout without eating each other's work, what a session hands the next one,
and how the documentation is written so the next session can trust it. `CLAUDE.md` is the
router every session gets; this is the process it routes to.

**What was cut from the boilerplate, and why.**

- **Part 0, the adapt protocol** — it did its job on 2026-09-14 and was deleted. The original
  boilerplate is where it lives if this is ever re-adapted.
- **Part 12, teams** — one person decides everything here. Several *sessions* run at once;
  one *person* runs them. Part 6 carries everything the sessions need.
- **The *CI* enforcement tag, and every "what CI runs"** — there is no CI. `ls .github`
  returned nothing, 2026-09-14. The gates are five local commands and they are in `CLAUDE.md`.
- **The ratchet rules** — there is no linter. No SwiftLint, SwiftFormat or EditorConfig
  configuration exists at the root (checked 2026-09-14). The compiler's warnings are the whole
  lint story, and the house rule is that our own code produces none.
- **The migration-number rule** — there is no database and there are no migrations. State is
  JSON in an App Group `UserDefaults` (`Shared/Core/SharedStore.swift`), versioned by tolerant
  decoders rather than by numbered files. The general numbered-shared-resource rule is **kept**,
  and Part 6 names the four numbers this repo actually shares.

**Kept against the instruction to cut.** The parity rules stayed. iOS and Mac genuinely mirror
each other, the divergences are real and deliberate (`ShieldReconciler.swift` and
`ActivityNaming.swift` are excluded from the Mac targets in `project.yml`; `TargetKind` is
tokens on iOS and `.macApp`/`.host` strings on the Mac — `HANDOFF.md`, "The Mac"), and a
sanctioned-divergence registry is the thing that stops a session "fixing" one of them.

**Part 11 was kept as shipped**, with one rule added (release notes before a version bump). It
already matched what `HANDOFF.md` and `PASSOFF.md` say, which is unsurprising — see Provenance.

**Provenance.** Distilled from two working repos, each rule written after the failure that made
it necessary. **Repo B is this repo**: the boilerplate describes it as "a Swift app (iOS +
macOS + widgets + extensions, XcodeGen, no CI), small, gates are two `xcodebuild` commands,
work arrives as a stream of independent items", and its one worked example — "nothing can
screenshot the phone; the owner sends screenshots" — is `HANDOFF.md:19-20` almost verbatim. Its
examples are therefore facts about this codebase and are relabelled as such below. **Repo A is
not this repo**: a TypeScript/Go monorepo (Bun workspace, Next.js web + Expo native + Go API +
Postgres, ~15 CI jobs, ratcheted lint). Its `> **Worked example**` blocks are evidence for a
rule, never facts about Furlough, and say so.

**Placeholders.** There are none left. `grep -nE '\{\{' AGENT-PRACTICES.md` returns hits only
inside Appendix A's Token column, which is the record of what was filled in and with what.
Slots written `<like this>` inside fenced blocks are part of a template you copy — they are not
adapt-time values and stay as they are.

**Map.** Part 1 is the twelve rules that hold everywhere. Part 2 is where work gets written
down. Part 3 is the pass-off prompt. Part 4 picks the model. Part 5 sizes work to a model's
context. Part 6 is parallel sessions and git. Part 7 closes a piece of work. Part 8 is how the
docs are written. Part 9 is `CLAUDE.md`. Part 10 is agent memory. Part 11 is Zach's policy.
Appendix A records the values this adaptation chose; Appendix B lists what it produced.

---

# Part 1 — The rules that hold everywhere

These survive every adaptation. They are the ones that, when broken, cost a whole session or
silently corrupt a later one. Each ends with its **test** — what a reader of the doc, the diff
or the hand-back checks — so whether a session complied is never a matter of opinion.
**"The owner"** throughout this file is Zach.

**R1 — Absolute dates only.** `2026-09-14`, never "today", "recently", "last week". Docs are
read months later by an agent with no idea when they were written.
*Test:* `grep -niE 'today|yesterday|recently|last (week|month)|this (week|month)'` over what
you wrote returns nothing.

**R2 — Every claim carries a citation.** `file:line`, a filename, a commit hash, a HANDOFF step
number, the query that produced it. A claim with no citation is a guess and will be treated as
one.
*Test:* every sentence stating what the code, the data or the tooling does names its source;
one that cannot is deleted before hand-off.

**R3 — A claim in an existing doc is a lead, not a fact.** Re-verify before building on it.
This applies to `HANDOFF.md` as much as to anything else: it is 3,274 lines written across six
weeks, and its older paragraphs describe a codebase that has moved.
*Test:* a claim carried forward appears with `verified <date>` and the citation from your own
check, not the original's.

> **Worked example — repo A, not this repo.** A handoff recorded "there is no vision anywhere
> in the repo". Vision was live the whole time at `backend/helpers/listingHelpers.go:326`. On
> that same track, handoff "missing feature" claims were three for three wrong.

**R4 — Grep before recording an absence.** "Nothing does X" is the most expensive kind of wrong
claim, because everything downstream is built on it.
*Test:* every "nothing does X" and "there is no X" carries the grep or query that produced it.

> **Worked example — this repo, 2026-09-14.** `PASSOFF.md`'s note on items 23–32 records three
> ideas that did not survive the grep: a tag tap already drops the anchor as well as lifting it
> (`AnchorView`'s `.drop` branch), `AnchorDrop.drop` already takes an `until`, and location- and
> Focus-triggered drops already work through Shortcuts. Three items became one page.

**R5 — When you disprove something, record the disproof where the wrong claim lives.** With the
reason it was wrong. Silent deletion means the next session rediscovers it.
*Test:* the wrong claim is still findable, marked wrong, dated, with the disproof beside it.

> **Worked example — this repo.** `PASSOFF.md` keeps items 16 and 17 on the board marked Done
> *and* records that their prompts describe the work wrongly: item 16's first step rests on a
> false premise (StandBy scales the **small** widget; there is no StandBy family), and item
> 17's configurable scope was dropped on Zach's call. The prompts were not edited into a lie.

**R6 — Ask Zach where he will see it, before building, in one batch.** That is the chat, in the
same turn. Questions written into a doc for async review do not get answered. Put every open
question into one prompt rather than trickling them.
*Test:* the questions went out in one message before any code that depends on an answer was
written; the hand-back lists any still unanswered.

**R7 — For user-facing copy, never pick silently.** Where a decision has not already fixed the
words, write 2–3 real variations in different registers (plain, warm, terse) and ask which.
Check `HANDOFF.md`'s "Settled" sections first; re-opening decided copy wastes Zach's time.
*Test:* the ask shows the variants with their registers named, or cites where the copy was
settled.

**R8 — Never re-litigate a settled decision.** `HANDOFF.md`'s "Settled:" sections and
`PASSOFF.md`'s **Settled as no** rows are the marker. Check for it before treating anything as
open. Genuinely new evidence produces a *supersession* — stated explicitly, dated, naming what
it replaces — not a quiet reversal.
*Test:* nothing carrying a settled marker is reopened in a doc or an ask; any change to one is
a dated supersession that names what it replaces.

> **Worked example — this repo.** The Apple Watch is `PASSOFF.md` item 15, **settled as no**,
> HANDOFF 42. The board says it "should not be re-proposed without a reason that answers what
> is written there". That sentence is the mechanism.

**R9 — Descoping is Zach's call.** If something is explicitly parked, record it and stop
raising it. If nothing has been said, a finding still blocks by default: surface the judgment
call rather than making it.
*Test:* every finding not fixed appears in the hand-back as `parked by Zach <date>` or `open`;
none is dropped silently.

**R10 — Report faithfully.** "Gates green, not seen running" and "walked the flow on the phone"
are different claims and must never be merged. Say which one you have. In this repo the gap is
wider than usual, because **nothing can screenshot the phone** (`HANDOFF.md:19-20`): a session
can reach "gates green" alone and never further without Zach.
*Test:* the hand-back says which of the two it claims, per item.

**R11 — Read the matching standard in full before writing code.** Not optional, not conditional
on task size. If you have not read it this session, read it now.
*Test:* the session's first reads include the standard, and the hand-back names it.

**R12 — Stop mid-file when something contradicts a settled decision.** Do not take the call and
flag it afterwards, do not finish the phase first. The test is whether the decision would have
come out differently; if you are unsure, that is itself the signal to ask. A build-level call
that merely *implements* a settled decision is yours to take — record it as a line in the
HANDOFF step (2.1), with one line on how to reverse it.
*Test:* the contradiction reaches Zach as a question before the next edit to that file lands.

**R13 — Run the model the item assigns, or hand it to one that is.** Every board row and every
pass-off prompt states a driver (Part 4). Compare it to the model you are actually running
**first** — before reading the codebase, before planning, before the first edit — and say in one
line which you are. If they match, go. If they do not, there are two moves and no third:
**delegate** the whole prompt to a subagent with that model passed explicitly, or **stop** and
hand Zach a pass-off prompt (Part 3) carrying what this session already established, naming the
model it is for. Prefer delegating when the item is self-contained; prefer handing off when it
needs Zach's decisions along the way, or when the context already built is worth more than the
work. Never do the work yourself on the wrong model, and never downgrade an assignment because
the item looked smaller once you had read it — "it turned out to be simple" is a judgement only
the assigned model gets to make. If an assignment looks wrong, say so and ask (R6); do not
overrule it. Added 2026-09-14, at Zach's instruction, and in `~/.claude/CLAUDE.md` too, because
a rule that lives only in a file read *after* work starts fires too late.
*Test:* the session's first message names both models; a mismatched session's diff is a
delegation or a pass-off, never an implementation.

---

# Part 2 — Where work gets written down

**This repo is Profile L**, and was before this standard arrived: `HANDOFF.md` and `PASSOFF.md`
already exist at the root under exactly those names, in exactly this shape. 2.1 describes what
is there, not what to build. 2.2 is the secondary profile, for the one effort that outgrows a
board row.

## 2.1 Profile L — ledger + board

Two files at the repo root.

### `HANDOFF.md` — what is true

Read first by every session. Append-only in its log; its standing sections are edited in place
when they go stale. Its sections, as they stand 2026-09-14:

- **Orientation** (line 1) — what Furlough is, who Zach is, what he knows, that he is
  interactive, and the read-first list: this file, then `README.md`, then `design/DESIGN.md`,
  plus `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` when the work is about
  shipping.
- **Environment** (line 9) — the verified build and test commands, Xcode and Swift versions,
  the phone's UDID, the team id and signing, where logs land. Each one was run before it was
  written. **It states plainly what an agent cannot do here**, and what to do instead.

  > **Worked example — this repo.** "Nothing can screenshot the phone from the Mac; Zach sends
  > screenshots" (`HANDOFF.md:19-20`). So every session ends with *exactly what to tap and what
  > should appear*, and waits. Naming the limit converts it from a silent gap into a handoff
  > step — and it is why Part 7's runtime entries are the only proof of a working screen that
  > this repo can produce.

- **Settled: `<topic>`** (lines 55, 171, 208) — what Furlough *is*, what the look is, what the
  hourglass is. Marked settled, with dates. **Do not re-ask anything under Settled** (R8).
- **Code map** (line 219) — every file in `Shared/Core`, `Shared/Intents`, `Tests/Core` and the
  two apps, one entry each, with what it holds and which step added it. Updated by the session
  that adds a file.
- **How enforcement works (do not break these invariants)** (line 408) — the activity budget,
  the 20-activity ceiling, reconcile-from-persisted-state, the clock stamp, what the shield
  extension may write, and who may write `Config.anchor`. These compile fine when broken.
- **Known API facts and quirks** (line 470) — platform behaviour learned the hard way, cited.
- **The step log** — under **"## Next work, in order"** (line 646). Numbered, append-only:
  `N. **Title.** Done <date>. <what changed, why, what is now fixed, which decisions it
  answered>`. Steps are addressable forever — "HANDOFF 24" is how everything else refers to
  work. It ran 1–44 on 2026-09-14 (`grep -cE '^[0-9]+\. \*\*' HANDOFF.md` → 44). Two rules:
  **take the next free number by reading the file, not by trusting one written elsewhere**
  (another session may have taken it), and **do not edit a step you did not write** — append a
  correction as a new step.
- **Style rules** (line 3128) — five lines: Swift 6 with approachable concurrency, SwiftUI,
  `@Observable`, async/await, no third-party dependencies, and shared code the monitor
  extension uses must not import SwiftUI. See 8.1: this is currently the whole code standard.
- **The Mac** (line 3134) — why the Mac has its own enforcement, and how it differs. In effect
  the sanctioned-divergence registry 8.1 asks for.

### `PASSOFF.md` — what is next

A board plus one standalone prompt per item (Part 3). The board is the parallelism model:

| # | Task | Status | Model | Lane | Waits on | Files it owns |
|---|------|--------|-------|------|----------|---------------|

- **Lanes run in parallel; items inside a lane run in order.** Each open lane is its own
  worktree. Items in one lane are serial because each changes the shape the next builds on —
  in lane A the order was 3, then 2, then 4, because each changes `AnchorProfile`.
- **"Files it owns"** is the collision check. Two items that name the same file do not run at
  the same time, whatever their lanes say. Check it against every open item before starting
  one. Note what `PASSOFF.md` already says: every lane touches `Shared/Core/Models.swift`,
  `Policy.swift`, `Tests/Core` and `HANDOFF.md`, so merges conflict a little by design — keep
  it mechanical, add a new numbered step at the end rather than editing one, and put tests in a
  new file named for the feature rather than inside an existing suite.
- **Status** uses the board words in 2.3, and `Done` points at the ledger step that is the real
  record: `Done — HANDOFF 24`. **Do not paste a prompt marked Done** — a fresh session would
  build it again. `PASSOFF.md` says this at the top of its board, twice, because it happened.
- **A prompt rots the moment it is executed.** The ledger step is the truth; the prompt is the
  ask. Where a Done prompt turns out to describe the work wrongly, say so on the board rather
  than editing the prompt into a lie (R5, and the item 16/17 example above).
- **An item exists before work on it starts:** a row, plus a dated paragraph under the board
  saying why it exists and what it came out of. An item settled as *no* stays on the board with
  its reason, so it is not re-proposed.

## 2.2 Profile P — project folders

The secondary profile here: open one only when a single effort will span many sessions and
needs decisions ratified before code. A board row and a HANDOFF step are enough for everything
else, and have been for 44 steps.

One folder per effort at `design/<slug>/`, from the first keystroke, moved to
`~/Projects/archive/furlough/<slug>/` when it closes. `design/` already holds the design docs
(`DESIGN.md`, `COMPANIONS.md`, `HOURGLASS.md`, `USAGE-ONBOARDING.md`) and two folders of
exactly this shape (`design/anchor-puck/`, `design/store/`).

| Stage | Artifact | Who decides | Exit condition |
|---|---|---|---|
| 0 · Intake | — | — | You know what tree and what data to read |
| 1 · Ground truth | (feeds 2) | — | Every claim carries a citation, dated |
| 2 · Scope | `SCOPE.md` | agent proposes | Options with defenses; nothing decided |
| **GATE 1** | — | **Zach** | Decisions ratified |
| 3 · Design | `DESIGN.md` | Zach decides, agent records | `D1…Dn` frozen, with supersessions |
| 4 · Plan | `PLAN.md` | agent proposes | Phases, lanes, done-when, dials |
| **GATE 2** | — | **Zach** | Plan approved |
| 5 · Build | `PLAN.md` per phase | agent | Gates green; header says BUILT + hash |
| 6 · As-built | `DESIGN.md` amended | agent | Every deviation recorded under its decision |
| 7 · Runtime pass | `RUNTIME-PASS.md` | Zach walks it | Findings folded back |
| 8 · Close-out | archive + index + memory | agent | Folder out of the repo, referrers checked |

**Stage 0 — Intake.** When Zach says "let's build X": say nothing back until Stage 1 is done. No
clarifying questions first — the audit answers most of them, and the rest are asked at GATE 1 in
one batch. Read first: `CLAUDE.md`, `HANDOFF.md`, and any existing doc that overlaps, including
`~/Projects/archive/furlough/INDEX.md`. That last one is what stops a project re-deciding
something already settled.

**Stage 1 — Ground truth.** Read the tree and the live state before proposing anything. R2–R5
apply hardest here. Output is a table — claim, verified state, citation — dated absolutely. It
becomes `DESIGN.md` §1. This stage routinely finds that the project is not the shape the request
assumed.

> **Worked example — repo A, not this repo.** A project opened by discovering the link it was
> asked to build already existed in the schema and ran backwards, destructively, deleting the
> user's addresses on every slider tick. That reordered the entire project.

**Stage 2 — `SCOPE.md`.** Its job is to make Zach's decisions cheap. It proposes and decides
nothing. Sections: **1. What exists today (verified `<date>`)** — the Stage 1 table, first,
because every option is only meaningful against it. **2. What this is / what this is not** — the
non-scope list is as load-bearing as the scope list and gets skipped constantly; without it
every parked item is relitigated mid-build. **3. Options** — each with a real defense *including
the strongest argument against it*, which is what stops that argument coming back in three weeks
as a new objection. **4. Dials** — every number the design leaves open, each with a recommended
default, destined for config rather than a constant hardcoded twice. **5. Hazards this work
walks into.** **6. Open questions** — the GATE 1 batch.

**GATE 1 — Ratification.** Stop. Ask in one batched question in the same turn the scope doc is
finished (R6). Every option carries a marked recommendation — never present a survey with no
opinion. R7 governs copy. Record every answer with its date, in the doc, the same turn it is
given.

**Stage 3 — `DESIGN.md`.** `SCOPE.md` is renamed (git records the transition) and the answers
are written in as `D1…Dn`, each carrying: the decision stated flatly; **the defense** — why this
and not the alternative, which is what makes it survivable when the next agent finds it
inconvenient; **supersession pointers**, specific, saying which half dies when a supersession is
partial; and the date. Also required: **"Rules that survive unchanged"** — listing what is *not*
changing is how you stop a build phase from helpfully rewriting it. **From here the design is
frozen**: it changes by amendment — a new dated `D<n>` or an `As built:` note — never by editing
a decision in place.

**Stage 4 — `PLAN.md`.** The design is *what and why*; the plan is *in what order, by whom, done
when*. Sections: **0. Facts verified `<date>` (supersede the design where they differ)** — a
second verification pass at build time, in the same table shape, because days have passed and
another session may have taken your number; the plan's table wins, and says so in its own
heading. **1. Decisions taken since ratification** — build-level calls, numbered `BD-1…BD-n` so
a later deviation can cite them, each with a one-line reversal. **2. Phases** — the table
(`# | Phase | Driver | Subagents | Est. context | Why that shape`), where `Est. context` is a
band against that phase's driver ceiling (Part 5): `comfortable`, `full` or `tight`; a `tight`
phase names what it will delegate if it runs long, and nothing is planned above `tight` — that
is a phase that needs splitting. Then one section per phase with exactly five parts: status
header, scope (numbered, executable without re-reading the design), subagents (model and job, or
`none`, decided here not improvised), **done when** (the literal gate commands *plus* a proof
obligation a green gate cannot supply), and **watch for** (the hazard specific to this phase).
**3. Dials.** **4. Seams reserved, deliberately not built** — so the next effort need not guess
whether an omission was considered. **5. Repo hazards, with live numbers.** **6. Session
protocol** — a link to this file, plus anything specific to this project.

> A phase whose done-when is only "gates pass" has no done-when. In this repo the gates cannot
> see a screen at all, and cannot see the phone even in principle. Real ones: *"`Tests/Core`
> proves a night window folds back to the one row it was written as, for a span crossing
> midnight on a Sunday"*; *"Zach taps Anchor with no tag paired and is refused, and the log
> line says why."*

**GATE 2 — Plan approval.** Phases, order, lanes and dials go to Zach before any code. Once
approved, the plan authorizes the whole run; phases do not each need re-approval.

**Stages 5–8** are Parts 5–7 of this file: build one phase per session, close it out, record
what actually shipped, walk the runtime pass, archive.

## 2.3 Status vocabulary

Use these words and no others, so a board or a folder can be scanned:

- **Board items (Profile L):** `Open` · `In flight` · `Done — HANDOFF <n>` · `Held` ·
  `Settled as no` · `Superseded`.
- **Project folders and phases (Profile P):** `SCOPING` · `RATIFIED` · `PLANNED` · `IN FLIGHT` ·
  `BUILT` · `HELD` · `SUPERSEDED` · `CLOSED`.

`BUILT` means gates green. `Done` always points at the HANDOFF step. `Held` always names what it
waits on — on this board that is usually Apple, not a session. `Superseded` always names what
replaced it. `Settled as no` always carries the reason, because its whole job is to not be
re-proposed.

There is no `MERGED`: this repo has one branch that matters (`main`), no pull requests, and Zach
commits. `BUILT` plus his commit is the end of the line.

## 2.4 Entering in the middle

Not every effort starts at the beginning.

- **A defect list from a real session** (Zach walking the phone, a TestFlight report) starts at
  Stage 4 — the findings *are* the scope. It gets the same phase / done-when / watch-for shape.
- **An audit** produces its findings as Stage 1 output and then enters at Stage 2.
- **A resumed effort** re-runs Stage 4 §0 before executing a single phase: days-old plans have
  stale numbers, closed findings, and phases another session superseded.

---

# Part 3 — The pass-off prompt

**The single highest-leverage artifact in this standard.** Every session ends by writing the
next one's first message. It must stand alone: the next agent will not see this conversation,
this reasoning, or this context. A prompt that assumes any of it produces a session that
rediscovers what you already knew.

Nine parts, in this order. Skip a part only when it is genuinely empty, and say so.

**1 — Title.** Imperative, naming the change, not the area. *"Drag the week grid: windows edited
where they are drawn, on both apps"*, not *"week grid work"*.

**2 — The header line.** `**Model: <tier>. Lane <X>. Waits on <what>.**` Plus the worktree
instruction when the item needs its own (Part 6).

**3 — Orientation.** Who you are picking up, what to read first and in what order, and the
session rules restated *inline* — not by reference. Two or three sentences. Repeating them in
every prompt is deliberate: a prompt is pasted alone, and a rule one file away is a rule that
does not arrive. `PASSOFF.md` keeps the canonical wording under "Session rules"; copy it.

**4 — Why this exists.** The product reason, in product terms. This is what lets the next agent
make a hundred small judgment calls the prompt does not cover.

**5 — What is fixed.** *"Read these before changing anything; do not relitigate them."* The
verified facts with citations: which files hold what, the sizes, the invariants, the house
precedent to copy rather than reinventing, the constraint that makes this smaller than it looks.
This section is where a session's Stage-1 reading is *banked* instead of re-paid.

**6 — Do these, in order.** Numbered steps, each carrying its reason and its constraint. A step
that says only what to do gets done differently than intended.

**7 — Ask before building.** The named decisions that are Zach's, each with what makes it a real
question and what the answer might be. Explicitly: *both are his calls, and the answer to either
may be no.*

**8 — Not in scope, whoever asks.** The negative list, named. It survives a persuasive
mid-session argument in a way that an unstated boundary does not.

**9 — Hand back.** Exactly what must be green (the literal commands), what Zach should tap and
see (Part 7's runtime entries), and the two commit blocks Part 11 specifies.

### Template

```
## <N>. <Imperative title>

**Model: <tier>. Lane <X>. Waits on <nothing | item N | an external approval>.**
<Worktree instruction if this item needs one.>

You are picking up Furlough. Read `HANDOFF.md` first — the build and test commands, the
invariants and the code map are there; do not re-derive them — then `README.md`, then
`design/DESIGN.md`. Never run `git commit` or `git push`; when the work is ready run
`git status --short` and print two bash blocks for Zach. Run `xcodegen generate` after adding
a file. Keep the build free of warnings in our code. Every change to `Shared/Core` gets tests
in `Tests/Core`. Nothing can screenshot the phone, so end with exactly what Zach should tap
and what he should see, then wait. Zach is interactive: when a decision is his, ask first.

**Why this exists.** <product reason>

**What is fixed.** Read these before changing anything; do not relitigate them.
- <verified fact with file:line>
- <invariant, and what breaks if it is broken>
- <the house precedent to follow rather than invent>

Do these, in order:
1. **<step>.** <why, and the constraint it must respect>
2. …
<N>. **Record it.** The new HANDOFF step at the next free number, naming what changed, why,
   what is now fixed, and which decisions it answered; plus the code-map line for any new file.

Ask before building: <Zach's calls>.
Not in scope, whoever asks: <the negative list>.

Hand back: <the exact gates, green>; <what Zach should tap and see>; the two commit blocks.
```

---

# Part 4 — Model selection

## The driver — the model the session runs on

**The discriminator is: can the failure be silent?** Not how big or how scary the work feels.
Sizing by fear over-assigns the expensive tier.

`PASSOFF.md` states the same rule in this repo's own terms, and it is the better test here:
**Fable goes wherever a mistake becomes an unblock.** Anything that changes what `Policy.decide`
shields, anything that writes `Config.anchor` from a new process, anything that crosses devices,
and the Mac network extension. Opus is right for work whose failure mode is a bad screen or a
missed API rather than a hole in the lock.

| Driver | Model (2026-09-14) | Use for |
|---|---|---|
| **Deep** | Fable 5.1 (`claude-fable-5-1`) | Only where a mistake compiles, passes every gate, and is wrong on the phone: `Policy.decide`, `AnchorProfile.holds`, the sync merge rules, the monitor's threshold arithmetic, a notification that must never send. Prefer **one narrow Deep review of a short load-bearing path** over a whole Deep phase — and that review can be a subagent (below). |
| **Default** | Opus 5 (`claude-opus-5`) | The default and the right answer for most work. Anything where failure is loud — a build break, a red gate, a wrong screen — because the gates do that reasoning for you. |
| **Mechanical** | Sonnet 5 (`claude-sonnet-5`) | Whole phases only when genuinely mechanical: close-out sweeps, doc reconciliation, a bounded rename, an audit with a fixed checklist (`PASSOFF.md` items 31 and 32 are both Sonnet for this reason). Escalate to Opus the moment a gate fails for a non-obvious reason. |

Every board item states its driver, and the close-out repeats it (Part 7, Block C) so Zach can
set the model before opening the next session.

## The check on pickup

**Stating the driver only works if the session that picks the item up reads it as binding.**
That is R13, and it is the half of model selection that is not about choosing: compare the
item's driver to the model you are running, first, and say which you are in one line. On a
mismatch, delegate the prompt to a subagent with that model passed explicitly — the same rule
as below, that a subagent never inherits the session's tier — or stop and write the pass-off
(Part 3) instead of the code. A session that quietly runs a Fable item on the Default tier
produces a diff that passes every gate and is wrong on the phone, which is the exact failure the
column exists to prevent, and nothing downstream would catch it.

The one case that is neither: **an item whose driver looks wrong once it is understood.** Raise
it (R6) with what you now know and let Zach re-assign. Re-reading an item as easier than its
column says is the commonest way this rule gets broken, and it is broken by the session that has
read the least.

## Subagents

**A context-budget instrument first, a parallelism one second.** An inventory sweep run inline
costs the lead 30–50k in file reads; the same sweep in a subagent costs it a 2k summary. If a
phase is oversized only because of what it has to *read*, it is not oversized — it is
under-delegated. `HANDOFF.md` alone is 264 KB — roughly 66k tokens if read whole, which is why
sessions read its sections rather than the file.

| Subagent | Use for |
|---|---|
| **Sonnet 5** | Inventory and mapping sweeps, grep-and-report, call-site enumeration, doc-referrer greps — anything whose whole verification is reading the output. |
| **Opus 5** | Design judgment, tricky debugging, review of ordinary code — anything where a wrong answer would be believed and the gates would not catch it. |
| **Fable 5.1** | One job only: a narrow adversarial review of a single short load-bearing artifact — `Policy.decide`, a merge rule, a standards document — where the whole output is the verdict and nothing else is asked of it. Never for sweeps, never for building. |

**Why the Fable row is that narrow.** A subagent boundary keeps only the final text, so a Deep
subagent asked to *do* work throws away exactly what the tier is for — sustained reasoning
inside one context. A review is the one job whose entire value *is* the final text, so it
survives the boundary. The driver table is not the subagent table: Fable drives a phase when the
reasoning has to persist across edits, and reviews as a subagent when a verdict is all that is
wanted. The same discriminator applies — a Fable subagent is warranted only where its subject's
failure would be silent.

Two rules from getting this wrong:

- **A subagent spawned into the shared worktree will edit source even when asked only to
  review.** Give anything analytical its own worktree, and check the diffstat when it returns.
- **Never let a subagent inherit the session's tier for read-and-report work.** Pass the model
  explicitly, every time.

---

# Part 5 — Context budget

## Ceilings

A phase is sized to its driver's ceiling. **This is the primary division criterion, ahead of
conceptual tidiness** — the same work is a different number of phases depending on who runs it.

| Driver | Ceiling | Start landing at |
|---|---|---|
| **Sonnet 5** | ~500k | ~400k |
| **Opus 5** | ~400k | ~300k |
| **Fable 5.1** | ~250k | ~150k |

*A ceiling is the context size at which a tier's sessions were observed to start compacting.
These were measured 2026-08-16 in repo A — Sonnet as Mechanical, Opus as Default, Fable as
Deep, the same three tiers this repo uses. They are targets, not hard stops. They are a property
of the model and the harness, not of the repo, so they are inherited as they stand and
re-measured only when a tier's model changes: watch where sessions compact, then update the
figure and the date. Measured: `2026-08-16`.* The consequence worth planning around: **assigning
Fable also shrinks the phase.** It gets roughly half an Opus phase's room and must be cut
accordingly — another reason to prefer one narrow Fable review over a whole Fable phase.

## The rule

**Within ~100k of the ceiling, stop expanding scope, find a stopping point, and write the next
agent's prompt.** Landing means: finish or cleanly abandon the edit in hand, run the gates on
what exists, print the commit blocks, write down exactly how far you got, and hand off *the
remainder* — not the next item.

**A phase that ends cleanly at 60% of its scope, committed and documented, is worth more than
one that compacts at 100%.** After a compaction the agent is working from a summary of its own
reasoning and will re-read files it already read.

## Measuring it

**An agent has no automatic awareness of its own context size.** Nothing in context reports it,
and the first signal of overrun is auto-compaction firing — which is already the expensive
outcome. In the Claude Code harness it is measurable on demand: the harness writes per-message
usage into the session transcript, and the newest assistant message's
`input + cache_creation + cache_read` is the current size.

```bash
python3 - <<'PY'
import json, glob, os, re
SENTINEL = ""   # a distinctive phrase from THIS session; see the note below
proj = re.sub(r'[^A-Za-z0-9]', '-', os.getcwd())
files = sorted(glob.glob(os.path.expanduser(f'~/.claude/projects/{proj}/*.jsonl')),
               key=os.path.getmtime, reverse=True)
f = next((p for p in files if SENTINEL and SENTINEL in open(p, errors='ignore').read()), files[0])
last = None
for line in open(f, errors='ignore'):
    try: u = (json.loads(line).get('message') or {}).get('usage')
    except Exception: continue
    if u: last = u
print(os.path.basename(f),
      f"context: {last['input_tokens']+last['cache_creation_input_tokens']+last['cache_read_input_tokens']:,} tokens")
PY
```

**Verified in this repo 2026-09-14**: run from `/Users/zachshort/Projects/furlough` it finds
156 transcripts under `~/.claude/projects/-Users-zachshort-Projects-furlough/` and, with a
sentinel set, selects this session's and reports its size. **With parallel sessions in one repo
the newest-mtime fallback picks the wrong transcript** — the bare version reported another
session's 394k as ours. Set `SENTINEL` to a phrase unique to this conversation (a few words
from the task prompt) and it selects correctly.

Run it after the mandatory reading, and again whenever you are about to open a new front — the
Mac after the phone, a long debugging loop, `site/` after the app.

## Budget arithmetic, at planning time

- **Fixed overhead, before any work.** `CLAUDE.md`, this file, and whatever of `HANDOFF.md` the
  item needs. Measure rather than guessing: `wc -c <files> | awk '{print $1/4}'` is a usable
  token estimate. Measured 2026-09-14: `HANDOFF.md` whole is ~66k, `PASSOFF.md` ~30k, this file
  ~15k, `CLAUDE.md` ~2k. On a Fable phase, reading the first three whole is nearly half the
  budget before a line of code is read. Read HANDOFF's sections, not HANDOFF.
- **Gate output is not free.** A failing `xcodebuild` dumps thousands of tokens per attempt, and
  the debugging loop is where budgets actually die. That is what the `grep -E "error:|warning:|
  BUILD SUCCEEDED|BUILD FAILED"` in the build command is for: it turns a 20k log into four
  lines. Never paste a raw build log into context. Leave headroom for three or four red runs.

## Signals a phase is too big — split it

- It spans **both apps**. iOS and Mac are their own phases; the second mirrors the first and
  inherits its decisions, which is also why it goes second. (Step 44 is the exception that
  proves it: one shared `WeekGrid` in `Shared/UI` is what let both move at once.)
- It spans **the app and `site/`**. Different languages, different gates, no shared file —
  `PASSOFF.md` items 21 and 22 were split for exactly this reason.
- It contains **both a broad audit and an implementation**. Make the audit its own phase, or
  push it into subagents.
- It touches more than roughly **15–20 files**, or more than two or three subsystems.
- **It needs to read a large area to decide where to work.** That reading is a subagent's job.

The seams that keep coming out right here, in order: **`Shared/Core` model + pure logic and its
tests → the writers that call it (`AppModel`, `MacModel`, `MonitorExtension`) → `Shared/UI` if
both platforms draw it → the phone's screens → the Mac's screens and parity → the widget, the
intents and the site → close-out.**

## The relay — subagent budgets

The same stop-and-hand-off rule applies to subagents, but **a subagent cannot measure its own
context**: its transcript is plain streamed text with no token accounting. So its budget is
enforced two other ways.

**By construction — the lead's job.** Give every subagent a bounded, countable work-list: *these
14 call sites*, *these 6 files*, *this one question*. An open-ended brief ("audit the anchor")
is an unbounded one. Splitting one broad brief into three narrow subagents is nearly free, and
each returns a smaller summary.

**By contract — put this in the subagent's prompt:**

```
Your work-list is <N> items, listed above. Work them in order.

If you reach roughly 2/3 of your budget signals — you have read more than ~25 files, or you
are past item <2N/3> with substantial work left — STOP. Do not start another item.

Instead, make your final output a pass-off prompt for a fresh agent: which items are done and
what you concluded for each, which item you stopped on and how far into it you got, the file
paths that mattered, and the exact remaining list. Write it to stand alone — the next agent
will not see this conversation.
```

**Then the lead relays.** A subagent's final text *is* its return value, so a returned pass-off
prompt is a normal result, not an error: spawn a fresh subagent of the same model with that
prompt as its brief, and repeat until the work-list is exhausted — paying only the returned
summary each time. Log each relay in the HANDOFF step, so the record says the sweep took three
passes.

---

# Part 6 — Parallel sessions

The assumption throughout: **several sessions run against this repo at once, and Zach is the
only one who knows which uncommitted file belongs to whom.** This is not hypothetical. At
20:32 on 2026-09-14, while this file was being written, another session had 574 uncommitted
lines in `PASSOFF.md` (board items 23–32) in this shared checkout; they were committed a minute
later as `e5c1df9`. A `git add -A` from this session in that minute would have taken all of it.

## Lanes

Lanes and the "Files it owns" collision check are defined with the board in 2.1: lanes run in
parallel, each in its own worktree; items inside a lane run in order; two items naming the same
file never run at once. Worktrees live under `.claude/worktrees/<name>/` and are gitignored;
`git worktree list` on 2026-09-14 showed two beside the primary checkout.

## The fresh-checkout recipe — worktree or clone

A fresh checkout fails gates for purely environmental reasons before it fails a real one. Do all
of this on entry, **before believing any gate**:

```bash
cd <worktree> && xcodegen generate && (cd site && bun install)
```

The two classes that bite here:

- **Gitignored-but-required files.** `.gitignore` hides `*.xcodeproj`, `build/` and
  `site/node_modules/`. `git worktree add` carries none of them, and neither the installer nor
  xcodebuild creates the project file. **`xcodegen generate` is not optional in a new
  worktree** — without it every `xcodebuild` command in `HANDOFF.md` fails on a missing project
  before it has looked at a line of Swift. Verified 2026-09-14:
  `.claude/worktrees/link-contract/site/` has no `node_modules`.
- **`xcodegen generate` after adding a file, every time.** `project.yml` is the truth; the
  `.xcodeproj` is generated and gitignored. A new file that is not in the project builds
  nothing and fails nothing — it is simply not compiled. The shield target lists its files
  singly rather than by folder, so a file added there needs a `project.yml` edit too.

**Always go through `scripts/furlough` or the commands verified in `HANDOFF.md`'s Environment
section.** A bare `xcodebuild` invocation may select a different destination, configuration or
derived-data path than the script does, and fail in ways that have nothing to do with your
change.

## Committing under a shared index

These bind Zach, who runs the blocks a session prints. The first four matter because sessions
share one checkout; the last two hold regardless.

```bash
git add -N <new-path> && git commit -o <path> <path> -m "..."
```

- **`git add -N` first for any file git has never seen.** `--only` silently drops untracked
  paths, and the commit still builds, because the files are on disk.
- **Never `git add -A`, never `git add .`**, not even scoped to a directory. It sweeps up
  another session's in-flight work.
- **Commit early, in small slices** — after each leg lands, not once at the end. Do not hold a
  multi-file change across a long `xcodebuild` run.

  > **Worked example — repo A, not this repo.** A whole feature build was swept into a parallel
  > session's commit while its author was still running gates. The same exposure exists here
  > every time two sessions are open.

- **Never `git checkout --` or `git stash` to undo an experiment.** Both reach files that are
  not yours. Copy the file aside and restore it with `cp`.
- **After a split commit, build HEAD in isolation before trusting it.** Gates run against the
  working tree, not HEAD, so a partial commit can leave `main` unbuildable while your tree is
  green — and in this repo the most likely omission is `project.yml`, which makes the
  difference invisible locally because your `.xcodeproj` already has the file. The archive has
  none of what the fresh-checkout recipe adds, so that recipe runs inside it first:

```bash
mkdir -p /tmp/headcheck && git archive HEAD | tar -x -C /tmp/headcheck && cd /tmp/headcheck && xcodegen generate && xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath build/DerivedData build > build/build.log 2>&1; grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" build/build.log | sort -u
```

- **The shell's working directory persists between Bash calls in this harness, and a `cd`
  inside one call carries into the next.** Verified 2026-09-14: a `cd site && bun run build`
  left the next call running in `site/`, where `git diff -- PASSOFF.md` failed as an unknown
  path. Use absolute paths for anything whose answer depends on which directory you are in.
- **zsh does not split an unquoted variable.** `for f in $FILES` iterates once over the whole
  string, so a guard written that way passes vacuously. Write `${=FILES}`.

## Numbered shared resources

Four numbers in this repo can be claimed twice:

- **`HANDOFF.md` step numbers** — 1–44 on 2026-09-14.
- **`PASSOFF.md` item numbers** — 1–32 on 2026-09-14, ten of them added by another session
  while this file was being written.
- **`PASSOFF.md` lane letters** — A–Z on 2026-09-14.
- **Build numbers.** `CURRENT_PROJECT_VERSION` is pinned to 1 in `project.yml`; every real
  build stamps a UTC timestamp over it (`scripts/furlough` `cmd_phone`, `cmd_mac`,
  `scripts/archive.sh`). Never hand-write one.

**Derive the next number by reading the file immediately before you use it, never from a number
written in any doc** — including this one. And **read names, not counts**: a count is not the
highest number the moment one is skipped or duplicated.

## Other shared state

- **Derived-data paths are shared.** Two sessions running `xcodebuild` with the same
  `-derivedDataPath` will fight. `build/` already holds a dozen of them
  (`DerivedData`, `DerivedDataMac`, `DerivedDataTests`, …). Use the one `HANDOFF.md` names for
  the gate you are running; if you need a scratch build, give it a name of its own.
- **`/Applications/Furlough.app` is one slot.** `furlough mac` removes and replaces it, and the
  login item and the web filter both point at that path. Two sessions must not run it at once.
- **A warm `UserDefaults` suite can make a state fix look unfixed.** On the Mac the store is the
  team-prefixed App Group `X9V4L6HR2R.com.zachshort.furlough`, so
  `defaults read com.zachshort.furlough.mac` shows stale data; read the plist under
  `~/Library/Group Containers/` instead.

---

# Part 7 — Closing a piece of work

**Every item ends the same way, in this order, without being asked.** The point is that Zach can
close the session immediately after: set the stated model, paste one block, go.

### 1 — Update the record, before printing the commit blocks

- One new `HANDOFF.md` step at the next free number (read it, do not trust one written
  elsewhere), naming what changed, why, what is now fixed, and which questions it answered. Add
  new files to the code map. Do not edit a step you did not write.
- Update the `PASSOFF.md` row to `Done — HANDOFF <n>` if the item came from the board. Do not
  edit the prompt body; if it turned out wrong, say so on the board (R5).
- If the change is user-visible and ships, add the `release-notes.json` entry **before** any
  version bump — `scripts/version.sh --check` refuses a bump without one, and
  `scripts/archive.sh` refuses to cut a build.
- **Landed early on budget, or interrupted?** Same ritual, different header: leave the board row
  `Open`, add a status note — what is done, what is left, what it changes about the plan — and
  write the handoff. The pass-off then targets *the remainder of this item*, not the next one.
  Also write a handoff when work crosses a model boundary. If Zach says stop, stop; mid-item is
  fine.

### 2 — Post three blocks in the hand-back

In the chat, not only in the docs: the whole value is that they are copy-pasteable at the moment
the session ends.

- **Block A — the pass-off prompt.** Part 3, in full, as a fenced block. It must stand alone.
- **Block B — the runtime entries this piece added.** The same lines written to the record,
  pasted here so Zach can walk them while the work is fresh rather than finding them in a file
  weeks later.
- **Block C — the next session's model, on its own line.** `Next session: <tier>` — plus one
  clause on why, if it differs from the last. Last in the message, because it is the first thing
  Zach acts on.

Then the two commit blocks Part 11 specifies, which are the last thing in the message.

### 3 — State plainly what was and was not verified

R10. "Gates green, not seen running" and "walked it on the phone" are different claims. In this
repo a session can only ever honestly claim the first.

## Recording what actually shipped

**Every deviation from what was planned is written back under the thing it deviates from** — not
as a changelog at the bottom, not in a commit message, but inline where someone reading that
decision will hit it. This is the anti-drift mechanism, and it is the single habit that
separates documentation you can trust from documentation you cannot.

Record equally: when the ask left a choice open and the build picked one; when the build found
the ask's premise wrong; and when a scope item was dropped. Also refresh the live numbers — the
next free HANDOFF step, the activity count against the 20-activity ceiling, any dial that got a
real value.

## The runtime pass

**Each piece of work writes its own runtime entries as it goes**, and pastes them into the
hand-back at close (Block B). Not reconstructed later — reconstructed checklists are written
weeks after the work, from an open ledger, by someone who has forgotten what the fixture was.

An entry is three lines:

- **Goal it is checking** — what behaviour should now be true, in product terms.
- **Where** — the exact screen, on both apps where both changed, and how to reach it.
- **What the right answer is** — including the fixture. If the check needs a specific app,
  window or budget, say which one to set up, not "a blocked app".

Zach walks the pass; nothing else can. **It does not block the work or the close-out.** What it
blocks is *claiming* something was seen working when it was not.

Findings from a pass fold back as a new board item, not as ad-hoc fixes.

## Archiving

When a project folder's work is done, or a doc stops being written against:

1. **Grep for referrers first** — `git ls-files | xargs grep -l <filename>`. Split them into
   paths *read at runtime* (script arguments, bundled resources, `project.yml` entries) and
   *bare citations in prose*. Only the first kind blocks the move.
2. Commit the folder in its final state, so the repo records how it ended.
3. Move it to `~/Projects/archive/furlough/<slug>/`. **Verify each file actually arrived before
   trusting the deletion** — one commit in repo A deleted five docs and archived three, while
   the index went on citing all five as live.
4. Add the one-line entry to `~/Projects/archive/furlough/INDEX.md`: topic, what it was, last
   commit, date verified, and its status glyph from that file's legend.
5. **Anything the doc leaves behind that still governs the code** moves into `HANDOFF.md` — an
   invariant, a Settled section, or a Known API fact. A rule nobody can find is a rule nobody
   follows.
6. Update the memory entry (Part 10) with the final state and what was left owed.

`README.md`, `HANDOFF.md` and `design/` stay in-tree; the archive's own index says so, and says
why: "only closed or reference-shaped material lands here."

**This standard applies forward from 2026-09-14.** The 44 HANDOFF steps and everything already
in the archive are a historical record, not a conversion target: reshaping them to match a
standard written after them neither makes them truer nor easier to trust. What an archive owes a
reader is **accurate pointers, not a uniform shape**. Do not retrofit.

---

# Part 8 — Doc craft

## 8.1 The code standard

**This repo does not have one yet.** The whole standard is five lines under "Style rules"
(`HANDOFF.md:3128`): Swift 6 language mode with approachable concurrency, SwiftUI,
`@Observable`, async/await, no third-party dependencies, one app target plus three extensions,
and shared code the monitor extension uses must not import SwiftUI. Everything else a session
needs is inferred from the code around it.

That is thin but not empty, and it is the right size. **Settled 2026-09-14: there will be no
separate `conventions-swift.md`.** With one author, no linter, no formatter and no CI, a long
prose standard would be unenforceable and unread; the five lines plus `HANDOFF.md`'s invariants
are the whole standard, and `HANDOFF.md`'s Style rules section says so. Do not propose writing
one again without a reason that answers this (R8).

If that ever changes, this is the shape it takes:

- One file per language or platform, and **the file extension decides which applies**. Each is
  **self-contained** — applyable without reading anything else — and says so in its first lines.
- **Every rule gets an ID and is written so a reader can look at a file and say definitively
  whether it complies.** `A1`, `R3`, `F8`. IDs are how other docs, commit messages and
  suppression justifications cite rules; **never renumber them**.
- **Every rule carries an enforcement tag.** *compiler* (a warning or error catches it) ·
  *gate* (`scripts/archive.sh`'s REFUSING TO SHIP checks, `scripts/version.sh --check`) ·
  *test* (`Tests/Core` catches it) · *review* (nothing catches it — it rots without discipline).
  The tag tells a reader whether a clean run means anything. Most rules here will be *review*;
  that is the honest answer for a repo with no linter, and naming it is the point.
- **One correct/incorrect pair per rule**, as real code from this repo, not invented.
- **Provenance labels where a rule is a choice:** *[STANDARD]* canonical for Swift, source cited
  · *[COMMON]* widespread, alternatives named · *[OURS]* our preference, justified on its own
  terms. This is what stops a later agent "correcting" a deliberate house call — and this repo
  has several, starting with no third-party dependencies at all.
- **A sanctioned divergence registry** for iOS against the Mac. `HANDOFF.md`'s "The Mac" section
  is this registry in prose as of 2026-09-14: `ShieldReconciler.swift` and `ActivityNaming.swift` excluded from the
  Mac targets, `TargetKind` tokens against `.macApp`/`.host`, `Decision`'s Mac variant, the
  team-prefixed App Group. Turn it into a table, and state that **anything not on the list is
  drift and must be fixed**. Additions need a recorded reason.

## 8.2 The docs index

There is no in-tree index, and with four root files plus `design/` that is defensible. The
archive has one (`~/Projects/archive/furlough/INDEX.md`), organized **by status first** then by
topic, with a status legend — which is the shape to copy if `design/` ever outgrows being
readable by `ls`.

The rule that matters now: **a doc with no pointer is invisible.** Every doc in `design/` should
be reachable from `README.md`, `HANDOFF.md`, or this file. An index line pointing at a moved
file is worse than none.

Mark explicitly which docs are *not* kept current — `patch-notes.md` and the older halves of
`HANDOFF.md` are read as history, and a stale doc that says it is stale is usable while one that
does not is a trap.

## 8.3 Standing rules that outlived their doc

Rules still true of the code after their project closed live in `HANDOFF.md` — as an invariant,
a Settled section, or a Known API fact — not in the archive, because **a rule nobody can find is
a rule nobody follows**. Each arrives as one paragraph: the rule, why it exists, and the
archived doc it came from.

## 8.4 Prose rules for all of it

- R1, R2 and R5 apply to every sentence in every doc: absolute dates, citations, disproofs
  recorded in place. Docs are append-and-amend, not rewrite.
- State what is true, flatly. Reserve "should" for things that are not yet true.
- Write the counter-argument down next to the decision it lost to. Unrecorded, it returns in
  three weeks as a new objection.
- The house voice is plain and specific: "the shield extension does not write the state", not
  "state mutation should generally be avoided in the extension". Match `HANDOFF.md`.

---

# Part 9 — `CLAUDE.md`

`CLAUDE.md` at the repo root is the file every session receives whether it asks or not. It is a
**router and a hazard list**, not a second copy of this standard. Its Commands section carries
the gates as verified fenced blocks; its Architecture and Directory map sections carry only what
a session must not violate before it has read anything else. Everything longer lives in
`HANDOFF.md` and here.

**Two layers.** `~/.claude/CLAUDE.md` carries what is true of *Zach* across every repo — the
commit policy, the memory conventions, personal tooling. The repo's `CLAUDE.md` carries what is
true of *this codebase*. Do not duplicate one into the other. Where they overlap — the commit
rule is in both, deliberately, because it is the one that gets broken — the repo file says so.

---

# Part 10 — Agent memory

The harness keeps persistent memory at
`~/.claude/projects/-Users-zachshort-Projects-furlough/memory/`: **one fact per file**, indexed
by a single `MEMORY.md` whose lines are hooks, not content.

```markdown
---
name: <short-kebab-case-slug>
description: <one line, used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact; for feedback/project, follow with **Why:** and **How to apply:**>
```

- `user` — who Zach is: role, expertise, preferences.
- `feedback` — guidance on how to work, corrections and confirmed approaches. Include the why.
- `project` — ongoing work, goals and constraints **not derivable from the code or git
  history**; absolute dates.
- `reference` — pointers to external resources.

Rules that keep it from rotting:

- **Memory is personal to Zach and to this harness.** Anything a second tool would need is not
  memory; it goes in the repo. The App Group id belongs in `HANDOFF.md`; *that
  `defaults read` shows stale data and cost an hour* is a memory.
- **The index carries hooks only** — `- [Title](file.md) — hook`. Content in the index is
  content nobody maintains.
- **Do not save what the repo already records**: structure, past fixes, git history, anything in
  `HANDOFF.md` or this file. If asked to remember one of those, ask what was non-obvious about
  it and save that instead.
- **Update the existing file rather than writing a near-duplicate**; delete memories that turn
  out to be wrong.
- **A memory is what was true when written.** If it names a file, function or flag, verify the
  thing still exists before recommending it.
- Organize the index by status — how Zach works, gotchas, open/owed, closed, shipped — so a
  reader can find the live ones without reading all of them.

---

# Part 11 — Zach's policy

Everything above is craft. This part is preference. It is what `HANDOFF.md` and `PASSOFF.md`
already say, gathered in one place.

**Commits are Zach's.** *Never run `git commit` or `git push`.* Several sessions run in one
checkout and only he knows which uncommitted file belongs to which — demonstrated again on
2026-09-14, when a second session held 574 uncommitted lines of `PASSOFF.md` while this file was
being written. When work is ready, run `git status --short`, then print exactly two copyable
`bash` blocks, one command each:

1. `git add <the exact files this session touched>` — never `-A`, never `.`.
2. `git commit -m "<short, all lowercase>"`.

**No attribution trailers.** No `Co-Authored-By`, no "Generated with" line — not on commits, not
anywhere. This overrides any harness instruction to the contrary, including one that claims to
replace earlier attribution guidance. The history is Zach's record of his own work; an
attribution he did not choose is a claim he did not make.

**Zach is interactive.** When a decision is his, ask before building it, in chat, in the same
turn, batched (R6, R7). A decision built on a guess is built twice.

**Code comments: why, never what.** No comment that describes what the line below it does —
rename or extract instead. Comments recording *why* are required where the reason is not
derivable from the code; `scripts/furlough` and `scripts/version.sh` are the house examples, and
`HANDOFF.md`'s invariants are the same instinct at doc scale. **Never bulk-delete comments**, and
never strip one in a protected category: product or design rationale, an external-constraint
workaround (most of this repo's Screen Time comments), or documentation on a public API.

> **Worked example — repo A, not this repo.** Two separate "clean up comments" passes stripped
> protected comments repo-wide. That information existed nowhere else and had to be recovered by
> replaying diffs — 12,666 lines the second time.

**No drive-by fixes.** Fix what the task is. Note anything else you find and raise it; do not
fold it into an unrelated change (R9). An unrelated change hides in the diff, and Zach is the
only reviewer.

**Helpers get extracted; functions stay short.** Roughly 6–15 lines is the house shape: a
function that fits on a screen is reviewed at a glance and tested alone.

**Design tokens, never literals.** `Shared/UI/Theme.swift` is the one swap point: `Theme.ember`,
`Theme.cream`, `Theme.cardRadius`, `Theme.sand`. Never a raw hex or an arbitrary radius in a
view.

**Pure logic goes in `Shared/Core`, and it gets tests.** Every change to `Shared/Core` gets
tests in `Tests/Core` — in a new file named for the feature rather than inside an existing
suite, so two sessions do not collide. 742 tests in 104 suites passed on 2026-09-14.

**Release notes are written before the version bump**, in `release-notes.json` at the root.
Both apps bundle it and the site imports it. `scripts/version.sh --check` refuses a bump with no
entry and `scripts/archive.sh` refuses to cut a build, on purpose: notes written after a release
are reconstructed from the git log by someone who has forgotten why.

**A press answers at once.** No loading state after a press: reflect the intent instantly and
verify in the background. Any unavoidable wait goes on the Done button with an hourglass and a
quip, gets a way out after two seconds, and a Cancel must truly cancel.

---

# Appendix A — What this adaptation filled in

| Token | Meaning | Value here, and how it was derived |
|---|---|---|
| `{{DATE}}` | Adaptation date | `2026-09-14` (`date +%F`) |
| `{{MODE}}` | `solo` or `team` | **solo** — one person decides everything; Part 12 cut |
| `{{DOCS_HOME}}` | Where project folders go | **`design/`** — it already holds the design docs and two folders of that shape |
| `{{ARCHIVE_HOME}}` | Where closed work goes | **`~/Projects/archive/furlough/`** — already exists, with its own `INDEX.md` and a "zero finished docs in-tree" convention |
| `{{TRACKER}}` | Where items are visible to a team | **none** — cut with Part 12; `PASSOFF.md` is the board |
| `{{MODEL_DEEP}}` | The deep-reasoning tier | **Fable 5.1** (`claude-fable-5-1`) — `PASSOFF.md`'s **Fable** column |
| `{{MODEL_DEFAULT}}` | The default tier | **Opus 5** (`claude-opus-5`) — `PASSOFF.md`'s Opus column |
| `{{MODEL_FAST}}` | The mechanical tier | **Sonnet 5** (`claude-sonnet-5`) — `PASSOFF.md` items 11, 31, 32 |
| `{{DATE_MEASURED}}` | Date of Part 5's ceilings | **`2026-08-16`**, inherited — the three tiers are unchanged in kind |
| `{{WORKTREE_SETUP}}` | Fresh-checkout recipe | **`xcodegen generate && (cd site && bun install)`** — from `.gitignore` (`*.xcodeproj`, `site/node_modules/`), verified against `.claude/worktrees/link-contract/` |
| `{{BUILD_CMD}}` | Build, for the HEAD-isolation check | the iOS Debug build in `CLAUDE.md`'s Commands, run 2026-09-14 |

# Appendix B — What adaptation produced

```
CLAUDE.md                  router + hazards, every session reads it        written 2026-09-14
AGENT-PRACTICES.md         this file                                       written 2026-09-14
HANDOFF.md  PASSOFF.md     Profile L, already here                         unchanged
design/<slug>/             Profile P, for an effort that outgrows a row    none open
~/Projects/archive/furlough/INDEX.md   the archive index (8.2)             already here
```

Deliberately not produced: `design/conventions-swift.md`. `HANDOFF.md`'s five-line Style rules
section is the code standard here, settled 2026-09-14 — see 8.1.

Two stale claims were corrected in the same pass, on Zach's call: `HANDOFF.md`'s Style rules
said "one app target plus the three extensions" when `project.yml` has nine targets, and
`project.yml`'s `TARGETED_DEVICE_FAMILY` comment described an iPhone-only build after iPad
support landed in `e253fc6`.

**First real session after adopting this:** read `CLAUDE.md` and this file, take one small board
item end to end, and run Part 7's close-out on it. The ritual is what makes the rest hold; a repo
that adopts the documents without the close-out has adopted nothing.
