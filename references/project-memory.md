# The project's CLAUDE.md is a deliverable

A theme built this way accumulates knowledge that is nowhere in the code: which command runs where,
which script still has to be run on production, why a rule that looks arbitrary exists. Write it down
in the repository's `CLAUDE.md` as you go — it is part of the handover, not a by-product of it.

## What goes in

- **Commands nobody can guess.** The build, the test entry point, the translation pipeline, and
  *where* each runs (host vs container). Include the flag that must never be dropped and why.
- **Environment constraints.** "`wp` only exists inside the container", "the formatter must not touch
  these paths", "these files are gitignored and exist only locally".
- **Traps, written symptom-first.** Start from what you would actually observe — *"the sidebar fields
  don't save and there is no error"* — then the cause, then the fix. That is the order in which
  someone meets the problem, and therefore the order in which they will search for it.
- **Scripts that must be run per environment**, with their state per environment. "Run on local and
  staging; not yet on production" is the single most valuable line in the file, and the one that rots
  fastest.
- **Decisions with a cost if reversed.** Why the content model has no ACF, why schema is emitted
  unconditionally, why a coupling was accepted. Not the decision alone — the consequence of undoing it.
- **The working agreements**, verbatim: commits and pushes only on explicit request; production
  deploys only on explicit request, always via `bin/deploy`; the deploy config in `~/.config/<slug>/` is the user's — ask, never read.
  They are in `.claude/settings.json` too, but a rule written in prose is the one a new session reads.
- **The boundary rules** of the project: what lives in the theme, what lives in the mu-plugin, what
  never gets invented without asking.

## What stays out

Anything the code already tells you: the directory tree, the list of components, the history of fixes,
what a function does. If a line of `CLAUDE.md` could be replaced by reading one file, delete it — every
line is loaded into every session, so the file competes with itself for attention.

Also out: notes that matter only to the conversation that produced them.

## Form

- One entry per trap, two to five lines. Symptom, mechanism, rule. If the mechanism is subtle, say
  what makes it invisible — *"the paragraph still looks right, which is why nobody notices"* is the
  sentence that makes the entry useful a year later.
- Mark the load-bearing ones. A visual marker (⚠️) on the entries that cost real time lets a reader
  skim to the expensive parts.
- Prefer "must / never" over "should" for the rules that have already been broken once.
- Absolute dates, never relative ones.

## Maintenance rule

**If a change alters how the project is worked on, update `CLAUDE.md` in the same commit**: a new
command, a new constraint, a trap discovered. Not the implementation detail — the working rule that
follows from it.

Two corollaries worth stating explicitly in the file itself:

- A fixed bug without a test comes back; a fixed bug without a written rule comes back as a *different*
  bug in the same place.
- When a trap turns out to be wrong or obsolete, delete the entry. A stale warning costs more than a
  missing one, because it will be believed.
