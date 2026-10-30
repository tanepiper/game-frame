# AGENTS.md: reverse engineering GAME_NAME

Rules for every agent (Claude Code, Codex, Cursor and others) and every person working here.
The method and the tools come from GameFrame. GameFrame is an agentic framework for reverse
engineering games. Its playbook of skills and agents runs inside your coding agent. Its toolkit of tested tools checks every result against the original. The skills, the
stage agents, the gates and the MCP servers come from GameFrame's Claude Code plugin, enabled
in `.claude/settings.json`, so they stay current. Each agent does one step and hands off to the
next (`re-start`, "Stage agents"). `./gameframe` runs the toolkit on this project.
The other coding agents (Codex, Gemini CLI, Copilot, Cursor, OpenCode) read a copy of the
skills in `skills/` through the `.agents/skills` link, and their own agents, hooks and MCP
servers, for each agent named with `new-project.sh --agent`. A project made with `--copy` also
has the link `.claude/skills`.
GameFrame's `scripts/update-project.sh` keeps these files current (`./gameframe root` prints where GameFrame is).

## The goal

GOAL: write one paragraph here. For example: "a 1:1 reimplementation of GAME_NAME VERSION in
LANGUAGE, reading the player's own data files", or "document the save format", or "a mod
loader". Say what "done" means and how exact it must be.

### Milestones

The usual order for a new project. Change it to suit the goal; the user decides. Each milestone
gets an entry in the project's diary (`re-site`).

1. **Inventory.** Every file known: binaries, engine, containers, the kind of game (`re-inventory`).
2. **Profile.** A quick start based on the game's family, engine, release, presentation, hardware,
   input and likely traps (`re-profile`).
3. **A viewer of every asset.** Pictures, palettes, sounds, music, models, levels, text and
   saves, all opened by the project's own readers (`re-browse`, `re-format`). Build it before
   the game. Each format becomes a reader crate or module with tests on every file, a document
   in `docs/`, and a panel in the viewer. The port, mod tools and the site reuse all three.
4. **A site.** The diary and the format documents, for the people who will use them (`re-site`).
5. **The foundations.** The random generator, the maths, the game clock and the main loop,
   measured and verified (`re-trace`, `re-emulate`, `re-verify`).
6. **The game.** One system at a time, each verified before the next (`re-port`, `re-verify`).

## The user decides

The agent is not the judge of the user's intentions, of which law applies to them, or of what
that law means. If the user wants to do something, the agent helps them do it. The agent may
advise. When it knows something that bears on the choice, such as a law, a risk or one of the
defaults below, it says so once, briefly, with its source. Then it follows the user's decision.
What 35 countries allow is in GameFrame's `docs/preservation/law/README.md`.

## Working rules

These are the project's defaults. They keep the work exact and the repository publishable. The
user may change any of them.

1. **Keep game material out of git.** The game's binaries and data stay in `game/`, its discs
   and installers in `media/`, saves in `saves/`, Ghidra output and decompiled code in
   `analysis/`, emulator output and extracted assets in `derived/`. Each is a link into the
   GameFrame home (`~/gameframe/games/ID/`), outside the repository, and git ignores the links;
   never force-add past `.gitignore`. Do not paste
   decompiled code, disassembly or data dumps into tracked files: describe findings in prose,
   tables, addresses (`FUN_1400be770`), field offsets (`+0x44`) and constants.
   Screenshots are always fine, of the original game and of the port. Commit them and put them
   on the site: copy each one out of `derived/`, compress it (WebP) and caption it.
   `game/` and `media/` are your copy of the game, and git keeps none. Never delete, move or
   clean them, and never run `git clean -x` here. `game/GAME-FILES-NOT-BUILD-OUTPUT.txt` says
   so, and the gates block such commands. Removing the link itself (`rm game`) is harmless.
   Cargo builds into `build/` (`.cargo/config.toml`). Add a game with
   `./gameframe game add ID DISC.iso`, and check the links with `./gameframe home doctor`.
2. **Evidence before code.** Every finding and every reimplemented behaviour names the original
   function it came from, and says how it is known: *observed* (read in code or data),
   *measured* (emulated or run), *inferred* (a reasoned guess) or *unknown* (an open question).
3. **Measure before claiming exactness.** Numeric, random or procedural code is checked against
   the original under the emulator (`re-emulate`), bit for bit.
4. **Mark every intentional difference** from the original in a code comment containing
   `Deviation:` (and a piece left out with `not ported`), then regenerate the ledger:
   `./gameframe run deviations --out docs/DEVIATIONS.md SOURCE_DIR`.
5. **Keep the core exact and the additions apart.** The part that decides what happens (rules,
   clock, random numbers, saves) does not draw, play sound or use the network. Anything the
   original does not have (multiplayer, mod code, debug tools) is an addition behind a build
   option, reaches the core only through commands, events and queries, and can be switched off
   for a run (`re-port`, "Additions the original does not have").
6. **Write it down.** Findings go into `docs/`, function names into `labels/names.tsv`, struct
   fields into `labels/fields.tsv`, the meaning, unit and range of each value into
   `labels/dictionary.tsv`, progress into `docs/CHECKLIST.md`. An undocumented finding
   is re-derived by the next session.
7. **Several sessions may work at once.** Stage only your own files (`git add path`), never
   `git add -A`. Never revert work you did not do. Before ending, commit each completed slice
   that has passed its gates and integrate it into local `main`. Do not leave completed,
   merge-ready work uncommitted or waiting in a branch or worktree. If a gate or conflict blocks
   integration, record the exact blocker and keep the slice marked as not landed. Do not stage
   another session's work to make the tree clean.
8. **Ask before downloading** anything; say the file, the source and the size.
9. **Licence and instructions.** Our code is Apache 2.0 (LICENSE-APACHE; `license =
   "Apache-2.0"` in manifests); documentation and other prose are CC0 1.0,
   dedicated to the public domain (LICENSE-CC0-1.0). Every part (core, player,
   viewer, tools) has build and run instructions in its README and a row in README.md.
10. **Clean-room-style tasks.** When the project asks for source-blind implementation, use
    `re-cleanroom`. Keep the source evidence ledger out of the implementer's packet. Record
    whether the task boundary is prompt-based, workspace-isolated or independently staffed.
    A shared workspace does not provide technical access control.
11. **Keep files small and modular.** One concern per module; split a file before it passes a
   few hundred lines, generated code included (one file per original unit or table).

## Where things are

| Path | What |
|---|---|
| `game/` | Your copy of the game (ignored, and the only copy: never delete or clean it) |
| `build/` | Cargo's build output (ignored, safe to clean) |
| `analysis/export/<binary>/` | Ghidra's text export: decomp.c, functions.tsv, strings.txt, imports, exports (ignored) |
| `derived/` | Ground truth from the emulator, extracted files (ignored) |
| `docs/FINDINGS.md` | The overview: binaries, engine, formats, systems, with links |
| `docs/GAME_PROFILE.md` | The evidence-backed quick start: game type, engine, release, hardware, traps and next steps |
| `docs/CHECKLIST.md` | What is traced, measured and reimplemented, and what is next |
| `docs/lore.md` | The game's world from its manual and its own text, and what it says each system is for ("in the story → in the code → evidence"). Read it again when a system's purpose is unclear |
| `labels/names.tsv`, `labels/fields.tsv` | Names for original functions and struct fields, read by the tools |
| `labels/dictionary.tsv` | The data dictionary: the meaning, unit, range and evidence of each value the rules use |
| `./gameframe` | Runs GameFrame's toolkit here: `run NAME ARGS`, `python FILE`, `doctor`, and help on the method: `steps`, `skills`, `agents`, `tools`, `tool NAME`, `find WORD`. `root` prints where GameFrame is. `install [extra]` builds the port's release programs from `install.json` and installs them in the GameFrame folder (GameFrame's `docs/working/building-the-port.md`) |
| `.claude/settings.json` | Enables GameFrame's plugin: the skills, the agents, the gates, and the MCP servers (REA, and `dosbox` for DOS games) |
| `skills/`, `.agents/skills` | The skills, for the coding agents other than Claude Code |
| `.codex/`, `.gemini/`, `.github/agents/`, `.github/hooks/`, `.cursor/`, `.vscode/mcp.json`, `.opencode/`, `opencode.json` | Each other agent's agents, gate hooks (through `./gameframe gate`) and MCP servers, for the agents the project was set up for |
| GameFrame's `docs/` | The reference documents and guides the skills name (`docs/DOS.md`, `docs/ABI.md`, `docs/games/` and the rest), in GameFrame's folder and on https://tanepiper.github.io/game-frame/ |

## The loop

inventory → profile → observe → decompile → trace → (format) → emulate → reimplement → verify → land. Start each
session by reading `docs/CHECKLIST.md` and searching `docs/` and `labels/` for the addresses
and names you are about to work on. `./gameframe find WORD` shows which skills and
tools cover a subject, and `./gameframe tool NAME` prints a tool's usage. When a command
fails, or the work turns to a new era, runtime or kind of hardware, run
`./gameframe advise "<error text or topic>"`. It names known failures with their fixes, and dead
ends with what was tried. Record this game's own in `docs/knowhow/` (`re-land`, "Know-how").

Keep a resource viewer from the first day (`re-browse`): the catalogue
(`./gameframe run catalog game derived/catalog --decoder GLOB=DECODER.py`) until the
port has readers, then the project's own viewer on them. Look at every decoder's output there
before porting it, and copy the catalogue's coverage line into `docs/CHECKLIST.md`.

Work a subsystem at a time and verify by risk (`re-start`, "Spend effort where it pays";
`re-verify` section 0): fuzz only maths, random draws and branchy code; check the rest
against recorded frames.

When something here would help any game (a tool fix, a new format reader, a pitfall), add it
to GameFrame too, with a test against its own samples. There is one GameFrame checkout on this
machine (`./gameframe root` prints it, `GAMEFRAME_ROOT` in `.env` names it). Change it only in
a git worktree of that checkout, never in a clone of your own, and merge into its `main`
(GameFrame's `docs/working/environments.md`). Build this game's own tools, crates and scripts
here as it needs them. Only what would help any game goes back to GameFrame.
