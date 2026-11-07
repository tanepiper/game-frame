# Changelog

Every release of GameFrame, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/). The newest version here is the one in
`.claude-plugin/plugin.json`, and `tests/run.sh` checks that the two match.

## [1.5.0-dev] - Unreleased

### Added

- Lessons from TabStationToo, PCSX2 compiled to WebAssembly. `re-verify` gains written lists of
  what is compared and what is left out, lockstep (both versions run each unit, the program goes
  on with the reference's result), fuzzing new code against a reference, a deterministic mode for
  threads, and running WebAssembly tests in both of V8's compilers.
  `docs/working/building-the-port.md` gains browser pitfalls (hosting headers, faults that do not
  trap, storage limits, WebGPU readback and features, gamepads, code generated at run time) and
  how to measure speed, starting with a check that the CPU is not capped.
  `docs/consoles/porting.md` notes emulators in the browser and how their licence carries over.

- The call log in the replacement libraries: `WRAPPER_CALLS=FILE` writes every call the game
  makes into Glide, SGL, ATI3DCIF or the S3D Toolkit, one line each, in the format
  `tools/verify/seqdiff.py` compares. Vertices are written as their values, texture data and
  frame-buffer writes as a size and hash. `WRAPPER_CALLS_FRAMES` keeps a range of frames.
  A Glide vertex is written as the fields the card reads under the current state
  (`wrappers/glide/src/used.rs`), so leftover values in unread fields do not make two logs
  differ. `grFogTable` writes its table as a size and hash.
  `shim::call!` and `shim::calls` hold it, and the tests check that every export writes itself.
- The rendering pipeline (`docs/hardware/rendering-pipeline.md`): the five stages of a frame,
  where each ran on the CPU or the card machine by machine, what a port can check at each seam,
  and the port built as a virtual graphics card with swappable devices, which fits the vanilla
  and extra builds. Five new diagrams, and an interactive lab page on the site
  (`/lab/pipeline`) that takes one frame through every stage and draws it with a software
  renderer, a 16-bit card and a modern device side by side. `re-port` gains the device
  interface; `re-verify` checks the renderer at its seams, earliest first.
- `gameframe install` (`tools/install/install_app.py`): build a project's release programs from
  its `install.json` and install them as an application in the GameFrame folder:
  `/Applications/GameFrame/NAME.app` on macOS, `%LOCALAPPDATA%\Programs\GameFrame` on Windows,
  `~/.local/share/GameFrame` on Linux, with the player's data kept apart. `install extra`
  installs the vanilla build and the extra build with the additions on, side by side. GameFrame's
  own `install.json` installs the frame demo.
- `tools/live/winegdb.py`: attach to a game under Wine or CrossOver through `winedbg --gdb`,
  read its registers and memory, wait at breakpoints with dumps of memory, and always detach with
  the original code back in place. `tools/live/gdbremote.py` is its GDB remote protocol client,
  for any GDB stub. Know-how entry `winedbg-gdb-server`: winedbg's bare `c` resumes one thread,
  it refuses software breakpoints, and hardware breakpoints never fire under Rosetta.
- Know-how on Windows machines for an Apple-silicon Mac: which emulator or VM suits each era
  (86Box, QEMU with TCG, VMware Fusion and Parallels with Windows 11 Arm, Wine, a real PC), with
  three failures met on the way: Windows Setup in QEMU stopped mid-install, Fusion's "Press any
  key to boot from CD" prompt, and Windows 11 Arm Setup stopping on the logo in a VM made with
  `vmcli` (open). The know-how taxonomy gains the `2010s` era.
- `tools/rea/rea_session.py`: REA on a game's binary from a script. `fn` gives REA the project's
  labels and prints a summary of each function's dossier (size, references, callees, memory
  effects), `snapshot` saves REA's answers to reuse, and `labels` writes
  `set_addresses_names` input. `tools/rea/mcp_client.py` is the small stdio MCP client under
  it, which starts a provider from the project's `.mcp.json`. The know-how entry
  `context-rea-sessions-and-snapshots` has what a session costs and what a snapshot keeps,
  measured on Banished.
- `gameframe-d3d`: Direct3D 3 immediate mode in software. It writes and parses execute buffers
  (`Builder`, `exec::parse`: `D3DTLVERTEX`, `PROCESSVERTICES`, `STATERENDER`, `TRIANGLE`) and runs
  them (`Device::execute`) into an RGB565 target at any multiple of the game's resolution. It
  follows Direct3D's fill rules (integer pixel centres, top-left) and covers flat and Gouraud
  shading, perspective-correct textures in 565, 1555 and 4444, the texture blends, colour keys,
  the alpha test, every blend factor, the stipple pattern and vertex fog, all from Microsoft's
  public documentation. `docs/hardware/card-apis.md` has a new section on Direct3D 3 execute
  buffers.
- `gameframe-powervr`: a software model of PowerVR's PCX2 as SGL 3.1 drives it. `Sgl` has the
  calls by their names (lists, transforms, meshes, materials and texture effects, cameras,
  fog, ambient and point lights, translucent passes, `sgl_render`) and draws into an RGB565
  buffer at any multiple of the device's size, with the driver's lighting (`SGLMID4.dll`) and
  the chip's per-pixel depth sort. The scene graph moved here from `wrappers/sgl`, which now
  uses it.
- The ATI 3D Rage and S3 ViRGE draw in their own crates: `gameframe_rage::draw`
  (`Context`, `C3D_VTCF`, `render_prim_list`: triangles and quads, solid, flat or Gouraud,
  alpha blended) and `gameframe_virge::draw` (`State`, the 32-byte vertex, `triangle_set`:
  lists, strips and fans, Gouraud, source-alpha blended), both on `gameframe-raster`, the
  triangle walker moved out of `wrappers/raster`. The `ati3dcif` and `s3dtkw` DLLs draw with
  them, and so can a port.
- `gameframe-report`: reports from a running port. `unported!` and `mismatch!` at the places
  the port has not done, and panics, each written once per place with the original's address,
  the values there, the game's state, the launch and the devices. Dev keeps them on the
  machine; Production adds a link to a filled-in GitHub issue. The frame lists them
  (`report.new`, `Link::send_reports`), and `tools/triage/report_issue.py` lists and files
  them, once per place.
- `library.json`: `issues`, one report button per repository (the game's, GameFrame's), and
  `links` with an `icon` and a `place` (`header`, `play`, `footer`) for a row of links such as
  GitHub and Mastodon. New icons `github`, `mastodon`, `home` and `link`.
- The frame's setup dialog (contract 1.1): device slots beside the renderers, such as the
  sound card and the music device, as a 1990s game's Manager or `SETUP.EXE` offered them.
  `device.select`, `devices` in `frame.ready` and `game.start`, `Session::select_device`,
  `Manifest::playable` and `chosen` for kernels, `{device:SLOT}` for `frame.json` games, and
  one id per card for every game (`device::ids`, with the crate or wrapper that models each in
  `device::known`). Play shows one drop-down per slot with a card for the chosen device. A
  device not ported yet may name a `stand_in` that starts in its place
  (`Manifest::stand_in`), and the kernel reports the gap.
- `gameframe-voodoo`: a software 3dfx Voodoo Graphics pipeline driven by Glide 2.x (combine
  units, chroma key, alpha test, table fog, Z and W buffers, blending, the 565 buffer with its
  dither), after 3dfx's SST-1 specification, and a `Glide` context with the calls by their
  names, drawn at any multiple of the game's resolution.
- One crate per 3D chip: `gameframe-voodoo` (Glide's formats and NCC tables),
  `gameframe-rage` (ATI3DCIF), `gameframe-virge` (S3D Toolkit), and `gameframe-texel` for the
  texel layouts and the 2:1 reduction they share. Each lists the layouts its API takes
  (`TEXTURE_FORMATS`).
- `gameframe-frame`: `Link`, the program's end of `Process` for a Rust port (the manifest, the
  events until a start, then `stopping()` and `status()` while the game runs), and `Respawn`,
  a `Game` that starts the program again for each start, for ports whose winit window can be
  made only once per process. Both come from POD's and Hardwar's launchers.
- `gameframe-bitmap-font`: an old game's bitmap font as a TrueType font, built in memory, and
  a CSS `@font-face` rule with a data URL, so a launcher's theme can use the game's own letters
  read from the player's files at run time. From Hardwar's launcher.
- `gameframe-frame-ui`: the frame names the theme it draws as `data-theme` on `#library`, so a
  game's own styles can apply to one theme only.
- `gameframe-library`: `Folder::link_in`, which fills a section from the player's own folder
  by hard links.
- `gameframe-frame`: `Manifest::resolve`, `Held` and `Setup` (`setup`). A kernel works out the
  devices of a start in one call: the pick per slot, the stand-ins and the gaps.
  `Setup::report_gaps` writes one report per gap at the kernel's place.
- Building the port: "One program or two, one build or many". One build holds every device, and
  `devices` chooses at the start. The frame and the game are two processes on the desktop, and
  one file can hold both roles.

### Removed

- `gameframe-gpu-1997`: its pieces are in the per-chip crates above. `glide` is now
  `gameframe_voodoo::formats`, `ncc` is `gameframe_voodoo::ncc`, `ati` is `gameframe_rage`,
  `s3` is `gameframe_virge`, and `texel` and `resample` are `gameframe_texel`. The `card`
  table became each crate's `TEXTURE_FORMATS`.

- A game can give the frame a theme of its own: `FrameSetup::with_theme(name, label, css)`.
  `"preset"` and `"presets"` in `library.json` name it as they name the ready-made themes, so
  the player can still choose between them.
- `scripts/release.py X.Y.Z` cuts a release. It dates the changelog's Unreleased section, sets
  the version in `.claude-plugin/plugin.json`, commits and tags `vX.Y.Z`, then opens the next
  minor version as `-dev`. `--push` pushes the branch and tag, and `--publish` also makes the
  GitHub release from the changelog. `release.py next` opens the next version on its own.
- The commit gate blocks a commit while `plugin.json` still names a release that has its tag,
  so every change after a release lands under the next version's Unreleased section.
- `launcher/`, gameframe-launcher: the frame in front of a game that a `frame.json` describes,
  such as a port's own program. It hides while the game runs and comes back when
  the game ends, or exits to the desktop if the player chose that. `--no-frame` starts the game
  at once.
- A choice setting can list what is on the disc. `"from": {"files": PATTERN}` lists the
  matching files in the game's folder (`Configured::load`, `list_files`), and `"from": {"game":
  true}` waits for the game's `config.options`. `frame.json` takes a `folder`, where the command
  runs.
- A way back to the launcher. `frame.open` from a running game shows the frame, "Back to the
  game" sends `frame.close`, and `Session::hide_while_running` hides it while the game runs.
  `FrameSetup::with_window` shows and hides a desktop window. In a page the hidden frame leaves an
  "Open the frame" button.
- Game exit. `frame.on-exit` chooses what happens when the game ends by itself: the launcher
  comes back, or the program exits to the desktop. "Exit to desktop" (`Session::exit`,
  `frame.exit`, `FrameSetup::with_exit`) stops the game, then leaves.
- Big files in the browser library. `gameframe-library`'s `IndexedDb` streams a file of at
  least `web::BIG` bytes (64 MiB), such as a 700 MB CD image, into the origin private file
  system 8 MiB at a time, kept plain so it can be read in slices. `Library::add_file` and
  `Store::write_file` take a `web_sys::File`; `Library::file` and `Store::file` give one back.
  The game's hooks see the first 1 MiB of a big file. The frame's Library tab adds files this
  way in the browser.
- The GameFrame home, `~/gameframe` or `$GAMEFRAME_HOME`, outside every clone. It holds
  `config.env` (machine-wide settings, read before a project's `.env`), the shared Python in
  `python/`, `tools/`, `emulators/`, `machines/`, `drivers/`, `games/ID/`, `projects/ID/`,
  `worktrees/`, `cache/` and `data/`. `gameframe home init` makes it, `gameframe home doctor`
  checks it, and `gameframe home` lists it.
- `gameframe game add ID FILE` keeps a disc image or installer in `games/ID/media/`, records
  its SHA-256 in `game.json` and extracts it into `games/ID/game/`. `gameframe game link ID
  PROJECT` links a project's `game`, `media`, `saves`, `analysis` and `derived` into the home.
  `gameframe home adopt PROJECT --id ID` moves an older project's folders there and leaves a
  link at each old name. It keeps a folder that git tracks files in.
- The launcher reads a game from a disc image. `frame.json` takes `"image"`, file lists come
  from the ISO 9660 volume (`list_image_files`), and `{image}` and `{folder}` in the arguments
  become absolute paths.

### Changed

- `Session::state()` is `idle` before the first start and `starting` from `game.start` until the
  game answers. It was `stopped`, so a test that waited for `stopped` ended before the game ran.

- A project's game folder is `game/`, a link into the home. `target/` still works for older
  projects, and the gates protect both. `scripts/new-project.sh NAME` with no slash makes the
  project in `projects/NAME`, and `--local` keeps real folders in the project instead.
- The README lists the tools most projects start with, by step of the method, and links to the
  site's tools page, which is built from each tool's own help. `./gameframe tools` lists them all.
- A site's day post no longer replaces that day's live entries. The live entries stay, the day
  post ends with "The day's entries" linking each one, and the diary's list and sidebar show
  only the day post for a past day. `tools/site/check.py` fails when a day post misses a link.
- Screenshots are always fine, of the original game and of the port. The project rules, the
  viewer guide, `re-land`, `re-site` and `re-publisher` now say so, so agents commit them and
  put them on the site instead of leaving them out as game material.

### Fixed

- `decomp_query` picks the .exe with the most functions when an export holds several, not the first
  by name, and says on stderr which it chose. A game no longer loses to its smaller launcher. An
  address past the end of every function now stops the query and names the other binaries, where
  it used to return the nearest function before it.
- `gameframe-report` panicked in the browser on its first report ("time not implemented on
  this platform"): it stamped reports with `std::time::SystemTime`, which wasm32 lacks. It
  uses `web-time` now, the same clock natively.
- `tests/run.sh` no longer asks the wrappers workspace for `raster`, which moved to
  `crates/raster` (`gameframe-raster`), where the crates check tests it. The wrappers check
  failed on every run since the move.
- The library's browser store read none of its files back: `seal` gave the browser its
  AES-GCM nonce as a view of a Rust value dropped before `encrypt` read it, so files were
  encrypted under another nonce than the one kept with them. Both directions now pass the nonce
  as a JavaScript array. Files kept before this fix do not decrypt; add them again.
- `Process` reports a game program's end once, after its last lines, where it sent `stopped`
  again on every tick. A program that exits with an error is `failed`, with its exit status and
  its last line on standard error, so the launcher shows why and does not leave for the desktop.
  A program that said `stopped` or `failed` itself and then exited successfully gets no second
  status. `Configured` reports a command that exits with an error as `failed` too.

## [1.4.0] - 2026-10-26

### Added

- `crates/library` (`gameframe-library`) keeps a port's game data, saves and opt-in sections
  (mods, screenshots, recordings, custom). The game declares them in one `library.json`, with
  hooks for save cards and file checks. It has folder, memory and browser stores. In the browser,
  files are encrypted with a non-extractable WebCrypto key.
- `templates/library-page/` is a plain HTML page for browser ports that works with the crate.
  It has a design system of `--lib-*` tokens, replaceable icons and named components. Panels
  show Markdown, a changelog, messages, a click-to-load YouTube video and GitHub releases, and
  ports can add their own. Markdown help pages sit at hash routes, with `::: tip` boxes and
  `::: panel` slots.
- `crates/frame` (`gameframe-frame`) is the contract between a port's core and the frame
  around it. It has event topics, a manifest of capabilities, renderers with coverage grades,
  settings and controls, and a session with listeners. A game joins in Rust, in any language
  over JSON lines, or with a `frame.json` alone. A demo game stands in when there is no port and
  presses its own controls. A minor contract version only adds fields, and older frames ignore
  them.
- `crates/frame-ui` (`gameframe-frame-ui`) draws the frame as Dioxus components for the browser
  and the desktop. Its tabs are Play, Settings, Library, help pages and Console, styled by the
  library page's tokens. `examples/frame-demo` runs it with no game, in both targets.
- Eleven ready-made themes in `templates/library-page/themes/`: Windows 98, XP and Vista,
  System 7, Aqua, BeOS, NeXTSTEP, CDE, GNOME 2, Amiga Workbench and Atari ST GEM. `"preset"`
  in `library.json` picks one for the HTML page and the frame. `"presets"` lets the player choose between them in the frame's Settings tab, saved as `frame.preset`.
- `crates/disc-image` and `crates/game-source` move from POD into GameFrame. They read CD images
  in place, and give a game's files from a folder, a disc image or a URL, in ranges in the
  browser.
- `tools/llm/decision.py` routes bounded choice, yes-or-no and score questions to a user-selected
  decision model through its native System One endpoint. `decision_feedback.py` stores explicit
  user corrections locally and exports training examples. Neither tool selects a paid service,
  changes model weights or uploads data.
- The site diary is now written live and then put together by day. During the day, each
  milestone gets a live entry named `YYYY-MM-DD-HHMM-slug.md`, which the diary shows with its
  time. On the next run, `re-site` and `re-publisher` turn each past day's live entries into
  one post in the style of update notes: what is new, a little detail, and a short change list.
  The post drops the repeats. `tools/site/check.py` fails while a past day still has live
  entries. `--days` lists those days, and `--keep-live` turns the check off.
- The plugin check in `tests/run.sh` ignores system files that sit on disk but not in git, and a
  new check fails if git tracks a `.DS_Store`, `Thumbs.db`, `desktop.ini` or `__MACOSX` file.

### Changed

- Model-powered tools now default to the local provider. `GAMEFRAME_LLM_ENDPOINT` can point to a
  local or compatible endpoint; hosted services are selected by name with `GAMEFRAME_LLM_PROVIDER`
  with provider-specific model and key settings. Hosted providers and remote endpoints require
  confirmation before a request. Image location supports local vision models; function naming
  uses synchronous calls where a server has no batch API.
- The REA skill now documents how to check Ghidra provider readiness, open an explicit Ghidra
  session, inspect a native function and its raw instructions, retain the Evidence bundle, and
  close the temporary project. It separates focused REA analysis from whole-program Ghidra
  searches and emulator measurements.
- 86Box setup guidance now covers the optional GDB build, its dynamic-recompiler tradeoff and
  the debugger tools provided by the opt-in `86box-mcp` server. The provider launcher places its
  automation socket in a home-mounted temporary directory for Docker builds, and defaults to
  token-protected TCP transport for container compatibility.

## [1.3.0] - 2026-10-25

### Changed

- Stage agents, separate tasks and worktrees are optional. The current session is the default,
  and a task being self-contained does not imply permission to delegate. Paid unattended runs
  and recurring schedules require the user's choice.

### Added

- The modular GameFrame MCP server now exposes workflow and tool discovery, knowledge queries,
  progress and provider configuration, plus execution for every runnable catalog program and
  script. Long-running calls report progress and support cancellation. Its sample coverage check
  now resolves help for all 117 catalog entries, invokes the help path of all 95 runnable
  commands, runs a sample PE analysis, and checks progress, cancellation and timeout handling.
  External REA, DOSBox-X, MCPEmulate and 86Box servers are opt-in through `gameframe mcp`, with
  pinned package versions or source revisions. Their project-local launchers read custom server
  and emulator paths from `.env`. Copilot agent allowlists track each project's enabled providers.

- The new `re-profile` skill builds an evidence-backed game quick start after inventory. It
  records the game's family, engine, release, graphics, sound and input support, separates
  official support from community reports, and lists project-specific traps and next steps.

- A clean-room-style workflow with source-visible specification and source-blind implementation
  roles, a behavior-contract template, packet checklist, team guide and emulator/debugger options.
  It records the limits of prompt-based separation and the current gap in packet isolation tools.

- The observation guidance now covers 86Box as a configurable full-PC reference for DOS and
  Windows 3.x/9x games. It records sound-card resource settings, guest OS and machine details,
  and labels captures as emulator measurements rather than physical-hardware evidence.

- `gameframe-sn76496` adds a TI SN76496 tone/noise model, input-clock advancement, PCjr `C0h` and
  original Tandy `C0h`–`C7h` adapters, PCjr and Tandy `61h` output muxes and the Tandy PIT-2 input
  route. The Tandy adapter exposes the service manual's approximate 42 CPU wait states. Static
  traces of Sierra's original `JR.DRV` and `TANDY.DRV` confirm tone latch/data writes, attenuation
  writes, startup mutes and PSG-source selection. TI noise details, period-zero behavior, the
  Tandy mux's fourth input, NCR/PSSJ variants, sample parity, CPU wait mapping and analog behavior
  have software-only follow-up checks. The SN76496N timing source is the IBM PCjr reference; the
  Tandy service schematic confirms its matching 3.579 MHz clock.

- `gameframe-saa1099` adds a Philips SAA1099 stereo sound generator and a two-chip Creative Music
  System/Game Blaster port model. It applies tone and octave writes at generator transitions,
  buffers envelope controls to waveform boundaries and models common CMS detection-port behavior.
  Static traces of `CMSDRV.COM` and Sierra's `CMS35.BIN` establish the chip ports, default base and
  detection probe. The noise seed, combined tone/noise mixing, exact custom-chip behavior, bus waits
  and analog output have software-only follow-up steps; physical card testing is optional.

- `gameframe-sound-blaster` adds port-level Creative DSP models for 1.xx through 4.xx cards,
  CT1335/CT1345/CT1745 mixer registers, SB16 MPU-401 UART, and FM routing through GameFrame's OPL2
  and OPL3 crates. Profiles cover SB Pro 1's dual YM3812 stereo path, Pro 2 YMF262 ports, and SB16
  8/16-bit mono/stereo DMA. DSP MIDI timestamps and UART reset restoration follow the published
  interface. The docs record preservation context, the bundled driver restriction and its
  assessment limits, the clean-implementation boundary, ADPCM/analog/timing limits, and software-
  only follow-up checks. Physical card testing is optional.

- An investigation of Creative's SBBASIC SB16/SB32/AWE32 package verifies the archive hash and
  release metadata. Its driver payload remains inside TTComp `.PVL` archives until the DOSBox-X
  installer can be driven to a temporary destination. The findings document records the exact
  software-only next step; no driver behavior is claimed.

- A PC audio coverage map separates chip crates, card models, compatibility libraries and host
  audio backends. It inventories common PC audio from the speaker and Tandy PSG through Sound
  Blaster, Gravis UltraSound, MIDI modules and late-1990s Windows audio, and prioritizes OPL3,
  Sound Blaster DSP/DMA, GF1 and MIDI work. It records the clean-implementation process and
  owner-selected licensing options.

- `gameframe-opl3` adds a YMF262 chip model with two register banks, 18 channels, six selectable
  four-operator pairs, four connection algorithms, eight waveforms, four output words,
  OPL2 compatibility mode, shared note-select, timers, indexed I/O ports with timestamped
  write-spacing checks, and serial DAC frames. Timer divider phase resets when a timer starts. It reuses
  GameFrame's OPL2 engine and follows Yamaha's datasheet and YM3812 Application Manual. An original
  AdLib Gold Windows driver trace records its register write path, voice pools, busy polling and
  second data-port reads. The AdLib Gold Control Chip and port overlay are modeled separately in
  `gameframe-adlib-gold`. Independent four-operator carrier routing, physical parity, YAC512 analog
  conversion and card-level audio processing remain open.

- `gameframe-yac512` adds a clean model of the YAC512's LSB-first serial receiver, offset-binary or
  two's-complement input selection, falling-edge channel latches and held digital input words. The
  floating DAC transfer and analog sample-and-hold stage stay documented as open behavior because
  Yamaha's available datasheet does not provide the conversion formula. The open-question page
  proposes software-only protocol and integration checks; physical hardware testing is optional.

- `gameframe-adlib-gold` combines the YMF262 with the documented AdLib Gold Control Chip port
  overlay, status, register reads/writes, EEPROM save/restore commands and audio-port relocation.
  The Developer Toolkit v1.01 resolves the Windows driver's `0xFF`/`0xFE` bank switches and second
  data-port reads. It routes the MMA at offsets `+4` through `+7` and feeds its sampling request
  into Control Chip status. `mix_sources()` now applies the documented linear source-volume,
  speaker/microphone/telephone routing, output-channel selection, forced mono, mute and final
  output-volume controls. Analog tone and spatial processing remain documented limits.

- `gameframe-ymz263` adds the YMZ263B/MMA digital model used by AdLib Gold. It includes dual
  128-byte PCM/ADPCM FIFOs, documented rates and sample layouts, timer counters, per-channel DMA
  request state, MIDI FIFOs and timestamped UART output. A static trace of the original GSS Wave/MIDI
  driver confirms its two index/data pairs and timer, sample and MIDI register use. EEPROM save
  latency stays configurable because its duration is unspecified. Analog mixer/filter behavior,
  external DMA/IRQ delivery and chip details needing software comparison are documented as open;
  physical hardware tests are not required.

### Fixed

- The Windows 3.x and Windows 9x know-how entries now use the canonical `virtual-machine`
  runtime facet for 86Box. The `86box` spelling remains a taxonomy alias.

## [1.2.0] - 2026-10-25

GameFrame 1.2.0 expands the late-1990s replacement libraries, adds a clean-room Indeo 4.1
decoder and a runtime harness, and improves input capture and project safety. Know-how now has
broad starting entries for major topics alongside its specific failure notes.

### Added

- Know-how now has broad starting entries for sound cards, CPU behavior, display output,
  CD-ROMs, input, networking, game files, and timing. The entries link to detailed guides, with
  case notes where available. Know-how guidance now calls for an overview when a major topic has
  only narrow entries.
- `sgl.dll` draws the immediate mode's shadow and light volumes (`sgltri_shadow`), which it
  only counted before. Each call's faces become the planes of one convex volume, oriented as
  PowerVR's driver orients them, and every pixel is tested against them: a shadow multiplies
  by its brightness, a light volume adds its colour. Texture wrapping now moves a vertex by one
  turn at most, as measured in the driver. In shadow mode a Gouraud face with a translucent map
  is drawn flat, as the driver does. The fog constant is 1.0, a person's choice until a PCX2
  picture settles it. Free texture memory and the `sglhw.ini` the library writes follow the
  driver's installer (`TSPParamSize` 256). `sgltritest.c` draws one volume of each kind.
- `gameframe-msvc-crt` adds safe byte memory operations, C byte-string functions, integer parsing
  and integer formatting. It models Windows `long` as 32 bits and documents its C-locale limits.
  The 2008, 2010, 2012 and 2013 x86 CRT exports and selected decompiles informed the new routines.
  Their runtime parity is still open.

- `glide2x.dll` draws under Wine on macOS. There Wine gives OpenGL 2.1, which cannot compile
  the library's shaders. The library now asks for a forward-compatible 3.2 core context when the
  first one is older than OpenGL 3. `glidetest.exe` passes all 27 checks under Wine on an Apple
  M3 Max (`docs/knowhow/wine-macos-opengl-2-1.md`).

- `glide2x.dll` now implements all 156 Glide 2 calls. The last 25 are in. The PCI library
  (`pci*`) shows one Voodoo Graphics. `guMPDrawTriangle` draws two textures in two passes, as
  Glide 2.43 does. The `guMovie*` calls record each frame shown as a TGA file. That is a
  Deviation, as Glide 2.43 cannot record. `guEncodeRLE16` gives the same bytes as the
  original on 2009 test images, faults included. `ConvertAndDownloadRle` downloads zeros, as
  the original does, since its line decoder is empty. `grSstConfigPipeline` and
  `grSstVidMode` do nothing, as the window is the library's. `glidetest.c` checks the PCI
  library, the encoder, the two passes and a recorded frame.

- A project's `target/`, the user's own copy of the game, is now hard to delete by mistake. A
  disk cleanup took it for Cargo build output and lost three projects' game copies and an
  original save (`docs/knowhow/game-folder-deleted-as-build-output.md`).
  `new-project.sh` writes `target/GAME-FILES-NOT-BUILD-OUTPUT.txt`, and `update-project.sh`
  adds it and `.cargo/config.toml` (`target-dir = "build"`) to older projects. A new delete
  gate (`scripts/hooks/gates/deletes.py`) blocks an agent's `rm`, move to the Trash,
  `find -delete`, `git clean -x`, `cargo clean` into `target/` and build-folder cleaners on a
  game folder; `GAMEFRAME_DELETE_GAME=1` on the command lets it through. `./gameframe doctor`
  reports a missing or empty `target/`. `templates/project/AGENTS.md` says `target/` is the
  only copy and `build/` is Cargo's.

- `glide2x.dll` implements 131 of the 156 Glide calls, up from 55, so it runs more Glide 2
  games than POD. It now draws points, polygons, and the antialiased and clipping draws. It
  handles culling, the alpha test, colour and depth masks, depth bias, drawing to the front
  buffer, the lower left origin and the colour formats. It saves and restores state
  (`grGlideGetState`, `grGlideSetState`). Textures gain mipmaps, LOD bias, NCC tables,
  multibase, partial downloads, the `gu` texture manager and 3DF files. The frame buffer gains
  region reads and colour formats. The queries, statistics and `gu` fog tables are in. The
  fog tables match the original byte for byte. `wrappers/glide/test/glidetest.c` draws and
  checks a known scene through the DLL, and `tests/run.sh` builds it. The host tests cover
  clipping, culling, mip level layout, fog tables, 3DF files and NCC tables.

- `sgl.dll` now has SGL's immediate mode, which Hardwar's PowerVR mode uses. It has the
  `sgltri_*` calls for triangles, quads and rendering. It has SGL's DirectDraw mode with its 2D
  callback. It also has the end-of-render callback, the error, version and texture-memory
  calls and `sgl_delete_all_textures`. That is 14 more calls, so SGL has 61 of 134. The faces
  go through the scene graph's renderer. The header leaves facing, flat shading, translucency
  levels, the order of translucent passes and the fog register open. They were read from
  PowerVR's own SGLMID4.dll, partly by unattended `re-tracer` runs.
  `wrappers/sgl/test/sgltritest.c` draws a known scene with them. The plain-Rust part has
  host tests.

- Every wrapper DLL now exports every call of the original library, so any game that uses one
  loads. Calls implemented of calls exported: Glide 55 of 156 (Glide 2.43 and 2.1.1), SGL 47
  of 134, ATI3DCIF 6 of 17, S3D Toolkit 6 of 6, DirectDraw 2 of 9. Each crate's `api.tsv`
  holds the original's API table. `wrappers/stubgen.py` writes the crate's `.def` and
  `src/stubs.rs` from it. It stubs each call not written yet. It fails on a call written with
  the wrong convention. The originals stay outside the repository.
- `tools/pe/apitable.py` writes the API table of a 32-bit DLL or of an SDK's import library.
  For a DLL, each export's convention and argument bytes come from the `ret N` its code ends
  with. A header gives the parameter counts and return kinds. The tool is tested on a DLL
  built from our own C.
- The wrappers log what they lack in one way. `shim::stub!` and `shim::gap!` log the first call
  of each stub and unhandled mode with its arguments. They count the later calls. When the game
  exits, they list them all with their counts. `ddraw.dll` names each COM method that is a stub. `sgl.dll` now logs the
  convex objects it skips.
- Debug and release builds of the wrappers. `cargo build` gives symbols, debug assertions, the
  first 50 calls of each stub logged and OpenGL errors checked after each frame. `cargo build
  --release` gives link-time optimisation and stripped DLLs. Each log names its build.
- `S3DTK_ExitLib` and `S3DTK_PhysicalToLinear`, from the original's code. With them the S3D
  Toolkit is complete.

- `wrappers/`, a Cargo workspace of replacement libraries for the 3D cards of 1997, moved from
  the POD project: `glide2x.dll` (Glide 2.x on OpenGL), `ddraw.dll` (DirectDraw in memory,
  scaled), `ati3dcif.dll` and `s3dtkw.dll` (the chips' faces drawn in software), and `sgl.dll`
  (PowerVR SGL's scene-graph half on OpenGL). The shared crates are `shim`, `raster`,
  `scalers` and `pixels`. The game-specific parts became settings: `WRAPPER_WINDOW_CLASS`,
  `WRAPPER_MARKER` and a patch file named by `WRAPPER_PATCHES`. `tests/run.sh` runs the host
  tests, builds the DLLs, checks their export tables against the `.def` files and builds
  `sgltest.c`.
- Thirty-seven know-how entries: thirteen from POD (POD Gold, the PowerVR build, the emulated
  PC, ptrace under Wine, the FPU control word in the game's own thread and more) and
  twenty-four from Hardwar, among them running the original on a whole-process snapshot,
  registers left by callees, fake worlds and Ghidra function recovery. The taxonomy gains the
  API `sgl` (PowerVR).

- A guide to the replacement libraries, [docs/hardware/wrappers.md](docs/hardware/wrappers.md):
  why games had a build per card, what each DLL draws and lacks, how to build and use them,
  patch files, logs, adding a game or a call, tests, and POD as the worked example with
  screenshots of its runs. The home page has a section on them.
- `gameframe-indeo`, a clean-room Indeo 4.1 decoder that matches Intel's `IR41_32.DLL` byte
  for byte, and `ir41_32.dll`, a Video for Windows codec built on it. The decoder's empty-band
  path now uses the same fill words as Intel's Pentium path.
- `wrappers/maxi94` supplies a silent `94DLL32.dll` so POD Gold's Maxi Sound 64 build starts,
  then maps its opened wave outputs and mixer lines to host audio. A full race measured the
  output. The sound-card API guide distinguishes measured behavior from unverified descriptions.
- `tools/live/emupc.py` gives each game's emulated PC a project-specific name and refuses to
  start a second copy for the same project.
- The runtime harness inspects a game folder, names its runtime needs and writes setup steps.
  Its initial modules cover Wine, emulated PCs, DOSBox-X, Steam, audio, disc drives and Glide
  wrappers. `tools/live/align.py` maps a known screen to a capture so scripts can place clicks;
  `tools/llm/locate.py` can locate a changed screen, and `tools/formats/pngio.py` reads and writes
  PNG. `re-observe` now plans the harness before the first run and maps click points before
  driving it.
- The repository now backs up its Codex Cloud environment settings, install script and start
  instructions under `docs/working/` and `scripts/`.

### Changed

- `scripts/zcc.sh` also finds a DLL's `.def` file one folder down, in `ZCC_DEF_DIR/*/NAME.def`,
  for a workspace with one `.def` in each crate.
- The replacement-libraries guide points at `wrappers/` and says how a game uses them.
- Three know-how entries take POD's newer findings: the game races with the x87 word 0x027f,
  and CD audio and PulseAudio in the emulated PC.
- `re-randomiser` lists chance taken from the frame clock; the recording guide records the
  FPU's control word and measures sequences; `re-start` gives the order for moving to a newer
  version; the object-model guide says a probe client takes any JSON answer.
- `tools/llm/name_functions.py` submits functions in batches, reports each batch's status,
  fetches every result, and can cancel the run.

### Fixed

- `memrec --name` takes the game's own process, never the shell or launcher that started it,
  whose command line names the game too.
- `client.py` keeps reading a project `.env` file after a key is absent, so later settings are
  still available.
- `new-project.sh --copy` removes generated Python caches from copied `scripts/` as well as
  `tools/`, so they do not keep GameFrame's scripts behind when a project moves to the plugin.

## [1.1.0] - 2026-10-24

GameFrame 1.1.0 brings the lessons of POD, Hardwar and Tyrian into the framework: a know-how
layer of failure modes and context with a hook for every agent, tools for 32-bit and 1990s games
(a 32-bit emulator, Watcom register arguments, export gaps, card-library probes, recordings and
replays), tools that spend a plan's monthly API credits, guides for MMX, 3D cards, versions and
the story, a website for each project, and one GameFrame checkout per machine.

### Added

- `tools/llm/`, tools that spend a Max or Team plan's monthly API credits
  ([API credits](docs/working/api-credits.md)): `name_functions.py` suggests names for every
  unnamed function in one Message Batch; `skillcheck.py` gives an agent one skill and a task
  on the sample game and checks the answer against ground truth (`tests/skill-tasks.json`);
  `headless.py` runs an agent unattended under a budget, and `docs-check` runs `re-checker`
  and `re-editor` over the documents; `ask.py` answers a question from the know-how entries.
  `fake_api.py` stands in for the API in `tests/run.sh`. The SDK is optional, in
  `requirements-llm.txt`. Know-how: `api-credits-refused`, the messages a refused run gives
  and the fix for each.
- `ghidra-run.sh ... callargs regs=watcom`: the constant each register gets before every call,
  in Watcom's order (EAX, EDX, EBX, ECX) or any list, where the decompiler shows no arguments.
- `ghidra-run.sh ... fill-gaps`: makes a function at each start `exportcov` finds, goes on past
  a bad one, and exports the binary again. The sample DLL gains a routine Ghidra misses.
- `tools/verify/replay.py`: checks a port's trace against a recording read from outside, where
  one sample can mix frames; a value passes when any state in its window holds it.
- `tools/triage/axes.py`: the up axis, its sign and the handedness of a 3D game, from a recorded
  path over the level's vertices.
- `tools/pe/probegen.py`: a probe library for a DLL a 32-bit game imports, exporting the same
  names (decorated `__stdcall` ones too) and logging every call with its arguments.
- The `gameframe-scale` crate: nearest, Scale2x (EPX) and a CRT look, for a finished frame.
- `re-browse` section 5: growing the viewer into an editor.
- `tools/triage/buildid.py`: everything a copy says about its own version (the disc's mastering
  date, link dates, VERSIONINFO, version strings, readme and setup lines), written into the
  project's `docs/versions.md`. `re-inventory`, `re-start` and the versions guide check on day one
  whether the copy is the latest official build, and where to search for later official
  releases; the template has a "Build identity" and an "Is this the latest official version?"
  section.
- Versions and their deltas: [the versions guide](docs/working/versions.md) now starts with
  finding every edition, takes the last version released as the default reference, and has the
  steps for moving to a newer edition mid-project. A project template, `docs/versions.md`,
  records each edition, its checksums, languages, content and builds, the data and code
  deltas, the extras and the reference. `re-inventory` and `re-start` have the step.
- `tools/triage/versiondiff.py`: two editions compared as folders or disc images: files added,
  removed and changed by folder, PE link dates and languages, as Markdown.
- Know-how: `context-newer-edition-mid-project`, from POD's first edition and POD Gold.
- `ExportAll.java` writes `bodies.tsv`, every piece of every function (start, end, entry), and
  `exportcov.py` reads it beside `functions.tsv` (or with `--bodies`). Before, a function whose
  body lies in several pieces counted as one run from its entry: Hardwar's export measured
  93.7% where 98.0% of its code is in functions.
- Know-how: a project whose `./gameframe` runs a second clone or another project's copy of
  GameFrame (pin the machine's one checkout in `.env`), and scripted edits that stop matching
  after a formatter reflows the code.
- Three guides from the POD: Planet of Death project:
  [Recording the original, and replaying it](docs/observe/recording.md),
  [Replacement libraries for a 1990s game](docs/hardware/replacement-libraries.md) and
  [Writers, editors and mods](docs/working/mods.md); and a section on the emulated-PC route in
  [Running the original](docs/observe/running-the-original.md).
- `scripts/zcc.sh`: rustc's linker for 32-bit Windows DLLs through `zig cc`, exporting exactly
  the names in a `.def` file.
- `pe32_emu`: `array`, `put` and `get` lay out the game's structures; the sample DLL gains
  `sum_list` and `heaviest_path` to test them.
- `tools/formats/derived.py`: which fields next to geometry are bounds, centres, normals or
  plane distances.
- Reading the story, from the Hardwar project: the guide
  [Reading the story for design decisions](docs/working/lore.md), which makes the case that a
  game's manual and its own text say what each system is for and which must be exact, with
  Hardwar as the worked example. `re-inventory` has a new step, "Read the story", and
  `re-start`, `re-surveyor` and the games taxonomy point to it. New projects get a
  `docs/lore.md` template with the table "in the story → in the code → evidence".
- A case study of Hardwar (1998), and Hardwar in the vehicle simulations' reference games.
- `tools/triage/sentences.py`: the sentences in a program or a Ghidra `strings.txt`, ASCII and
  UTF-16, with addresses, for reading the story.
- `tools/formats/shadetable.py`: a palette game's shade, fog or light table, with the levels
  that are black, unchanged and white, the colour it fades toward, the shift that reaches
  normal light, and a picture.
- `xorscan.py --records` and `--key-in`: a key XORed into one field of every directory record,
  read from the names' zero padding and completed from the executable.
- `rawimage.py` and `catalog.py --dac shift`: 6-bit palettes shifted left by 2 (63 is 252).
  The catalogue fills a palette of fewer than 256 colours with magenta.
- `constants.py` reports Park-Miller's 16807 without `--all` when its modulus 0x7fffffff, or
  Schrage's 127773 or 2836, is beside it.
- `new-site.sh --manual`: a Pages workflow that runs only when started by hand. New sites get a
  theme to colour from the game and a `public/` folder; `re-site` asks for figures and diagrams
  in every diary entry from the first. `re-browse` describes the viewer's `--export` mode for
  agents.
- Know-how from Hardwar: Watcom pseudocode that drops register arguments, the x87 control word
  `0x0c7f`, a variable frame step in replays, 6-bit palettes shifted by 2, light tables with an
  unchanged level, worktrees without the ignored folders and Ghidra's project lock, and
  reading the story. The entries on missed functions and on Watcom name `exportcov` and Hardwar.
- Know-how entries for GameFrame's own tools: unmapped memory under the emulators, an import
  with no handler, a tool run without the `.venv`, and Ghidra refusing a path in a dot folder.
- `dos_env` has a keyboard: `env.press(scan, at, hold)` and `env.key_script('10:39:3')` put
  make and break codes on port 0x60 and raise IRQ 1 through the game's INT 9 handler, which
  acknowledges through port 0x20. The BIOS's INT 9 feeds the INT 16h queue, and INT 16h waits
  for a key still to come. The DOS sample gains `wait_keys` and a keyboard handler.
- `tools/triage/exportcov.py`: how much code a Ghidra export covers, its largest gaps, and the
  likely starts of the functions it missed (call targets, starts after a return or padding),
  written for the batch decompile.
- `pe32_emu`: `fpu_cw=` loads an x87 control word before a call, `fpu_modes()` lists the cases
  whose result depends on the rounding mode, and `until=` stops at an address and returns the
  stack there, as for a call to `sprintf`. The sample's 32-bit DLL gains `fix_mul` (a magic-number
  `fadd`) and `report` (a call to `wsprintfA`).
- `validate.py --write`: decode, encode and compare every file, naming the first differing byte.
  The sample decoder has an `encode`.
- `tools/live/memlog.py` (read a recording back: summary, CSV), `tools/live/emulock.py` (who
  uses a shared emulator) and `tools/live/loopcut.py` (a recorded path cut into one loop).

- Thirty-five know-how entries promoted from the POD: Planet of Death project. They cover
  replacement card libraries under Wine (Glide 2, the S3D Toolkit, ViRGE surfaces, missing
  card libraries), mods (the install folder first, values replaced at run time, mods in a
  reference recording),
  recording a run from memory and replaying it (samples that straddle frames, stand-ins for
  unported logic, a game clock that is not real time, waiting for a phase), x87 rounding and
  truncating helpers, functions Ghidra missed and claims that need an address scan, editors
  and writers (one edit type, float views, derived geometry data, round trips of every file,
  axes measured in the running game), input drivers (held keys, click timing, closed racing
  lines), shared VMs (`pkill`, `sudo` and `DISPLAY`), keeping every dialog, and the emulated-PC
  route (CD drives under Wine on Linux, Xvfb and a window manager, SSH, a script that shadows a
  standard module). The card builds' context now says to measure what the card is given.
- `tools/triage/refs.py`: every instruction that refers to an address, found in the code bytes
  (32-bit immediates and displacements, 64-bit RIP-relative). Each hit is marked as a read, a
  write or a value. Hits outside any function are marked too. The sample's 32-bit DLL has a
  table with two writers to test it.
- `tools/live/memrec.py`: snapshots of a running game's writable memory for `memscan.py`. It
  also records named values and arrays as JSON Lines. It reads `/proc/PID/mem`. `--wait` waits
  for a phase.
- `discinfo.py --iso`: the data track of a BIN/CUE as a plain ISO.
- `tools/live/emupc.py`: the files that run the original in an emulated PC (QEMU, a Debian
  cloud image, cloud-init with Wine and 32-bit Mesa, Xvfb, openbox, SSH, the disc as a CD-ROM).
- `tools/live/shot.py`: captures kept under names of their own, with their text. It never
  overwrites a capture.
- `tools/live/modfolder.py`: install, list and clear a folder of changed files in an install
  folder.
- `winput`: keys held by `down` are released at exit. New steps `release`, `point` and
  `button`, and a new option `--hold MS`.
- A case study of POD: Planet of Death.
- Know-how: `pgrep-wait-matches-itself`. A wait loop with `pgrep -f` never ends, because the
  pattern matches the waiting shell's own command line.
- `re-observe`: a capture script prints its usage for `--help` and runs nothing, and never
  overwrites an earlier capture. Seen when checking a script's usage started a 15-minute run
  over the saved data.
- `gameframe progress`: every agent keeps a progress log, one line per step, in
  `derived/progress/<agent>.log` (`gameframe progress <agent> --add TEXT`). `gameframe progress`
  shows each log's last lines, newest first, so the main session can answer "how is it going?"
  without reading an agent's transcript. Each agent's file has a Progress section that says
  when to write.
- Know-how: a taxonomy of failure modes and context, one Markdown entry per failure, each with
  its symptoms, cause, evidence, status (solved, workaround, dead end, open) and what was tried
  ([the design](docs/working/knowhow.md), [the entries](docs/knowhow/README.md)).
  `gameframe advise "<error text or topic>"` finds entries by error signature, facet, alias and
  word. It reads a log on stdin. `--check` checks every entry. It reads a project's own
  `docs/knowhow/` too.
- A Claude Code hook, `scripts/hooks/advise.py`. It names the matching entries after a shell
  command (`PostToolUse` and `PostToolUseFailure`), once per session. It names the context
  entry for Wine when a command starts Wine.
- Eighteen seed entries from the POD: Planet of Death project. The failure entries cover
  privileged port probes under Wine, DirectDraw mode tables, windowed mode on a 16-bit desktop,
  16-bit back surfaces, "insert the CD", ini paths, VirtualSize 0, `SuspendThread`, DirectInput
  focus, input inside Wine, `DYLD_*` on macOS, `wineserver -w`, leftover processes, winedbg,
  and the open `wow64cpu` fault under Rosetta with every attempt. The context entries cover
  Windows 95 DirectDraw games, Wine on macOS and Watcom programs.
- The know-how hook for Codex (`PostToolUse`), Gemini CLI (`AfterTool`), Cursor (`postToolUse`)
  and GitHub Copilot (`postToolUse`, `postToolUseFailure`).
  `scripts/hooks/gates/post_events.py` reads and answers each agent in its own format. A plugin
  project runs the hook through `./gameframe advise-hook AGENT`.
- `gameframe serve`, GameFrame's own MCP server, with the tools `advise`, `knowhow_entry`,
  `knowhow_list` and `find`. `.mcp.json` names it `gameframe`.
- `tools/live/winput.py` and `winput.c`, a small Windows program built with zig. It sends keys
  as scancodes, relative mouse moves and clicks to a game from inside Wine. A `--dry-run` build
  serves the tests.
- Context entries for DOS games in DOSBox-X, games with a build per 3D card, and 16-bit
  Windows programs.
- The skills (`re-start`, `re-observe`, `re-land`'s new "Know-how" step), every agent and the
  project template suggest `gameframe advise` when a command fails or the work turns to a new
  era, runtime or hardware.

- Two hardware guides from the POD: Planet of Death (1997) project:
  [MMX and other SIMD code](docs/hardware/simd.md) (finding hand-written MMX routines,
  matching each to its plain version through its callers, measuring both, porting exactly) and
  [The card makers' 3D APIs](docs/hardware/card-apis.md) (Glide 2.x, ATI3DCIF and the S3D
  Toolkit: reading their state calls, how textures reach each card, games with one build per
  card, and renderer profiles for viewers).
- Two crates: `gameframe-mmx`, the MMX instructions bit for bit, and `gameframe-gpu-1997`, the
  texture formats and API constants of Glide 2.x (with NCC), ATI3DCIF and the S3D Toolkit,
  with one texel decoder.
- Two specialist task agents: `re-vectoriser` (SIMD code and CPU builds) and `re-accelerator`
  (3D card APIs and per-card builds).
- `tools/emu/pe32_emu.py` runs routines of 32-bit (x86) Windows games under Unicorn, with
  inputs in registers or on the stack, MMX included. It stops at any import without a handler
  and names it. The sample game builds a 32-bit DLL (`mixer32.c`) to test it.
- `tools/triage/insns.py` lists the pattern for MMX code among its groups.

### Changed

- The plugin has an icon, `.claude-plugin/icon.png`, and the tests read the plugin validator's
  own warning counts, allowing only GameFrame's own `CLAUDE.md` (Claude Code 2.1.310).
- One GameFrame checkout per machine. A project made by `new-project.sh` pins it with
  `GAMEFRAME_ROOT` in its `.env`, and `./gameframe` reads that from the project and from its main
  checkout, so worktrees use the same one. The launcher no longer looks in `../game-frame` next
  to a project, where projects side by side shared a stale symlinked clone. A game's session
  changes GameFrame in a worktree of that checkout, never in a second clone
  ([environments](docs/working/environments.md)).
- `ExportAddressBatch` (`ghidra-run.sh decompile`) reports a bad address and goes on, and makes
  no function at an address that nothing refers to unless it follows a `ret` or padding, so a
  call site no longer splits the function around it.

- The know-how hook reads only `stdout`, `stderr` and the error of a Claude Code command. The
  desktop app adds notes on changed files to the result. Those notes had matched the text of
  the entries themselves.

- `peinfo --imports`, `--exports` and `--strings` list their items again. The section loop had
  reused the name of the flags.
- The hook matches context patterns against the first line of a command only.
- A project's entry replaces GameFrame's entry of the same id.
- `peinfo` and `vtable` use a section's raw size when its VirtualSize is 0, as Watcom's linker
  writes it. `peinfo` marks such a section.

- `re-site`, `re-publisher`, `re-land` and `docs/OUTPUTS.md` now allow screenshots of the
  original game and of the project's viewer in documents and on the site, a few at a time,
  each captioned with its source. The game's files, extracted assets in bulk and decompiled
  code still stay out of git.

### Fixed

- `pe32_emu` zeroes a section whose file pointer is 0, as Windows does. Watcom marks `.bss` this
  way, and the emulator had filled it with the file's first bytes, so flags read as code
  (from Hardwar). It also starts the x87 at the control word 0x037f, as Windows starts a program;
  Unicorn alone starts at 0, which rounds every result to 24 bits (from POD).
- Thirteen know-how entries from POD and Hardwar: the AI's chance from the frame clock, a missed
  key tap, a 3D card that draws part of the frame, measuring library calls that lock mutexes, a
  screen that closes while a key is held, decompiled switches that drop cases, painter's order
  with big faces, a pointer the game draws, recording sound in a VM with no sound card, a
  replay that plays too fast, the emulator's x87 start state, one multiply for two channels,
  and the `.bss` file pointer. The taxonomy gains the symptom `wrong-result`.
- `tools/site/check.py` and the gates no longer take the English word "undefined" in prose for
  decompiled code. The pattern now matches Ghidra's sized types, pointers and variables of
  those types, and statements with `FUN_` and `DAT_` names (calls, assignments and
  declarations). Names cited in a sentence pass, as before.
- The animated diagrams: in every animated diagram the static labels are drawn last, so a
  moving token or highlight passes under the text it crosses instead of hiding it. Tokens that
  loop start with a negative `begin`, so none waits in the card's top-left corner before its
  path starts. Each "original" label in the function-swap diagram hides while its new tile
  shows. The raster-split and Atari 2600 beams now keep step with what they trigger, and the
  raster scroll loops with no seam.
- `site/diagrams/animcheck.py` (run by the tests) fails on loops that drift apart, animations a
  browser would drop and elements shown before their turn. `site/diagrams/animrender.html`
  plays every animated diagram in a browser and lists shapes over labels, tokens off the card
  and boxes that light up when the playhead is elsewhere.

- `readseg.py` stops with a clear message when an argument is not an address, such as a count
  written without `--count`. It printed the first value and then crashed.
- The Claude Code commit and push gates check the command's own git verbs. Claude Code's
  `if: Bash(git commit *)` also matches commands it cannot parse (a heredoc, a shell variable,
  a for loop), so the gates fired on commands that neither commit nor push.
- `./gameframe run decomp_query` without `--export` reads the project's `analysis/export`
  (the folder `GAMEFRAME_PROJECT` names), and its `labels/names.tsv` after the current
  folder's. Before, it read GameFrame's own sample export.
- `dosinfo.py --pstrings` prints a Pascal string's length byte address, the address code
  uses, instead of the text's. It finds a string right after another one when the second's
  length byte is a printable character.
- `tdinfo.py`: `types` and `globals` print the fields of anonymous records inside a type or
  a variable's declaration. `labels` leaves out imported procedures, whose segment numbers
  are past the program's (`procs` marks them). A scope's parameters and locals go to the
  procedure in the scope's own segment, not the first procedure at the same offset in any
  segment.

## [1.0.1] - 2026-10-23

GameFrame 1.0.1 sets up projects for the coding agents they name, and adds a website with a
diary of the work.

### Skills and agents

- A new skill, `re-site`, builds and keeps a project's website: a VitePress site in
  `sites/<name>/`, or one `site/`. It holds a diary with one entry per milestone and the
  project's documents shown through `@include`, so each has one copy. Entries are written for
  readers, as findings with their evidence, never as commit lists or tool output.
- A new task agent, `re-publisher`, writes the diary entry for each milestone, adds pages for
  new documents and checks the site before `re-lander` commits it.
- `scripts/new-site.sh` starts a site from `templates/site/`, with a GitHub Pages workflow that
  builds every site in the project.
- `tools/site/check.py` checks a site for game files, decompiled code, missing includes, diary
  entries without a title or summary, and entries that read like a commit log.
- New projects get milestones in their `AGENTS.md` and checklist. A viewer of every asset comes
  before the game, since each format then becomes a reader, a document and a viewer panel that
  the rest of the project reuses. `re-start` gives the same goals.

### Projects

- `new-project.sh --agent LIST` sets a project up for the coding agents it names: `claude`,
  `codex`, `gemini`, `copilot`, `cursor`, `opencode`, or `all` (the default). Each agent gets its
  skill link, its agents, its gate hooks and its MCP servers. Without `claude` the project has no
  `.claude/settings.json` or `CLAUDE.md`.
- `update-project.sh --agent LIST` adds agents to a project. Without it, the script refreshes
  the agents whose files the project already has.
- A plugin project now works in the other agents too. They get a copy of the skills in `skills/`
  with the `.agents/skills` link, and Cursor gets its agents in `.cursor/agents`.
- `./gameframe gate KIND` runs GameFrame's gates from a plugin project, which has no `scripts/`.
  Its Codex, Gemini CLI, Cursor and Copilot hooks call it.
- `scripts/clients.py` holds the list of files each agent needs. Both project scripts use it.
- A copied project's hook files now come from GameFrame too, so `new-project.sh --copy` gives
  Codex, Cursor and Copilot their hooks.

## [1.0.0] - 2026-10-23

GameFrame 1.0.0 runs its playbook in any coding agent. Claude Code, Codex, Gemini CLI, GitHub
Copilot, Cursor and OpenCode can each use the skills, the agents, the gates and the MCP servers.

### Skills

- The skills live in one `skills/` folder. `.claude/skills` and `.agents/skills` link to it, so
  every agent finds the same copy.
- The skills' wording no longer assumes Claude Code.

### Agents

- `agents/re-*.md` stays the one source for the 9 stage agents and 9 task agents.
- `gameframe agents --emit all` writes copies for Codex (`.codex/agents`), Gemini CLI
  (`.gemini/agents`), Copilot (`.github/agents`) and OpenCode (`.opencode/agents`). Each copy
  keeps its agent's limits, as an allowlist, a deny map or a sentence in its instructions.
- A session that cannot start subagents takes each role itself, from the agent's file.
- The support matrix in [docs/working/agents.md](docs/working/agents.md#agents-in-every-client)
  shows where each client reads rules, skills, subagents, hooks and MCP servers.

### Gates

- A git pre-commit hook blocks game material and decompiled code for every client and for people.
- Hook adapters for Claude Code, Codex, Gemini CLI, Cursor and Copilot. Outside Claude Code,
  agents name themselves to the gates with `GAMEFRAME_AGENT=<name>`.

### MCP and rules

- `gameframe mcp --emit all` writes each client's MCP configuration from `.mcp.json`, and points
  each client at `AGENTS.md`.

### Projects

- `new-project.sh --copy` and `update-project.sh` copy the skills folder and every client's
  agents. Older projects' `.claude/skills` move to `skills/`.

### Plugin

- The Claude Code plugin now carries version `1.0.0`. Claude Code updates it when the version
  changes, so plugin projects move from release to release.

[1.5.0-dev]: https://github.com/tanepiper/game-frame/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/tanepiper/game-frame/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/tanepiper/game-frame/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/tanepiper/game-frame/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/tanepiper/game-frame/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/tanepiper/game-frame/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tanepiper/game-frame/releases/tag/v1.0.0
