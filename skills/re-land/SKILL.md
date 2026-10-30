---
name: re-land
description: Finish a reverse-engineering slice by documenting evidence, updating labels and the checklist, then committing only your own files, merging completed work into local main, and pushing. Never leave completed, merge-ready work uncommitted or waiting to merge.
---

# Document, label, commit and merge

Undocumented findings are re-derived by the next session, at full cost. Landing is part of the
work.

## 1. Document

- **Where:** extend the topic document if one exists (`grep -rln ADDRESS docs/`); otherwise
  create `docs/<TOPIC>.md` and link it from `docs/FINDINGS.md`.
- **Style:**
  - an opening paragraph: what it covers, which binary and version, which kinds of evidence
    (static reading of Ghidra pseudocode, disassembly, emulation, decoded files, observation of
    the running game) and what was not checked;
  - prose and tables keyed by function address and field offset;
  - every claim *observed*, *measured* (with the script and inputs), *inferred* (with what would
    confirm it), or under **Open questions**;
  - no copied pseudocode, disassembly or data dumps: describe them.
  - plain English with no rhetorical patterns (colon reveals, "X, not Y" endings, matched
    pairs, two clauses of the same shape joined by ", and", "and the ..." chains): see `docs/working/writing.md`.
- **Labels:** a row in `labels/names.tsv` for every function you identified
  (`1400be770<TAB>Citizen::ChooseJob<TAB>called from the AI tick, reads the job table`), a row in
  `labels/fields.tsv` for every field, and a row in `labels/dictionary.tsv` with the meaning,
  unit and range of every value you learned about (`docs/DATA-DICTIONARY.md`). Check it with
  `tools/triage/dictionary.py labels/dictionary.tsv --fields labels/fields.tsv`.
  Functions the port cites with `Original: FUN_…` get labels automatically:
  `tools/triage/cite_labels.py SRC --existing labels/names.tsv --out labels/names-from-port.tsv`,
  then `decomp_query.py --labels labels/names.tsv --labels labels/names-from-port.tsv`.
  Add `--notes` to name module notes after their module. Add `--any --prefix FUN_` when the port
  also cites functions as a `FUN_` address in the comment above an item, without "Original:".
- **Checklist:** tick or add the items in `docs/CHECKLIST.md` and update its date.
- **Ledgers:** if the change adds or removes a `Deviation:` or `not ported` comment, regenerate
  the ledger (`tools/triage/deviations.py --out docs/DEVIATIONS.md SOURCE_DIR`) and commit it
  with the change. `tools/triage/coverage.py SOURCE_DIR` gives the progress figures for the
  checklist.

### Know-how

Ask whether this slice hit a failure, a dead end or a fact about the era, runtime or hardware
that the next game would hit too. Examples are a tool that crashed, a game that would not
start, a fix that took an hour and an idea that did not work. If it did, record it as a
know-how entry (`docs/working/knowhow.md`). Then `./gameframe advise` and the hook find it
next time.

1. Run `./gameframe advise "<the exact error text>"`. If an entry exists, add to it: a new line
   under `## Tried`, a new signature, or the fix that turns `open` into `solved`.
2. Otherwise copy GameFrame's `docs/knowhow/_template.md` into the project's `docs/knowhow/`,
   named by the entry's id. Fill in the facets from GameFrame's `docs/knowhow/README.md`. When
   the failure prints anything, add at least one signature (a regular expression for the exact
   message). Add the sections its status needs: `Symptoms`, `Cause` and `What to do` when
   solved; `Symptoms` and `Tried` when open or a dead end.
3. Run `./gameframe advise --check`, then the error text again. The entry should come first.
4. An entry that holds for other games belongs in GameFrame too. Say so in the report. The
   user decides whether to move it.

Record an open problem too, with every attempt under `## Tried`. That list saves the next
session the most time. Never put game material in an entry. Only addresses and short message
texts belong there.

## 2. Check what you are about to commit

```bash
git status --short
git diff --stat
```

Never stage anything from `game/`, `analysis/` or `derived/`, game files (`.exe .dll .pak
.sav` and the game's own extensions), decompiled code, disassembly, emulator output or
extracted assets. `.gitignore` covers the folders: never force-add. Screenshots are always
fine, of the original game and of the port: copy each one out of `derived/`, compress it
(WebP), caption it where it is used and commit it. Never leave one out for being game material.

## 3. Stage only your own work

Other sessions may edit the repository at the same time:

- stage files by name: `git add docs/AI.md labels/names.tsv` (never `git add -A`, `git add .`,
  `git commit -a`);
- in a shared file that also holds someone else's edits, stage only your lines (build the version
  with only your change and write it to the index with `git hash-object -w` and
  `git update-index --cacheinfo`), or ask;
- never revert or reformat changes you did not make.

### Mistakes that cost time

- **A scripted edit that silently does nothing.** A search-and-replace whose text does not
  match the file changes nothing and reports nothing. In scripts, check that each replacement
  matched (count it, or assert it). Look at `git diff` before you commit.
- **`git add` with a moved file.** After a file is moved, naming its old or new path may stage only part of the move. Then a commit that does not build goes in. After staging, check that
  nothing you meant to commit is still unstaged (`git status --short`, look for lines that do
  not start with a letter in the first column) and read `git diff --cached --stat`.
- **Processes left running.** Games, servers and emulators started for a test keep running
  after it fails. Stop them before you finish. Give long runs a time limit.

## 4. Commit, merge and push

A subject in the imperative, at most 72 characters (`Trace the citizen job choice`), and a body
that says what was traced, measured or reimplemented and how it was checked. Then:

```bash
git status --short                    # check for your own unfinished changes
git show --stat HEAD                  # confirm only your slice landed
```

Commit only the files or hunks from your slice. If you worked on a branch or in a worktree,
merge that commit into the local `main` branch before hand-off. If you started on `main`, the
commit is already integrated. Never leave completed, merge-ready work uncommitted or waiting in
a branch to be merged. If a conflict or required gate prevents integration, record the exact
blocker in the hand-off and mark the slice as not landed.

After integration, update local `main` from its remote and push it, following the project's
workflow. If the rebase or push conflicts in files you did not touch, stop and report the exact
blocker; do not rewrite or stage another session's work.

## 5. Ship

When a version is ready for players, `docs/OUTPUTS.md` lists what to release and how: programs
for each system built by CI from the tag, a browser version, a website. When the slice reached
a milestone, write its diary entry on the project's site (`re-site`) before you commit.

## 6. Report

Two or three lines: the commit, what landed, what is verified, and the next open item.
