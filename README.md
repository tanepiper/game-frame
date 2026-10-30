# GameFrame

GameFrame is an agentic framework for reverse engineering games. Its playbook of skills and agents runs inside your coding agent. Its toolkit of tested tools checks every result against the original. AI agents and people use it to study a game from its shipped files. They
document its formats and rules, and reimplement it so it behaves exactly like the original.

Each reimplementation is an exact core with a frame around it. The core is the game, ported
from the original and checked against it. The frame is GameFrame's launcher, the player's
library of game files and saves, the settings, the renderer choice, help pages and an event
console. Every port gets the same frame. The core and the frame talk only through a versioned
contract of events ([Building the port](docs/working/building-the-port.md#the-frame)).

The toolkit works with [Ghidra](https://ghidra-sre.org), the
[Unicorn](https://www.unicorn-engine.org) emulator and [REA](https://github.com/morluto/rea)
(Reverse Engineer Anything). It uses [DOSBox-X](https://dosbox-x.com) and its debugger for DOS
runs, and [86Box](https://github.com/86Box/86Box) when tests need a configurable period PC.
GameFrame grew out of [Un-Banished](https://github.com/tanepiper/unbanished), a 1:1
reimplementation of the game Banished built this way; see
[the case studies](docs/case-studies/README.md).

## Set it up with your agent

Copy this prompt into your coding agent (Claude Code, Codex, Cursor or another). It clones
GameFrame and checks your tools. It asks before it installs anything, then starts a project for
your game.

<!-- #region setup-prompt -->
```text
Set up GameFrame on this computer for me.

1. Clone https://github.com/tanepiper/game-frame into ~/code/game-frame
   (or update it with git pull if it is already there).
2. Read AGENTS.md and skills/re-setup/SKILL.md.
3. Run scripts/setup.sh and show me the table of what is present and what is missing.
4. Before you install anything, tell me what scripts/setup.sh --install will install and how
   large each part is. Wait for my answer, then run it.
5. Run tests/run.sh --ghidra and report how many checks passed. If any failed, show the
   failures and fix the setup before going on.
6. Run scripts/setup.sh --rea and help me register REA with this agent.
7. Run ./gameframe home init. It makes the GameFrame home, ~/gameframe, where the games, the
   projects, the virtual machines and the shared settings (config.env) live.
8. Ask me for the name of the game and where my own copy of it is: a disc image, an installer
   or a folder. Then run
   scripts/new-project.sh <short-name> "<Game Name>" "<path to the game>".
   It copies the game into ~/gameframe/games/<short-name>/ and makes the project in
   ~/gameframe/projects/<short-name>/.
9. Open the new project, read its AGENTS.md, and start with the re-start skill.

Never copy the game's files, extracted assets or decompiled code into a git repository.
```
<!-- #endregion setup-prompt -->

To set it up by hand instead, follow the [quick start](#quick-start).

## Framework, playbook and toolkit

GameFrame is the whole framework. It has two parts.

The **playbook** is the method and the rules an agent follows:

- the skills in `skills/re-*/`, one per step of the method;
- the stage agents in `agents/`, packaged with the skills as a Claude Code plugin
  (`.claude-plugin/`);
- the rules in `AGENTS.md` and, for each game, in the project's own `AGENTS.md`
  (`templates/project/`).

The **toolkit** is the tested tools the playbook runs:

- the tools in `tools/`, such as the Ghidra export and query, the Unicorn emulators, format
  validation and the bit-exact comparison tools;
- the scripts in `scripts/`, such as setup, new-project and the Ghidra runs;
- the checks in `tests/run.sh`, which prove every tool on the samples in `examples/`.

## Quick start

```bash
git clone https://github.com/tanepiper/game-frame.git
cd game-frame
scripts/setup.sh --install          # Ghidra, JDK 21, objdump, Node, Zig, and .venv (unicorn, pefile, capstone)
tests/run.sh --ghidra               # proves every tool on the sample game (about 1½ minutes)

./gameframe home init               # ~/gameframe: games, projects, machines, config.env, shared Python
scripts/new-project.sh mygame "My Game" "/path/to/disc.iso"   # the game in games/mygame, the repository in projects/mygame
```

Then open the new project with your agent and ask it to start with the **re-start** skill.
The skills follow the Agent Skills format (https://agentskills.io). There is one copy, in
`skills/`. The links `.claude/skills` and `.agents/skills` point to it, so Claude Code,
Codex, Gemini CLI, GitHub Copilot, Cursor and OpenCode find the skills without setup. Agents
that do not read skill folders read `AGENTS.md` and the `SKILL.md` files. On Windows, git makes the links
only with symbolic links turned on (`git clone -c core.symlinks=true`, with Developer Mode);
without them, point the agent at `skills/`.

### As a Claude Code plugin

The skills and the stage agents are also a Claude Code plugin. In Claude Code:

```text
/plugin marketplace add tanepiper/game-frame
/plugin install gameframe@game-frame
```

The plugin brings the skills, the agents, the gates and GameFrame's MCP server. External MCPs are
off until a project opts in with `./gameframe mcp --enable NAME`. A project made with
`scripts/new-project.sh` enables the plugin in its `.claude/settings.json`, with
auto-update on, and runs the toolkit through its own `./gameframe` launcher, which finds
GameFrame in a clone or in the plugin's install. `plugin.json` carries the release's version.
Claude Code updates the plugin when that version changes, so projects move from one release to
the next. Each release raises the version and tags the commit with it. A project's own
tools and scripts sit beside the launcher, and GameFrame never touches them.

## Find your way with `gameframe`

`./gameframe` is a small command for help and discovery. It reads the skills and the tools'
own help from the files, so it never goes out of date. It needs only Python 3. Every new
project gets a small launcher of the same name, which runs this command and the toolkit on the
project (`./gameframe run NAME`, `./gameframe python FILE`, `./gameframe root`).

```bash
./gameframe steps                      # the method's loop, each step with its skill
./gameframe skills                     # every skill in one line
./gameframe skill re-trace --sections  # a skill's headings; --section TITLE prints one part
./gameframe tools                      # every tool and script, with its first line of help
./gameframe tool decomp_query          # one tool's full help
./gameframe run peinfo game/game.exe # run a tool with GameFrame's .venv
./gameframe find vtable                # which skills and tools mention a word
./gameframe advise "<error text>"      # known failures, fixes and dead ends (docs/knowhow/)
./gameframe doctor                     # the toolchain check (scripts/setup.sh)
```

`steps`, `skills`, `tools`, `tool` and `find` also print JSON with `--json`, for agents and
scripts.

## The method

![The method as a loop. Inventory, observe, decompile, trace, format, emulate, reimplement, verify and land, each with its skill. When a check fails, the work goes back to the trace.](docs/assets/method-loop.svg)

Write each claim with its evidence (an address, a value, a measurement) and one label:
*observed*, *measured*, *inferred* or *unknown*. Measure each number the reimplementation must match by running the original function under the emulator. The reimplementation must give the same result bit for bit.

## How a port is built

A port has three layers.

- **The core** is the game: its rules, formats and simulation. It matches the original bit
  for bit, and has no platform code. Reusable libraries plug into it: the chip and runtime
  [crates](#crates) and the [replacement 3D-card libraries](#replacement-libraries).
- **The platform layer** gives the core a window, drawing, sound, input, time and files. It
  behaves like the original wherever the player can see the difference.
- **The frame** is GameFrame's program around the game. It opens on the first run, and
  `--frame` opens it again. It holds the player's library, the settings from the game's
  manifest, a choice of renderer with a coverage grade for each (exact, good, partial,
  experimental or missing), help pages and a console of every event.

The game opts into each part of the frame by naming a capability in its manifest. It can add
event topics of its own. A Rust port implements the `Game` trait. A port in any other language
speaks JSON lines on standard input and output. A game the frame only starts needs a
`frame.json` and no code. The frame takes its look from design tokens in one `library.json`.
[Building the port](docs/working/building-the-port.md) has the contract, and
[the library page](templates/library-page/README.md) has the tokens. A ready-made desktop
launcher and the viewer as a tab of the frame are planned.

When a game needs something the frame lacks, it adds it to GameFrame with a pull request, or
opens an issue.

## Skills

Each skill is a self-contained guide for one step: when to use it, exact commands, what evidence
to produce, and the pitfalls that cost time.

| Skill | Step |
|---|---|
| [re-start](skills/re-start/SKILL.md) | Rules, the loop, a first-session checklist, routing to the other skills |
| [re-setup](skills/re-setup/SKILL.md) | Install and check the toolchain; register REA for your agent |
| [re-inventory](skills/re-inventory/SKILL.md) | Which files hold the game's code; native, managed, scripted or packed; engine and middleware; data containers; what kind of game it is; the story from the manual and the program's text, in `docs/lore.md` |
| [re-profile](skills/re-profile/SKILL.md) | After the first inventory, build an evidence-backed quick start with the game's family, engine, release, hardware support, likely traps and next steps |
| [re-browse](skills/re-browse/SKILL.md) | A resource viewer from day one: the catalogue of every file (`catalog.py`), then the project's own viewer on the port's readers, for people and agents to check decoded content |
| [re-observe](skills/re-observe/SKILL.md) | Run the original where you can watch, drive and capture it; every input; every screen; an object model with entry points for tests and agents |
| [re-rea](skills/re-rea/SKILL.md) | When to use REA's MCP tools, and how they fit with the text export |
| [re-ghidra](skills/re-ghidra/SKILL.md) | Headless export, queries, one-off decompiles, vtables, constants, checking the disassembly |
| [re-trace](skills/re-trace/SKILL.md) | From a string, import, export or class name to the function, its fields and constants |
| [re-format](skills/re-format/SKILL.md) | Decode archives, resources and saves; prove decoders on every file |
| [re-emulate](skills/re-emulate/SKILL.md) | Run original functions under Unicorn for ground truth; trace random draws |
| [re-port](skills/re-port/SKILL.md) | Reimplement exactly: precision, order of operations, draw order, iteration order; an exact core with commands, digests and a headless runner; additions (multiplayer, mods) kept apart |
| [re-cleanroom](skills/re-cleanroom/SKILL.md) | Write a neutral behavior contract in a source-visible role, then implement it in a fresh source-blind role |
| [re-verify](skills/re-verify/SKILL.md) | Bit-exact parity, draw order, determinism with digests and on every platform, recordings, saves, pictures, version against version, test tiers |
| [re-land](skills/re-land/SKILL.md) | Document in evidence style, label, commit owned files, and merge completed slices into `main` |
| [re-site](skills/re-site/SKILL.md) | The project's website in `sites/`: a diary entry per milestone, the documents shown as pages with `@include`, no commit dumps and no game material |

## Stage agents

One agent per stage of the method, in [agents/](agents/). Each has its skills preloaded, does only its
stage and ends with a hand-off that names the next agent. The main session sends them one at a
time; only the lander commits and integrates completed slices into `main`. `re-start` ("Stage
agents") has the table of hand-offs.
[Permissions and gates](docs/working/gates.md) lists what runs without asking and the hooks
that block game material, decompiled code and commits by other agents.

`re-surveyor` → `re-observer`, `re-decompiler` → `re-tracer` → `re-decoder`, `re-measurer` →
`re-porter` → `re-verifier` → `re-lander`, and back to the tracer or the porter when a check
fails.

Fourteen task agents do one job each, in any stage: `re-identifier` (engine and libraries),
`re-randomiser` (random generators and draw order), `re-listener` (every input),
`re-cataloguer` (every screen), `re-mapper` (hardware and memory), `re-typer` (structures and
classes), `re-matcher` (a crate or
library against the game), `re-editor` (documents to the writing rules), `re-checker`
(claims and sources), `re-publisher` (the project's site and diary), and two hardware
specialists, `re-vectoriser` (MMX and other SIMD code) and `re-accelerator` (the 3D card
APIs), `re-specifier` (source-visible behavior contracts) and `re-cleanroomporter`
(source-blind implementation). `re-start` ("Task agents") has their table.

Claude Code, Cursor and VS Code read the agents in `agents/` (through `.claude/agents`). Codex,
Gemini CLI, GitHub Copilot and OpenCode read copies in their own formats, which
`gameframe agents --emit all` writes. A client without subagents takes each role in one
session. [Agents in every client](docs/working/agents.md#agents-in-every-client) has the support
matrix.

[Agent teams](docs/teams/README.md) shows how the agents work together: eight teams for
common pieces of work (start-up, an exact system, a data format, the main loop, the interface,
sound and hardware, clean-room implementation, documentation), each with a diagram of its
hand-offs, the data passed between agents, the outcome, and the failure path.

## Scripts

| Script | What it does |
|---|---|
| `scripts/setup.sh [--install] [--rea]` | Checks every tool; installs what is missing; shows REA's registration plan |
| `source scripts/env.sh` | Sets `GAMEFRAME_ROOT`, loads `.env`, puts `gameframe` and the `.venv` Python on `PATH`, for each shell or agent session |
| `scripts/new-project.sh DIR "Name" [GAME] [--id ID] [--local] [--copy] [--agent LIST]` | Creates a project for one game: rules, the plugin enabled, the `./gameframe` launcher, and links into the GameFrame home for the game and its derivatives. A `DIR` with no slash goes in the home's `projects/`. `--local` keeps real, ignored folders in the project instead. `--copy` copies the toolkit, skills and guides instead. `--agent` names the coding agents to set it up for (`claude,codex,gemini,copilot,cursor,opencode`, or `all`, the default): each gets its skill link, agents, gate hooks and MCP servers |
| `scripts/update-project.sh DIR [--plugin] [--agent LIST] [--dry-run]` | Keeps a project current. For a plugin project, refreshes the launcher, settings and each agent's files. For a copied project, adds what is missing, replaces older copies and keeps the project's own edits; `--plugin` moves it to the plugin and removes only GameFrame's own files. `--agent` adds agents; without it, the agents the project already has are refreshed |
| `scripts/new-site.sh NAME "Title" ["Description"] [--single] [--repo URL]` | Starts a project's website in `sites/NAME/` (or `site/`): the front page, the diary, the findings and status pages through `@include`, and a GitHub Pages workflow (`re-site`) |
| `scripts/ghidra-export.sh [--labels FILE] BINARY...` | Headless Ghidra analysis and a text export: pseudocode, functions, strings, imports, exports; names applied from a labels file |
| `scripts/ghidra-run.sh BINARY decompile\|named\|refs\|vtable\|labels\|callargs\|blocks\|disasm\|fill-gaps OUT ARGS` | One-off jobs in the analysed project, without re-analysis: also every call with its arguments (`regs=watcom` for register arguments), raw memory pieces, and `fill-gaps` to make the functions `exportcov` finds and export again |
| `scripts/extract-installer.sh [--detect] INSTALLER OUT` | Unpacks an installer or package without running it: Inno Setup (GOG), NSIS, InstallShield, MSI, archives, `.dmg`, `.pkg`, GOG's `.sh`, CD images |
| `scripts/zcc.sh` | rustc's linker for 32-bit Windows DLLs through `zig cc`, with no MinGW, exporting exactly the names in a `.def` file: replacement libraries a 1990s game imports by name |
| `scripts/dosbox-run.sh [--fileio] [--break] [--mcp PORT] DIR PROGRAM` | Runs a DOS program in DOSBox-X without a window: exit code, file I/O log, debugger control |
| `./gameframe COMMAND` | Help and discovery: the steps, the skills, every tool's own help; runs a tool with the `.venv` |
| `tests/run.sh [--ghidra]` | The checks against the two sample games; `--ghidra` adds the Ghidra ones |

## Tools

GameFrame has over a hundred tools. Each one documents itself: `--help` prints its usage, and
`./gameframe tools` lists them all by folder. The [tools page](https://tanepiper.github.io/game-frame/tools/)
on the site is built from that same help, with a page for every tool. These are the ones most
projects start with, in the order of the method.

| Step | Tool | What it answers |
|---|---|---|
| Inventory | `tools/disc/discinfo.py` | A CD image's tracks, file systems and dates; copies files and audio out |
| Inventory | `tools/triage/filetypes.py` | What each file is from its bytes: signature, entropy, compressed or packed |
| Inventory | `tools/triage/buildid.py` | Which build a copy is, from dates, VERSIONINFO and version strings |
| Inventory | `tools/pe/peinfo.py`, `tools/dos/dosinfo.py` | What a Windows or DOS binary is: compiler, engine, imports, packer, debug symbols |
| Inventory | `tools/triage/needs.py` | What a game needs to run: CPU, OS, graphics and sound APIs, DRM, media |
| Trace | `tools/triage/decomp_query.py` | A function with your labels, its callers and callees, who uses a string or writes a field |
| Trace | `tools/triage/exportcov.py` | How much code a Ghidra export covers, and the functions it missed |
| Trace | `tools/triage/sigscan.py` | Byte signatures, to find known library code in a game |
| Measure | `tools/emu/pe32_emu.py`, `pe_emu.py`, `dos_emu/` | Any function of a 32-bit, 64-bit or 16-bit program, run with chosen inputs |
| Measure | `tools/emu/call_trace.py` | The calls an emulated function makes, such as random draws, in order |
| Formats | `tools/formats/reader.py`, `validate.py` | A decoder prototype, proved to read every byte of every file |
| Formats | `tools/formats/rawimage.py` | Raw pixels to PNG: VGA, Mode X, EGA, CGA and packed formats, with palettes |
| Observe | `tools/live/memrec.py`, `tools/triage/memscan.py` | Where a running game keeps a value, and recordings of named values |
| Verify | `tools/verify/bitcompare.py`, `seqdiff.py` | Ground truth against the port, bit for bit, and the first random draw that differs |
| Verify | `tools/triage/coverage.py`, `deviations.py` | How much of the original the port cites, and every marked deviation |
| Ship | `tools/install/install_app.py` (`gameframe install`) | The port's release build, vanilla and extra, installed as an application in the GameFrame folder |

Model-powered tools in `tools/llm/` use a local model by default. A hosted provider is chosen by
name and asks before each request ([model providers](docs/working/api-credits.md)).

## Crates

Clean Rust implementations of chips and runtimes that many old games need, each checked against
an original program in one of the case studies. The same workspace holds the pieces every port
shares: reading the player's files, the player's library and the frame. They live in `crates/`,
a Cargo workspace, under Apache 2.0. See [docs/crates](docs/crates/README.md).

| Crate | What it is |
|---|---|
| [gameframe-opl2](crates/opl2/README.md) | The YM3812 (OPL2) FM chip of the AdLib and Sound Blaster, with a resampler |
| [gameframe-wma](crates/wma/README.md) | A WMA v2 decoder for xWMA and ASF streams, building for WebAssembly |
| [gameframe-msvc-crt](crates/msvc-crt/README.md) | MSVC's `sinf`, `cosf`, `acosf`, `atan2f`, `qsort` order and `rand`, bit for bit |
| [gameframe-turbo-pascal](crates/turbo-pascal/README.md) | Turbo Pascal's 6-byte `Real`, `Random` and Pascal data layouts |
| [gameframe-indeo](crates/indeo/README.md) | An Indeo Video Interactive 4.1 (`IV41`) decoder, picture for picture as Intel's own codec (clean room) |
| [gameframe-disc-image](crates/disc-image/README.md) | Reads CD images in place (CUE/BIN, ISO, ISO 9660 and Joliet), with no dependencies |
| [gameframe-game-source](crates/game-source/README.md) | A game's files from a folder, a CD image or a URL, read in ranges in the browser |
| [gameframe-library](crates/library/README.md) | The player's game data, saves and mods, kept on the desktop or encrypted in the browser, with an [HTML page](templates/library-page/README.md) to manage them |
| [gameframe-frame](crates/frame/README.md) | The contract between a port and the frame: event topics, the manifest with capabilities, renderers and their grades, settings and controls, adapters for games in other languages or set up from `frame.json`, and the port's own end of that link |
| [gameframe-frame-ui](crates/frame-ui/README.md) | The frame's views as Dioxus components for the browser and the desktop: play, settings, library, help pages and console, with ready-made themes ([demo](examples/frame-demo/README.md), and [gameframe-launcher](launcher/README.md) for a game described by `frame.json`) |
| [gameframe-report](crates/report/README.md) | Reports from a running port: each unported path the game reaches, and each crash, with its context, as a local file in Dev and a filled-in GitHub issue link in Production |
| [gameframe-bitmap-font](crates/bitmap-font/README.md) | An old game's bitmap font as a TrueType font, built in memory, for a launcher's theme in the game's own letters |

## Replacement libraries

`wrappers/` is a Cargo workspace of DLLs that stand in for the 3D card libraries of 1997 and
for DirectDraw. A game that imports one of them runs unchanged and draws at any size. The guide
[Replacement 3D-card libraries](docs/hardware/wrappers.md) says how to build and use them. See
also [wrappers](wrappers/README.md) and [replacement libraries](docs/hardware/replacement-libraries.md).

| DLL | Stands in for |
|---|---|
| [glide2x.dll](wrappers/glide/README.md) | 3dfx Glide 2.x, drawn with OpenGL |
| [ddraw.dll](wrappers/ddraw/README.md) | DirectDraw, every surface in memory, the frame shown scaled |
| [ati3dcif.dll](wrappers/ati3dcif/README.md) | ATI 3D Rage (ATI3DCIF), drawn in software |
| [s3dtkw.dll](wrappers/s3dtkw/README.md) | S3 ViRGE (S3D Toolkit), drawn in software |
| [sgl.dll](wrappers/sgl/README.md) | PowerVR SGL's scene-graph half, drawn with OpenGL |

## Worked example

[examples/sample-game](examples/sample-game) is a tiny Windows x64 game (an EXE and an engine
DLL, built from C with Zig on any host) with the parts real games have: a fixed-step update, a
random number generator, a constant table, objects with a vtable, and a data file. It comes with
a ground-truth script, a reimplementation that matches the original bit for bit on 20 seeds,
and a deliberately naive reimplementation (doubles instead of floats) that the checks catch.

[examples/dos-sample](examples/dos-sample) does the same for DOS: 16-bit Pascal-style code
assembled with Zig and linked by our own script into an NE program (with Borland debug
symbols), and a real-mode MZ program, checked under the emulator and under DOSBox-X.

## Documents

The documentation is in [docs/](docs/README.md). It is also built as a website
(`npm --prefix site run dev`; see [site/README.md](site/README.md)).

- **[A taxonomy of games](docs/games/README.md)**: who drives (the game or the player), the axes
  every game sits on, ten families from arcade action to online games, each with a rule set,
  reference games and projects to learn from, and the systems they share.
- **[Software engines and middleware](docs/engines/README.md)**: how to recognise an engine,
  the id, Build and Unreal engines, other licensed and studio engines, and middleware.
- **[Hardware of the era](docs/hardware/README.md)**: CPUs from the 8086 to SSE2, fixed point
  and the x87 FPU, VGA and Mode X, 3dfx and the other 3D cards, sound cards and FM synthesis.
- **[Console games](docs/consoles/README.md)**: the platforms from the NES to the sixth
  generation, the tools, the routes to a port, and matching decompilation.
- **[Working on a project](docs/working/README.md)**: how agents work well on this, and how to
  write findings in plain English.
- **[Observing the original](docs/observe/README.md)**: running the original, every kind of
  input, capturing the interface, and an object model with entry points for tests and agents.
- **[The harness](docs/harness/README.md)**: what a game needs to run, the modules that
  provide it (runtimes such as Wine, an emulated PC and DOSBox-X; layers such as the Steam
  client), and how each game adds the modules it taught us.
- **[Case studies](docs/case-studies/README.md)**: Un-Banished, Tyrian 2000, Frontier: Elite II
  and POD: Planet of Death, and the tooling each built to capture its game.
- [docs/GAME-PATTERNS.md](docs/GAME-PATTERNS.md): main loops, random generators, entities,
  resources, saves, rendering, as they appear in machine code.
- [docs/DOS.md](docs/DOS.md): 16-bit DOS programs, Borland debug symbols, the DOS emulators.
- [docs/ABI.md](docs/ABI.md): calling conventions, C++ layout, floating-point and integer details
  that a bit-exact port must copy.
- [docs/TYPES.md](docs/TYPES.md): structures, classes, enumerations and the C++ standard
  containers, recovered from the code that uses them.
- [docs/OUTPUTS.md](docs/OUTPUTS.md): what a project can ship: documents, a website, programs
  for each system built by CI and attached to releases, a browser version, a server, tools.
- [docs/LEGAL.md](docs/LEGAL.md): working from your own copy, sharing none of the game's files,
  and writing new code from documented behaviour.
- [docs/SETUP.md](docs/SETUP.md): the toolchain, and tools for targets beyond native code.

## Scope

Native Windows x64 games and 16-bit DOS games (MZ real mode, NE protected mode, Borland
Pascal and C) are covered end to end; 32-bit LE/LX DOS-extender games are recognised and run
in DOSBox-X, but have no loader or emulator here yet. 32-bit Windows games run under
`tools/emu/pe32_emu.py`, routine by routine. Linux and macOS binaries work with Ghidra and the
tools where they apply; the emulator needs a variant for them (`re-emulate` lists what changes). Managed (.NET, Unity), scripted and packed games are routed to the right
tools by `re-inventory`.

Use it on games you own, keep the game's files and anything derived from them out of
repositories, and write new code from documented behaviour: see [docs/LEGAL.md](docs/LEGAL.md).

## Licence

GameFrame uses two licences, one for each kind of work.

| What | Licence |
|---|---|
| **Code**: `tools/`, `scripts/`, `tests/`, `examples/`, `crates/`, `launcher/`, `wrappers/`, `templates/`, `site/` (its configuration and code), `.claude-plugin/`, the Ghidra scripts | [Apache License 2.0](LICENSE-APACHE) |
| **Content**: the documentation (`docs/`), the skills (`skills/`), the agents (`agents/`, and their generated copies in `.codex/`, `.gemini/`, `.github/agents/` and `.opencode/`), the READMEs, `AGENTS.md` and `CHANGELOG.md`, and the website's text | [CC0 1.0](LICENSE-CC0-1.0), dedicated to the public domain |

CC0 1.0 gives up all copyright in the content, as far as the law allows. Anyone may copy,
adapt, translate and remix it for any purpose, commercial included, without asking and without
giving credit.

The screenshots in `docs/assets/case-studies/` show the games' own art. That art belongs to
the games' rights holders, is shown to illustrate the case studies, and is under neither
licence.

Projects made with `scripts/new-project.sh` start with the same two licences: Apache 2.0 for
their code and CC0 1.0 for their documentation.
