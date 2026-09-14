# Updating the patch notes

A runbook for an agent asked to "update the patch notes," "check release-notes.json," or
similar, with no further detail. Read this file, then follow it — do not re-derive the process
from scratch each time. The version-number rules it leans on (`patch` vs `minor` vs `major`,
"one version, one batch") live in the **Versioning** section of `README.md`; this file is about
the step before that: deciding what happened and writing it down in the house voice.

## 1. Find where the notes last left off

```bash
git log -1 --format=%H -- release-notes.json
git log --oneline <that-hash>..HEAD
```

Everything in that range is a candidate. Do not assume the top entry in `release-notes.json` is
current — check its `channel`:

- `"unreleased"` — nothing has shipped yet under that version. New changes join *this* entry's
  `changes` array. This is the common case between one `furlough beta` and the next.
- `"testflight"` or `"appstore"` — that batch is already cut. New changes need a fresh entry
  above it, not edits to the old one (see §4).

## 2. Read every commit's diff, not just its message

`git show --stat` first for shape, then the actual diff for anything not obviously out of scope.
A commit titled `comments` can be a no-op for release notes; one titled after a design asset can
still touch a `Shared/` file that changes behavior. Check, don't assume from the title.

**Skip** (never patch-note-worthy):
- Comment-only or doc-comment diffs with no code change
- `design/**` (store listings, screenshot boards, marketing copy)
- `README.md`, `HANDOFF.md`, `PASSOFF.md` and other repo-process docs
- Test-only changes (`Tests/**`)
- Build/release tooling (`scripts/**`, CI, entitlements, project.yml plumbing) unless it changes
  something a user can see or do
- Pure refactors — same behavior, different code shape

**Include** (a candidate line item):
- A new screen, setting, or way in (widget, Control Center, intent, Focus filter)
- Any UI/UX change a user would notice, however small — this project's notes already cover
  things like "a busy button keeps its height" and "the hourglass glow falls past its page"
- A fix: a crash, a wrong label, a spinner that never resolves, a slow screen, behavior that
  didn't match what was intended
- Anything that changes what `Policy.decide` shields — always worth a line, per README, even if
  it's also a fix

When in doubt, read `Shared/Core/` and platform-target diffs (`Furlough/`, `FurloughMac/`) closely;
that's almost always where the user-visible truth is, regardless of what the commit title says.

## 3. Classify each candidate

For every line item, decide:

- **`kind`**: `"new"` (something new to find), `"better"` (existing behavior polished),
  `"fixed"` (something that was wrong now works)
- **`platform`**: `"iphone"` (`Furlough/`), `"mac"` (`FurloughMac*`), or `"both"` (shared
  behavior in `Shared/` that surfaces on both, or a coordinated change like the cross-device
  Anchor link)

## 4. Decide which version entry it belongs to

- Top entry is `"unreleased"`: append to its `changes` array. Don't invent a version bump or
  touch `project.yml` — that only happens at `scripts/version.sh` time, which is a release-cut
  step for a human to run, not something to do while drafting notes.
- Top entry is already shipped: open a new entry above it with `"channel": "unreleased"`, no
  `version` decided yet if you're unsure — flag the PATCH/MINOR/MAJOR call to the user using the
  README table rather than guessing, since it's a project-wide contract (`Version` comparisons,
  `scripts/version.sh --check`, the What's New screen) and wrong is worse than undecided.
- If new items you're adding to an *existing* unreleased entry would upgrade its classification
  (e.g. it was tracking as a `patch` and you're adding a `new`-kind item, which forces `minor`),
  say so — don't silently rewrite the version string yourself.

## 5. Write it in the house voice

Read a few existing entries in `release-notes.json` before writing new ones — the voice matters
more than the schema here. Patterns to keep:

- Plain sentences, second person, no marketing language ("simply," "seamlessly," "powerful")
- Lead with the fact, then the *why* when it's non-obvious — what broke, what someone would have
  seen, what changed about it. Example: *"A Screen Time query that never answers no longer
  leaves the button turning."*
- Titles are short and describe the change itself, not the fix as a category — `"Apply happens
  when you press it"`, not `"Fixed a bug in the Apply flow"`
- `headline` is one sentence, present tense, naming the batch's biggest change
- `lead` is 2–4 sentences tying the batch together thematically — it doesn't need to enumerate
  every item, just orient the reader. If part of the batch already shipped inside an earlier
  version's builds (as happened between 1.1 and 1.2), say so plainly, the way the 1.2.0 entry
  does.

## 6. Validate before handing off

```bash
python3 -m json.tool release-notes.json > /dev/null && echo ok
./scripts/version.sh
```

The second command is read-only when run with no arguments — it reports whether the notes cover
`MARKETING_VERSION`, it doesn't change anything. Confirm it still says "The notes cover this
version" (or, if you opened a new unreleased entry ahead of the current build, that this is
expected and intentional).

## 7. Stop there

This file only covers drafting and editing `release-notes.json`. Don't run
`scripts/version.sh minor|major|patch` (that stamps `project.yml`) and don't commit — both are
separate, human-triggered steps. Summarize what you added and let the normal commit flow (see
`CLAUDE.md`) take it from there.
