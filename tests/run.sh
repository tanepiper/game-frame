#!/usr/bin/env bash
# Prove every tool in GameFrame's toolkit against the sample game. Run after changing any tool.
#
#   tests/run.sh            the fast checks (about 20 s): PE tools, emulator, call traces,
#                           ground truth against the port, format validation, the 16-bit DOS
#                           tools and emulator, project scaffold
#   tests/run.sh --ghidra   also the Ghidra exports (Windows x64 and 16-bit NE), labels and
#                           decomp_query (about a minute more)
#
# Needs scripts/setup.sh --install (and zig, to build the sample game).
set -uo pipefail
. "$(dirname "$0")/../scripts/lib.sh"
cd "$ROOT"
S=examples/sample-game; B=$S/build
pass=0; fail=0
# A home of its own, so the checks never touch the real ~/gameframe.
export GAMEFRAME_HOME="$(mktemp -d)/home"
ok() { echo "  ok    $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/        /'; fail=$((fail + 1)); }
expect() { # name expected-substring command...
  local name="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if [[ "$out" == *"$want"* ]]; then ok "$name"; else bad "$name" "$out"; fi
}

echo "Building the sample game"
$S/build.sh >/dev/null 2>&1 && ok "sample game builds (zig cc, Windows x64)" || { bad "sample game builds: is zig installed?"; exit 1; }

echo "PE tools"
expect "peinfo reads the EXE" "EXE, x64 (64-bit), image base 0x140000000" "$PYTHON" tools/pe/peinfo.py $B/game.exe
expect "peinfo lists the engine DLL import" "engine.dll" "$PYTHON" tools/pe/peinfo.py $B/game.exe
table=$("$PYTHON" -c "import pefile;p=pefile.PE('$B/game.exe');print(hex(p.OPTIONAL_HEADER.ImageBase+[e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols if e.name==b'growth_table'][0]))")
expect "readdata reads a float table" "0.05000000074505806, 0.125, 0.3333333134651184, 1.0" "$PYTHON" tools/pe/readdata.py $B/game.exe f32 "$table" --count 4
vt=$("$PYTHON" -c "import pefile;p=pefile.PE('$B/game.exe');print(hex(p.OPTIONAL_HEADER.ImageBase+[e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols if e.name==b'tree_vtbl'][0]))")
expect "vtable lists two slots" "+0x008" "$PYTHON" tools/pe/vtable.py $B/game.exe "$vt"
vz="$(mktemp -d)"; "$PYTHON" -c "import pefile,sys;p=pefile.PE(sys.argv[1]);[setattr(s,'Misc_VirtualSize',0) for s in p.sections];p.write(sys.argv[2])" $B/game.exe "$vz/game.exe"
expect "vtable reads a PE whose sections have a VirtualSize of 0, as Watcom writes" "+0x008" "$PYTHON" tools/pe/vtable.py "$vz/game.exe" "$vt"
expect "peinfo shows the raw size of a section with a VirtualSize of 0" "(raw size: VirtualSize 0)" "$PYTHON" tools/pe/peinfo.py "$vz/game.exe"
rm -rf "$vz"
RS="$(mktemp -d)"; RF=tests/fixtures/rea; RSRV="$PYTHON $RF/fake_rea.py"
expect "rea_session labels keeps the binary's addresses, the first file winning, :: as __" '"0x140001100": "Thing__tick"' sh -c "\"$PYTHON\" tools/rea/rea_session.py labels $B/game.exe --labels $RF/names.tsv --labels $RF/more.tsv --out $RS 2>&1 && cat $RS/game.exe-names-1.json"
expect "rea_session labels leaves out another binary's address" "4 labels in 1 files" "$PYTHON" tools/rea/rea_session.py labels $B/game.exe --labels $RF/names.tsv --labels $RF/more.tsv --out $RS
expect "rea_session labels gives a name used twice its address" '"0x140001300": "other_140001300"' cat $RS/game.exe-names-1.json
expect "rea_session snapshot saves dossiers through an MCP server" "wrote $RS/game.exe.snapshot.json (1 new dossiers)" "$PYTHON" tools/rea/rea_session.py snapshot $B/game.exe 0x140001000 --out $RS --server "$RSRV"
expect "rea_session fn applies the labels and names the callee" "calls: Thing__tick" "$PYTHON" tools/rea/rea_session.py fn $B/game.exe FUN_140001000 --labels $RF/names.tsv --out $RS --server "$RSRV"
expect "rea_session fn prints the evidence and the memory effects" "memory effects: memory_read 1, memory_write 1" "$PYTHON" tools/rea/rea_session.py fn $B/game.exe 0x140001000 --snapshot-only --labels $RF/names.tsv --out $RS --server "$RSRV"
expect "rea_session fn writes the dossier under OUT/fn" "sample_fn" sh -c "\"$PYTHON\" tools/rea/rea_session.py fn $B/game.exe 140001000 --json --labels $RF/names.tsv --out $RS --server '$RSRV' 2>/dev/null; ls $RS/fn/game.exe/"
expect "mcp_client says how to enable a missing provider" "run ./gameframe mcp --enable rea" "$PYTHON" -c "import sys;sys.path.insert(0,'tools/rea');import mcp_client as m
try: m.provider_command('rea', project='$RS')
except m.McpError as e: print(e)"
rm -rf "$RS"
expect "peinfo counts the base relocations" "base relocations: " "$PYTHON" tools/pe/peinfo.py $B/game.exe
expect "dates finds a FILETIME and a DOS date" "0x00000b  filetime   2026-10-22 14:30:00" "$PYTHON" - <<'PY'
import struct, datetime as dt, subprocess, sys, tempfile
t = dt.datetime(2026, 10, 22, 14, 30, tzinfo=dt.timezone.utc); u = int(t.timestamp())
data = b'HEAD' + struct.pack('<I', u) + b'\0' * 3 + struct.pack('<Q', (u + 11644473600) * 10**7)
data += struct.pack('<HH', (14 << 11) | (30 << 5), ((2026 - 1980) << 9) | (10 << 5) | 22)
f = tempfile.NamedTemporaryFile(suffix='.bin', delete=False); f.write(data); f.close()
print(subprocess.run([sys.executable, 'tools/triage/dates.py', f.name, '--near', '2026-10-22T14:00'],
                     capture_output=True, text=True).stdout)
PY
expect "compare_trees pairs a renamed file by its content" "like NEW.PAK in B" "$PYTHON" - <<'PY'
import os, random, subprocess, sys, tempfile
r = random.Random(1); d = bytes(r.getrandbits(8) for _ in range(100000)); t = tempfile.mkdtemp()
os.makedirs(f'{t}/a'); os.makedirs(f'{t}/b')
open(f'{t}/a/OLD.PAK', 'wb').write(d); open(f'{t}/b/NEW.PAK', 'wb').write(d[:60000] + b'patch' + d[60000:])
print(subprocess.run([sys.executable, 'tools/triage/compare_trees.py', f'{t}/a', f'{t}/b', '--similar'],
                     capture_output=True, text=True).stdout)
PY
expect "hashnames gives the ROR-13 hash of an import name" "0xec0e4e8e" "$PYTHON" tools/triage/hashnames.py --hash LoadLibraryA
expect "screenmarks projects a point through the camera's matrices" "corner: 240.0, 50.0" "$PYTHON" - <<'PY'
import struct, subprocess, sys, tempfile, zlib
w, h = 320, 200
raw = b''.join(b'\0' + b'\x20' * 3 * w for _ in range(h))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
f = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')); f.close()
print(subprocess.run([sys.executable, 'tools/triage/screenmarks.py', f.name, '--view', '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1',
                      '--proj', '1 0 0 0 0 1 0 0 0 0 1 1 0 0 0 0', '--point', '1,1,2=corner', '--out', f.name + '.svg'],
                     capture_output=True, text=True).stdout)
PY
expect "relocs finds the vtable as a run of code pointers" "$vt  .rdata      2 pointers  (2 code)" "$PYTHON" tools/pe/relocs.py $B/game.exe
ot=$("$PYTHON" -c "import pefile;p=pefile.PE('$B/mixer32.dll');print(hex(p.OPTIONAL_HEADER.ImageBase+[e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols if e.name==b'order_table'][0]))")
out="$("$PYTHON" tools/triage/refs.py $B/mixer32.dll "$ot")"
[[ $(grep -c "  write  " <<<"$out") == 2 && $(grep -c "  read   " <<<"$out") == 2 && "$out" == *"  value  "* ]] \
  && ok "refs finds both writes, both reads and the address taken of a 32-bit table, from the code bytes" || bad "refs on mixer32.dll" "$out"
sw=$("$PYTHON" -c "import pefile;p=pefile.PE('$B/mixer32.dll');print(hex(p.OPTIONAL_HEADER.ImageBase+[e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols if e.name==b'swap_order@8'][0]))")
printf '%s\t4\tswap_head\t\n' "${sw#0x}" > "$B/refs-functions.tsv"
expect "refs marks a hit outside every function the export knows" "(no function)" "$PYTHON" tools/triage/refs.py $B/mixer32.dll "$ot" --functions "$B/refs-functions.tsv"
expect "refs finds a RIP-relative reference in 64-bit code" "lea " "$PYTHON" tools/triage/refs.py $B/game.exe "$table"

echo "Input inside Wine (tools/live/winput)"
if command -v zig >/dev/null; then
  WI="$(mktemp -d)"
  "$PYTHON" tools/live/winput.py build --out "$WI/winput.exe" >/dev/null && "$PYTHON" tools/live/winput.py host --out "$WI/winput-host" >/dev/null
  expect "winput builds as a 32-bit Windows program that calls SendInput" "SendInput" "$PYTHON" tools/pe/peinfo.py "$WI/winput.exe" --imports
  expect "peinfo --imports names each imported function" "EnumWindows" "$PYTHON" tools/pe/peinfo.py "$WI/winput.exe" --imports
  expect "winput sends arrows as extended scancodes" "key down scancode 0x50 extended down" "$WI/winput-host" --dry-run key down:10
  expect "winput types capitals with shift, and other characters as Unicode" $'key shift scancode 0x2a down\nkey a scancode 0x1e down' "$WI/winput-host" --dry-run type "Aé"
  expect "winput types a character outside ASCII as one code point" "unicode U+00E9" "$WI/winput-host" --dry-run type "é"
  expect "winput runs its steps in order" $'window POD\nmove 5 -3\nclick 10 20 right\nwait 5' "$WI/winput-host" --dry-run window POD move 5 -3 click 10 20 right wait 5
  expect "winput refuses an unknown key" "rc 2" sh -c "'$WI/winput-host' --dry-run key nope 2>/dev/null; echo rc \$?"
  expect "winput.py lists the key names" "enter" "$PYTHON" tools/live/winput.py keys
  expect "winput releases a key that down holds when it ends" "key left scancode 0x4b extended up" "$WI/winput-host" --dry-run down left wait 1
  expect "winput points, then presses where the cursor is" $'point 10 20\nwait 5\nbutton right' "$WI/winput-host" --dry-run point 10 20 wait 5 button right
  expect "winput --hold sets how long a key is held" $'down\nwait 500' "$WI/winput-host" --dry-run --hold 500 key enter
  rm -rf "$WI"
else
  echo "  skip  winput (needs zig)"
fi

out="$("$PYTHON" - <<'PY' 2>&1
import json, os, struct, subprocess, sys, tempfile, time
d = tempfile.mkdtemp(); pd = f'{d}/4242'; os.makedirs(pd)
open(f'{pd}/cmdline', 'wb').write(b'C:\\GAME\\GAME.EXE\0-window\0')
# The shell and the launcher that started the game come first, and name it too: --name must
# still find the game's own process (they have no memory to read).
for pid, argv in ((100, [b'bash', b'-c', b'wine C:\\GAME\\GAME.EXE -window']), (200, [b'wine', b'C:\\GAME\\GAME.EXE', b'-window'])):
    os.makedirs(f'{d}/{pid}'); open(f'{d}/{pid}/cmdline', 'wb').write(b'\0'.join(argv) + b'\0')
sys.path.insert(0, 'tools/live'); import memrec
assert memrec.find(d, 'GAME.EXE') == 4242, memrec.find(d, 'GAME.EXE')
open(f'{pd}/maps', 'w').write('00400000-00401000 r-xp 00000000 00:00 0 GAME.EXE\n00500000-00502000 rw-p 00000000 00:00 0 [heap]\n')
mem = f'{pd}/mem'
with open(mem, 'wb') as f:
    f.truncate(0x502000)
def put(addr, fmt, *v):
    with open(mem, 'r+b') as f:
        f.seek(addr); f.write(struct.pack(fmt, *v))
put(0x500100, '<I', 0); put(0x500200, '<iii', 10, 20, 30)
spec = f'{d}/spec.txt'; open(spec, 'w').write('# test\nclock 0x500100 u32\nxs 0x500200 i32 3\n')
writer = subprocess.Popen([sys.executable, '-c', f'''
import struct, time
def put(a, fmt, *v):
    with open({mem!r}, "r+b") as f: f.seek(a); f.write(struct.pack(fmt, *v))
time.sleep(0.4); put(0x500300, "<I", 2)
for i in range(1, 40):
    put(0x500100, "<I", i * 100); put(0x500200, "<iii", 10 + i, 20, 30 - i); time.sleep(0.02)
'''])
M = 'tools/live/memrec.py'
r = subprocess.run([sys.executable, M, 'record', spec, '--name', 'GAME.EXE', '--proc', d, '--rate', '20', '--seconds', '0.4', '--wait', '0x500300=2'], capture_output=True, text=True, timeout=20)
writer.wait()
rows = [json.loads(l) for l in r.stdout.splitlines()]
assert len(rows) >= 4, (r.stdout, r.stderr)
assert all(isinstance(x['xs'], list) and len(x['xs']) == 3 and x['xs'][1] == 20 for x in rows)
assert rows[-1]['clock'] >= rows[0]['clock'] and rows[-1]['clock'] > 0, rows
assert all(-1 <= x['xs'][0] - 10 - x['clock'] // 100 <= 2 for x in rows), rows   # a sample may straddle writer steps, either way
r = subprocess.run([sys.executable, M, 'snap', '--pid', '4242', '--proc', d, '--out', f'{d}/snap'], capture_output=True, text=True)
data = open(f'{d}/snap/0x500000.bin', 'rb').read()
assert len(data) == 0x2000 and struct.unpack_from('<I', data, 0x100)[0] == 3900 and not os.path.exists(f'{d}/snap/0x400000.bin'), r.stdout
r = subprocess.run([sys.executable, M, 'read', '--pid', '4242', '--proc', d, '0x500200', 'i32', '3'], capture_output=True, text=True)
assert r.stdout.strip() == '[49, 20, -9]', r.stdout
print('record with --wait and arrays, snap of writable mappings, read')
PY
)"
[[ $? == 0 ]] && ok "memrec records named values and arrays after --wait, snaps writable mappings and reads a value ($out)" || bad "memrec" "$out"
T2="$(mktemp -d)"; printf 'PNG' > "$T2/a.png"
for n in 1 2; do "$PYTHON" tools/live/shot.py s3-error --from "$T2/a.png" --text "S3DTK Error : SetState" --dir "$T2/c" >/dev/null; done
[[ $(ls "$T2"/c/*/ | tr '\n' ' ') == "s3-error-2.png s3-error-2.txt s3-error.png s3-error.txt " && "$(cat "$T2"/c/*/s3-error.txt)" == "S3DTK Error : SetState" ]] \
  && ok "shot keeps each capture under a new name with its text, never overwriting" || bad "shot" "$(ls -R "$T2/c")"
mkdir -p "$T2/mod/Data/Binary/Cars" "$T2/inst/Data"; echo a > "$T2/mod/Data/Binary/Cars/CAR.BIN"; echo own > "$T2/inst/Data/OWN.BIN"
"$PYTHON" tools/live/modfolder.py install "$T2/mod" "$T2/inst" >/dev/null
rm "$T2/mod/Data/Binary/Cars/CAR.BIN"; mkdir -p "$T2/mod/Data/Text"; echo b > "$T2/mod/Data/Text/T.BIN"
"$PYTHON" tools/live/modfolder.py install "$T2/mod" "$T2/inst" >/dev/null
after="$(cd "$T2/inst" && find . -type f | sort | tr '\n' ' ')"
"$PYTHON" tools/live/modfolder.py clear "$T2/inst" >/dev/null
cleared="$(cd "$T2/inst" && find . | sort | tr '\n' ' ')"
[[ "$after" == "./.gameframe-mod.json ./Data/OWN.BIN ./Data/Text/T.BIN " && "$cleared" == ". ./Data ./Data/OWN.BIN " ]] \
  && ok "modfolder replaces an earlier mod with no stale file, and clear leaves only the game's own" || bad "modfolder" "$after | $cleared"
echo own > "$T2/mod/Data/OWN.BIN"
expect "modfolder refuses to replace the game's own file" "the game's own" "$PYTHON" tools/live/modfolder.py install "$T2/mod" "$T2/inst"
echo "ssh-ed25519 AAAAtest me@example" > "$T2/k.pub"; touch "$T2/img.qcow2" "$T2/disc.iso"
free_port="$("$PYTHON" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
"$PYTHON" tools/live/emupc.py init "$T2/vm" --image "$T2/img.qcow2" --key "$T2/k.pub" --disc "$T2/disc.iso" --ssh-port "$free_port" >/dev/null
bash -n "$T2/vm/start.sh" && grep -q "IdentitiesOnly yes" "$T2/vm/ssh_config" && grep -q "disc.iso,media=cdrom" "$T2/vm/start.sh" \
  && grep -q "wine32:i386" "$T2/vm/cloud-init/user-data" && grep -q "openbox" "$T2/vm/cloud-init/user-data" && grep -q "ssh-ed25519 AAAAtest" "$T2/vm/cloud-init/user-data" \
  && ok "emupc writes cloud-init, an SSH config with IdentitiesOnly, and a QEMU start script with the disc as a CD-ROM" || bad "emupc init" "$(ls -R "$T2/vm")"
out="$(GAMEFRAME_PROJECT=/x/My_Game "$PYTHON" - "$T2" <<'PY'
import socket, subprocess, sys
t = sys.argv[1]
s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen(1); port = s.getsockname()[1]
r = subprocess.run([sys.executable, 'tools/live/emupc.py', 'init', t + '/vm2', '--image', t + '/img.qcow2',
                    '--key', t + '/k.pub', '--ssh-port', str(port)], capture_output=True, text=True)
print('refused' if r.returncode and 'in use' in r.stderr else 'accepted', r.stderr.strip())
s.close()
r = subprocess.run([sys.executable, 'tools/live/emupc.py', 'init', t + '/vm3', '--image', t + '/img.qcow2',
                    '--key', t + '/k.pub', '--ssh-port', str(port)], capture_output=True, text=True)
print('name', open(t + '/vm3/cloud-init/meta-data').read().split()[1])
PY
)"
[[ "$out" == refused*"name gf-vm-my-game"* ]] && ok "emupc refuses another VM's port and names the VM after the project" || bad "emupc port and name" "$out"
rm -rf "$T2"

T3="$(mktemp -d)"
"$PYTHON" -c "
import json, math, sys
with open(sys.argv[1], 'w') as f:
    for n in range(150):
        a = 2 * math.pi * n / 100
        f.write(json.dumps({'t': n / 10, 'n': n, 'x': [int(1000 * math.cos(a)), 5], 'y': int(1000 * math.sin(a)), 'clock': n * 6553}) + '\n')
" "$T3/rec.jsonl"
expect "loopcut cuts a recording of one and a half laps at its first return to the start" "kept 100 of 150 samples" "$PYTHON" tools/live/loopcut.py "$T3/rec.jsonl" --x x --y y
head -60 "$T3/rec.jsonl" > "$T3/short.jsonl"
expect "loopcut refuses a recording shorter than a lap" "record more than a loop" "$PYTHON" tools/live/loopcut.py "$T3/short.jsonl" --x x --y y
expect "memlog summarises a recording: rate, ranges and changes" "x[1]                 int    5 .. 5   0 changes" "$PYTHON" tools/live/memlog.py summary "$T3/rec.jsonl"
expect "memlog writes CSV with arrays split and 16.16 values as decimals" $'t,n,x[0],x[1],clock\n0.0,0,1000,5,0.000000\n0.1,1,998,5,0.099991' "$PYTHON" tools/live/memlog.py csv "$T3/rec.jsonl" --fields x,clock --fixed clock
"$PYTHON" tools/live/emulock.py take gf-vm --who a --why "recording a race" --dir "$T3/L" >/dev/null
expect "emulock refuses a second holder and names the first" 'held by a since' "$PYTHON" tools/live/emulock.py take gf-vm --who b --why mods --dir "$T3/L"
"$PYTHON" tools/live/emulock.py free gf-vm --who b --dir "$T3/L" >/dev/null 2>&1; rc=$?
"$PYTHON" tools/live/emulock.py free gf-vm --who a --dir "$T3/L" >/dev/null
[[ $rc == 1 ]] && "$PYTHON" tools/live/emulock.py take gf-vm --who b --why mods --dir "$T3/L" >/dev/null \
  && ok "emulock lets only the holder free a lock, then the next one take it" || bad "emulock free and take"
fakestub() { # LOG [flags]: start the fake GDB stub in the background, print its port
  mkfifo "$T3/port.$$"; "$PYTHON" tests/fixtures/gdbstub_fake.py "$@" > "$T3/port.$$" & read -r port < "$T3/port.$$"; rm "$T3/port.$$"; echo "$port"
}
port=$(fakestub "$T3/s1.log")
expect "winegdb reads memory through a GDB stub" "4d 5a 90 00" "$PYTHON" tools/live/winegdb.py read --connect "127.0.0.1:$port" 0x140000000 4
port=$(fakestub "$T3/s2.log" --hit --no-z0)
expect "winegdb waits at an int3 it writes itself when Z0 is refused, with rip moved back" "hit=1 pc=0x140001000" "$PYTHON" tools/live/winegdb.py break --connect "127.0.0.1:$port" 0x140001000 --timeout 5
grep -qx 'M140001000,1:cc' "$T3/s2.log" && [[ $(grep -c '^G' "$T3/s2.log") == 1 && $(tail -2 "$T3/s2.log" | head -1) == M140001000,1:48 && $(tail -1 "$T3/s2.log") == D ]] \
  && ok "winegdb puts the original byte back and detaches after a hit" || bad "winegdb after a hit" "$(cat "$T3/s2.log")"
port=$(fakestub "$T3/s3.log")
expect "winegdb gives up on a breakpoint that is never hit" "no hit within 1.0 s" "$PYTHON" tools/live/winegdb.py break --connect "127.0.0.1:$port" 0x140001000 --timeout 1
grep -qxF '^C' "$T3/s3.log" && grep -qx 'z0,140001000,1' "$T3/s3.log" && [[ $(tail -1 "$T3/s3.log") == D ]] \
  && ok "winegdb stops the program, removes the breakpoint and detaches after a timeout" || bad "winegdb after a timeout" "$(cat "$T3/s3.log")"
port=$(fakestub "$T3/s4.log")
"$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/live')
from gdbremote import Remote
with Remote.connect('127.0.0.1', $port, hw_per_thread=True) as r:
    r.set_breakpoint(0x140001000, kind=1)
" && [[ $(grep -c '^Z1,140001000' "$T3/s4.log") == 2 && $(grep -c '^z1,140001000' "$T3/s4.log") == 2 ]] && grep -qx 'Hg02' "$T3/s4.log" \
  && ok "gdbremote sets and clears a hardware breakpoint in every thread for winedbg" || bad "gdbremote per-thread breakpoints" "$(cat "$T3/s4.log")"

echo "Installing builds"
TI="$(cd "$(mktemp -d)" && pwd -P)"; cp -R tests/fixtures/install-project "$TI/p"
inst() { python3 tools/install/install_app.py --project "$TI/p" --data-root "$TI/data" --no-menu "$@"; }
inst extra --dest "$TI/mac" --system macos >/dev/null 2>&1
[[ "$(python3 -c 'import plistlib,sys;d=plistlib.load(open(sys.argv[1],"rb"));print(d["CFBundleExecutable"],d["CFBundleShortVersionString"])' "$TI/mac/Fixture Game.app/Contents/Info.plist")" == "gameframe-start 1.2.3" \
   && -x "$TI/mac/Fixture Game.app/Contents/MacOS/helper" && -f "$TI/mac/Fixture Game Extra.app/Contents/Resources/library.json" ]] \
  && ok "install writes NAME.app and NAME Extra.app with the programs, resources and Info.plist" || bad "install's macOS bundles" "$(ls -R "$TI/mac")"
expect "install's start script runs the program in its data folder with {data}, {resources} and the player's arguments" \
  "vanilla cwd=$TI/data/Fixture Game args=--data $TI/data/Fixture Game --look $TI/mac/Fixture Game.app/Contents/Resources/library.json --frame" \
  "$TI/mac/Fixture Game.app/Contents/MacOS/gameframe-start" --frame
expect "install's extra build is the extra program, with its own data folder" "extra cwd=$TI/data/Fixture Game Extra" "$TI/mac/Fixture Game Extra.app/Contents/MacOS/gameframe-start"
echo keep > "$TI/data/Fixture Game/save.dat"
inst --dest "$TI/mac" --system macos >/dev/null 2>&1 && [[ -f "$TI/data/Fixture Game/save.dat" && ! -e "$TI/mac/.Fixture Game.app.new" ]] \
  && ok "install replaces its own build and keeps the data" || bad "install over its own build"
mkdir -p "$TI/other/Fixture Game.app"
expect "install refuses to replace a folder it did not install" "was not installed by this command" inst --dest "$TI/other" --system macos --no-build
expect "install --list names the installed builds" "extra    Fixture Game Extra" python3 tools/install/install_app.py --list --dest "$TI/mac"
inst --dest "$TI/lin" --system linux >/dev/null 2>&1
expect "install writes a Linux folder with a start script and a .desktop entry" "vanilla cwd=$TI/data/Fixture Game args=--data $TI/data/Fixture Game --look $TI/lin/Fixture Game/library.json" "$TI/lin/Fixture Game/start"
grep -qx "Exec=\"$TI/lin/Fixture Game/start\"" "$TI/lin/Fixture Game/fixture-game.desktop" && ok "install's .desktop entry starts the start script" || bad "install's .desktop entry" "$(cat "$TI/lin/Fixture Game/fixture-game.desktop")"
inst --dest "$TI/win" --system windows --no-build >/dev/null 2>&1
expect "install writes a Windows batch file that starts the program in its data folder" '"%~dp0game" "--data" "%data%" "--look" "%~dp0./library.json" %*' cat "$TI/win/Fixture Game/Fixture Game.cmd"
expect "install --dry-run prints the build commands and changes nothing" "would install vanilla" inst --dest "$TI/dry" --system macos --dry-run
[[ ! -e "$TI/dry" ]] || bad "install --dry-run made $TI/dry"
rm -rf "$TI"
rm -rf "$T3"

T4="$(mktemp -d)"
"$PYTHON" - "$T4/rec.jsonl" <<'PY'
import json, random, sys
sys.path.insert(0, 'tools/formats')
from derived import newell
r = random.Random(7); out = open(sys.argv[1], 'w')
for k in range(200):
    x, y, z = r.uniform(-2000, 2000), r.uniform(-2000, 2000), r.uniform(0, 80)
    q = [[x, y, z], [x + 40, y, z + r.uniform(-1, 1) * (k % 4 == 0)], [x + 40, y + 30, z + 5], [x, y + 30, z + 5]]
    q = [[round(c * 65536) / 65536 for c in v] for v in q]
    vs = [[round(c * 65536) for c in v] for v in q]
    n = newell(q)
    fields = [min(v[i] for v in vs) for i in range(3)] + [max(v[i] for v in vs) for i in range(3)]
    fields += [round(c * 65536) for c in n] + [r.randrange(1 << 30)]
    out.write(json.dumps({'vertices': vs, 'fields': fields}) + '\n')
PY
out="$("$PYTHON" tools/formats/derived.py "$T4/rec.jsonl" --field-scale 65536 --vertex-scale 65536)"
[[ "$out" == *"field 0   min_x           100.0 %"* && "$out" == *"field 5   max_z           100.0 %"* && "$out" == *"field 8   newell_z        100.0 %"* && "$out" == *"field 9   nothing explains it"* ]] \
  && ok "derived finds stored bounds and Newell normals, and nothing for noise" || bad "derived" "$out"
if command -v cargo >/dev/null && rustup target list --installed 2>/dev/null | grep -q i686-pc-windows-gnu && command -v zig >/dev/null; then
  mkdir -p "$T4/crate/src"
  printf '[package]\nname = "probe"\nversion = "0.1.0"\nedition = "2021"\n\n[lib]\ncrate-type = ["cdylib"]\n\n[profile.release]\npanic = "abort"\n' > "$T4/crate/Cargo.toml"
  printf '#[no_mangle]\npub extern "stdcall" fn answer() -> u32 { 42 }\n\n#[no_mangle]\npub extern "C" fn plain(x: u32) -> u32 { x + 1 }\n' > "$T4/crate/src/lib.rs"
  printf 'LIBRARY probe.dll\nEXPORTS\n_answer@0=answer@0\nplain\n' > "$T4/crate/probe.def"
  (cd "$T4/crate" && CARGO_TARGET_I686_PC_WINDOWS_GNU_LINKER="$ROOT/scripts/zcc.sh" ZCC_DEF_DIR="$T4/crate" cargo build -q --release --target i686-pc-windows-gnu --target-dir "$T4/build" >/dev/null 2>&1)
  expect "zcc links a 32-bit Rust DLL with zig that exports the .def's names, and its stdcall export runs" "['_answer@0', 'plain'] 42" "$PYTHON" -c "
import sys, pefile; sys.path.insert(0, 'tools/emu')
from pe32_emu import Emu32
d = '$T4/build/i686-pc-windows-gnu/release/probe.dll'; p = pefile.PE(d)
ex = {e.name.decode(): p.OPTIONAL_HEADER.ImageBase + e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols}
print(sorted(ex), Emu32(d).call(ex['_answer@0'])['eax'])"
else
  echo "  skip  zcc (needs cargo, rustup target i686-pc-windows-gnu and zig)"
fi
expect "zcc prints its usage" "rustc's linker for 32-bit Windows DLLs" scripts/zcc.sh --help
rm -rf "$T4"

out="$("$PYTHON" - <<'PY' 2>&1
import os, shutil, struct, subprocess, sys, tempfile
d = tempfile.mkdtemp(); A, B = f'{d}/old', f'{d}/new'
def put(root, rel, data):
    p = os.path.join(root, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'wb').write(data)
exe = open('examples/sample-game/build/game.exe', 'rb').read()
off = struct.unpack_from('<I', exe, 0x3c)[0]
old_exe = exe[:off + 8] + struct.pack('<I', 857692800) + exe[off + 12:]     # 1997-03-07
new_exe = exe[:off + 8] + struct.pack('<I', 877910400) + exe[off + 12:]     # 1997-10-27
put(A, 'GAME.EXE', old_exe); put(B, 'game.exe', new_exe)
put(A, 'Data/Text/French/T.DAT', b'bonjour'); put(B, 'DATA/TEXT/FRENCH/T.DAT', b'bonjour')
put(B, 'Data/Text/English/T.DAT', b'hello')
put(A, 'Data/Cars.bin', b'x' * 10); put(B, 'Data/Cars.bin', b'x' * 12)
put(B, 'Data/Tracks/Lake.bl4', b't' * 5); put(A, 'Data/Old.brt', b'r')
r = subprocess.run([sys.executable, 'tools/triage/versiondiff.py', A, B], capture_output=True, text=True)
out = r.stdout.lower()     # folder names keep whichever case the file system gave
for want in ('2 added, 1 removed, 2 changed, 1 the same', '| `data/tracks` | 1 | 0 | 0 | 0 |', '| `data` | 0 | 1 | 1 | 0 |',
             '| `game.exe` | 1997-03-07 00:00 | 1997-10-27 00:00 | yes |', '| english |  | yes |', '| french | yes | yes |',
             '- `data/cars.bin` (10 -> 12 bytes)', '- `data/old.brt` (1 byte)'):
    assert want in out, (want, out)
print('folders by group, link dates, languages, added, removed and changed')
PY
)"
[[ $? == 0 ]] && ok "versiondiff writes the data delta of two editions: folders, link dates, languages ($out)" || bad "versiondiff" "$out"

echo "Live tracing"
if "$PYTHON" -c "import frida" 2>/dev/null && command -v cc >/dev/null; then
  T="$(mktemp -d)"
  printf '%s\n' '__attribute__((noinline)) int draw(int *s, int r) { *s = *s * 1103515245 + 12345; return (unsigned)(*s >> 16) % r; }' \
    '__attribute__((noinline)) int spawn(int *s) { return draw(s, 10) + draw(s, 20); }' \
    'int main(void) { int s = 7, t = 0; for (int i = 0; i < 3; i++) t += spawn(&s) + draw(&s, 5); return t == 0; }' > "$T/target.c"
  cc -O1 -o "$T/target" "$T/target.c"
  expect "frida_trace logs outermost calls with their call sites" "draw(" "$PYTHON" tools/live/frida_trace.py \
    --hook 'target!draw' --hook 'target!spawn' --args 2 --spawn "$T/target"
  printf '%s\n' '#include <unistd.h>' 'volatile int table[65536];' \
    '__attribute__((noinline)) int touch(int i) { table[i] += 1; return table[i]; }' \
    'int main(void) { int t = 0; for (int i = 0; i < 3; i++) { usleep(100000); t += touch(i * 4); } return t == 0; }' > "$T/watch.c"
  cc -O1 -o "$T/watch" "$T/watch.c"
  expect "frida_trace logs each access to watched memory" "table:r+0x20" "$PYTHON" tools/live/frida_trace.py \
    --watch 'watch!table:262144=table' --spawn "$T/watch"
else
  echo "  skip  live tracing (run: scripts/setup.sh --install for Frida; needs a C compiler)"
fi

echo "Emulator"
expect "RNG matches MSVC rand() from seed 1" "[41, 18467, 6334]" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
emu = Emu('examples/sample-game/build/game.exe', ['examples/sample-game/build/engine.dll'])
r = emu.malloc(4); emu.call(emu.export('engine.dll', 'rng_seed'), r, 1)
print([emu.call(emu.export('engine.dll', 'rng_next'), r) for _ in range(3)])
PY
expect "mem_trace lists the loader's reads of the file buffer" "('file', 'r', 0, 1, 'game.exe+0x" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
from mem_trace import MemTrace
emu = Emu('examples/sample-game/build/game.exe', ['examples/sample-game/build/engine.dll'])
data = open('examples/sample-game/build/sample.dat', 'rb').read(); w = emu.malloc(64); buf = emu.bytes_in(data)
t = MemTrace(emu, [(buf, len(data), 'file')])
emu.call_i32(emu.export('game.exe', 'load_records'), buf, len(data), w)
print(t.log[0])
PY
expect "mem_trace follows the file through registers into the records" "marked records 3" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
from mem_trace import MemTrace
emu = Emu('examples/sample-game/build/game.exe', ['examples/sample-game/build/engine.dll'])
data = open('examples/sample-game/build/sample.dat', 'rb').read(); w = emu.malloc(64); buf = emu.bytes_in(data)
t = MemTrace(emu, [(buf, len(data), 'file')], registers=True)
emu.call_i32(emu.export('game.exe', 'load_records'), buf, len(data), w)
t.reg_log()
print('marked records', sum(1 for a, _, _ in t.regions if w <= a < w + 64))
PY
expect "data loader runs on emulated memory" "3 (0.5, 1.25, 2.0)" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
emu = Emu('examples/sample-game/build/game.exe', ['examples/sample-game/build/engine.dll'])
data = open('examples/sample-game/build/sample.dat', 'rb').read(); w = emu.malloc(64)
n = emu.call_i32(emu.export('game.exe', 'load_records'), emu.bytes_in(data), len(data), w)
print(n, emu.f32s(w, 3))
PY
cp $B/engine.dll $B/copy.dll
expect "overlapping DLLs are relocated" "relocated True" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
b = 'examples/sample-game/build/'
emu = Emu(b + 'game.exe', [b + 'engine.dll', b + 'copy.dll'])
m = emu.module('copy.dll'); r = emu.malloc(4)
emu.call(emu.export('copy.dll', 'rng_seed'), r, 1)
ok = emu.call(emu.export('copy.dll', 'rng_next'), r) == 41
print('relocated', m.base != m.preferred and ok)
PY
expect "an unhandled import names itself" "unhandled import" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from pe_emu import Emu
b = 'examples/sample-game/build/'
emu = Emu(b + 'game.exe', [b + 'engine.dll'], stubs={'malloc': None})
try:
    emu.call(emu.export('engine.dll', 'mem_alloc'), 16)
except RuntimeError as e:
    print(e)
PY

expect "pe32_emu runs MMX machine code given its registers" "(32767, -32768, 12, 0)" "$PYTHON" - <<'PY'
import struct, sys; sys.path.insert(0, 'tools/emu')
from pe32_emu import Emu32
emu = Emu32.raw(bytes.fromhex('0f6f06' '0fed07' '0f7f06' '0f77' 'c3'))  # movq, paddsw, movq, emms, ret
a, b = emu.alloc(8), emu.alloc(8)
emu.write(a, struct.pack('<4h', 32000, -32000, 5, -1)); emu.write(b, struct.pack('<4h', 1000, -1000, 7, 1))
emu.call(0x401000, esi=a, edi=b); print(struct.unpack('<4h', emu.read(a, 8)))
PY
expect "pe32_emu calls a 32-bit DLL's stdcall export and stubs its imports" "(32767, -32768, 16383, 1) 47 KERNEL32.dll!GetTickCount, which has no handler" "$PYTHON" - <<'PY'
import struct, sys, pefile; sys.path.insert(0, 'tools/emu')
from pe32_emu import Emu32, EmuError
path = 'examples/sample-game/build/mixer32.dll'
p = pefile.PE(path); ex = {e.name.decode().split('@')[0]: p.OPTIONAL_HEADER.ImageBase + e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols}
emu = Emu32(path, stubs={'GetTickCount': lambda e: 0x105})
o, i = emu.alloc(8), emu.alloc(8)
emu.write(o, struct.pack('<4h', 32000, 0, 0, 0)); emu.write(i, struct.pack('<4h', 32767, -32768, 16384, 2))
emu.call(ex['mix4'], args=[o, i, 0xffff]); got = struct.unpack('<4h', emu.read(o, 8))
ticks = emu.call(ex['add_ticks'], args=[40, 2])['eax']
try:
    Emu32(path).call(ex['add_ticks'], args=[1, 2]); msg = 'no stop'
except EmuError as e:
    msg = str(e).split('called ')[1]
print(got, ticks, msg)
PY
expect "pe32_emu zeroes a section with no file data and starts the x87 at 0x037f, as Windows does" "bss zero True, header bytes False; cw 0x37f 0x37f" "$PYTHON" - <<'PY'
import os, shutil, struct, sys, tempfile, pefile; sys.path.insert(0, 'tools/emu')
from pe32_emu import Emu32
# A copy of the sample DLL whose .tls section claims file pointer 0, as Watcom's .bss does.
d = tempfile.mkdtemp(); path = os.path.join(d, 'bss.dll')
shutil.copy('examples/sample-game/build/mixer32.dll', path)
pe = pefile.PE(path)
s = [x for x in pe.sections if x.Name.rstrip(b'\0') == b'.tls'][0]
s.PointerToRawData, s.Misc_VirtualSize = 0, 0
pe.write(path); pe.close()
emu = Emu32(path)
at = emu.base + s.VirtualAddress; got = emu.read(at, s.SizeOfRawData)
# fstcw [esp-4]; mov ax, [esp-4]; ret: the control word the code sees at start, and after reset().
raw = Emu32.raw(bytes.fromhex('d97c24fc668b4424fcc3'))
first = raw.call(0x401000)['eax'] & 0xffff
raw.reset(); again = raw.call(0x401000)['eax'] & 0xffff
print(f'bss zero {got == bytes(len(got))}, header bytes {got[:2] == b"MZ"}; cw {first:#x} {again:#x}')
shutil.rmtree(d)
PY
expect "pe32_emu prints its usage with no arguments" "registers in" "$PYTHON" tools/emu/pe32_emu.py
if command -v zig >/dev/null; then
  P="$(mktemp -d)"
  # A program that imports a card library as 1990s games do: a decorated stdcall name, a plain
  # one, and an undecorated stdcall one (as S3D's). Its import library comes from a .def.
  printf 'LIBRARY card.dll\nEXPORTS\n  _cardDraw@12\n  cardInit\n  S3DTK_Flip\n' > "$P/imp.def"
  cat > "$P/game.c" <<'EOF'
extern unsigned card_draw(unsigned, unsigned, unsigned) __asm__("__cardDraw@12");
extern unsigned card_init(void) __asm__("_cardInit");
extern unsigned card_flip(unsigned) __asm__("_S3DTK_Flip");
int main(void) { card_init(); card_flip(9); return (int)card_draw(1, 2, 3); }
EOF
  (cd "$P" && zig dlltool -m i386 -d imp.def -l cardimp.lib && zig cc -target x86-windows-gnu -O1 game.c cardimp.lib -o game.exe) >/dev/null 2>&1
  "$PYTHON" tools/pe/probegen.py "$P/game.exe" card.dll "$P/out" --stdcall S3DTK_Flip=4 >/dev/null 2>&1 && sh "$P/out/build.sh" >/dev/null 2>&1
  expect "probegen writes a probe that exports the imported names, logs each call's arguments and keeps the stack" \
    "['S3DTK_Flip', '_cardDraw@12', 'cardInit'] one stack | _cardDraw@12 0x00000001 0x00000002 0x00000003 | cardInit 0x00000000 0x00000000 0x00000000 0x00000000 | S3DTK_Flip 0x00001234" \
    "$PYTHON" - "$P/out/card.dll" <<'PY'
import sys, pefile; sys.path.insert(0, 'tools/emu')
from pe32_emu import Emu32
pe = pefile.PE(sys.argv[1])
ex = {e.name.decode(): pe.OPTIONAL_HEADER.ImageBase + e.address for e in pe.DIRECTORY_ENTRY_EXPORT.symbols}
log = []
def write(e):
    log.append(e.read(e.arg(1), e.arg(2)).decode().strip()); return 1
emu = Emu32(sys.argv[1], stubs={'CreateFileA': (lambda e: 0x77, 28), 'WriteFile': (write, 20)})
sps = {emu.call(ex[n], args=a)['esp'] for n, a in (('_cardDraw@12', [1, 2, 3]), ('cardInit', []), ('S3DTK_Flip', [0x1234]))}
print(sorted(ex), 'one stack' if len(sps) == 1 else f'stacks {sps}', '|', ' | '.join(log))
PY
  rm -rf "$P"
else
  echo "  skip  probegen (needs zig)"
fi
if command -v zig >/dev/null; then
  A="$(mktemp -d)"
  zig cc -target x86-windows-gnu -O1 -shared tests/fixtures/apitable/api.c tests/fixtures/apitable/api.def -o "$A/api.dll" >/dev/null 2>&1
  expect "apitable reads each export's convention and argument bytes from the code, with the header's parameters and returns" \
    "_decorated@8 stdcall 8 2 int name+ret|nothing cdecl 0 0 void ret|plain_c cdecl 0 2 int ret|plain_std stdcall 12 3 int ret|ratio cdecl 0 1 float ret|table_data data 0 - - -" \
    sh -c "'$PYTHON' tools/pe/apitable.py '$A/api.dll' --header tests/fixtures/apitable/api.h | sed 1d | cut -f2,4-8 | tr '\t' ' ' | paste -sd'|' -"
  printf 'LIBRARY api.dll\nEXPORTS\ndecorated@8\nplain_std@12\n' > "$A/imp.def"
  zig dlltool -d "$A/imp.def" -l "$A/imp.lib" -m i386 >/dev/null 2>&1
  expect "apitable reads the stdcall names of an import library" "_decorated@8 stdcall 8 2 lib|_plain_std@12 stdcall 12 3 lib" \
    sh -c "'$PYTHON' tools/pe/apitable.py '$A/imp.lib' --header tests/fixtures/apitable/api.h | sed 1d | cut -f2,4,5,6,8 | tr '\t' ' ' | paste -sd'|' -"
  rm -rf "$A"
else
  echo "  skip  apitable (needs zig)"
fi
expect "apitable prints its usage" "Write the API table of a 32-bit Windows DLL" "$PYTHON" tools/pe/apitable.py --help
expect "probegen prints its usage" "probegen.py GAME.EXE DLL OUT_DIR" "$PYTHON" tools/pe/probegen.py
expect "pe32_emu loads an FPU control word: a magic-number add rounds to nearest, or truncates" "nearest 4, chop 3; 103 of 200 cases differ; whole multiples none" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
import pefile
from pe32_emu import Emu32, NEAREST, CHOP
D = 'examples/sample-game/build/mixer32.dll'
p = pefile.PE(D); ex = {e.name.decode(): p.OPTIONAL_HEADER.ImageBase + e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols}
e = Emu32(D); f = ex['fix_mul']; v = 3 * 65536 + 40000
a, b = e.call(f, args=[v, 1], fpu_cw=NEAREST)['eax'], e.call(f, args=[v, 1], fpu_cw=CHOP)['eax']
d = e.fpu_modes(f, [[k * 1000 + 7, 13] for k in range(200)])
none = e.fpu_modes(f, [[65536 * k, 3] for k in range(1, 50)])
print(f'nearest {a}, chop {b}; {len(d)} of 200 cases differ; whole multiples {"none" if not none else len(none)}')
PY
expect "pe32_emu lays out a linked list and a graph of records for a function to walk" "42 111" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
import pefile
from pe32_emu import Emu32
D = 'examples/sample-game/build/mixer32.dll'
p = pefile.PE(D); ex = {e.name.decode(): p.OPTIONAL_HEADER.ImageBase + e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols}
e = Emu32(D)
n = e.array(3, 8)
for i, (v, nx) in enumerate([(5, n[1]), (7, n[2]), (30, 0)]):
    e.put(n[i], 'iI', v, nx)
g = e.array(4, 12)
e.put(g[0], 'iII', 1, g[1], g[2]); e.put(g[1], 'iII', 10, g[3], 0); e.put(g[2], 'iII', 4, 0, 0); e.put(g[3], 'iII', 100, 0, 0)
print(e.call(ex['sum_list'], args=[n[0]])['eax'], e.call(ex['heaviest_path'], args=[g[0]])['eax'])
PY
expect "pe32_emu stops at a call to a library routine and reads its arguments" "[42, 5]" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
import capstone, pefile
from pe32_emu import Emu32
D = 'examples/sample-game/build/mixer32.dll'
p = pefile.PE(D); r = p.OPTIONAL_HEADER.ImageBase + [e.address for e in p.DIRECTORY_ENTRY_EXPORT.symbols if e.name == b'report'][0]
e = Emu32(D)
site = [i.address for i in capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32).disasm(e.read(r, 80), r) if i.mnemonic == 'call'][0]
print(e.call(r, args=[21, 4], until=site)['stack'][2:4])
PY
out="$("$PYTHON" - <<'PY' 2>&1
import capstone, os, pefile, subprocess, sys, tempfile
D = 'examples/sample-game/build/mixer32.dll'
p = pefile.PE(D); base = p.OPTIONAL_HEADER.ImageBase
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
rows = []
for e in p.DIRECTORY_ENTRY_EXPORT.symbols:
    name = e.name.decode()
    if name == 'order_table':
        continue
    start = base + e.address
    code = p.get_data(e.address, 0x400)
    end = start
    for i in md.disasm(code, start):
        end = i.address + i.size
        if i.mnemonic == 'ret':
            break
    rows.append((start, end - start, name))
keep = [r for r in rows if r[2] != 'reset_order']
t = tempfile.NamedTemporaryFile('w', suffix='.tsv', delete=False)
t.write(''.join(f'{s:x}\t{n}\t{name}\t\n' for s, n, name in keep)); t.close()
r = subprocess.run([sys.executable, 'tools/triage/exportcov.py', D, t.name, '--min', '0', '--starts', t.name + '.starts'],
                   capture_output=True, text=True)
missing = [r_ for r_ in rows if r_[2] == 'reset_order'][0][0]
starts = open(t.name + '.starts').read().split()
print(r.stdout)
assert hex(missing) in starts, (hex(missing), starts)
print('the function left out of functions.tsv is found as a gap and a likely start')
# bodies.tsv beside functions.tsv: a function's second piece is counted where it lies.
miss = [r_ for r_ in rows if r_[2] == 'reset_order'][0]
d = tempfile.mkdtemp()
fn, bd = os.path.join(d, 'functions.tsv'), os.path.join(d, 'bodies.tsv')
open(fn, 'w').write(''.join(f'{s:x}\t{n}\t{name}\t\n' for s, n, name in keep))
open(bd, 'w').write(''.join(f'{s:08x}\t{s + n:08x}\t{s:08x}\n' for s, n, name in keep)
                    + f'{miss[0]:08x}\t{miss[0] + miss[1]:08x}\t{keep[0][0]:08x}\n')
r = subprocess.run([sys.executable, 'tools/triage/exportcov.py', D, fn, '--min', '0', '--starts', fn + '.starts'],
                   capture_output=True, text=True)
assert 'bodies.tsv' in r.stdout, r.stdout
assert hex(miss[0]) not in open(fn + '.starts').read().split(), r.stdout
print('a piece listed in bodies.tsv is covered, not a gap')
PY
)"
[[ $? == 0 ]] && ok "exportcov measures an export's coverage, finds a function left out of it, and reads bodies.tsv" || bad "exportcov" "$out"

echo "Ground truth and the port"
"$PYTHON" $S/ground_truth.py $B/truth >/dev/null && "$PYTHON" $S/port.py $B/port >/dev/null \
  && "$PYTHON" $S/port.py --naive $B/naive >/dev/null
same=0; drift=0; draws=0
for s in $(seq 1 20); do
  "$PYTHON" tools/verify/bitcompare.py f32 $B/truth/seed-$s.f32 $B/port/seed-$s.f32 >/dev/null && same=$((same + 1))
  "$PYTHON" tools/verify/bitcompare.py f32 $B/truth/seed-$s.f32 $B/naive/seed-$s.f32 >/dev/null || drift=$((drift + 1))
  "$PYTHON" tools/verify/seqdiff.py $B/truth/seed-$s.trace $B/port/seed-$s.trace >/dev/null && draws=$((draws + 1))
done
[[ $same == 20 ]] && ok "the port matches the original bit for bit (20 seeds x 600 steps)" || bad "port matches on $same of 20 seeds"
[[ $draws == 20 ]] && ok "the port draws random numbers in the original's order (20 seeds)" || bad "draw order matches on $draws of 20 seeds"
[[ $drift == 20 ]] && ok "bitcompare catches the naive double-precision port (20 seeds)" || bad "naive port caught on only $drift of 20 seeds"
expect "call traces name the call site" "game.exe+0x" head -1 $B/truth/seed-1.trace
R="$(mktemp -d)"
"$PYTHON" - "$R" <<'PY'
import json, sys
d = sys.argv[1]
# A toy game: x moves 3 a step, (a, b) follow the clock. The recorder samples every 8 steps and
# reads the clock at one step, x one step later and the pair (a, b) two steps later.
def state(k): return {'clock': k, 'x': 3 * k, 'a': k % 7, 'b': (k * 5) % 11}
states = [state(k) for k in range(200)]
rec = [{'t': n / 10, 'n': n, 'clock': k, 'x': states[k + 1]['x'], 'a': states[k + 2]['a'], 'b': states[k + 2]['b']}
       for n, k in enumerate(range(0, 190, 8))]
bad = [dict(s, x=s['x'] + (1 if s['clock'] >= 100 else 0)) for s in states]
for name, rows in (('rec', rec), ('port', states), ('bad', bad)):
    open(f'{d}/{name}.jsonl', 'w').write(''.join(json.dumps(r) + '\n' for r in rows))
PY
out="$("$PYTHON" tools/verify/replay.py $R/rec.jsonl $R/port.jsonl --clock clock --block a,b; echo "rc $?"; "$PYTHON" tools/verify/replay.py $R/rec.jsonl $R/bad.jsonl --clock clock --block a,b; echo "rc $?")"
[[ "$out" == *"ok   a b: 24 of 24"*"ok   x: 24 of 24"*"rc 0"*"FAIL x: 13 of 24"*"recorded {'x': 315}"*"rc 1"* ]] \
  && ok "replay accepts a port on samples that straddle steps, and catches a one-unit change" || bad "replay" "$out"
expect "replay prints its usage" "replay.py RECORDING PORT_TRACE" "$PYTHON" tools/verify/replay.py
rm -rf "$R"

echo "Formats"
expect "the sample decoder consumes every byte" "1 of 1 files decode completely" "$PYTHON" tools/formats/validate.py $S/decode_sample.py "$B/*.dat"
printf 'SMPL\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x3f\x03oakEXTRA' > $B/broken.dat
expect "validate fails a file with unread bytes" "5 bytes left unread" "$PYTHON" tools/formats/validate.py $S/decode_sample.py $B/broken.dat
expect "validate --write checks that every file writes back identical" "1 of 1 files decode completely and write back identical" "$PYTHON" tools/formats/validate.py $S/decode_sample.py "$B/sample.dat" --write
VW="$(mktemp -d)"; sed 's/len(name)) + name/len(name)) + name.upper()/' $S/decode_sample.py > "$VW/lossy.py"
expect "validate --write names the first byte a writer changes" "differs at offset 0x11 (file 0x6f, written 0x4f)" "$PYTHON" tools/formats/validate.py "$VW/lossy.py" "$B/sample.dat" --write
rm -rf "$VW"
rm -f $B/broken.dat
C=$(mktemp -d)
mkdir "$C/game" && cp $B/sample.dat "$C/game/"
printf 'def decode(r):\n    r.magic(b"PIC0"); w, h = r.u16(), r.u16()\n    return (w, h, r.bytes(w * h))\ndef images(p):\n    return [("title", p[0], p[1], p[2])]\n' > "$C/pic.py"
"$PYTHON" -c "import struct,sys;open(sys.argv[1],'wb').write(b'PIC0'+struct.pack('<HH',8,4)+bytes(range(32)))" "$C/game/TITLE.PIC"
printf 'unknown bytes' > "$C/game/notes.bin"
expect "catalog decodes, counts coverage and draws a picture" "2 of 3 files decode completely" "$PYTHON" tools/formats/catalog.py "$C/game" "$C/out" --decoder "*.dat=$S/decode_sample.py" --decoder "*.pic=$C/pic.py"
[[ -f "$C/out/index.html" && "$(head -c 8 "$C/out/f0-0.png" | xxd -p)" == 89504e470d0a1a0a ]] && ok "catalog writes the page and the decoder's picture" || bad "catalog page or picture missing"
rm -rf "$C"

echo "16-bit DOS tools (examples/dos-sample)"
D=examples/dos-sample/build
python3 examples/dos-sample/make_exe.py $D >/dev/null 2>&1 && ok "DOS sample builds (zig, .code16; our own NE and MZ linker)" || bad "DOS sample builds"
expect "dosinfo reads the NE header" "NE: module 'DOSSAMPL'" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe
expect "dosinfo gives Ghidra's selector per segment" "2  1008  file" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe
expect "dosinfo lists imports by ordinal" "KERNEL.3" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe --imports
expect "dosinfo lists exports at seg:off" "1000:0028  RNG_NEXT" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe --exports
expect "dosinfo prints a Pascal string at its length byte" "1008:0010  [12] 'DOS SAMPLE 1'" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe --pstrings 5
expect "dosinfo finds a Pascal string right after another, with a printable length byte" "1008:003d  [42] 'SECOND STRING" "$PYTHON" tools/dos/dosinfo.py $D/sample.exe --pstrings 5
expect "dosinfo reads a real-mode MZ" "3 relocations" "$PYTHON" tools/dos/dosinfo.py $D/sample-mz.exe
expect "dosinfo finds Turbo Debugger symbols" "debug symbols: Turbo Debugger" "$PYTHON" tools/dos/dosinfo.py $D/sample-td.exe
expect "readseg reads a typed constant" "1008:0000  4660" "$PYTHON" tools/dos/readseg.py $D/sample.exe u32 DAT_1008_0000
expect "readseg says where a count goes" "a count goes after --count" bash -c "\"$PYTHON\" tools/dos/readseg.py $D/sample.exe hex 1008:0000 2 2>&1; true"
expect "readseg reads a Pascal string" "'DOS SAMPLE 1'" "$PYTHON" tools/dos/readseg.py $D/sample.exe pstr 1008:0010
expect "readseg decodes a Turbo Pascal Real" "[1.0, -2.5, 0.0]" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/dos')
from readseg import real48
print([real48(b) for b in (bytes([129, 0, 0, 0, 0, 0]), bytes([130, 0, 0, 0, 0, 0xA0]), bytes(6))])
PY
expect "tdinfo lists procedures with sizes and parameters" "param     [bp+6] range: Word" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe procs rng_next
expect "tdinfo lays out a record" "+0x0004  total: Word  (2)" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe types
expect "tdinfo types shows an anonymous record inside a record" "        +0x0004  y: Word  (2)" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe types spot
expect "tdinfo globals shows the fields of a variable declared as an anonymous record" "            +0x0004  y: Word  (2)" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe globals player
out="$("$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe labels)"
[[ "$out" != *host_call* && "$out" == *"1 imported procedures left out"* ]] && ok "tdinfo labels leave out imported procedures (no address in the program)" || bad "tdinfo labels and imports" "$out"
out="$("$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe procs)"
[[ "$(echo "$out" | sed -n 2p)" != *range* && "$out" == *"rng_next"$'\n'"        param     [bp+6] range"* ]] && ok "tdinfo gives a scope to the procedure in its segment (not another at the same offset)" || bad "tdinfo scope owner" "$out"
expect "tdinfo writes labels" "1008:0000	RandSeed" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe labels
expect "tdinfo maps code to source lines" "1000:0028	SAMPLE.S:11" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe lines
expect "tdinfo writes a Rust reader for a record" "seed: r.i32()?," "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe rust SampleState
expect "tdinfo writes the Rust Pascal reader and writer" "pub struct PascalWriter" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe rust-reader
expect "tdinfo writes record writers" "w.u16(self.total);" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe rust SampleState
g="$(mktemp -d)/globals"; "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe rust-globals "$g" >/dev/null
expect "tdinfo writes Globals per unit at their DS offsets" "w.seek(0x4); w.u16(self.total);" cat "$g/sample.rs"
expect "tdinfo writes a procedure's locals at their BP offsets" "[bp+6] range: Word" "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe rust-locals rng_next
expect "tdinfo joins the units into Globals" "pub sample: sample::Sample," cat "$g/mod.rs"
"$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe labels > $D/labels.tsv
expect "nedis applies relocations and names far calls" "lcall   KERNEL.3" "$PYTHON" tools/dos/nedis.py $D/sample.exe 1000:008c 6 --labels $D/labels.tsv
expect "nedis names data in DS" "[RandSeed]" "$PYTHON" tools/dos/nedis.py $D/sample.exe 1000:0028 8 --labels $D/labels.tsv
fr=$(awk '$1=="field_read"{print $3}' $D/symbols.tsv)
expect "nedis leaves register-relative operands alone ([si + 4] is not Total)" "[si + 4]" "$PYTHON" tools/dos/nedis.py $D/sample.exe "1000:${fr#0x}" 4 --labels $D/labels.tsv

echo "16-bit emulator"
expect "dos_emu runs the NE random generator (matches the reference)" "True [722, 842, 312, 2, 309]" "$PYTHON" - <<'PY'
import sys; sys.path.insert(0, 'tools/emu')
from dos_emu import DosEmu, Long
ref, seed = [], 1234
for _ in range(5):
    seed = (seed * 0x08088405 + 1) & 0xFFFFFFFF
    ref.append(((seed >> 16) * 1000) >> 16)
emu = DosEmu('examples/dos-sample/build/sample.exe')
emu.call('RNG_SEED', Long(1234))
got = [emu.call('1000:0028', 1000) for _ in range(5)]
print(got == ref, got)
PY
expect "dos_emu applies selector relocations (Ghidra's numbering)" "0x1008" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
print(hex(DosEmu('$D/sample.exe').call('GET_DATA_SEG')))"
expect "dos_emu gives scripts whole segments" "1020 104" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe'); s = e.new_segment(b'hello'); print(f'{s:04x}', e.call('CHECKSUM', (s, 0), 1))"
expect "dos_emu runs a fragment between two addresses" "ax=42" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe'); f = int(open('$D/symbols.tsv').read().split('field_read')[1].split()[1], 16)
s = e.new_segment(b'....' + bytes([42, 0]))
e.run_range(f'1000:{f:04x}', f'1000:{f + 3:04x}', regs={'ds': s, 'si': 0}); print(f'ax={e.reg(\"ax\")}')"
expect "run_to carries on with the registers as they are (run_range resets the stack)" "ax=42 sp=1234" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe'); f = int(open('$D/symbols.tsv').read().split('field_read')[1].split()[1], 16)
s = e.new_segment(b'....' + bytes([42, 0]))
e.run_range(f'1000:{f:04x}', f'1000:{f:04x}', regs={'ds': s, 'si': 0, 'sp': 0x1234})
e.run_to(f'1000:{f + 3:04x}'); print(f'ax={e.reg(\"ax\")} sp={e.reg(\"sp\"):04x}')"
expect "dos_emu passes far pointers" "532" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe'); print(e.call('CHECKSUM', e.bytes_in(b'hello'), 5))"
expect "dos_emu traces random draws with call sites" "rng_next(50)	1000:005d" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu, Long
e = DosEmu('$D/sample.exe'); e.call('RNG_SEED', Long(99)); e.trace({'RNG_NEXT': 'rng_next'}, args=1)
e.call('SUM_DRAWS', 4, 50); print(e.traces[0])"
expect "an unhandled import names itself" "unhandled import KERNEL.3 called from 1000:0091" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
try: DosEmu('$D/sample.exe').call('ASK_HOST')
except RuntimeError as e: print(e)"
expect "import stubs and interrupt handlers run" "0xa03 5" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe', stubs={'KERNEL.3': lambda m: m.set(ax=0x0a03)}, interrupts={0x21: lambda m: m.set(ax=5)})
print(hex(e.call('ASK_HOST')), e.call('DOS_VERSION'))"
expect "call() sets general registers for routines that take them in registers" "0x4242" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
e = DosEmu('$D/sample.exe', stubs={'KERNEL.3': lambda m: m.set(ax=m.reg('cx'))})
print(hex(e.call('ASK_HOST', regs={'cx': 0x4242})))"
expect "an unhandled interrupt names itself" "unhandled interrupt 21h (AH=30h) at 1000:0094" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu
try: DosEmu('$D/sample.exe').call('DOS_VERSION')
except RuntimeError as e: print(e)"
expect "dos_emu runs real-mode MZ code at Ghidra's addresses (data after the code)" "True [722, 842, 312]" "$PYTHON" -c "
import sys, os; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu, Long
m = DosEmu('$D/sample-mz.exe'); ds = m.call('1000:0088')
last = max(int(l.split()[2], 16) for l in open('$D/symbols.tsv'))
m.call('1000:000f', Long(1234), regs={'ds': ds})
print(ds > 0x1000 + last // 16, [m.call('1000:0028', 1000, regs={'ds': ds}) for _ in range(3)])"

echo "Headless DOS environment (dos_env)"
printf 'HELLO DOS ENV\n' > $D/SAMPLE.TXT
expect "dos_env serves DOS file reads from a folder (names without case)" "14 b'HELLO DOS ENV'" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); print(e.call('READ_FILE'), e.read((0x1008, 0x90), 13))"
w="$(mktemp -d)"
expect "dos_env never writes the game folder: writes go to the overlay" "unchanged XYZ" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D', overlay='$w')
e.write((0x1008, 0x90), b'XYZ'); e.call('READ_FILE') if False else None; e.call('WRITE_FILE')
print('unchanged' if open('$D/SAMPLE.TXT').read() == 'HELLO DOS ENV\\n' else 'CHANGED', open('$w/SAMPLE.TXT').read()[:3])"
rm -rf "$w"
expect "dos_env delivers timer interrupts to the program's own INT 8 handler" "3 3" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); print(e.call('WAIT_TICKS'), env.irq0_count)"
expect "dos_env types queued keys and stops when none is left" "0x1c0d the program waits for a key" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); env.keys = [0x1C0D]; k = e.call('GET_KEY')
try: e.call('GET_KEY')
except RuntimeError as x: print(hex(k), x)"
expect "dos_env delivers scripted scan codes as IRQ 1 to the program's INT 9 handler (key table, EOI)" "1 2 0 5 39b9 2" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); env.key_script('2:39:3')
e.call('WAIT_KEYS', 1); held = e.read((0x1008, 0x139), 1)[0]; at = env.irq0_count
e.call('WAIT_KEYS', 2); print(held, at, e.read((0x1008, 0x139), 1)[0], env.irq0_count, e.read((0x1008, 0xB0), 2).hex(), env.irq1_count)"
expect "dos_env's BIOS INT 9 feeds INT 16h from scan codes (extended keys too)" "0x1c0d 0x4800" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); env.press(0x1C, at=1); env.press(0xE048, at=1)
print(hex(e.call('GET_KEY')), hex(e.call('GET_KEY')))"
expect "dos_env's DPMI gives selectors at a base, and the constant selectors point at VGA" "a0000 b8123" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/emu'); from dos_emu import DosEmu; from dos_env import DosEnv
e = DosEmu('$D/sample.exe'); env = DosEnv(e, root='$D'); s = e.new_selector(base=0xB8123)
print(hex(e.linear(e.new_selector(base=0xA0000)))[2:], hex(e.linear(s))[2:])"

echo "Fragments of a main loop (fragments.py)"
a() { printf '1000:%s' "$(awk -v n="$1" '$1 == n { sub(/^0x/, "", $3); print $3 }' $D/symbols.tsv)"; }
w="$(mktemp -d)"
expect "fragments captures fragments of a running main loop" "draw: 8 of 8 runs saved" "$PYTHON" tools/emu/fragments.py $D/sample.exe "$w" 8 \
  "draw=$(a draw)-$(a draw_even_end)|$(a draw_odd_end),heap=1" "event=$(a event)-$(a event_end),changed=a8" \
  "tail=$(a event_end)-$(a frame_top),every=2,max=3" --frame-top "$(a frame_top)" --start "$(a main_loop)" \
  --screen a0 --display a2 --heap a0,a4
expect "fragments keeps only runs that change a word, and one in N up to K" "event 2 tail 3" sh -c "
  echo event \$(ls '$w/event' | grep -c before.ds) tail \$(ls '$w/tail' | grep -c before.ds)"
expect "fragments saves state before and after: DS, screen, display, files, heap" "ds scr vga files heap 2 1" "$PYTHON" -c "
w = '$w/draw/00000'; r = lambda e: open(w + e, 'rb').read()
print(' '.join(k for k in ('ds', 'scr', 'vga', 'files') if r('.before.' + k) != r('.after.' + k)), 'heap', len(r('.before.heap')) // 65538, len(r('.after.heap')) // 65538)"
expect "fragments saves the open files with their positions" "5	1	sample.txt" cat "$w/draw/00000.after.files"
rm -rf "$w"

echo "DOSBox-X runtime"
log="$(mktemp)"
cat > "$log" <<'LOG'
      10 DEBUG FILES:file open command 2 file C:\GAME\DATA.DAT
      11 DEBUG FILES:Reading 4 bytes from DATA.DAT
      12 DEBUG FILES:Reading 2 bytes from DATA.DAT
      13 DEBUG FILES:Reading 1 bytes from DATA.DAT
      14 DEBUG FILES:Reading 2 bytes from DATA.DAT
      15 DEBUG FILES:Reading 1 bytes from DATA.DAT
      16 DEBUG FILES:Reading 2 bytes from DATA.DAT
      17 DEBUG FILES:Reading 1 bytes from DATA.DAT
      18 DEBUG FILES:Seeking to 100 bytes from position type (0) in DATA.DAT
      19 DEBUG FILES:Reading 16 bytes from DATA.DAT
LOG
expect "fileio_trace groups a table of records" "0x000004: [2, 1] x 3 (stride 3)" "$PYTHON" tools/dos/fileio_trace.py "$log"
expect "fileio_trace follows seeks" "0x000064: 16" "$PYTHON" tools/dos/fileio_trace.py "$log" --file data.dat
rm -f "$log"
if command -v dosbox-x >/dev/null; then
  g="$(mktemp -d)"; mkdir "$g/game"; cp $D/sample-mz.exe "$g/game/SAMPLEMZ.EXE"   # output stays outside the game folder it copies
  expect "dosbox-run runs a DOS program and reads its exit code (= dos_emu's first draw)" "exit code 23" \
    scripts/dosbox-run.sh --out "$g/out" --time 20 "$g/game" SAMPLEMZ.EXE
  if ! dosbox_has_debug_channel; then
    echo "  skip  dbx_control (DOSBox-X $(dosbox_version) has no debugger control channel; needs 2026.10+)"
  else
  expect "dbx_control drives the debugger: break at exit, read AL and the new seed" "AL=23 seed=3b032b05" "$PYTHON" - "$g" <<'PY'
import os, sys; sys.path.insert(0, 'tools/dos')
from dbx_control import Debugger
g = sys.argv[1]
with Debugger(port=0, timeout=30) as d:            # a free port: no stale DOSBox-X can connect
    d.launch([os.path.abspath('scripts/dosbox-run.sh'), '--out', g + '/dbx', '--time', '40', '--break', '--mcp', str(d.port), g + '/game', 'SAMPLEMZ.EXE'])
    d.wait_connected(); d.wait_break()          # DEBUGBOX: stopped at the first instruction
    d.exec('BPINT 21 4C'); d.run()
    regs = d.wait_break()                       # stopped at INT 21h AH=4Ch (exit)
    seed = int.from_bytes(d.memdump('DS', 0, 4), 'little')
    d.run()
print(f'AL={regs["STEP_AX"] & 0xFF} seed={seed:08x}')
PY
  fi
  rm -rf "$g"
else
  echo "  skip  dosbox-run (dosbox-x is not installed: scripts/setup.sh --install)"
fi

echo "Installers and releases"
I="$(mktemp -d)"
cp $B/game.exe "$I/setup.exe" && printf 'Inno Setup Setup Data (5.6.2)' >> "$I/setup.exe"
expect "extract-installer recognises an Inno Setup installer" "Inno Setup -> innoextract" scripts/extract-installer.sh --detect "$I/setup.exe"
mkdir -p "$I/web.app/Contents/MacOS" && : > "$I/web.app/Contents/MacOS/GalaxyWebInstaller"
expect "extract-installer flags a web-installer app" "probably no game files inside" scripts/extract-installer.sh --detect "$I/web.app"
mkdir -p "$I/src/data" && echo level > "$I/src/data/LEVEL1.DAT" && cp $S/../dos-sample/build/sample-mz.exe "$I/src/GAME.EXE"
(cd "$I/src" && zip -qr ../game.zip .)
printf '#!/bin/sh\n# MojoSetup installer\nexit 0\n' > "$I/game.sh" && cat "$I/game.zip" >> "$I/game.sh"
expect "extract-installer unpacks a zip" "extracted into" scripts/extract-installer.sh "$I/game.zip" "$I/a"
expect "extract-installer unpacks a GOG-style .sh (zip after a script)" "GOG Linux installer" scripts/extract-installer.sh "$I/game.sh" "$I/b"
echo changed > "$I/b/data/LEVEL1.DAT"
expect "compare_trees finds the changed file, ignoring case" "DIFFERENT  DATA/LEVEL1.DAT" "$PYTHON" tools/triage/compare_trees.py "$I/a" "$I/b"
expect "compare_trees counts identical files" "1 identical, 1 different" "$PYTHON" tools/triage/compare_trees.py "$I/a" "$I/b"
rm -rf "$I"

echo "Discs, file kinds, similarity, obfuscation, timestamps"
W="$(mktemp -d)"
"$PYTHON" tests/make_disc.py "$W"
expect "discinfo lists a data track and an audio track" "track  2  audio AUDIO       start 00:02:40  length 00:02:00" "$PYTHON" tools/disc/discinfo.py "$W/test.cue"
expect "discinfo reads the ISO 9660 creation date" "1995-11-03 14:30:00 UTC+01:00" "$PYTHON" tools/disc/discinfo.py "$W/test.iso"
expect "discinfo reads Joliet names and finds the hidden file" "Secret Data.dat" "$PYTHON" tools/disc/discinfo.py "$W/test.cue" --files
expect "extract-installer hands a CUE sheet to discinfo" "CD image -> discinfo" scripts/extract-installer.sh --detect "$W/test.cue"
"$PYTHON" tools/disc/discinfo.py "$W/test.cue" --extract "$W/x" --audio "$W/wav" >/dev/null
[[ "$(cat "$W/x/ReadMe File.txt")" == "hello from the disc" && $(wc -c < "$W/wav/track02.wav") -eq 352844 ]] \
  && ok "discinfo copies the files and writes the audio track as WAV" || bad "discinfo --extract --audio"
"$PYTHON" tools/disc/discinfo.py "$W/test.cue" --iso "$W/cut.iso" >/dev/null
expect "versiondiff reads a disc image in place and finds no change against its own extracted files" "0 removed, 0 changed" "$PYTHON" tools/triage/versiondiff.py "$W/test.cue" "$W/x"
expect "buildid reads a disc image's volume label and mastering date" "Disc: volume TESTDISC; created 1995-11-03 14:30:00 UTC+01:00" "$PYTHON" tools/triage/buildid.py "$W/test.cue"
expect "discinfo --iso cuts the data track of a BIN/CUE into an ISO that reads the same" "Secret Data.dat" "$PYTHON" tools/disc/discinfo.py "$W/cut.iso" --files
[[ $(( $(wc -c < "$W/cut.iso") % 2048 )) == 0 ]] && ok "the cut ISO holds whole 2048-byte sectors" || bad "discinfo --iso sector size"
expect "filetypes names a PE executable" "executable (PE, Windows)" "$PYTHON" tools/triage/filetypes.py $B/game.exe
head -c 65536 /dev/urandom > "$W/noise.dat"
expect "filetypes flags a high-entropy file" "compressed or encrypted" "$PYTHON" tools/triage/filetypes.py "$W/noise.dat"
expect "similar scores a file against itself" "100" "$PYTHON" tools/triage/similar.py $B/game.exe $B/game.exe
"$PYTHON" - "$W" <<'PY'
import random, sys
d = sys.argv[1]; r = random.Random(7); data = bytes(r.randrange(256) for _ in range(100000))
open(f'{d}/v1.dat', 'wb').write(data); open(f'{d}/v2.dat', 'wb').write(data[:40000] + b'patch' * 20 + data[40000:])
sys.path.insert(0, 'tools/formats'); from xorscan import decode
open(f'{d}/hidden.txt', 'wb').write(decode(open('README.md', 'rb').read()[:4000], 'xor-key:1f2e3d4c'))
PY
s=$("$PYTHON" tools/triage/similar.py "$W/v1.dat" "$W/v2.dat" | awk '{print $1}')
(( s >= 90 && s < 100 )) && ok "similar sees a patched file as close but changed ($s)" || bad "similar on a patched file" "$s"
"$PYTHON" - "$W" <<'PY'
import random, struct, sys
d = sys.argv[1]; r = random.Random(5); mem = bytearray(r.randbytes(65536))
for i, gold in enumerate((500, 480, 480, 612)):
    for _ in range(200): mem[r.randrange(len(mem))] = r.randrange(256)
    struct.pack_into('<H', mem, 0x1235, gold); struct.pack_into('<I', mem, 0x4000, 0x21235)
    open(f'{d}/m{i}.bin', 'wb').write(mem)
PY
expect "memscan narrows dumps to the one address that holds the value" "0x00021235  u16  500 -> 480 -> 480 -> 612" "$PYTHON" tools/triage/memscan.py "$W/m0.bin:=500" "$W/m1.bin:=480" "$W/m2.bin:same" "$W/m3.bin:up" --base 0x20000
expect "memscan finds a pointer to the value" "0x00024000" "$PYTHON" tools/triage/memscan.py "$W/m3.bin" --pointers 0x21235 --base 0x20000
"$PYTHON" - "$W" <<'PY'
import json, math, sys
d = sys.argv[1]
# A level whose up is -y, in right-handed coordinates; a car 0.5 above it turns left (anticlockwise
# seen from above). The mirrored copy (x negated) is the same level drawn left-handed.
h = lambda x, z: 4 * math.sin(x / 9) + 3 * math.cos(z / 7)
pts = [(x, -h(x, z), z) for x in range(0, 101, 2) for z in range(0, 101, 2)]
rec = []
for n in range(240):
    a = n / 240 * 2 * math.pi
    x, z = 50 + 30 * math.cos(a), 50 + 30 * math.sin(a)
    rec.append({'t': n / 10, 'px': round(x * 65536), 'py': round(-(h(x, z) + 0.5) * 65536), 'pz': round(z * 65536)})
for name, p, r in (('level', pts, rec), ('mirror', [(-x, y, z) for x, y, z in pts], [dict(s, px=-s['px']) for s in rec])):
    open(f'{d}/{name}.pts', 'w').write(''.join(f'{x} {y} {z}\n' for x, y, z in p))
    open(f'{d}/{name}.jsonl', 'w').write(''.join(json.dumps(s) + '\n' for s in r))
PY
expect "axes finds the up axis and its sign from a path on the level" "up is -y: the object rides 0.500 above the surface" \
  "$PYTHON" tools/triage/axes.py "$W/level.jsonl" "$W/level.pts" --pos px,py,pz --scale 1/65536
expect "axes tells right-handed coordinates from a left turn" "right-handed coordinates" \
  "$PYTHON" tools/triage/axes.py "$W/level.jsonl" "$W/level.pts" --pos px,py,pz --scale 1/65536 --left-turn 0:6
expect "axes reports a mirrored copy as left-handed" "left-handed coordinates" \
  "$PYTHON" tools/triage/axes.py "$W/mirror.jsonl" "$W/mirror.pts" --pos px,py,pz --scale 1/65536 --left-turn 0:6
expect "xorscan finds a repeating XOR key" "xor-key:1f2e3d4c " "$PYTHON" tools/formats/xorscan.py "$W/hidden.txt" --top 1
expect "timestamps reads a FAT date" "dos       1995-11-03 14:30:10" "$PYTHON" tools/formats/timestamps.py 0x1F6373C5
expect "reader reads LEB128 and big-endian numbers" "624485 -123456 4660" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/formats'); from reader import Reader
r = Reader(bytes([0xe5, 0x8e, 0x26, 0xc0, 0xbb, 0x78, 0x12, 0x34])); print(r.uleb(), r.sleb(), r.u16be()); r.done()"
expect "discinfo --map finds data in a sector no file uses" "sectors 34-34 (1): ZIP archive" "$PYTHON" tools/disc/discinfo.py "$W/test.cue" --map
expect "discinfo finds a file the Joliet tree leaves out" "missing from the Joliet tree: NOJOLIET.TXT" "$PYTHON" tools/disc/discinfo.py "$W/test.cue"
expect "discinfo reads a PlayStation-style system area" "PlayStation licence text" "$PYTHON" tools/disc/discinfo.py "$W/xa.cue"
"$PYTHON" tools/disc/discinfo.py "$W/xa.cue" --extract "$W/xa" >/dev/null
[[ $(wc -c < "$W/xa/MOVIE.STR") -eq 4704 && -f "$W/xa/NOJOLIET.TXT" ]] \
  && ok "discinfo copies an XA Form 2 file as whole sectors, and files only ISO 9660 lists" || bad "discinfo XA extract"
rm -rf "$W"

echo "Constants, resources, stack strings, Flash, function matching"
W="$(mktemp -d)"
expect "constants finds the MSVC-style random generator in the engine" "MSVC rand() multiplier 214013" "$PYTHON" tools/triage/constants.py $B/engine.dll
"$PYTHON" - "$W" <<'PY'
import random, struct, sys
d = sys.argv[1]; r = random.Random(3); junk = lambda n: bytes(r.randrange(256) for _ in range(n))
# Park-Miller: 16807 beside its modulus in one function; a lone 16807 elsewhere is not reported.
open(f'{d}/pm.bin', 'wb').write(b'\x90' * 100 + b'\x69\xc0' + struct.pack('<I', 16807) + b'\x25'
                                + struct.pack('<I', 0x7fffffff) + b'\xc3' + b'\x90' * 300 + struct.pack('<I', 16807) + b'\x90' * 300)
# Sentences among binary noise, one of them UTF-16, one a template with a format code.
open(f'{d}/text.bin', 'wb').write(junk(300) + b'The pilot is low on power and looks for a lightwell.\0' + junk(50)
     + b'OPEN_FILE_TABLE_ENTRY_NAMES\0' + 'Water goes into power cells, sold by the two factions.'.encode('utf-16-le')
     + b'\0\0' + junk(30) + b'%s pays %d credits for the cargo.\0' + junk(20))
open(f'{d}/strings.txt', 'w').write('00401000\tshort\n00402000\tThe crater lights rise and fall with the clock.\\nA second sentence on the next line.\n')
# A pack directory whose names are XORed with a key the executable keeps.
key = b'GAMEFRAMESAMPLE!'
words = ['HANGAR', 'CRATER', 'MOTH', 'LOGO', 'FONT', 'HUD', 'RADAR', 'TUNNEL', 'PILOT', 'WATER', 'SKY', 'DOCK']
recs = b''
for i in range(40):
    name = f'{r.choice(words)}{r.randrange(10)}.{r.choice(["WAV", "SPR", "PAL", "SHP"])}'.encode().ljust(16, b'\0')
    recs += struct.pack('<I', 2) + bytes(a ^ b for a, b in zip(name, key)) + struct.pack('<II', i * 10, 10)
open(f'{d}/pack.dat', 'wb').write(b'\x11' * 500 + recs + struct.pack('<I', 500))
open(f'{d}/keyed.exe', 'wb').write(b'\x90' * 64 + key + b'\0' * 32)
# A 64-level light table on a grey palette (6-bit, after a 4-byte header): 0 black, 32 unchanged, 63 white.
open(f'{d}/grey.pal', 'wb').write(b'\0\0\xf8\0' + bytes(v for c in range(256) for v in (c * 63 // 255,) * 3))
t = bytes((c * L // 32 if L <= 32 else c + (255 - c) * (L - 32) // 31) for L in range(64) for c in range(256))
open(f'{d}/light.rmp', 'wb').write(b'HDR!' + t)
open(f'{d}/light-by-colour.rmp', 'wb').write(bytes(t[L * 256 + c] for c in range(256) for L in range(64)))
PY
expect "constants reports Park-Miller's 16807 when its modulus is beside it" "16807, with modulus 0x7fffffff nearby  [paired]" "$PYTHON" tools/triage/constants.py "$W/pm.bin"
[[ $("$PYTHON" tools/triage/constants.py "$W/pm.bin" | grep -c 16807) == 1 ]] && ok "constants leaves out a lone 16807 without --all" || bad "constants lone 16807"
expect "sentences lists the long strings of a binary, UTF-16 too" "Water goes into power cells, sold by the two factions. [utf-16]" "$PYTHON" tools/triage/sentences.py "$W/text.bin"
expect "sentences keeps format codes and drops identifiers" "# 3 sentences" "$PYTHON" tools/triage/sentences.py "$W/text.bin"
expect "sentences reads a Ghidra strings.txt and splits its lines" "0x00402000    7  A second sentence on the next line." "$PYTHON" tools/triage/sentences.py "$W/strings.txt"
expect "xorscan --records shows the key bytes the names' zero padding gives away" '?? 45 53 41 4d 50 4c 45 21  "????????ESAMPLE!"' "$PYTHON" tools/formats/xorscan.py "$W/pack.dat" --records 500:28:4:16
expect "xorscan --key-in finds the whole key in the executable" '"GAMEFRAMESAMPLE!" stored in '"$W"'/keyed.exe at file offset 0x40' "$PYTHON" tools/formats/xorscan.py "$W/pack.dat" --records 500:28:4:16 --key-in "$W/keyed.exe"
expect "shadetable finds the level of normal light and the shift that reaches it" "normal light: level 32; a 2.14 intensity of 0x4000 >> 9 lands there" "$PYTHON" tools/formats/shadetable.py "$W/light.rmp" --offset 4 --palette "$W/grey.pal" --palette-offset 4 --png "$W/light.png"
expect "shadetable names the black and white ends" "level 63       mostly colour 255 (252, 252, 252)" "$PYTHON" tools/formats/shadetable.py "$W/light.rmp" --offset 4 --palette "$W/grey.pal" --palette-offset 4 --dac shift
expect "shadetable tells a table stored colour by colour" "layout colour" "$PYTHON" tools/formats/shadetable.py "$W/light-by-colour.rmp" --palette "$W/grey.pal" --palette-offset 4
expect "rawimage and catalog shift 6-bit palettes when asked, and fill a short palette with magenta" "(252, 252, 252) (255, 255, 255) (255, 0, 255)" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/formats'); import rawimage, catalog
print(rawimage.load_palette('$W/grey.pal', 4, 'shift')[255], rawimage.load_palette('$W/grey.pal', 4)[255], catalog.load_palette('$W/grey.pal', 4 + 6, 'shift')[255])"
printf '10001000\t%d\tFUN_10001000\t\n' $((0x20000)) > "$W/half.tsv"
printf 'int main(void){return 0;}\n' > "$W/m.c"
if zig cc -target x86_64-windows-gnu "$W/m.c" tests/fixtures/resources.rc -o "$W/res.exe" >/dev/null 2>&1; then
  expect "peres reads the version information" "OriginalFilename         SAMPLE.EXE" "$PYTHON" tools/pe/peres.py "$W/res.exe"
  expect "peres reads a string table" "17  'Insert disc 2'" "$PYTHON" tools/pe/peres.py "$W/res.exe" --strings
else bad "peres: zig could not compile tests/fixtures/resources.rc"; fi
mkdir -p "$W/copy"; printf 'const char *banner = "Sample Game Version 2.8";\nint main(void){return banner[0] == 0;}\n' > "$W/bm.c"
if zig cc -target x86-windows-gnu "$W/bm.c" tests/fixtures/resources.rc -o "$W/copy/GAME.EXE" >/dev/null 2>&1; then
  printf 'Sample Game\r\n\r\nVersion 2.8 (September 29th, 1997)\r\nThanks for playing.\r\n' > "$W/copy/README.TXT"
  out="$("$PYTHON" tools/triage/buildid.py "$W/copy" --name Gold)"
  [[ "$out" == *"ProductVersion 2.8; FileVersion (fixed) 1.2.3.4; CompanyName GameFrame Samples"* && "$out" == *'"Sample Game Version 2.8"'* \
     && "$out" == *'`README.TXT`: "Version 2.8 (September 29th, 1997)"'* && "$out" == *"Executables linked 20"* && "$out" != *"Thanks for playing"* ]] \
    && ok "buildid reads VERSIONINFO, the link date, version strings and the readme's version line" || bad "buildid" "$out"
  printf '# Versions\n\n## Build identity\n\n## The reference\n\nFirst edition.\n' > "$W/versions.md"
  "$PYTHON" tools/triage/buildid.py "$W/copy" --name Gold --write "$W/versions.md" >/dev/null
  "$PYTHON" tools/triage/buildid.py "$W/copy" --name Gold --write "$W/versions.md" >/dev/null
  [[ $(grep -c '^<!-- buildid Gold -->' "$W/versions.md") == 1 && "$(sed -n '/## Build identity/,/## The reference/p' "$W/versions.md")" == *"### Gold"* ]] \
    && ok "buildid writes its block under Build identity in docs/versions.md, and replaces it on a second run" || bad "buildid --write" "$(cat "$W/versions.md")"
else bad "buildid: zig could not compile the sample"; fi
if zig cc -target x86-windows-gnu -O1 -fno-sanitize=undefined tests/fixtures/stackstring.c -o "$W/ss.exe" >/dev/null 2>&1; then
  expect "stackstrings finds text built on the stack" "'SAVE'" "$PYTHON" tools/pe/stackstrings.py "$W/ss.exe"
else bad "stackstrings: zig could not compile tests/fixtures/stackstring.c"; fi
"$PYTHON" tests/make_swf.py "$W"
expect "swfinfo reads an LZMA SWF and sees ActionScript 3" "3 (DoABC: AVM2)" "$PYTHON" tools/formats/swfinfo.py "$W/game-zws.swf"
expect "swfinfo lists the classes linked to symbols" "GameMain" "$PYTHON" tools/formats/swfinfo.py "$W/game-cws.swf"
"$PYTHON" tools/formats/swfinfo.py "$W/projector.exe" --extract "$W/out.swf" >/dev/null
cmp -s "$W/out.swf" "$W/game-cws.swf" && ok "swfinfo extracts the movie from a projector" || bad "swfinfo --extract"
expect "filetypes names a compressed Flash movie" "Flash movie (SWF, zlib)" "$PYTHON" tools/triage/filetypes.py "$W/game-cws.swf"
"$PYTHON" - "$W" <<'PY'
import os, sys
d = sys.argv[1]
body = {'update': 'void FUN_{a}(int *p)\n{{\n  p[1] = p[1] + p[2] * 3;\n  if (p[1] > 100) {{\n    FUN_{b}(p, DAT_{c});\n  }}\n  return;\n}}\n',
        'spawn': 'void FUN_{b}(int *p, int n)\n{{\n  int i;\n  for (i = 0; i < n; i = i + 1) {{\n    p[i + 4] = i * 7 + 0x10;\n  }}\n  return;\n}}\n'}
for build, (a, b, c) in (('A', ('401000', '401100', '409000')), ('B', ('402000', '402300', '40a000'))):
    os.makedirs(f'{d}/{build}', exist_ok=True)
    with open(f'{d}/{build}/decomp.c', 'w') as f:
        f.write(f'// ==== {a} FUN_{a}\n' + body['update'].format(a=a, b=b, c=c))
        f.write(f'// ==== {b} FUN_{b}\n' + body['spawn'].format(b=b))
    open(f'{d}/{build}/functions.tsv', 'w').write(f'{a}\t60\tFUN_{a}\t\n{b}\t40\tFUN_{b}\t\n')
open(f'{d}/names.tsv', 'w').write('401000\tunit_update\tgrows by 3 a tick\n401100\tunit_spawn\t\n')
PY
"$PYTHON" tools/triage/match_functions.py "$W/A" "$W/B" --labels "$W/names.tsv" --out "$W/names-b.tsv" >/dev/null
expect "match_functions carries labels to the new build's addresses" "402300	unit_spawn	matched from A 401100 (exact 1.0)" cat "$W/names-b.tsv"
rm -rf "$W"

echo "Pictures, tables, signatures, pointers, markers, instructions"
W="$(mktemp -d)"
"$PYTHON" -c "
d = bytes((x ^ y) & 255 for y in range(200) for x in range(320)); open('$W/screen.bin', 'wb').write(d)"
"$PYTHON" tools/formats/rawimage.py "$W/screen.bin" "$W/screen.png" --mode linear8 >/dev/null
[[ "$(head -c 8 "$W/screen.png" | xxd -p)" == 89504e470d0a1a0a ]] && ok "rawimage writes a mode 13h screen as PNG" || bad "rawimage"
expect "rawimage decodes Mode X planes" "640 x 480, mode modex" "$PYTHON" tools/formats/rawimage.py "$W/screen.bin" "$W/x.png" --mode modex --scale 2
expect "binview draws a file as a picture" "512 x 512, 1 byte(s) per pixel" "$PYTHON" tools/triage/binview.py $B/game.exe "$W/bv.png" --layout hilbert
"$PYTHON" -c "
import math, os, struct
a = os.urandom(999) + b''.join(struct.pack('<h', round(math.sin(2 * math.pi * i / 1024) * 16384)) for i in range(1280))
open('$W/sine.bin', 'wb').write(a)"
expect "tables finds a sine table and its shape" "sine table: 1024 steps per circle, scale 16384, i16, nearest; 1024 entries match" "$PYTHON" tools/triage/tables.py "$W/sine.bin"
expect "tables sees the cosine table inside the sine table" "the cosine table is the same table from entry 256 on" "$PYTHON" tools/triage/tables.py "$W/sine.bin"
printf "140001000\ttree_update\n140001090\tsimulate\n" > "$W/names.tsv"
"$PYTHON" tools/triage/sigscan.py make $B/game.exe --names "$W/names.tsv" > "$W/game.sigs"
expect "sigscan makes signatures that wildcard addresses" "48 8D 15 ?? ?? ?? ??" cat "$W/game.sigs"
printf 'static int pad(int x){return x*7+1;}\nint first(int x){return pad(x)+pad(x+1);}\n' > "$W/pad.c"
cat "$W/pad.c" $S/game.c > "$W/game2.c"
if zig cc -target x86_64-windows-gnu -O2 "$W/game2.c" $B/engine.lib -o "$W/game2.exe" >/dev/null 2>&1; then
  expect "sigscan finds the named functions in a rebuilt game at new addresses" "simulate" "$PYTHON" tools/triage/sigscan.py scan "$W/game.sigs" "$W/game2.exe"
else bad "sigscan: zig could not build the second game"; fi
"$PYTHON" tests/make_omf.py "$W"
expect "omf lists a library's public names" "_puts                            _TEXT:0013" "$PYTHON" tools/dos/omf.py "$W/RT.LIB"
expect "omf turns a fixup into wildcards" "_puts: 55 8B EC FF 76 04 E8 ?? ??" "$PYTHON" tools/dos/omf.py "$W/RT.LIB" --sigs
"$PYTHON" tools/dos/omf.py "$W/RT.LIB" --sigs > "$W/rt.sigs"
expect "sigscan names a library function inside a DOS program" "_puts                            1000:0051" "$PYTHON" tools/triage/sigscan.py scan "$W/rt.sigs" "$W/GAME.EXE"
expect "insns lists the interrupts of a DOS program" "1000:0003  int 0x21" "$PYTHON" tools/triage/insns.py "$W/GAME.EXE" '^int '
"$PYTHON" - "$W" <<'PY'
import random, struct, sys
d = sys.argv[1]
for run, (w, p) in enumerate([(0x1001000, 0x1003000), (0x1005400, 0x1002200)]):
    r = random.Random(run)
    mem = bytearray(0x10000); heap = bytearray(0x10000)
    for i in range(0, 0x10000, 4):
        struct.pack_into('<I', mem, i, r.randrange(0, 0x3fffff)); struct.pack_into('<I', heap, i, r.randrange(0, 0x3fffff))
    struct.pack_into('<I', mem, 0x4000, w); struct.pack_into('<I', heap, w - 0x1000000 + 0x18, p)
    struct.pack_into('<I', heap, p - 0x1000000 + 0x24, 500)
    open(f'{d}/run{run}.bin', 'wb').write(mem + bytes(0x1000000 - 0x410000) + heap)
PY
expect "pointerpaths finds the chain that survives a restart" "[0x404000] -> +0x18 -> +0x24" "$PYTHON" tools/triage/pointerpaths.py "$W/run0.bin@0x400000:0x1003024" "$W/run1.bin@0x400000:0x1002224" --static 0x400000-0x40ffff
"$PYTHON" -c "
import struct; d = bytearray(64); struct.pack_into('<IH', d, 16, 1234, 77); open('$W/save.dat', 'wb').write(d)"
"$PYTHON" tools/formats/markers.py plant "$W/save.dat" "$W/save-m.dat" --from 16 --to 24 >/dev/null
"$PYTHON" -c "
m = bytearray(4096); m[100:104] = open('$W/save-m.dat', 'rb').read()[20:24]; open('$W/dump.bin', 'wb').write(m)"
expect "markers maps a file's field to its address in memory" "file 0x000014  marker 0xc0de0001  ->  0x20064" "$PYTHON" tools/formats/markers.py find "$W/save-m.dat.markers" "$W/dump.bin@0x20000"
expect "reader reads bit fields in both orders" "4 22 5 20" "$PYTHON" -c "
import sys; sys.path.insert(0, 'tools/formats'); from reader import Reader
a = Reader(bytes([0b10110100])); b = Reader(bytes([0b10110100])); print(a.bits(3), a.bits(5), b.bits(3, True), b.bits(5, True))"
rm -rf "$W"

echo "Network captures, fields, coverage, fixity"
W="$(mktemp -d)"
"$PYTHON" tests/make_pcap.py "$W/c.pcap"
expect "pcap lists the flows of a capture" "UDP  10.0.0.1:27960 <-> 10.0.0.2:50123  80 messages" "$PYTHON" tools/formats/pcap.py "$W/c.pcap"
"$PYTHON" tools/formats/pcap.py "$W/c.pcap" --flow 1 --stream "$W/s.bin" >/dev/null
[[ "$(cat "$W/s.bin")" == "HELLO LOBBY" ]] && ok "pcap joins a TCP direction into a stream" || bad "pcap --stream"
"$PYTHON" tools/formats/pcap.py "$W/c.pcap" --flow 0 --dir b --dump "$W/msgs" >/dev/null
expect "fields finds the type byte" "+0x002  3 values: 0x01, 0x02, 0x03 (each with its own length: a type?)" "$PYTHON" tools/formats/fields.py "$W/msgs"
expect "fields finds the sequence counter" "+0x003  counter u16 LE (+1 each)" "$PYTHON" tools/formats/fields.py "$W/msgs"
expect "fields finds the length field" "length u16 LE (the whole message)" "$PYTHON" tools/formats/fields.py "$W/msgs"
expect "fields groups by type and sees the counter's step" "+0x003  counter u16 LE (+3 each)" "$PYTHON" tools/formats/fields.py "$W/msgs" --by-type 2
"$PYTHON" - "$W" <<'PY'
import struct, sys
d = sys.argv[1]
def drcov(path, blocks):
    head = ('DRCOV VERSION: 2\nDRCOV FLAVOR: drcov\nModule Table: version 2, count 2\n'
            'Columns: id, base, end, entry, checksum, timestamp, path\n'
            ' 0, 0x400000, 0x450000, 0x401000, 0x0, 0x0, C:\\game\\GAME.EXE\n'
            ' 1, 0x77000000, 0x77100000, 0x0, 0x0, 0x0, C:\\Windows\\ntdll.dll\n'
            f'BB Table: {len(blocks)} bbs\n').encode()
    open(path, 'wb').write(head + b''.join(struct.pack('<IHH', s, 8, m) for s, m in blocks))
base = [(0x1000, 0), (0x1010, 0), (0x2000, 0), (0x500, 1)]
drcov(f'{d}/a.cov', base); drcov(f'{d}/b.cov', base + [(0x3000, 0), (0x3020, 0), (0x600, 1)])
open(f'{d}/functions.tsv', 'w').write('401000\t32\tmain_loop\t\n402000\t16\tdraw\t\n403000\t64\tbuy_unit\t\n')
PY
expect "coverdiff names the function that ran only with the action" "403000  buy_unit  (2 blocks)" "$PYTHON" tools/triage/coverdiff.py "$W/a.cov" "$W/b.cov" --module game.exe --base 0x400000 --functions "$W/functions.tsv"
mkdir -p "$W/game/DATA" && echo a > "$W/game/GAME.EXE" && echo b > "$W/game/DATA/L1.DAT"
"$PYTHON" tools/triage/fixity.py bag "$W/game" "$W/bag" --info "External-Description=test" >/dev/null
expect "fixity makes a BagIt bag that verifies" "2 files checked: all unchanged" "$PYTHON" tools/triage/fixity.py verify "$W/bag"
echo x >> "$W/bag/data/DATA/L1.DAT"
expect "fixity finds a changed file" "changed  data/DATA/L1.DAT" "$PYTHON" tools/triage/fixity.py verify "$W/bag"
rm -rf "$W"

echo "Reports to issues"
RT="$(pwd)"
R="$(mktemp -d)"; mkdir -p "$R/reports" "$R/bin"
printf '{"id": "unported-1a2b3c4d", "kind": "unported", "what": "the sky fog", "original": "0x4a5e00", "file": "src/sky.rs", "line": 88, "count": 3, "meta": {"issues": "owner/game"}}\n' > "$R/reports/unported-1a2b3c4d.json"
printf '# [unported] the sky fog at src/sky.rs:88 (0x4a5e00)\n\n<!-- gameframe-report: unported-1a2b3c4d -->\nBODY\n' > "$R/reports/unported-1a2b3c4d.md"
printf '{"id": "panic-00000001", "kind": "panic", "what": "boom", "file": "src/a.rs", "line": 1, "count": 1}\n' > "$R/reports/panic-00000001.json"
# A stand-in gh: logs each call; `issue list` answers with $GH_FOUND.
printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\ncase "$1 $2" in "issue list") echo "$GH_FOUND";; "issue create") echo https://github.com/owner/game/issues/9;; esac\n' "$R" > "$R/bin/gh"; chmod +x "$R/bin/gh"
expect "report_issue lists the reports, most frequent first" "3  unported-1a2b3c4d  [unported] the sky fog at src/sky.rs:88 (0x4a5e00)" sh -c "cd '$R' && '$PYTHON' '$RT/tools/triage/report_issue.py' list"
expect "report_issue shows the body the crate wrote" "BODY" sh -c "cd '$R' && '$PYTHON' '$RT/tools/triage/report_issue.py' show unported-1a2b3c4d"
out="$(cd "$R" && PATH="$R/bin:$PATH" GH_FOUND= "$PYTHON" "$RT/tools/triage/report_issue.py" file unported-1a2b3c4d)"
out2="$(cd "$R" && PATH="$R/bin:$PATH" GH_FOUND=9 "$PYTHON" "$RT/tools/triage/report_issue.py" file unported-1a2b3c4d)"
log="$(cat "$R/gh.log")"
[[ "$out" == *"issues/9"* && "$out2" == *"issue #9: added the new count"* && "$log" == *"--repo owner/game"* && "$log" == *"--label gameframe-report,unported"* && "$log" == *"issue comment 9"* && "$log" == *"unported-1a2b3c4d in:body"* ]] \
  && ok "report_issue files a report once, to the report's repository, then comments on that issue" || bad "report_issue file" "$out / $out2 / $log"
rm -rf "$R"

echo "Ledger and coverage"
L="$(mktemp -d)"; mkdir -p "$L/src/build" "$L/export/game.exe"
printf '/// Original: `FUN_140001090`\nfn grow() {}\n// Deviation: the time comes in as an argument,\n// so tests can fix it.\nfn tick() {}\n// Not ported: the debug overlay.\n' > "$L/src/world.rs"
printf '# A helper. Original: `rng_next`\n' > "$L/src/tool.py"
echo "// Deviation: generated" > "$L/src/build/gen.rs"; echo "# Deviation notes" > "$L/src/NOTES.md"
printf '140001000\t40\trng_next\t\n140001090\t300\tsimulate\t\n140001200\t20\tFUN_140001200\t\n140001300\t5\tthunk_x\tthunk\n' > "$L/export/game.exe/functions.tsv"
expect "deviations joins a comment block and skips build/ and prose" "Deviation: 1, Not ported: 1." "$PYTHON" tools/triage/deviations.py "$L/src"
expect "deviations keeps the whole block" "argument, so tests can fix it." "$PYTHON" tools/triage/deviations.py "$L/src"
"$PYTHON" tools/triage/deviations.py --out "$L/DEV.md" "$L/src" >/dev/null
echo "// Deviation: new" >> "$L/src/tool.py"
expect "deviations --check finds a stale ledger" "out of date" "$PYTHON" tools/triage/deviations.py --out "$L/DEV.md" --check "$L/src"
expect "coverage counts addresses and names, not thunks" "2 of 3 functions cited (66.7 %), 340 of 360 bytes (94.4 % by size)" "$PYTHON" tools/triage/coverage.py --export "$L/export" "$L/src"
expect "coverage lists the largest uncited function" "140001200" "$PYTHON" tools/triage/coverage.py --export "$L/export" "$L/src"
mkdir -p "$L/export/OVL2.OVL" "$L/mod"
printf '1000:0100\t30\tadd\t\n1000:0200\t70\tmul\t\n' > "$L/export/OVL2.OVL/functions.tsv"
printf '/// Port of `OVL2:0100` (add); not of 1000:0200.\nfn add() {}\n' > "$L/mod/ovl.rs"
expect "coverage --module counts NAME:offset citations only" "1 of 2 functions cited (50.0 %), 30 of 100 bytes" "$PYTHON" tools/triage/coverage.py --export "$L/export" --module OVL2 "$L/mod"
rm -rf "$L"

echo "Project scaffold"
tmp="$(mktemp -d)/re-test"
scripts/new-project.sh "$tmp" "Test Game" $B >/dev/null 2>&1
[[ -f "$tmp/AGENTS.md" && -f "$tmp/docs/versions.md" && -f "$tmp/docs/GAME_PROFILE.md" && -f "$tmp/README.md" && -f "$tmp/LICENSE-APACHE" && -f "$tmp/LICENSE-CC0-1.0" && ! -e "$tmp/LICENSE-CC-BY-4.0" && ! -e "$tmp/LICENSE-MIT" && -f "$tmp/.cargo/config.toml" && -f "$tmp/.claude/settings.json" && -x "$tmp/gameframe" && -f "$tmp/game/game.exe" && -L "$tmp/game" && -d "$tmp/.git" && ! -e "$tmp/tools" && ! -e "$tmp/scripts" && ! -e "$tmp/.claude/skills" && -f "$tmp/skills/re-start/SKILL.md" && -f "$tmp/skills/re-profile/SKILL.md" && -L "$tmp/.agents/skills" && ! -e "$tmp/docs/DOS.md" ]] \
  && grep -q "Test Game" "$tmp/AGENTS.md" && grep -q '^# Game profile: Test Game$' "$tmp/docs/GAME_PROFILE.md" && grep -q "In the story | In the code | Evidence" "$tmp/docs/lore.md" && grep -q '"gameframe@game-frame": true' "$tmp/.claude/settings.json" && ! grep -q "gate.py" "$tmp/.claude/settings.json" \
  && grep -q 'gameframe gate cursor' "$tmp/.cursor/hooks.json" && grep -q 'gameframe\\" gate codex' "$tmp/.codex/hooks.json" && grep -q '"AGENTS.md"' "$tmp/.gemini/settings.json" \
  && ! (cd "$tmp" && git ls-files | grep -qE '^(game|media|saves)(/|$)') \
  && ok "new-project makes a plugin project: docs/lore.md and GAME_PROFILE.md from their templates, settings enable the plugin, no copied toolkit, the other agents' skills and hooks through ./gameframe gate, game/ a link into the home and out of git" || bad "new-project scaffold" "$(ls -la "$tmp" 2>&1)"
expect "the launcher finds GameFrame and runs its tools on the project" "EXE, x64 (64-bit)" sh -c "cd '$tmp' && GAMEFRAME_ROOT='$(pwd)' ./gameframe run peinfo game/game.exe"
expect "the launcher runs a project script with the toolkit on its path" "pe_emu ok" sh -c "cd '$tmp' && printf 'import pe_emu\\nprint(\"pe_emu ok\")\\n' > probe.py && GAMEFRAME_ROOT='$(pwd)' ./gameframe python probe.py"
out="$(cd "$tmp" && git config core.hooksPath && git add -f game && GAMEFRAME_ROOT="$OLDPWD" git commit -qm game 2>&1; git reset -q)"
[[ "$out" == *".githooks"*"stages game material"* ]] && ok "a plugin project's git pre-commit hook finds GameFrame and blocks game material" || bad "plugin project pre-commit hook" "$out"
expect "the session hook says where GameFrame's guides are" "read docs/NAME.md as" sh -c "echo '{\"cwd\": \"$tmp\"}' | python3 scripts/hooks/gate.py session"
out="$("$PWD/scripts/update-project.sh" "$tmp" 2>&1)"
[[ "$out" == *"Plugin project: the gameframe launcher is current"* && "$out" == *"0 were added, 0 were replaced"* ]] && ok "update-project leaves a plugin project's launcher, settings and agent files current" || bad "update-project on a plugin project" "$out"
expect "scripts/clients.py prints its usage" "scripts/clients.py write DEST" python3 scripts/clients.py --help
expect "Codex Cloud environment installer prints its usage" "Usage: scripts/codex-cloud-environment-install.sh" bash scripts/codex-cloud-environment-install.sh --help
one="$(mktemp -d)/re-claude"
scripts/new-project.sh "$one" "Test Game" --agent claude >/dev/null 2>&1
[[ -f "$one/.claude/settings.json" && -f "$one/CLAUDE.md" && ! -e "$one/skills" && ! -e "$one/.agents" && ! -e "$one/.codex" && ! -e "$one/.gemini" && ! -e "$one/.cursor" && ! -e "$one/opencode.json" ]] \
  && ok "new-project --agent claude writes only Claude Code's files" || bad "new-project --agent claude" "$(ls -A "$one" 2>&1)"
two="$(mktemp -d)/re-two"
scripts/new-project.sh "$two" "Test Game" --agent codex,cursor >/dev/null 2>&1
[[ ! -e "$two/.claude" && ! -e "$two/CLAUDE.md" && -f "$two/.codex/agents/re-tracer.toml" && -f "$two/.cursor/agents/re-tracer.md" && ! -e "$two/.gemini" && "$(python3 scripts/clients.py detect "$two")" == "codex,cursor" ]] \
  && ok "new-project --agent codex,cursor writes their files and no Claude Code settings" || bad "new-project --agent codex,cursor" "$(ls -A "$two" 2>&1)"
out="$(GAMEFRAME_ROOT="$PWD" python3 - "$two" <<'PY'
import json, subprocess, sys
event = lambda c: json.dumps({'cwd': sys.argv[1], 'hook_event_name': 'PreToolUse', 'tool_name': 'Bash', 'tool_input': {'command': c}})
run = lambda c: subprocess.run(['./gameframe', 'gate', 'codex'], cwd=sys.argv[1], input=event(c), text=True, capture_output=True).returncode
print(run('GAMEFRAME_AGENT=re-' + 'tracer git ' + 'commit -m x'), run('ls'))
PY
)"
[[ "$out" == "2 0" ]] && ok "a plugin project's Codex hook runs the gates through ./gameframe gate" || bad "./gameframe gate" "$out"
out="$("$PWD/scripts/update-project.sh" "$two" --agent gemini 2>&1)"
grep -q 'gameframe\\" gate gemini' "$two/.gemini/settings.json" && grep -q '"AGENTS.md"' "$two/.gemini/settings.json" && [[ -f "$two/.gemini/agents/re-tracer.md" ]] \
  && ok "update-project --agent gemini adds Gemini CLI's agents, hooks and settings to a project" || bad "update-project --agent gemini" "$out"
out="$(scripts/new-project.sh "$(dirname "$two")/re-bad" "Test Game" --agent bogus 2>&1)"
[[ $? != 0 && "$out" == *"unknown agent bogus"* && ! -e "$(dirname "$two")/re-bad" ]] && ok "new-project refuses an unknown agent before writing anything" || bad "new-project --agent bogus" "$out"
rm -rf "$(dirname "$one")" "$(dirname "$two")"

tmp="$(mktemp -d)/re-copy"
scripts/new-project.sh "$tmp" "Test Game" $B --copy >/dev/null 2>&1
[[ -f "$tmp/docs/DOS.md" && -f "$tmp/docs/games/README.md" && -f "$tmp/docs/GAME_PROFILE.md" && -f "$tmp/skills/re-start/SKILL.md" && -f "$tmp/skills/re-profile/SKILL.md" && -L "$tmp/.claude/skills" && -f "$tmp/.claude/skills/re-start/SKILL.md" && -L "$tmp/.agents/skills" && -f "$tmp/.agents/skills/re-start/SKILL.md" && -f "$tmp/.claude/agents/re-tracer.md" && -f "$tmp/requirements-live.txt" && -f "$tmp/scripts/hooks/gate.py" && -f "$tmp/docs/assets/diagrams/fixed-step.svg" ]] \
  && ok "new-project --copy copies the toolkit, skills, agents, gates and guides" || bad "new-project --copy" "$(ls -la "$tmp" 2>&1)"
expect "gameframe works in a copied project" "tools/pe/peinfo.py  (program)" "$tmp/gameframe" tool peinfo
[[ -f "$tmp/.codex/agents/re-tracer.toml" && -f "$tmp/.gemini/agents/re-tracer.md" && -f "$tmp/.github/agents/re-tracer.agent.md" && -f "$tmp/.opencode/agents/re-tracer.md" ]] \
  && ok "new-project --copy copies the agents for Codex, Gemini CLI, Copilot and OpenCode" || bad "new-project --copy agents for other clients" "$(ls -a "$tmp" 2>&1)"
echo "# a local note" >> "$tmp/tools/triage/memscan.py"
rm "$tmp/skills/re-trace/SKILL.md"
out="$(cd "$tmp" && "$OLDPWD/scripts/update-project.sh" . 2>&1)"
[[ -f "$tmp/skills/re-trace/SKILL.md" && "$out" == *"1 files were added"* && "$out" == *"tools/triage/memscan.py"* ]] \
  && grep -q "a local note" "$tmp/tools/triage/memscan.py" \
  && ok "update-project restores a missing file and keeps a file the project changed" || bad "update-project" "$out"
old="$(mktemp -d)/re-old"
cp -R "$tmp" "$old"
rm "$old/.claude/skills" "$old/.agents/skills" && mv "$old/skills" "$old/.claude/skills"
mkdir -p "$old/.claude/skills/my-own" && echo "# mine" > "$old/.claude/skills/my-own/SKILL.md"
out="$("$PWD/scripts/update-project.sh" "$old" 2>&1)"
[[ -f "$old/skills/re-start/SKILL.md" && -f "$old/skills/my-own/SKILL.md" && -L "$old/.claude/skills" && -L "$old/.agents/skills" && -f "$old/.agents/skills/my-own/SKILL.md" && "$out" == *"0 files were added"* ]] \
  && ok "update-project moves an older project's .claude/skills to skills/ and links both agent folders to it" || bad "update-project moves the skills" "$out $(ls -la "$old/.claude" 2>&1)"
rm -rf "$old"
(cd "$tmp" && git add -A && git commit -qm copy)
out="$("$PWD/scripts/update-project.sh" "$tmp" --plugin --agent claude 2>&1)"
[[ ! -e "$tmp/skills" && ! -e "$tmp/.claude/skills" && ! -e "$tmp/.agents" && ! -e "$tmp/scripts" && ! -e "$tmp/.codex" && ! -e "$tmp/.cursor" && ! -e "$tmp/.gemini" && ! -e "$tmp/opencode.json" && ! -e "$tmp/docs/DOS.md" && -f "$tmp/tools/triage/memscan.py" && ! -e "$tmp/tools/pe" && "$out" == *"tools/triage/memscan.py"* ]] \
  && grep -q "GAMEFRAME_PROJECT" "$tmp/gameframe" && grep -q '"gameframe@game-frame": true' "$tmp/.claude/settings.json" && ! grep -q "gate.py" "$tmp/.claude/settings.json" \
  && ok "update-project --plugin removes the copies, keeps the project's changes, enables the plugin" || bad "update-project --plugin" "$out"

echo "Project sites (re-site)"
expect "new-site prints its usage" "scripts/new-site.sh NAME" bash scripts/new-site.sh
expect "tools/site/check.py prints its usage" "tools/site/check.py SITE_DIR" python3 tools/site/check.py --help
sp="$(mktemp -d)/re-site"
scripts/new-project.sh "$sp" "Test Game" --agent claude >/dev/null 2>&1
out="$(cd "$sp" && GAMEFRAME_ROOT="$OLDPWD" ./gameframe run new-site test "Test: \"Game\"" --repo https://github.com/example/test 2>&1)"
S="$sp/sites/test"
[[ -f "$S/.vitepress/config.mts" && -f "$S/diary/posts.data.mts" && -f "$sp/.github/workflows/sites.yml" ]] \
  && grep -q '<!--@include: ../../docs/FINDINGS.md-->' "$S/findings.md" && grep -q 'title: "Test: \\"Game\\""' "$S/.vitepress/config.mts" \
  && ok "new-site writes sites/NAME with the diary, the included documents and the Pages workflow, and quotes the title" || bad "new-site" "$out $(ls -A "$S" 2>&1)"
out="$(cd "$sp" && GAMEFRAME_ROOT="$OLDPWD" ./gameframe run new-site test "Again" 2>&1)"
[[ $? != 0 && "$out" == *"exists"* ]] && ok "new-site never writes over a site" || bad "new-site twice" "$out"
grep -q 'paths:' "$sp/.github/workflows/sites.yml" && [[ -f "$S/.vitepress/theme/custom.css" && -d "$S/public" ]] \
  && ok "new-site writes a theme to colour from the game and a public/ folder for the diary's figures" || bad "new-site theme"
sm="$(mktemp -d)/re-manual"
scripts/new-project.sh "$sm" "Test Game" --agent claude >/dev/null 2>&1
(cd "$sm" && GAMEFRAME_ROOT="$OLDPWD" ./gameframe run new-site test "Manual" --manual >/dev/null 2>&1)
grep -q 'workflow_dispatch:' "$sm/.github/workflows/sites.yml" && ! grep -q 'push:' "$sm/.github/workflows/sites.yml" \
  && ok "new-site --manual writes a Pages workflow that runs only when started by hand" || bad "new-site --manual" "$(cat "$sm/.github/workflows/sites.yml" 2>&1 | head -20)"
out="$(python3 tools/site/check.py "$S" 2>&1)"
[[ $? == 1 && "$out" == *"TODO(site)"* ]] && ok "check.py fails a site with the template's TODO(site) lines" || bad "check.py TODO" "$out"
sed -i.bak 's/TODO(site) //' "$S/index.md" && rm "$S/index.md.bak"
words="The reader checks the record count against the file size before it reads anything, and every record decodes."
undef="The value is undefined when the count is zero; \`FUN_004436c8\` and \`DAT_005920a4\` are cited by name."
{ printf -- '---\ntitle: "The first format"\nsummary: The data file is a table of fixed records.\n---\n\n# The first format\n\n'
  for i in 1 2 3 4 5 6 7 8; do echo "$words"; done; echo "$undef"; } > "$S/diary/2026-10-23-first-format.md"
out="$(python3 tools/site/check.py "$S" 2>&1)"
[[ $? == 0 && "$out" == *"0 errors, 0 warnings"* ]] && ok "check.py passes a site with a real diary entry (the word undefined and cited FUN_/DAT_ names too)" || bad "check.py clean site" "$out"
{ printf -- '---\ntitle: Work\nsummary: Commits.\n---\n\n'
  for h in 1a2b3c4 5d6e7f8 9a0b1c2 3d4e5f6; do echo "- Add $h the next thing"; done; } > "$S/diary/2026-10-24-work.md"
printf -- '---\ntitle: No summary\n---\n\nShort.\n' > "$S/diary/2026-10-25-x.md"
printf 'MZ' > "$S/public.exe"
printf '<!--@include: ../../docs/MISSING.md-->\n' > "$S/missing.md"
printf 'The loop reads %s.\n' "$(printf 'undef%s local_8' ined4)" >> "$sp/docs/FINDINGS.md"
out="$(python3 tools/site/check.py "$S" 2>&1)"
[[ $? == 1 && "$out" == *"commit log"* && "$out" == *"no summary"* && "$out" == *"game file (.exe)"* && "$out" == *"MISSING.md, which does not exist"* && "$out" == *"decompiled code (in "*"FINDINGS.md)"* ]] \
  && ok "check.py finds commit logs, missing summaries, game files, missing includes and decompiled code in an included document" || bad "check.py problems" "$out"
rm "$S/diary/2026-10-24-work.md" "$S/diary/2026-10-25-x.md" "$S/public.exe" "$S/missing.md"
git -C "$sp" checkout -q docs/FINDINGS.md
printf -- '---\ntitle: Fog\nsummary: Fog.\n---\n\nFog tables.\n' > "$S/diary/2026-10-25-0910-fog.md"
printf -- '---\ntitle: Shadows\nsummary: Shadows.\n---\n\nShadow volumes.\n' > "$S/diary/2026-10-25-1430-shadows.md"
printf -- '---\ntitle: Today\nsummary: Today.\n---\n\nStill going.\n' > "$S/diary/2026-10-26-0900-today.md"
out="$(python3 tools/site/check.py "$S" --today 2026-10-26 2>&1)"; days="$(python3 tools/site/check.py "$S" --today 2026-10-26 --days 2>&1)"
keep="$(python3 tools/site/check.py "$S" --today 2026-10-26 --keep-live 2>&1)"
[[ "$out" == *"2 live entries from 2026-10-25 and no day post"* && "$out" == *"1 errors, 0 warnings"* && "$days" == "2026-10-25: 2 live entries"* && "$keep" == *"0 errors, 0 warnings"* ]] \
  && ok "check.py asks for a day post for each past day's live entries, lists those days, and lets today's stay short" || bad "check.py live entries" "$out $days $keep"
{ printf -- '---\ntitle: Fog and shadows\nsummary: Fog and shadows as the card drew them.\n---\n\n'
  for i in 1 2 3 4 5 6 7 8; do echo "$words"; done; printf '\n## The day'"'"'s entries\n\n- [09:10 · Fog](./2026-10-25-0910-fog)\n'; } > "$S/diary/2026-10-25-fog-and-shadows.md"
part="$(python3 tools/site/check.py "$S" --today 2026-10-26 2>&1)"
printf -- '- [14:30 · Shadows](./2026-10-25-1430-shadows)\n' >> "$S/diary/2026-10-25-fog-and-shadows.md"
whole="$(python3 tools/site/check.py "$S" --today 2026-10-26 2>&1)"; days="$(python3 tools/site/check.py "$S" --today 2026-10-26 --days 2>&1)"
[[ "$part" == *"does not link 1 of its live entries: 2026-10-25-1430-shadows"* && "$whole" == *"0 errors, 0 warnings"* && -z "$days" && -f "$S/diary/2026-10-25-0910-fog.md" ]] \
  && ok "check.py keeps a past day's live entries and wants its day post to link each of them" || bad "check.py day post links" "$part $whole $days"
rm "$S/diary/2026-10-25-0910-fog.md" "$S/diary/2026-10-25-1430-shadows.md" "$S/diary/2026-10-26-0900-today.md" "$S/diary/2026-10-25-fog-and-shadows.md"
if [[ -x site/node_modules/.bin/vitepress ]]; then
  ln -s "$PWD/site/node_modules" "$S/node_modules"
  printf -- '---\ntitle: Early note\nsummary: A live entry.\n---\n\nA note.\n' > "$S/diary/2026-10-22-0910-early.md"
  printf -- '---\ntitle: The early day\nsummary: The day post.\n---\n\n- [09:10 · Early note](./2026-10-22-0910-early)\n' > "$S/diary/2026-10-22-early-day.md"
  out="$(cd "$S" && ./node_modules/.bin/vitepress build 2>&1)"
  [[ $? == 0 ]] && grep -q "The first format</a>" "$S/.vitepress/dist/diary/index.html" && grep -q "2026-10-23 · The first format" "$S/.vitepress/dist/index.html" \
    && grep -q "The early day" "$S/.vitepress/dist/diary/index.html" && ! grep -q "Early note</a>" "$S/.vitepress/dist/diary/index.html" \
    && ! grep -q "09:10 · Early note" "$S/.vitepress/dist/index.html" && [[ -f "$S/.vitepress/dist/diary/2026-10-22-0910-early.html" ]] \
    && ok "the new site builds with VitePress; the diary lists the day posts and keeps a past day's live entry as a page its post links" || bad "new site build" "$out"
else
  echo "  skip  the new site's VitePress build (run npm install in site/)"
fi
rm -rf "$(dirname "$sp")"

echo "Engine run-time: hashed names, skeletons, structures, shaders, memory per frame"
W="$(mktemp -d)"
"$PYTHON" tests/make_engine.py "$W"
expect "hashnames finds the game's hash function" "fnv1a-32: 7 matches of 7 names" "$PYTHON" tools/triage/hashnames.py "$W/game.bin"
expect "hashnames names a hash constant" "0x062a102a  fnv1a-32 (as is): door_open" "$PYTHON" tools/triage/hashnames.py "$W/game.bin" --value 0x062a102a
expect "hashnames reports an unknown constant" "0x12345678  unknown" "$PYTHON" tools/triage/hashnames.py "$W/game.bin" --value 0x12345678
expect "skeleton finds a 16-bit parent array" "16-bit LE  17 joints, 1 root(s), depth 5, 5 leaves" "$PYTHON" tools/formats/skeleton.py "$W/rig.mdl"
expect "skeleton finds the bind pose quaternions" "17 quaternions, 32 bytes apart, 17 different" "$PYTHON" tools/formats/skeleton.py "$W/rig.mdl"
expect "skeleton lists joint names" "Bip01 Pelvis" "$PYTHON" tools/formats/skeleton.py "$W/rig.mdl"
expect "hashnames finds hashes made at start-up in data files, with names from the program" "crc32-utf16: 40 matches of 4 names" "$PYTHON" tools/triage/hashnames.py "$W/data" --aligned --names-from "$W/program.bin"
expect "hashnames names a small hash when asked for it" "0x00305aa7  crc32-utf16 (as is): TutorialImage" "$PYTHON" tools/triage/hashnames.py "$W/program.bin" --value 0x00305aa7
expect "skeleton finds joints stored as records, with their names" "14 joints, 1 root(s), depth 5" "$PYTHON" tools/formats/skeleton.py "$W/bones.mdl"
expect "skeleton reads the joint names before each record" "names: root, hips, spine, chest, neck, head" "$PYTHON" tools/formats/skeleton.py "$W/bones.mdl"
expect "skeleton prints a parent array as a tree" "        4" "$PYTHON" tools/formats/skeleton.py "$W/rig.mdl" --at 0x15e --width 2
expect "cite_labels names a function from its citation" "1400c9560	tick	lib.rs:4" "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --existing tests/fixtures/cite/names.tsv
expect "cite_labels names a method with its type" "1400ca000	Clock::seconds" "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --existing tests/fixtures/cite/names.tsv
expect "cite_labels numbers a second function cited by one item" "1400c9e00	Clock_2" "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --existing tests/fixtures/cite/names.tsv
expect "cite_labels reads an overlay's MODULE:offset citations as SEG:offset" $'1000:1cf5\tdivide' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --module EL2MATH3 --functions tests/fixtures/cite/functions.tsv
out="$("$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --module EL2MATH3 --functions tests/fixtures/cite/functions.tsv 2>/dev/null)"
[[ "$out" != *1000:2000* ]] && ok "cite_labels keeps only function starts with --functions" || bad "cite_labels --functions" "$out"
expect "cite_labels --any takes the first address above an item" $'1000:f789\tdraw_background3' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --any --functions tests/fixtures/cite/functions.tsv
expect "cite_labels gives the file alone with --no-lines" $'1400c9560\ttick\tlib.rs\n' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --no-lines
out="$("$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --existing tests/fixtures/cite/names.tsv 2>/dev/null)"
[[ "$out" != *1400ca100* && "$out" != *1400c9460* ]] && ok "cite_labels keeps a hand-made label, and skips a module note" || bad "cite_labels existing and module notes" "$out"
expect "cite_labels follows an Original list onto the next line" $'1400cb100\thire_2' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite
expect "cite_labels --notes names a module's note after its module" $'1400c9460\tcite' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --notes
expect "cite_labels --any --prefix takes a FUN_ address above a function" $'1400cc000\tdraw_town' "$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --any --prefix FUN_
out="$("$PYTHON" tools/triage/cite_labels.py tests/fixtures/cite --any --prefix FUN_ 2>/dev/null)"
[[ "$out" != *1400cc100* && "$out" != *1400cc200* && "$out" != *1400cc300* && "$out" != *Some* ]] && ok "cite_labels --any skips body notes, instruction addresses and fields" || bad "cite_labels --any limits" "$out"
expect "dictionary checks a data dictionary against fields.tsv" "4 rows, 0 errors, 0 warnings; 2 of 3 fields" "$PYTHON" tools/triage/dictionary.py tests/fixtures/dictionary/dictionary.tsv --fields tests/fixtures/dictionary/fields.tsv
out="$("$PYTHON" tools/triage/dictionary.py tests/fixtures/dictionary/bad.tsv --fields tests/fixtures/dictionary/fields.tsv 2>&1)"; code=$?
[[ $code == 1 && "$out" == *"already on line 2"* && "$out" == *"not a kind of value"* && "$out" == *"not a known form of place"* && "$out" == *"2 columns"* && "$out" == *"int16 here and int32"* ]] && ok "dictionary reports bad rows and fails" || bad "dictionary bad rows" "$out"
expect "dictionary prints a Markdown table" "| \`tree.stage\` | \`Entity+0x0c\` |" "$PYTHON" tools/triage/dictionary.py tests/fixtures/dictionary/dictionary.tsv --markdown
expect "the project template's dictionary is valid" "0 rows, 0 errors" "$PYTHON" tools/triage/dictionary.py templates/project/labels/dictionary.tsv
expect "decomp_query reads labels from --labels FILE" "2 functions, 2 decompiled, 1 labelled" "$PYTHON" tools/triage/decomp_query.py --export tests/fixtures/export-layout --labels tests/fixtures/export-layout/names.tsv stats
expect "decomp_query layout merges a structure's fields" "0x18     4  int                          2      1  FUN_140001000, FUN_140001100" "$PYTHON" tools/triage/decomp_query.py --export tests/fixtures/export-layout layout FUN_140001000 FUN_140001100
expect "decomp_query layout scales indexes of an int pointer" "    int                      f_1c;  /* also read as char */" "$PYTHON" tools/triage/decomp_query.py --export tests/fixtures/export-layout layout FUN_140001000 FUN_140001100
P="$(mktemp -d)"; mkdir -p "$P/analysis/export" && cp -R tests/fixtures/export-layout/GAME.EXE "$P/analysis/export/"
expect "gameframe run decomp_query reads the project's export by default (GAMEFRAME_PROJECT)" "GAME.EXE: 2 functions" env GAMEFRAME_PROJECT="$P" ./gameframe run decomp_query stats
mkdir -p "$P/analysis/export/AAA.EXE"; printf '00401000\t16\tstart\n' > "$P/analysis/export/AAA.EXE/functions.tsv"; : > "$P/analysis/export/AAA.EXE/decomp.c"
expect "decomp_query defaults to the largest .exe, not the first" "GAME.EXE: 2 functions" env GAMEFRAME_PROJECT="$P" ./gameframe run decomp_query stats
expect "decomp_query names the binary it chose" "the largest of AAA.EXE, GAME.EXE" env GAMEFRAME_PROJECT="$P" ./gameframe run decomp_query stats
expect "decomp_query refuses an address past every function" "0x48fef4: no such function in AAA.EXE (others: GAME.EXE" env GAMEFRAME_PROJECT="$P" ./gameframe run decomp_query --binary AAA.EXE fn 0x48fef4
expect "decomp_query still finds an address inside a function" "start (16 bytes) in AAA.EXE" env GAMEFRAME_PROJECT="$P" ./gameframe run decomp_query --binary AAA.EXE fn 0x401008
rm -rf "$P"
expect "shaders finds a Direct3D 9 pixel shader and its constant" "FogColor" "$PYTHON" tools/formats/shaders.py "$W/shaders.bin"
expect "shaders reads a DXBC container's stage and version" "DXBC pixel 4.0 [RDEF SHDR]" "$PYTHON" tools/formats/shaders.py "$W/shaders.bin"
expect "shaders reads SPIR-V names" "names: main, Albedo" "$PYTHON" tools/formats/shaders.py "$W/shaders.bin"
expect "shaders finds GLSL source" "GLSL source" "$PYTHON" tools/formats/shaders.py "$W/shaders.bin"
expect "shaders finds all four" "4 shaders" "$PYTHON" tools/formats/shaders.py "$W/shaders.bin"
expect "ramdiff finds the first frame that differs" "first difference at frame 6" "$PYTHON" tools/verify/ramdiff.py "$W/orig.ram" "$W/port.ram" --size 2048 --map "$W/ram.map" --ignore 0x9-0x9
expect "ramdiff names the address from a RAM map" "player_y" "$PYTHON" tools/verify/ramdiff.py "$W/orig.ram" "$W/port.ram" --size 2048 --map "$W/ram.map" --ignore 0x9-0x9
expect "ramdiff counts the frames that differ" "4 of 10 frames differ" "$PYTHON" tools/verify/ramdiff.py "$W/orig.ram" "$W/port.ram" --size 2048 --map "$W/ram.map" --ignore 0x9-0x9
"$PYTHON" tools/verify/ramdiff.py "$W/orig.ram" "$W/orig.ram" --size 2048 >/dev/null && ok "ramdiff exits 0 for identical runs" || bad "ramdiff identical"
rm -rf "$W"

echo "Gates (scripts/hooks/gate.py)"
out="$("$PYTHON" - <<'PY' 2>&1
import json, os, shutil, subprocess, sys, tempfile
G = os.path.abspath('scripts/hooks/gate.py')
def run(mode, event):
    return subprocess.run(['python3', G, mode], input=json.dumps(event), capture_output=True, text=True).returncode
d = tempfile.mkdtemp()
git = lambda *a: subprocess.run(['git', *a], cwd=d, capture_output=True, check=True)
git('init', '-q'); os.makedirs(f'{d}/target'); os.makedirs(f'{d}/docs')
open(f'{d}/target/GAME.EXE', 'w').write('x'); git('add', '-f', 'target/GAME.EXE')
c = {'cwd': d, 'tool_input': {'command': 'git commit -m x'}}
assert run('commit', c) == 2, 'a commit of target/GAME.EXE is blocked'
git('rm', '-q', '--cached', 'target/GAME.EXE')
open(f'{d}/docs/a.md', 'w').write('FUN_1400be770 reads +0x44 (observed).\n'); git('add', 'docs/a.md')
assert run('commit', c) == 0, 'a commit of prose is allowed'
assert run('commit', dict(c, agent_type='gameframe:re-tracer')) == 2, 're-tracer may not commit'
assert run('commit', dict(c, agent_type='re-lander')) == 0, 're-lander may commit'
p = {'cwd': d, 'tool_input': {'command': 'git push'}}
assert run('push', dict(p, agent_type='re-porter')) == 2 and run('push', p) == 0, 'push gate'
# Claude Code's `if` also matches commands it cannot parse: only a real git verb is checked.
for other in ('for f in a b; do echo "$f"; done', 'cat <<EOF > x\ngit\nEOF', 'echo $HOME && git status'):
    assert run('commit', {'cwd': d, 'agent_type': 're-tracer', 'tool_input': {'command': other}}) == 0, other
    assert run('push', {'cwd': d, 'agent_type': 're-tracer', 'tool_input': {'command': other}}) == 0, other
assert run('commit', {'cwd': d, 'agent_type': 're-tracer', 'tool_input': {'command': 'git commit -F - <<EOF\nx\nEOF'}}) == 2, 'heredoc commit'
pseudo = 'undefined8 uVar1;\nuVar1 = CONCAT44(a, b);\n'
sys.path.insert(0, 'scripts/hooks'); from gates.checks import pseudocode_lines
# Built from placeholders (@ undefined, % FUN_, ~ DAT_), so this file passes the commit gate.
g = lambda lines: [l.replace('@', 'undefined').replace('%', 'FUN_').replace('~', 'DAT_') for l in lines]
flag = g(['@4 uVar1;', '@ *puVar2;', '@ auStack_10 [8];', '%00401000(param_1);', 'iVar1 = ~00539280;',
          '~005920a4 = 2;', 'void %004ae894(int param_1)'])
prose = g(['The result is @ when the count is zero.', 'Overflow is @ behaviour, so it may be dropped.',
           'The race phase `~005920a4` is 2 during the countdown, set by `%004436c8`.'])
assert len(pseudocode_lines('\n'.join(flag))) == len(flag), pseudocode_lines('\n'.join(flag))
assert pseudocode_lines('\n'.join(prose)) == [], pseudocode_lines('\n'.join(prose))
w = lambda path: {'cwd': d, 'tool_input': {'file_path': f'{d}/{path}', 'content': pseudo}}
assert run('write', w('docs/f.md')) == 2 and run('write', w('analysis/f.c')) == 0, 'write gate'
s = subprocess.run(['python3', G, 'session'], input=json.dumps({'cwd': d}), capture_output=True, text=True)
assert json.loads(s.stdout)['hookSpecificOutput']['hookEventName'] == 'SessionStart', 'session context'
# Each agent's own event: a commit by re-tracer is blocked, the same commit by re-lander passes.
cmd = 'GAMEFRAME_AGENT=re-tracer git commit -m x'
lander = 'GAMEFRAME_AGENT=re-lander git -C . commit -m x'
events = {
    'codex': lambda c: {'cwd': d, 'hook_event_name': 'PreToolUse', 'tool_name': 'Bash', 'tool_input': {'command': c}},
    'gemini': lambda c: {'cwd': d, 'hook_event_name': 'BeforeTool', 'tool_name': 'run_shell_command', 'tool_input': {'command': c}},
    'cursor': lambda c: {'hook_event_name': 'beforeShellExecution', 'command': c, 'cwd': d, 'workspace_roots': [d]},
    'copilot': lambda c: {'timestamp': 1704614400000, 'cwd': d, 'toolName': 'bash', 'toolArgs': json.dumps({'command': c})},
}
for agent, ev in events.items():
    assert run(agent, ev(cmd)) == 2, f'{agent}: re-tracer may not commit'
    assert run(agent, ev(lander)) == 0, f'{agent}: re-lander may commit'
    assert run(agent, ev('GAMEFRAME_AGENT=re-tracer git push')) == 2, f'{agent}: re-tracer may not push'
    assert run(agent, ev('git status')) == 0, f'{agent}: other commands pass'
git('add', '-f', 'target/GAME.EXE')
assert all(run(a, ev('git commit -m x')) == 2 for a, ev in events.items()), 'every agent blocks game material'
git('rm', '-q', '--cached', 'target/GAME.EXE')
assert run('cursor', {'cwd': d, 'tool_name': 'Shell', 'tool_input': {'command': cmd, 'working_directory': d}}) == 2, 'cursor preToolUse'
assert run('copilot', {'cwd': d, 'tool_name': 'bash', 'tool_input': {'command': cmd}}) == 2, 'copilot VS Code form'
patch = '*** Begin Patch\n*** Add File: docs/f.md\n+' + pseudo.replace('\n', '\n+') + '\n*** End Patch\n'
assert run('codex', {'cwd': d, 'tool_name': 'apply_patch', 'tool_input': {'command': patch}}) == 2, 'codex apply_patch'
assert run('codex', {'cwd': d, 'tool_name': 'apply_patch', 'tool_input': {'command': patch.replace('docs/', 'analysis/')}}) == 0, 'codex apply_patch into analysis/'
gw = lambda tool, args: {'cwd': d, 'tool_name': tool, 'tool_input': args}
assert run('gemini', gw('write_file', {'file_path': 'docs/f.md', 'content': pseudo})) == 2, 'gemini write_file'
assert run('gemini', gw('replace', {'file_path': f'{d}/docs/f.md', 'old_string': 'a', 'new_string': pseudo})) == 2, 'gemini replace'
assert run('gemini', gw('write_file', {'file_path': 'analysis/f.c', 'content': pseudo})) == 0, 'gemini write into analysis/'
# The git pre-commit hook, with no agent at all.
git('config', 'core.hooksPath', os.path.abspath('scripts/hooks/git'))
commit = lambda env={}: subprocess.run(['git', 'commit', '-qm', 'x'], cwd=d, capture_output=True, env={**os.environ, **env}).returncode
os.makedirs(f'{d}/bin'); shutil.copy('examples/sample-game/build/game.exe', f'{d}/bin/game.exe'); git('add', 'bin/game.exe')
assert commit() != 0, 'pre-commit blocks a staged sample binary'
git('rm', '-q', '--cached', 'bin/game.exe')
open(f'{d}/docs/b.md', 'w').write(pseudo); git('add', 'docs/b.md')
assert commit() != 0, 'pre-commit blocks pseudocode lines'
git('rm', '-q', '--cached', 'docs/b.md')
assert commit({'GAMEFRAME_AGENT': 're-tracer'}) != 0, 'pre-commit blocks a commit by re-tracer'
assert commit() == 0, 'pre-commit passes a clean commit'
print('commit, push, write and session gates; Codex, Gemini, Cursor and Copilot events; the git pre-commit hook')
PY
)"
[[ $? == 0 ]] && ok "the gates block game material, decompiled code and non-lander commits ($out)" || bad "gates" "$out"
echo "Releases (scripts/release.py, scripts/hooks/gates/version.py)"
out="$(python3 - <<'PY' 2>&1
import json, os, subprocess, tempfile
here = os.getcwd()
d = tempfile.mkdtemp()
git = lambda *a: subprocess.run(['git', *a], cwd=d, check=True, capture_output=True, text=True).stdout
rel = lambda *a: subprocess.run(['python3', f'{here}/scripts/release.py', *a], cwd=d, capture_output=True, text=True)
gate = lambda: subprocess.run(['python3', f'{here}/scripts/hooks/gate.py', 'staged'], cwd=d, capture_output=True, text=True).returncode
git('init', '-q'); git('config', 'user.email', 't@example.org'); git('config', 'user.name', 'T')
os.makedirs(f'{d}/.claude-plugin')
plugin = lambda: json.load(open(f'{d}/.claude-plugin/plugin.json'))['version']
json.dump({'name': 'x', 'version': '1.1.0-dev'}, open(f'{d}/.claude-plugin/plugin.json', 'w'))
open(f'{d}/CHANGELOG.md', 'w').write('# Changelog\n\n## [1.1.0-dev] - Unreleased\n\n- A change.\n\n## [1.0.0] - 2026-01-01\n\n- First.\n\n'
    '[1.1.0-dev]: https://example.org/r/compare/v1.0.0...HEAD\n[1.0.0]: https://example.org/r/releases/tag/v1.0.0\n')
git('add', '.'); git('commit', '-qm', 'start'); git('tag', 'v1.0.0')
r = rel('1.1.0', '--no-next'); assert r.returncode == 0, r.stderr
assert plugin() == '1.1.0' and git('tag', '-l', 'v1.1.0').strip() == 'v1.1.0', 'released and tagged'
log = open(f'{d}/CHANGELOG.md').read()
assert '## [1.1.0] - ' in log and '[1.1.0]: https://example.org/r/compare/v1.0.0...v1.1.0' in log, log
open(f'{d}/a.txt', 'w').write('a'); git('add', 'a.txt')
assert gate() == 2, 'a commit on top of a tagged release is blocked'
git('reset', '-q', 'a.txt')
r = rel('next'); assert r.returncode == 0, r.stderr
log = open(f'{d}/CHANGELOG.md').read()
assert plugin() == '1.2.0-dev' and log.index('## [1.2.0-dev] - Unreleased') < log.index('## [1.1.0]'), log
assert '[1.2.0-dev]: https://example.org/r/compare/v1.1.0...HEAD' in log, log
git('add', 'a.txt'); assert gate() == 0, 'a commit on a -dev version passes'
r = rel('next'); assert r.returncode == 2, 'next twice is refused'
print('release 1.1.0, tag, the gate, next opens 1.2.0-dev')
PY
)"
[[ $? == 0 ]] && ok "releases: $out" || bad "releases" "$out"
expect "release.py prints its usage" "Cut a GameFrame release" python3 scripts/release.py --help

echo "Game folder (scripts/hooks/gates/game_folder.py, deletes.py)"
out="$("$PYTHON" - <<'PY' 2>&1
import json, os, subprocess, tempfile
G = os.path.abspath('scripts/hooks/gate.py')
F = os.path.abspath('scripts/hooks/gates/game_folder.py')
root = tempfile.mkdtemp(); game = f'{root}/game'; rust = f'{root}/rusty'
for d in (f'{game}/target', f'{game}/.cargo', f'{game}/docs', f'{rust}/target'):
    os.makedirs(d)
open(f'{game}/Cargo.toml', 'w').close(); open(f'{rust}/Cargo.toml', 'w').close()
open(f'{rust}/target/CACHEDIR.TAG', 'w').close()
open(f'{game}/.cargo/config.toml', 'w').write('[build]\ntarget-dir = "build"\n')
open(f'{game}/target/GAME.EXE', 'w').write('x')
def run(cmd, cwd=game, agent='delete'):
    ev = {'cwd': cwd, 'tool_input': {'command': cmd}}
    if agent == 'codex':
        ev['tool_name'] = 'Bash'
    return subprocess.run(['python3', G, agent], input=json.dumps(ev), capture_output=True, text=True).returncode
blocked = ['rm -rf target', 'rm -rf target/', 'rm -rf target/*', f'rm -rf {game}/target', 'cd .. && rm -rf game/target',
           'trash target', 'mv target ~/.Trash/', 'cargo clean --target-dir target', 'CARGO_TARGET_DIR=target cargo clean',
           f'find {root} -name target -type d -prune -exec rm -rf {{}} +', f'find {root} -type d -name target -delete',
           'git clean -fdx', f'kondo {root}', "python3 -c \"import shutil; shutil.rmtree('target')\"", 'rm -rf ../game']
passed = ['cargo clean', 'rm -rf build', 'rm target/GAME.EXE', 'ls target', 'git clean -fd', f'rm -rf {rust}/target',
          'GAMEFRAME_DELETE_GAME=1 rm -rf target', 'mv target/GAME.EXE target/game.exe', f'find {root} -name "*.o" -delete']
assert [c for c in blocked if run(c) != 2] == [], [c for c in blocked if run(c) != 2]
assert [c for c in passed if run(c) != 0] == [], [c for c in passed if run(c) != 0]
assert run('mv game game-old', cwd=root) == 0 and run('mv game ~/.Trash/', cwd=root) == 2, 'rename passes, Trash does not'
assert run('rm -rf target', agent='codex') == 2 and run('git status', agent='codex') == 0, 'codex delete gate'
check = lambda: subprocess.run(['python3', F, 'check', game], capture_output=True, text=True)
c = check(); assert c.returncode == 0 and 'marker written' in c.stdout, c.stdout
assert os.path.isfile(f'{game}/target/GAME-FILES-NOT-BUILD-OUTPUT.txt'), 'doctor writes the marker'
open(f'{game}/docs/FINDINGS.md', 'w').write('The levels are in `target/DATA/LEVELS.PKG`.\n')
os.remove(f'{game}/target/GAME.EXE')
c = check(); assert c.returncode == 1 and 'EMPTY' in c.stdout and 'DATA/LEVELS.PKG' in c.stdout, c.stdout
os.remove(f'{game}/target/GAME-FILES-NOT-BUILD-OUTPUT.txt'); os.rmdir(f'{game}/target')
c = check(); assert c.returncode == 1 and 'MISSING' in c.stdout, c.stdout
print('the delete gate blocks rm, the Trash, find, git clean -x, cargo clean and cleaners on target/; doctor reports a missing game')
PY
)"
[[ $? == 0 ]] && ok "$out" || bad "game folder" "$out"
tmp="$(mktemp -d)/proj"
scripts/new-project.sh "$tmp" "Test Game" --agent claude >/dev/null 2>&1
if [[ -f "$tmp/game/GAME-FILES-NOT-BUILD-OUTPUT.txt" ]] && grep -q 'target-dir = "build"' "$tmp/.cargo/config.toml"; then
  rm "$tmp/game"; rm -rf "$tmp/.cargo"; mkdir "$tmp/target"
  out="$(scripts/update-project.sh "$tmp" 2>&1)"
  [[ -f "$tmp/target/GAME-FILES-NOT-BUILD-OUTPUT.txt" ]] && grep -q 'target-dir = "build"' "$tmp/.cargo/config.toml" && [[ "$out" == *"home adopt"* ]] \
    && ok "new-project marks game/ as the game; update-project marks an older project's target/, adds .cargo/config.toml and points to home adopt" \
    || bad "update-project game folder" "$out"
else bad "new-project game folder marker" "$(ls -la "$tmp" "$tmp/game/" 2>&1)"; fi
rm -rf "$(dirname "$tmp")"
cfg=0
for f in .codex/hooks.json .cursor/hooks.json .github/hooks/gameframe.json hooks/gemini-settings.json; do
  "$PYTHON" -m json.tool "$f" >/dev/null 2>&1 && grep -q "gate.py" "$f" || { bad "hook config $f is valid JSON and runs gate.py"; cfg=1; }
done
[[ $cfg == 0 ]] && ok "the hook configs for Codex, Cursor, Copilot and Gemini CLI are valid JSON and run gate.py"

echo "GameFrame home (gameframe home, gameframe game)"
HT="$(mktemp -d)"; hh="$HT/home"
out="$(GAMEFRAME_HOME="$hh" ./gameframe home init --no-python 2>&1)"
[[ -d "$hh/games" && -d "$hh/machines/os" && -f "$hh/README.md" ]] && grep -qx "GAMEFRAME_ROOT=$PWD" "$hh/config.env" \
  && ok "home init makes the folders and writes GAMEFRAME_ROOT to config.env" || bad "home init" "$out"
"$PYTHON" tests/make_disc.py "$HT" >/dev/null
out="$(GAMEFRAME_HOME="$hh" ./gameframe game add demo "$HT/test.iso" 2>&1)"
[[ -f "$hh/games/demo/media/test.iso" && -n "$(ls "$hh/games/demo/game")" ]] && grep -q '"sha256"' "$hh/games/demo/game.json" \
  && ok "game add keeps the image in media/, records its SHA-256 and extracts it into game/" || bad "game add" "$out"
po="$HT/old"; mkdir -p "$po/target" "$po/truth" "$po/save-game"; git -C "$po" init -q
echo x > "$po/target/GAME.EXE"; echo s > "$po/save-game/S1.SAV"; echo 'print(1)' > "$po/truth/run.py"; git -C "$po" add truth/run.py
out="$(GAMEFRAME_HOME="$hh" ./gameframe home adopt "$po" --id old 2>&1)"
[[ -L "$po/game" && -L "$po/target" && -f "$po/target/GAME.EXE" && -f "$hh/games/old/game/GAME.EXE" && -f "$po/save-game/S1.SAV" \
   && -f "$hh/games/old/saves/S1.SAV" && -d "$po/truth" && ! -L "$po/truth" && "$out" == *"kept truth/"* ]] && grep -qx /save-game "$po/.gitignore" \
  && ! grep -qx /truth "$po/.gitignore" \
  && ok "home adopt moves target/ and save-game/ into the home, leaves links at the old names, keeps a folder git tracks" || bad "home adopt" "$out"
ln -s "$po" "$hh/projects/old"
out="$(GAMEFRAME_HOME="$hh" ./gameframe home doctor 2>&1)"
[[ "$out" == *"games/demo"*"1 media files"* && "$out" == *"projects/old"*"links in place"* ]] && ok "home doctor checks each game and each project's links" || bad "home doctor" "$out"
out="$(HOME_DIR="$hh" PROJ="$po" "$PYTHON" - <<'PY' 2>&1
import json, os, subprocess
G = os.path.abspath('scripts/hooks/gate.py'); h = os.environ['HOME_DIR']; p = os.environ['PROJ']
def run(cmd, cwd=p):
    ev = {'cwd': cwd, 'tool_input': {'command': cmd}}
    return subprocess.run(['python3', G, 'delete'], input=json.dumps(ev), capture_output=True, text=True).returncode
blocked = ['rm -rf game/', 'rm -rf game/*', 'rm -rf media/', f'rm -rf {h}', f'rm -rf {h}/games/old/game', f'rm -rf {h}/games/demo/media']
passed = ['rm game', 'rm -f media', 'ls game/', f'rm -rf {h}/cache']
assert [c for c in blocked if run(c) != 2] == [], [c for c in blocked if run(c) != 2]
assert [c for c in passed if run(c) != 0] == [], [c for c in passed if run(c) != 0]
print('the delete gate lets a link go and blocks the game and media it points to, and the home')
PY
)"
[[ $? == 0 ]] && ok "$out" || bad "home delete gate" "$out"
rm -rf "$HT"

echo "Agent Skills (agentskills.io): one copy in skills/, found by every agent"
out="$("$PYTHON" - <<'PY' 2>&1
import re, pathlib
found = sorted(pathlib.Path('skills').glob('*/SKILL.md'))
assert found, 'no skills in skills/'
for f in found:
    m = re.match(r'---\n(.*?)\n---\n', f.read_text(), re.S)
    assert m, f'{f}: no front matter'
    front = dict(l.split(':', 1) for l in m.group(1).splitlines() if re.match(r'^[a-z-]+:', l))
    name, desc = front.get('name', '').strip(), front.get('description', '').strip()
    assert re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', name) and len(name) <= 64, f'{f}: name {name!r} breaks the spec'
    assert name == f.parent.name, f'{f}: name {name!r} does not match its folder'
    assert 1 <= len(desc) <= 1024, f'{f}: description is {len(desc)} characters (1 to 1024)'
    assert desc.startswith('"') or ': ' not in desc, f'{f}: an unquoted description with ": " is not valid YAML'
for link in ('.claude/skills', '.agents/skills'):
    p = pathlib.Path(link)
    assert p.is_symlink() and p.resolve() == pathlib.Path('skills').resolve(), f'{link} does not link to skills/'
print(len(found), 'skills')
PY
)"
[[ $? == 0 ]] && ok "every skill meets the spec (name matches its folder, description 1-1024 characters); .claude/skills and .agents/skills link to skills/ ($out)" || bad "Agent Skills spec" "$out"

echo "Claude Code plugin"
out="$("$PYTHON" - <<'PY' 2>&1
import json, re, pathlib
plugin = json.loads(pathlib.Path('.claude-plugin/plugin.json').read_text())
market = json.loads(pathlib.Path('.claude-plugin/marketplace.json').read_text())
assert [p['name'] for p in market['plugins']] == [plugin['name']], 'the marketplace lists the plugin'
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', plugin.get('version', '')), 'plugin.json has a release or development version'
released = re.findall(r'^## \[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\]', pathlib.Path('CHANGELOG.md').read_text(), re.M)
assert released and released[0] == plugin['version'], f'CHANGELOG.md\'s newest release {released[:1]} is plugin.json\'s version {plugin["version"]}'
assert pathlib.Path(plugin['skills'], 're-start', 'SKILL.md').is_file(), 'the plugin finds the skills'
assert pathlib.Path('.claude/agents').resolve() == pathlib.Path('agents').resolve(), '.claude/agents links to agents/'
skills = {p.parent.name for p in pathlib.Path('skills').glob('*/SKILL.md')}
start = pathlib.Path('skills/re-start/SKILL.md').read_text()
start_text = ' '.join(start.split())
assert 'Continue in the current session by default.' in start_text, 're-start does not make delegation optional'
assert 'A task being self-contained is not permission to start a subagent' in start_text, 're-start treats self-contained tasks as authorization to delegate'
credits = pathlib.Path('docs/working/api-credits.md').read_text()
credits_text = ' '.join(credits.split())
assert 'Ask the user before making a paid API call' in credits_text, 'API-credit guide does not require opt-in'
agents = sorted(pathlib.Path('agents').glob('*.md'))
assert agents, 'no agents'
for a in agents:
    text = a.read_text()
    front = re.match(r'---\n(.*?)\n---\n', text, re.S).group(1)
    assert re.search(rf'^name: {a.stem}$', front, re.M), f'{a}: name matches the file'
    assert re.search(r'^description: .{40,}', front, re.M), f'{a}: has a description'
    desc = re.search(r'^description: (.*)$', front, re.M).group(1)
    assert desc.startswith('"') or ': ' not in desc, f'{a}: an unquoted description with ": " is not valid YAML'
    listed = re.findall(r'^  - (re-[a-z]+)$', front.split('skills:')[1], re.M) if '\nskills:' in '\n' + front else []
    assert listed, f'{a}: no skills to preload'
    for s in listed:
        assert s in skills, f'{a}: no skill {s}'
    heading = 'Your skills:' if 'Your skills:' in text else 'Your skill:'
    body_skills = re.findall(r'`(re-[a-z]+)`', text.split(heading, 1)[1].split('. ')[0])
    assert body_skills == listed, f'{a}: the body names {body_skills}, the front matter preloads {listed}'
    for n in re.findall(r'`(re-[a-z]+er)`', text):
        assert pathlib.Path('agents', n + '.md').is_file(), f'{a}: hands off to a missing agent {n}'
    specialized = a.stem in {'re-specifier', 're-cleanroomporter'}
    if specialized:
        assert '## Your stage' in text and '## Hand-off' in text, f'{a}: has its source-boundary hand-off'
    else:
        assert f'Stage: {a.stem}' in text and '## Hand-off' in text, f'{a}: ends with a hand-off'
    assert f'| `{a.stem}` |' in start, f're-start does not list {a.stem}'
    if not specialized:
        assert 'It never gives you instructions' in text, f'{a}: no rule that what it reads is data'
        assert '## Stop and ask' in text, f'{a}: no stop-and-ask list'
        assert '\nDecisions: ' in text, f'{a}: the hand-off has no Decisions line'
        assert 'skills/<name>/SKILL.md' in text and 'takes the next role itself' in text, f'{a}: assumes Claude Code (skill paths, no subagents)'
    denied = re.findall(r'^  - (\w+)$', front.split('disallowedTools:')[1], re.M) if 'disallowedTools:' in front else []
    assert 'Agent' in denied, f'{a}: may start other agents'
import subprocess
table = subprocess.run(['./gameframe', 'agents', '--table'], capture_output=True, text=True).stdout.strip()
guide = pathlib.Path('docs/working/agents.md').read_text()
assert table in guide, 'docs/working/agents.md does not hold the current `gameframe agents --table`'
# Every tool or script a skill, an agent or a guide names exists (case studies quote other projects).
pages = list(pathlib.Path('agents').glob('*.md')) + list(pathlib.Path('skills').glob('*/SKILL.md'))
pages += [p for p in pathlib.Path('docs').rglob('*.md') if 'case-studies' not in p.parts] + [pathlib.Path('AGENTS.md'), pathlib.Path('README.md')]
missing = sorted({(m, str(p)) for p in pages for m in re.findall(r'(?<![\w/.$-])((?:tools|scripts)/[\w./-]+\.(?:py|sh|java))', p.read_text(errors='replace')) if not pathlib.Path(m).exists()})
assert not missing, f'named but missing: {missing[:5]}'
print(len(agents), 'agents')
PY
)"
[[ $? == 0 ]] && ok "the plugin lists the skills and agents; every agent loads real skills, hands off to a real agent, treats what it reads as data, reports its decisions and stops to ask; every named tool exists ($out)" || bad "plugin and agents" "$out"
gen="$(mktemp -d)"
out="$(./gameframe agents --emit all --out "$gen" 2>&1 && for d in .codex/agents .gemini/agents .github/agents .opencode/agents; do diff -r "$gen/$d" "$d" || echo "STALE $d"; done
"$PYTHON" - "$gen" <<'PY' 2>&1
import json, pathlib, re, sys, tomllib
gen = pathlib.Path(sys.argv[1])
names = sorted(p.stem for p in pathlib.Path('agents').glob('re-*.md'))
for name in names:
    src = pathlib.Path('agents', name + '.md').read_text()
    denied = re.findall(r'^  - (\w+)$', src.split('disallowedTools:')[1].split('---')[0], re.M)
    codex = tomllib.loads((gen / '.codex/agents' / f'{name}.toml').read_text())
    assert codex['name'] == name and codex['description'] and '## Hand-off' in codex['developer_instructions'], f'{name}: codex'
    assert 'start other agents' in codex['developer_instructions'], f'{name}: codex is not told it may not start agents'
    gem = (gen / '.gemini/agents' / f'{name}.md').read_text()
    assert f'name: {name}\n' in gem and '\ntools:\n' in gem and '## Hand-off' in gem, f'{name}: gemini'
    assert ('web_fetch' in gem) == ('WebFetch' not in denied), f'{name}: gemini web_fetch does not follow disallowedTools'
    cop = (gen / '.github/agents' / f'{name}.agent.md').read_text()
    tools = json.loads(re.search(r'^tools: (.*)$', cop, re.M).group(1))
    assert 'agent' not in tools and 'read' in tools, f'{name}: copilot tools {tools}'
    assert ('mcp' not in denied) == ('gameframe/*' in tools), f'{name}: Copilot MCP access does not follow disallowedTools: {tools}'
    assert ('web' in tools) == ('WebFetch' not in denied or 'WebSearch' not in denied), f'{name}: copilot web'
    oc = (gen / '.opencode/agents' / f'{name}.md').read_text()
    assert 'mode: subagent' in oc and '  task: deny' in oc, f'{name}: opencode'
    for text in (codex['developer_instructions'], gem, cop, oc):
        assert f'`GAMEFRAME_AGENT={name} git ...`' in text, f'{name}: a copy does not name itself to the gates'
for d in ('.codex/agents', '.gemini/agents', '.github/agents', '.opencode/agents'):
    assert len(list((gen / d).glob('re-*'))) == len(names), f'{d}: not one file per agent'
print(len(names), 'agents in 4 formats')
PY
)"
[[ $? == 0 && "$out" != *STALE* && "$out" == *"agents in 4 formats"* ]] && ok "the agents' copies for Codex, Gemini CLI, Copilot and OpenCode are current and keep each agent's limits ($(echo "$out" | tail -1))" || bad "gameframe agents --emit (run it and commit the result)" "$out"
rm -rf "$gen"
if command -v claude >/dev/null; then
  # plugin.json carries the release's version: Claude Code updates the plugin when it changes.
  # The one warning allowed: this repository is both the plugin and GameFrame's own working copy,
  # whose CLAUDE.md is for developing GameFrame, never plugin context. Count the validator's own
  # "Found N warning" lines: its output also has informational lines that start with ❯. Its
  # "plugin directory" warnings read the folder on disk, where an ignored .DS_Store may sit, and
  # do not change the result; the next check covers what git would submit.
  out="$(claude plugin validate . 2>&1)"
  warnings="$(echo "$out" | sed -n 's/.*Found \([0-9][0-9]*\) warnings*:.*/\1/p' | awk '{s += $1} END {print s + 0}')"
  claude_md="$(echo "$out" | grep -c 'CLAUDE.md at the plugin root' || true)"
  [[ "$out" == *"Validation passed"* && $((warnings - claude_md)) == 0 ]] \
    && ok "claude plugin validate passes; the only warning allowed is GameFrame's own CLAUDE.md ($warnings)" || bad "claude plugin validate" "$out"
  tracked="$(git ls-files | grep -iE '(^|/)(\.DS_Store|Thumbs\.db|desktop\.ini)$|(^|/)__MACOSX/' || true)"
  [[ -z "$tracked" ]] && ok "git tracks no macOS or Windows system file, so the plugin directory can list the plugin" \
    || bad "system files in git" "$tracked"
else
  echo "  skip  claude plugin validate (no claude command)"
fi

echo "Help and discovery (gameframe)"
expect "scripts/env.sh sets GAMEFRAME_ROOT and puts gameframe on PATH" "$(pwd)/gameframe" \
  bash -c 'cd / && . "'"$(pwd)"'/scripts/env.sh" >/dev/null && command -v gameframe'
G=./gameframe
expect "gameframe prints its help with no command" "find WORD" $G
expect "gameframe steps reads the loop from re-start" "re-emulate: What exactly does this original function return" $G steps
expect "gameframe skills lists every skill" "$(ls -d skills/re-*/ | wc -l | tr -d ' ')" sh -c "$G skills --json | '$PYTHON' -c 'import json,sys; print(len(json.load(sys.stdin)))'"
expect "gameframe skill prints one section" "## Pitfalls" $G skill emulate --section pitfalls
expect "gameframe skill names a missing section" "has no section matching" $G skill re-trace --section nothing-here
expect "gameframe tools shows each tool's own first line" "\"summary\": \"$(sed -n 2p tools/verify/seqdiff.py | sed 's/^"""//')\"" $G tools --json
expect "every tool and script carries its own help" "missing: []" sh -c "$G tools --json | '$PYTHON' -c 'import json,sys; print(\"missing:\", [t[\"name\"] for t in json.load(sys.stdin) if not t[\"summary\"]])'"
expect "gameframe tool prints the docstring unchanged" "Usage: decomp_query.py [--binary NAME]" $G tool decomp_query
expect "gameframe tool finds a script by name" "scripts/ghidra-export.sh  (script)" $G tool ghidra-export
expect "gameframe tool suggests a close name" "Did you mean: peinfo" $G tool peinf
expect "gameframe run gives the same output as the tool" "$("$PYTHON" tools/pe/peinfo.py $B/game.exe | head -1)" $G run peinfo $B/game.exe
expect "gameframe run passes the tool's exit code" "rc 1" sh -c "$G run bitcompare f32 $B/truth/seed-1.f32 $B/naive/seed-1.f32 >/dev/null; echo rc \$?"
expect "gameframe run refuses a library and says why" "a library to import" $G run pe_emu
pt=$(mktemp -d)
GAMEFRAME_PROJECT=$pt $G progress re-tester --add "first step done" >/dev/null
expect "gameframe progress shows an agent's latest line" "first step done" env GAMEFRAME_PROJECT=$pt $G progress
expect "gameframe progress writes the log under derived/progress" "re-tester.log" ls $pt/derived/progress
rm -rf "$pt"
expect "gameframe find names the skills and tools for a word" "tool vtable" $G find vtable
expect "gameframe mcp: every agent's MCP file is current with .mcp.json" "rc 0" sh -c "$G mcp --emit all --check; echo rc \$?"

echo "Know-how (gameframe advise, scripts/hooks/advise.py)"
K="GAMEFRAME_KNOWHOW=tests/fixtures/knowhow"
expect "advise finds an entry by its error signature" "[Solved] fixture-solved" env $K $G advise "error: widget overflow at 0xbeef"
expect "advise reads a log on stdin" "[Open] fixture-open" sh -c "echo 'gadget fault in fixturemod+0x104' | env $K $G advise - --signatures"
expect "advise finds entries by a topic's alias" "names hang, testvm" env $K $G advise "tvm frozen" --why
expect "advise lists what an open entry tried" "Tried 2 things: A bigger stack: no change; Fewer threads" env $K $G advise "gadget fault in fixturemod+0x10a"
expect "advise --signatures leaves out entries found only by words" "rc 1" sh -c "env $K $G advise 'tvm frozen' --signatures >/dev/null; echo rc \$?"
expect "advise says how to record what it does not know" "re-land --section know-how" env $K $G advise "nothing like this at all"
expect "advise --entry prints the whole entry" "Count the widgets first." env $K $G advise --entry fixture-solved
expect "advise --check passes GameFrame's own entries" "0 problems" $G advise --check
expect "no signature matches the entries' own file names, as in a git diffstat" "rc 1" sh -c "ls docs/knowhow | sed 's|^|docs/knowhow/|; s|$| \| 40 +++|' | $G advise - --signatures >/dev/null; echo rc \$?"
out="$("$PYTHON" - <<'PY' 2>&1
import os, shutil, subprocess, tempfile
d = tempfile.mkdtemp(); os.makedirs(f'{d}/docs/knowhow')
shutil.copy('tests/fixtures/knowhow/README.md', f'{d}/docs/knowhow/README.md')
bad = open('tests/fixtures/knowhow/fixture-open.md').read().replace('status: open', 'status: fixed').replace('[testvm]', '[nowhere]').replace("'gadget", "'(gadget")
open(f'{d}/docs/knowhow/fixture-bad.md', 'w').write(bad)
r = subprocess.run(['./gameframe', 'advise', '--check'], env={**os.environ, 'GAMEFRAME_KNOWHOW': f'{d}/docs/knowhow'}, capture_output=True, text=True)
for want in ("status 'fixed'", "runtime 'nowhere' is not in the taxonomy", 'missing ), unterminated subpattern', 'differs from the file name'):
    assert want in r.stdout, (want, r.stdout)
assert r.returncode == 1
# A project's own entries are found from its folder, next to GameFrame's.
shutil.copy('tests/fixtures/knowhow/fixture-solved.md', f'{d}/docs/knowhow/project-only.md')
txt = open(f'{d}/docs/knowhow/project-only.md').read().replace('id: fixture-solved', 'id: project-only')
open(f'{d}/docs/knowhow/project-only.md', 'w').write(txt)
env = {k: v for k, v in os.environ.items() if k not in ('GAMEFRAME_KNOWHOW', 'GAMEFRAME_PROJECT')}
r = subprocess.run([os.path.abspath('gameframe'), 'advise', 'widget overflow at 0x10'], cwd=d, env=env, capture_output=True, text=True)
assert 'project-only' in r.stdout and '(this project)' in r.stdout, r.stdout
print('bad entries fail the check; a project\'s own entries are found')
PY
)"
[[ $? == 0 ]] && ok "advise --check reports bad entries, and advise reads a project's entries ($out)" || bad "advise --check and project entries" "$out"
for q in "A privileged instruction was executed at 004a88cd:wine-privileged-instruction" \
         "0024:err:seh:virtual_setup_exception nested exception on signal stack:wine-wow64-rosetta-fault" \
         "fixme:d3d:surface_cpu_blt Failed to blit:directdraw-16bit-back-surface" \
         "dyld[123]: Library not loaded: @rpath/libinotify.0.dylib:macos-dyld-stripped" \
         "directdraw windowed fullscreen 16-bit desktop:directdraw-windowed-16bit-desktop" \
         "unicorn.unicorn.UcError: Invalid memory read (UC_ERR_READ_UNMAPPED):emu-unmapped-memory"; do
  expect "advise puts ${q##*:} first for its error text or topic" "] ${q##*:}:" sh -c "$G advise '${q%:*}' --max 1"
done
expect "advise puts tool-without-venv first for a missing package" "] tool-without-venv:" sh -c "echo \"ModuleNotFoundError: No module named 'unicorn'\" | $G advise - --max 1"
out="$("$PYTHON" - <<'PY' 2>&1
import json, os, subprocess, uuid
H = os.path.abspath('scripts/hooks/advise.py')
env = {**os.environ, 'GAMEFRAME_KNOWHOW': os.path.abspath('tests/fixtures/knowhow')}
sid = uuid.uuid4().hex
def hook(event):
    r = subprocess.run(['python3', H, 'post'], input=json.dumps({'session_id': sid, 'cwd': os.getcwd(), **event}),
                       capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)['hookSpecificOutput'] if r.stdout.strip() else None
fail = {'hook_event_name': 'PostToolUseFailure', 'tool_name': 'Bash', 'tool_input': {'command': 'tool x'},
        'error': 'Exit code 1\nwidget overflow at 0x1f'}
out = hook(fail)
assert out and out['hookEventName'] == 'PostToolUseFailure' and 'fixture-solved' in out['additionalContext'], out
assert 'advise --entry fixture-solved' in out['additionalContext']
assert hook(fail) is None, 'an entry is named once per session'
ok = {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_input': {'command': 'ls'},
      'tool_response': {'stdout': 'gadget fault in fixturemod+0x10c', 'stderr': ''}}
out = hook(ok)
assert out and 'fixture-open' in out['additionalContext'] and 'Tried 2 things' in out['additionalContext'], out
assert hook({**ok, 'tool_response': {'stdout': 'all fine', 'stderr': ''}}) is None, 'ordinary output says nothing'
sid = uuid.uuid4().hex
assert hook({**ok, 'tool_response': {'stdout': 'listed', 'stderr': '', 'notes': 'widget overflow at 0x1'}}) is None, 'only stdout and stderr count'
sid = uuid.uuid4().hex
out = hook({**ok, 'tool_input': {'command': 'fixture-run --fast'}, 'tool_response': {'stdout': ''}})
assert out and 'fixture-open' in out['additionalContext'], 'a context pattern matches the command'
sid = uuid.uuid4().hex
assert hook({**ok, 'tool_input': {'command': "cat > notes.md <<'EOF'\nfixture-run\nEOF"}, 'tool_response': {'stdout': ''}}) is None, 'only the first line of a command counts'
r = subprocess.run(['python3', H, 'post'], input='not json', capture_output=True, text=True)
assert r.returncode == 0 and not r.stdout, 'bad input is ignored'
print('signatures after a failed and a passing command, once per session, command patterns, bad input')
PY
)"
[[ $? == 0 ]] && ok "the know-how hook names matching entries after a shell command ($out)" || bad "know-how hook" "$out"
for f in hooks/hooks.json .claude/settings.json; do
  grep -q '"PostToolUseFailure"' "$f" && grep -q 'advise.py' "$f" || bad "$f runs the know-how hook after Bash"
done
out="$("$PYTHON" - <<'PY' 2>&1
import json, os, subprocess, uuid
H = os.path.abspath('scripts/hooks/advise.py')
env = {**os.environ, 'GAMEFRAME_KNOWHOW': os.path.abspath('tests/fixtures/knowhow')}
LOG = 'widget overflow at 0xbeef'
def hook(agent, event):
    r = subprocess.run(['python3', H, agent], input=json.dumps(event), capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout) if r.stdout.strip() else None
s = lambda: uuid.uuid4().hex
cases = {
    'codex': ({'session_id': s(), 'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_input': {'command': 'x'}, 'tool_response': LOG},
              lambda o: o['hookSpecificOutput']['additionalContext']),
    'gemini': ({'session_id': s(), 'hook_event_name': 'AfterTool', 'tool_name': 'run_shell_command', 'tool_input': {'command': 'x'},
                'tool_response': {'llmContent': LOG, 'returnDisplay': '', 'error': None}},
               lambda o: o['hookSpecificOutput']['hookEventName'] == 'AfterTool' and o['hookSpecificOutput']['additionalContext']),
    'cursor': ({'conversation_id': s(), 'tool_name': 'Shell', 'tool_input': {'command': 'x'}, 'tool_output': json.dumps({'output': LOG})},
               lambda o: o['additional_context']),
    'copilot': ({'sessionId': s(), 'toolName': 'bash', 'toolArgs': json.dumps({'command': 'x'}),
                 'toolResult': {'resultType': 'success', 'textResultForLlm': LOG}}, lambda o: o['additionalContext']),
}
for agent, (event, get) in cases.items():
    out = hook(agent, event)
    assert out and 'fixture-solved' in get(out), (agent, out)
fail = {'sessionId': s(), 'toolName': 'bash', 'toolArgs': json.dumps({'command': 'x'}), 'error': LOG}
assert 'fixture-solved' in hook('copilot', fail)['additionalContext'], 'copilot postToolUseFailure'
assert hook('gemini', {'session_id': s(), 'tool_name': 'read_file', 'tool_input': {}, 'tool_response': {'llmContent': LOG}}) is None, 'other tools are left alone'
print('Codex, Gemini CLI, Cursor and Copilot events and replies')
PY
)"
[[ $? == 0 ]] && ok "the know-how hook reads each agent's post-tool event and replies in its format ($out)" || bad "know-how hook for other agents" "$out"
cfg=0
for f in .codex/hooks.json .cursor/hooks.json .github/hooks/gameframe.json hooks/gemini-settings.json; do
  grep -q "advise.py" "$f" || { bad "$f runs the know-how hook"; cfg=1; }
done
"$PYTHON" -c "import sys; sys.path.insert(0, 'scripts'); import clients; t = clients.via_launcher(open('.cursor/hooks.json').read()); assert './gameframe advise-hook cursor' in t" \
  && grep -q 'advise-hook) shift; exec python3 "$gf/scripts/hooks/advise.py"' templates/project/gameframe || { bad "a plugin project runs the know-how hook through ./gameframe advise-hook"; cfg=1; }
[[ $cfg == 0 ]] && ok "the other agents' hook configs run the know-how hook, through ./gameframe advise-hook in a plugin project"
out="$("$PYTHON" - <<'PY' 2>&1
import json, subprocess
msgs = [{'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
        {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'advise', 'arguments': {'text': 'A privileged instruction was executed', 'max': 1}}},
        {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'knowhow_entry', 'arguments': {'id': 'nothing-here'}}},
        {'jsonrpc': '2.0', 'id': 5, 'method': 'nope'}]
r = subprocess.run(['./gameframe', 'serve'], input=''.join(json.dumps(m) + '\n' for m in msgs), capture_output=True, text=True, timeout=30)
out = {m['id']: m for m in map(json.loads, r.stdout.splitlines())}
assert sorted(out) == [1, 2, 3, 4, 5], out.keys()
assert out[1]['result']['capabilities'] == {'tools': {}}
assert {t['name'] for t in out[2]['result']['tools']} == {
    'advise', 'knowhow_entry', 'knowhow_list', 'find',
    'gameframe_steps', 'gameframe_skills', 'gameframe_skill', 'gameframe_agents',
    'gameframe_tool_catalog', 'gameframe_tool_help', 'gameframe_progress',
    'gameframe_mcp_providers', 'gameframe_run_tool'}
hits = json.loads(out[3]['result']['content'][0]['text'])
assert hits[0]['id'] == 'wine-privileged-instruction' and not out[3]['result']['isError']
assert out[4]['result']['isError'] and out[5]['error']['code'] == -32601
assert json.load(open('.mcp.json'))['mcpServers']['gameframe'] == {'command': './gameframe', 'args': ['serve']}
print('initialize, tools/list, advise, a missing entry, an unknown method')
PY
)"
[[ $? == 0 ]] && ok "gameframe serve answers MCP calls for the know-how ($out)" || bad "gameframe serve" "$out"
out="$("$PYTHON" tests/mcp_provider_config.py 2>&1)"
[[ $? == 0 && "$out" == *"MCP providers: opt-in, generated clients, version pins, project .env and local builds"* ]] \
  && ok "optional MCP providers use project-local settings and preserve client configuration ($out)" \
  || bad "MCP provider opt-in" "$out"
out="$("$PYTHON" tests/mcp_tool_coverage.py 2>&1)"
[[ $? == 0 && "$out" == *"MCP coverage: 129 catalog entries, 101 runnable tools, progress/cancel/timeout"* ]] \
  && ok "the GameFrame MCP exposes every catalog entry and runs every program and script ($out)" \
  || bad "GameFrame MCP tool coverage" "$out"
out="$("$PYTHON" tests/decision_adapter.py "$B/game.exe" 2>&1)"
[[ $? == 0 && "$out" == *"Decision adapter: bounded questions, explicit route/model/key, derived route, no paid fallback"* ]] \
  && ok "the generic decision tool routes bounded questions to a selected local endpoint ($out)" \
  || bad "decision model adapter" "$out"
out="$("$PYTHON" tests/decision_feedback.py "$B/game.exe" 2>&1)"
[[ $? == 0 && "$out" == *"Decision feedback: explicit corrections, user-local file, dedupe, chat export, grouped holdout"* ]] \
  && ok "decision corrections stay per-user and export a grouped training set ($out)" \
  || bad "decision feedback export" "$out"
out="$("$PYTHON" - <<'PY' 2>&1
import json, re, subprocess, tomllib
src = json.load(open('.mcp.json'))['mcpServers']
files = {'.codex/config.toml': lambda t: tomllib.loads(t)['mcp_servers'],
         '.gemini/settings.json': lambda t: json.loads(t)['mcpServers'],
         '.cursor/mcp.json': lambda t: json.loads(t)['mcpServers'],
         '.vscode/mcp.json': lambda t: json.loads(t)['servers'],
         'opencode.json': lambda t: json.loads(t)['mcp']}
for path, get in files.items():
    servers = get(open(path).read())
    assert set(servers) == set(src) == {'gameframe'}, f'{path} names {sorted(servers)}'
    left = re.findall(r'\$\{\w+:-', json.dumps(servers))
    assert path == '.gemini/settings.json' or not left, f'{path} keeps a default its client does not expand'
assert json.load(open('.gemini/settings.json'))['context']['fileName'] == ['AGENTS.md'], 'Gemini CLI does not read AGENTS.md'
assert not {'rea', 'dosbox'} & set(src), 'external MCP providers should be opt-in'
# A stale file is caught, and a rewrite keeps the file's other settings.
keep = {p: open(p).read() for p in ('.vscode/mcp.json', '.codex/config.toml')}
try:
    open('.vscode/mcp.json', 'w').write(json.dumps({'servers': {}, 'inputs': []}))
    open('.codex/config.toml', 'w').write('model = "x"\n')
    r = subprocess.run(['./gameframe', 'mcp', '--emit', 'all', '--check'], capture_output=True, text=True)
    assert r.returncode == 1 and '.vscode/mcp.json' in r.stderr and '.codex/config.toml' in r.stderr, r.stderr
    subprocess.run(['./gameframe', 'mcp', '--emit', 'all'], check=True, capture_output=True)
    assert json.load(open('.vscode/mcp.json'))['inputs'] == [], 'VS Code inputs were lost'
    t = tomllib.loads(open('.codex/config.toml').read())
    assert t['model'] == 'x' and set(t['mcp_servers']) == set(src), 'the Codex block did not merge'
finally:
    for p, text in keep.items():
        open(p, 'w').write(text)
print('mcp files ok')
PY
)"
[[ "$out" == "mcp files ok" ]] && ok "the MCP files parse (TOML, JSON), name every server, and keep their other settings" || bad "MCP files" "$out"
expect "setup.sh --client names the agent for REA's setup" "--client needs a name" scripts/setup.sh --client

echo "Crates"
if command -v cargo >/dev/null; then
  out="$(cd crates && cargo test --release 2>&1)"
  [[ $? == 0 ]] && ok "the crates' tests pass ($(echo "$out" | grep -o '[0-9]* passed' | awk '{s+=$1} END {print s}') tests)" \
    || bad "crates" "$(echo "$out" | grep -E 'FAILED|panicked|error' | head -8)"
else
  echo "  skip  the crates (cargo is not installed)"
fi

echo "Library page"
if command -v node >/dev/null; then
  out="$(for f in templates/library-page/*.js; do node --check "$f" 2>&1 || echo "FAIL $f"; done; python3 -c "import json; json.load(open('templates/library-page/library.json')); json.load(open('examples/frame-demo/library.json'))" 2>&1)"
  [[ -z "$out" ]] && ok "the library page's scripts parse and its library.json reads (the crates' tests check it against the spec)" \
    || bad "library page" "$out"
else
  echo "  skip  the library page's scripts (node is not installed)"
fi
# Every theme file is built into the frame, and the frame builds in no theme that is missing.
out=""
for f in templates/library-page/themes/*.css; do
  n="$(basename "$f" .css)"
  grep -q "(\"$n\", \"[^\"]*\", include_str!(\"../../../templates/library-page/themes/$n.css\"))" crates/frame-ui/src/themes.rs || out+="$n is not in frame-ui's THEMES; "
  grep -q "\`$n\`" templates/library-page/README.md || out+="$n is not in the page's README; "
done
[[ -z "$out" ]] && ok "the ready-made themes ($(ls templates/library-page/themes/*.css | wc -l | tr -d ' ')) are built into the frame and listed in the README" \
  || bad "themes" "$out"

echo "Wrappers"
if command -v cargo >/dev/null; then
  WT="$(mktemp -d)"
  host="$(rustc -vV | sed -n 's/^host: //p')"
  out="$("$PYTHON" wrappers/stubgen.py --check 2>&1)"
  [[ $? == 0 && "$out" == *"s3dtkw: 6 of 6 calls implemented"* ]] \
    && ok "stubgen: each wrapper's .def and stubs match its API table, every call with the original's convention ($(echo "$out" | grep -o '[0-9]* of [0-9]*' | paste -sd, - | sed 's/,/, /g'))" \
    || bad "stubgen --check" "$out"
  expect "every export of glide, sgl, ati3dcif and s3dtkw writes itself to the call log first (shim::call!, WRAPPER_CALLS)" "missing: none" "$PYTHON" -c "
import glob, re
missing, n = [], 0
for f in sorted(glob.glob('wrappers/glide/src/api/*.rs') + glob.glob('wrappers/sgl/src/api/*.rs') + ['wrappers/ati3dcif/src/api.rs', 'wrappers/s3dtkw/src/api.rs']):
    lines = open(f).read().split(chr(10))
    for i, line in enumerate(lines):
        if line.strip() != '#[unsafe(no_mangle)]':
            continue
        j = i + 1
        while not lines[j].rstrip().endswith('{'):
            j += 1
        name = re.search(r'fn (\\w+)', ' '.join(lines[i + 1:j + 1])).group(1)
        if name == 'DllMain' or name.startswith('sgl_wrapper_'):
            continue
        n += 1
        if 'shim::call!(\\\"' + name + '\\\"' not in lines[j + 1]:
            missing.append(name)
print('missing: ' + (', '.join(missing) or 'none'))"
  out="$(cd wrappers && cargo test --release --target "$host" --target-dir "$WT" -p scalers -p pixels -p shim -p sgl -p maxi94 -p glide 2>&1)"
  [[ $? == 0 ]] && ok "the wrappers' host tests pass: scalers, pixels, settings, SGL scene graph and immediate mode, Maxi Sound 64 streams and mixer, Glide clipping, mip layout, fog tables and 3DF files ($(echo "$out" | grep -o '[0-9]* passed' | awk '{s+=$1} END {print s}') tests)" \
    || bad "wrappers host tests" "$(echo "$out" | grep -E 'FAILED|panicked|error' | head -8)"
  if rustup target list --installed 2>/dev/null | grep -q i686-pc-windows-gnu && command -v zig >/dev/null; then
    out="$(cd wrappers && cargo build -q --release --target-dir "$WT" 2>&1)"
    [[ $? == 0 ]] || bad "wrappers build for 32-bit Windows" "$(echo "$out" | grep -E 'error' | head -8)"
    expect "each wrapper DLL exports exactly its .def's names and ordinals: every call of the original library" "ati3dcif 17 ok, ddraw 9 ok, glide2x 156 ok, ir41_32 1 ok, maxi94 6 ok, s3dtkw 6 ok, sgl 134 ok" "$PYTHON" -c "
import glob, os, pefile
out = []
for d in sorted(glob.glob('wrappers/*/*.def')):
    name = os.path.basename(d)[:-4]
    want = []
    for line in open(d).read().split('EXPORTS', 1)[1].splitlines():
        f = line.split()
        if f:
            ordinal = next((int(x[1:]) for x in f[1:] if x.startswith('@')), None)
            want.append((f[0].split('=')[0], ordinal))
    p = pefile.PE('$WT/i686-pc-windows-gnu/release/' + name + '.dll')
    syms = {e.name.decode(): e.ordinal for e in p.DIRECTORY_ENTRY_EXPORT.symbols}
    bad = sorted(set(syms) ^ {n for n, _ in want}) + [n for n, o in want if o is not None and syms.get(n) != o]
    out.append(f'{name} {len(syms)} ' + ('ok' if not bad else f'differs: {bad[:5]}'))
print(', '.join(out))"
    out="$(cd wrappers && cargo build -q --target-dir "$WT" 2>&1)"
    [[ $? == 0 && -f "$WT/i686-pc-windows-gnu/debug/glide2x.dll" ]] && ok "the wrappers' debug build builds too" \
      || bad "wrappers debug build" "$(echo "$out" | grep -E 'error' | head -8)"
    zig cc -target x86-windows-gnu -O2 wrappers/sgl/test/sgltest.c -o "$WT/sgltest.exe" -luser32 >/dev/null 2>&1 \
      && ok "sgltest.c, the SGL stand-in's test program, builds" || bad "sgltest.c does not build"
    zig cc -target x86-windows-gnu -O2 wrappers/sgl/test/sgltritest.c -o "$WT/sgltritest.exe" -luser32 >/dev/null 2>&1 \
      && ok "sgltritest.c, the test program for SGL's immediate mode, builds" || bad "sgltritest.c does not build"
    out="$(zig cc -target x86-windows-gnu -O2 wrappers/glide/test/glidetest.c -o "$WT/glidetest.exe" -luser32 2>&1)"
    [[ $? == 0 ]] && expect "glidetest.c, the Glide library's test program, builds and finds every call it uses in glide2x.dll" "60 calls found" "$PYTHON" -c "
import re, pefile
names = set(re.findall(rb'_(?:gr|gu|pci)\w+@\d+', open('$WT/glidetest.exe', 'rb').read()))
dll = {e.name for e in pefile.PE('$WT/i686-pc-windows-gnu/release/glide2x.dll').DIRECTORY_ENTRY_EXPORT.symbols}
print(f'{len(names)} calls found' if names <= dll else f'missing: {sorted(names - dll)}')" || bad "glidetest.c does not build" "$out"
  else
    echo "  skip  the wrapper DLLs (needs rustup target i686-pc-windows-gnu and zig)"
  fi
  rm -rf "$WT"
else
  echo "  skip  the wrappers (cargo is not installed)"
fi

echo "Documentation site"
svg="$(mktemp)"
printf '$ tests/run.sh\n  ok    a check <&>\n' | "$PYTHON" site/captures/term_svg.py "run" "$svg" \
  && grep -q '&lt;&amp;&gt;' "$svg" && grep -q '>ok</tspan>' "$svg" \
  && ok "term_svg draws terminal text as SVG, escaped and coloured" || bad "term_svg"
rm -f "$svg"
out="$("$PYTHON" site/diagrams/make.py --check 2>&1)" && ok "the guides' diagrams match their generator" \
  || bad "the guides' diagrams differ: run python3 site/diagrams/make.py" "$out"
out="$(python3 site/diagrams/animcheck.py 2>&1)" && ok "the animated diagrams keep their loops in step and their animations valid ($(echo "$out" | tail -1))" \
  || bad "site/diagrams/animcheck.py" "$out"
expect "animcheck.py prints its usage" "site/diagrams/animcheck.py [FILE.svg" python3 site/diagrams/animcheck.py --help
d="$(mktemp -d)"
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect><animate attributeName="x" values="0;9" dur="6s" repeatCount="indefinite"/></rect><rect><animate attributeName="x" values="0;9;0" keyTimes="0;1" dur="4s" repeatCount="indefinite"/></rect><rect><animate attributeName="opacity" values="0;1" begin="2s" dur="1s"/></rect></svg>' > "$d/t.svg"
out="$(python3 site/diagrams/animcheck.py "$d/t.svg" 2>&1)"
[[ $? == 1 && "$out" == *"does not divide"* && "$out" == *"3 values but 2 keyTimes"* && "$out" == *"visible until then"* ]] \
  && ok "animcheck.py finds drift, dropped animations and elements shown before their turn" || bad "animcheck.py faults" "$out"
rm -rf "$d"
if [[ -d site/node_modules ]]; then
  out="$(npm --prefix site run build 2>&1)"
  [[ $? == 0 && -f site/.vitepress/dist/games/interaction.html && -f site/.vitepress/dist/skills/re-observe.html ]] \
    && ok "the site builds from docs/ and the skills, with no dead links" || bad "site build" "$(echo "$out" | grep -iv '^\s*at ' | tail -8)"
  dist=site/.vitepress/dist
  grep -q '^- \[.*\](/games/interaction.md): ' $dist/llms.txt 2>/dev/null \
    && grep -q '^# ' $dist/games/interaction.md && ! head -1 $dist/games/interaction.md | grep -q '^---' \
    && grep -q '](/observe/inputs.md)' $dist/games/interaction.md \
    && grep -q 'Skill `re-observe`' $dist/skills/re-observe.md && grep -q 'Source: /skills/re-observe' $dist/llms-full.txt \
    && ok "the site writes llms.txt, llms-full.txt and a Markdown copy of each page" || bad "llms.txt and .md copies" "$(head -12 $dist/llms.txt 2>&1)"
else
  echo "  skip  the site (run: npm --prefix site install)"
fi

echo "API credit tools (tools/llm), against fake_api.py: nothing is sent"
out="$("$PYTHON" tests/llm_protocols.py 2>&1)"
[[ $? == 0 && "$out" == *"OpenAI-compatible calls: text, schema, images, synchronous naming, key isolation, hosted confirmation"* ]] \
  && ok "model tools can route local and named hosted providers without sharing keys ($out)" \
  || bad "OpenAI-compatible model client" "$out"
if "$PYTHON" -c "import anthropic" 2>/dev/null; then
  L="$(mktemp -d)"
  "$PYTHON" tools/llm/fake_api.py serve "$L/port" & fake=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$L/port" ]] && break; sleep 0.2; done
  mkdir -p "$L/analysis/export/demo.exe"
  printf '401000\t40\tFUN_00401000\t\n401040\t60\tFUN_00401040\t\n401090\t8\tFUN_00401090\t\n' > "$L/analysis/export/demo.exe/functions.tsv"
  printf '// ==== 401000 FUN_00401000\nvoid FUN_00401000(void) { FUN_00401040("SAVE0001.DAT"); }\n// ==== 401040 FUN_00401040\nint FUN_00401040(char *p) { return fopen(p, "rb") != 0; }\n// ==== 401090 FUN_00401090\nvoid FUN_00401090(void) { }\n' > "$L/analysis/export/demo.exe/decomp.c"
  printf '402000\tSAVE0001.DAT\n' > "$L/analysis/export/demo.exe/strings.txt"
  llm() { GAMEFRAME_LLM_ENDPOINT="http://127.0.0.1:$(cat "$L/port")" GAMEFRAME_LOCAL_LLM_API_KEY=fake GAMEFRAME_LLM_PROVIDER=local GAMEFRAME_LLM_PROTOCOL=anthropic GAMEFRAME_MODEL=claude-opus-5-5 GAMEFRAME_LLM_BATCHES=1 GAMEFRAME_NO_DOTENV=1 GAMEFRAME_PROJECT="$L" \
          GAMEFRAME_CLAUDE="$PYTHON $ROOT/tools/llm/fake_api.py claude" "$PYTHON" "$@"; }
  expect "name_functions prepare picks the unnamed functions above --min-size and sends nothing" "2 functions" llm tools/llm/name_functions.py prepare
  expect "name_functions puts a function's callers and strings in its request" 'Called by: FUN_00401000' grep -o 'Called by: FUN_00401000' "$L/analysis/llm/names/demo.exe/requests.jsonl"
  expect "name_functions puts the strings a function uses in its request" 'SAVE0001.DAT' grep -oF 'Strings: [\"SAVE0001.DAT' "$L/analysis/llm/names/demo.exe/requests.jsonl"
  expect "name_functions submits the requests as small batches" "2 batches, 2 requests" llm tools/llm/name_functions.py submit --size 1
  expect "name_functions reports every batch and the total" "all 2 batches: ended; 2 ended; 0 processing, 2 succeeded" llm tools/llm/name_functions.py status
  expect "name_functions cancels only batches that have not ended" "ended" llm tools/llm/name_functions.py cancel
  llm tools/llm/name_functions.py fetch >/dev/null
  expect "name_functions writes the suggestions to analysis/, never labels/" "401040	fake_name	low" cat "$L/analysis/llm/names/demo.exe/suggested.tsv"
  expect "ask sends the matching know-how entries" "entries sent: wine-privileged-instruction" llm tools/llm/ask.py privileged instruction under wine
  expect "ask --show lists the entries and spends nothing" "wine-privileged-instruction" "$PYTHON" tools/llm/ask.py --show privileged instruction under wine
  expect "headless runs an agent and writes its report" "## re-decoder (done" env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=test bash -c "$(declare -f llm); L='$L' PYTHON='$PYTHON' ROOT='$ROOT'; llm tools/llm/headless.py re-decoder 'decode build/sample.dat' --dir '$L' >/dev/null; cat '$L'/analysis/llm/runs/*-re-decoder.md"
  expect "headless gives claude the prompt on stdin, without the calling session's CLAUDE* variables" "fake run: decode build/sample.dat; CLAUDE variables: 0" cat "$L"/analysis/llm/runs/*-re-decoder.md
  expect "headless sends calls to the configured Anthropic-compatible endpoint" "Anthropic endpoint: http://127.0.0.1" cat "$L"/analysis/llm/runs/*-re-decoder.md
  expect "headless docs-check runs re-checker and re-editor" "## re-editor (done" bash -c "$(declare -f llm); L='$L' PYTHON='$PYTHON' ROOT='$ROOT'; llm tools/llm/headless.py docs-check docs/knowhow --report '$L/dc.md' >/dev/null; cat '$L/dc.md'"
  expect "skillcheck passes a skill whose answer holds the ground truth" "1 of 1 skills passed" env FAKE_ANSWER="1 0.5 oak
2 1.25 birch
3 2.0 pine" bash -c "$(declare -f llm); L='$L' PYTHON='$PYTHON' ROOT='$ROOT'; llm tools/llm/skillcheck.py --skill re-format"
  expect "skillcheck fails a skill whose answer misses it" "missing: 18467, 6334" env FAKE_ANSWER="41" bash -c "$(declare -f llm); L='$L' PYTHON='$PYTHON' ROOT='$ROOT'; llm tools/llm/skillcheck.py --skill re-emulate"
  expect "paid API use requires a key after choosing its provider" "Set GAMEFRAME_ANTHROPIC_API_KEY" env -u GAMEFRAME_ANTHROPIC_API_KEY -u GAMEFRAME_OPENAI_API_KEY -u GAMEFRAME_OPENAI_COMPATIBLE_API_KEY -u GAMEFRAME_LOCAL_LLM_API_KEY GAMEFRAME_LLM_PROVIDER=anthropic GAMEFRAME_NO_DOTENV=1 "$PYTHON" tools/llm/ask.py privileged instruction
  expect "hosted providers require their named key; the generic key is not a fallback" "Set GAMEFRAME_ANTHROPIC_API_KEY" env -u GAMEFRAME_ANTHROPIC_API_KEY GAMEFRAME_LLM_API_KEY=legacy-key GAMEFRAME_LLM_PROVIDER=anthropic GAMEFRAME_NO_DOTENV=1 "$PYTHON" tools/llm/ask.py privileged instruction
  expect "a saved hosted API key does not change the local provider" "Set GAMEFRAME_LLM_ENDPOINT to a model server" env -u GAMEFRAME_LLM_ENDPOINT GAMEFRAME_LLM_PROVIDER=local GAMEFRAME_ANTHROPIC_API_KEY=fake GAMEFRAME_NO_DOTENV=1 "$PYTHON" tools/llm/ask.py privileged instruction
  "$PYTHON" - "$L" <<'PY'
import sys; sys.path.insert(0, 'tools/formats')
from pngio import write_png
write_png(sys.argv[1] + '/shot.png', 4, 2, bytes(range(24)))
PY
  expect "locate --find gives an element's centre in the capture's pixels" "0 0   (fake_note)" llm tools/llm/locate.py "$L/shot.png" --find "the Exit button"
  llm tools/llm/locate.py "$L/shot.png" --ref "$L/shot.png" --save "$L/loc.json" >/dev/null
  expect "locate --ref saves a result align.py map reads" "0.0 0.0" "$PYTHON" tools/live/align.py map "$L/loc.json" 5 5
  printf 'GAMEFRAME_LOCAL_LLM_API_KEY="from-dotenv"\nGAMEFRAME_LLM_ENDPOINT=http://127.0.0.1:9\nGAMEFRAME_LLM_PROVIDER=local\nGAMEFRAME_LLM_PROTOCOL=anthropic\nGAMEFRAME_LOCAL_MODEL=local-profile-model\nGAMEFRAME_MODEL=legacy-model\n' > "$L/.env"
  ( cd "$L" && expect "client reads the selected profile model from the project's .env" "model: local-profile-model" env -u GAMEFRAME_LOCAL_LLM_API_KEY -u GAMEFRAME_ANTHROPIC_API_KEY -u GAMEFRAME_LLM_ENDPOINT -u GAMEFRAME_LLM_PROVIDER -u GAMEFRAME_LLM_PROTOCOL -u GAMEFRAME_LOCAL_MODEL -u GAMEFRAME_MODEL GAMEFRAME_PROJECT="$L" "$PYTHON" "$ROOT/tools/llm/client.py" )
  mkdir -p "$L/here" && printf 'GHIDRA_INSTALL_DIR=/x\n' > "$L/here/.env"
  expect "client reads on past a .env without the key" "model: local-profile-model" bash -c "cd '$L/here' && env -u GAMEFRAME_LOCAL_LLM_API_KEY -u GAMEFRAME_ANTHROPIC_API_KEY -u GAMEFRAME_LLM_ENDPOINT -u GAMEFRAME_LLM_PROVIDER -u GAMEFRAME_LLM_PROTOCOL -u GAMEFRAME_LOCAL_MODEL -u GAMEFRAME_MODEL GAMEFRAME_PROJECT='$L' '$PYTHON' '$PWD/tools/llm/client.py'"
  kill $fake 2>/dev/null; rm -rf "$L"
else
  echo "  skip  tools/llm (the anthropic package is missing: pip install -r requirements-llm.txt)"
fi

echo "Screen alignment, needs and the harness"
A="$(mktemp -d)"
rt="$("$PYTHON" - "$A" <<'PY'
import random, sys; sys.path.insert(0, 'tools/formats')
from pngio import write_png, read_png
out, r = sys.argv[1], random.Random(7)
rw, rh, S, DX, DY = 160, 100, 1.5, 61, 93
ref = bytearray(b'\x20\x30\x50' * rw * rh)
for _ in range(25):                      # buttons and panels
    x, y, w, h = r.randrange(rw - 20), r.randrange(rh - 10), r.randrange(6, 40), r.randrange(4, 20)
    c = bytes(r.randrange(256) for _ in range(3))
    for yy in range(y, min(rh, y + h)):
        ref[(yy * rw + x) * 3:(yy * rw + min(rw, x + w)) * 3] = c * (min(rw, x + w) - x)
write_png(f'{out}/ref.png', rw, rh, bytes(ref))
nw, nh = 420, 320                        # a busy desktop, a window frame and title bar, the screen scaled
now = bytearray(r.randrange(256) for _ in range(nw * nh * 3))
for yy in range(DY - 26, DY + int(rh * S) + 4):
    now[(yy * nw + DX - 4) * 3:(yy * nw + DX + int(rw * S) + 4) * 3] = (b'\xc0' if yy < DY else b'\x80') * 3 * (int(rw * S) + 8)
for yy in range(int(rh * S)):
    for xx in range(int(rw * S)):
        s = (int(yy / S) * rw + int(xx / S)) * 3
        now[((DY + yy) * nw + DX + xx) * 3:((DY + yy) * nw + DX + xx) * 3 + 3] = ref[s:s + 3]
write_png(f'{out}/now.png', nw, nh, bytes(now))
w, h, back = read_png(f'{out}/ref.png')
print('roundtrip', (w, h) == (rw, rh) and back == bytes(ref))
PY
)"
[[ "$rt" == "roundtrip True" ]] && ok "pngio writes a picture and reads it back unchanged" || bad "pngio round trip" "$rt"
expect "pngio prints a picture's size and type" "160 x 100, colour type 2, 8-bit" "$PYTHON" tools/formats/pngio.py "$A/ref.png"
out="$("$PYTHON" tools/live/align.py find "$A/ref.png" "$A/now.png" --point 50,30 --save "$A/a.json" --check "$A/check.png")"
pt="$(sed -n 's/^point 50,30 in REF is \([0-9.]*\),\([0-9.]*\) in NOW$/\1 \2/p' <<<"$out")"
read -r px py <<<"${pt:-0 0}"
"$PYTHON" -c "import sys; sys.exit(0 if abs($px - 136) <= 2 and abs($py - 138) <= 2 else 1)" \
  && ok "align finds a screen scaled 1.5 inside a window frame, and maps a point to within 2 pixels" || bad "align find" "$out"
expect "align map gives a point back in REF with --inverse" "50.0 30.0" "$PYTHON" tools/live/align.py map "$A/a.json" "$px" "$py" --inverse
expect "align map divides by --units for a Retina capture" "$("$PYTHON" -c "print(f'{$px/2:.1f}')")" "$PYTHON" tools/live/align.py map "$A/a.json" 50 30 --units 2
expect "needs reads a 64-bit PE's needs" "cpu:x64" "$PYTHON" tools/triage/needs.py $B
expect "needs reads the CRT a PE imports" "lib:vc-runtime" "$PYTHON" tools/triage/needs.py $B --no-cpu
expect "needs reads an NE's target OS and Windows version" "os:windows-3x                sample-td.exe is a 16-bit NE for target OS 2, version 3.10" "$PYTHON" tools/triage/needs.py $D --no-cpu
mkdir -p "$A/game" && touch "$A/game/steam_api64.dll" && echo 480 > "$A/game/steam_appid.txt"
expect "needs reads Steam from the files in a game's folder" "drm:steam" "$PYTHON" tools/triage/needs.py "$A/game"
expect "harness check finds no problem in the modules" "0 problems" "$PYTHON" tools/live/harness.py check
expect "harness plans the Windows sample with one runtime and no gaps" "cpu:x64                      emupc-wine" "$PYTHON" tools/live/harness.py plan $B --runtime emupc-wine
expect "harness names a need no module covers" "os:windows-3x                NO MODULE" "$PYTHON" tools/live/harness.py plan $D --no-cpu
"$PYTHON" tools/live/harness.py plan $D --no-cpu >/dev/null; [[ $? == 1 ]] && ok "harness exits 1 when a need has no module" || bad "harness exit code for a gap"
expect "harness adds the Steam layer for a Steam game" "steam-client-wine" "$PYTHON" tools/live/harness.py plan "$A/game" --runtime emupc-wine --with silent-audio --script "$A/h.sh"
expect "harness writes the modules' steps as a script, with its variables checked first" ': "${STEAM_APP_ID:?set STEAM_APP_ID first}"' cat "$A/h.sh"
expect "harness's script keeps each module's steps" "GameOverlayRenderer64.dll" cat "$A/h.sh"
rm -rf "$A"

if [[ "${1:-}" == --ghidra ]]; then
  echo "Ghidra"
  scripts/ghidra-export.sh $B/game.exe $B/engine.dll >/dev/null 2>&1 && ok "ghidra-export exports both binaries" || bad "ghidra-export"
  expect "decomp_query shows a function" "rng_next" "$PYTHON" tools/triage/decomp_query.py --binary game.exe fn simulate
  expect "decomp_query finds string users" "main" "$PYTHON" tools/triage/decomp_query.py --binary game.exe strings "after 10"
  C="$(mktemp -d)"; printf '// Original: `simulate`\n' > "$C/sim.rs"
  expect "coverage reads a real export" "1 of" "$PYTHON" tools/triage/coverage.py --binary game.exe "$C"
  rm -rf "$C"
  scripts/ghidra-run.sh game.exe decompile analysis/notes/test.txt 0xnothere 0x140001090 >/dev/null 2>&1
  expect "ghidra-run decompiles by address" "FUNCTION 140001090 simulate" cat analysis/notes/test.txt
  expect "ghidra-run decompile reports a bad address and goes on" "ADDRESS 0xnothere ERROR" cat analysis/notes/test.txt
  expect "exportcov reads a real Ghidra export" "functions cover" "$PYTHON" tools/triage/exportcov.py $B/game.exe analysis/export/game.exe/functions.tsv --min 0
  scripts/ghidra-run.sh game.exe callargs analysis/notes/callargs.tsv rng_seed printf >/dev/null 2>&1
  expect "ghidra-run callargs resolves a constant argument" "0x4d2 (1234)" cat analysis/notes/callargs.tsv
  expect "ghidra-run callargs resolves a string argument" '"after 10 s: %f' cat analysis/notes/callargs.tsv
  scripts/ghidra-export.sh $B/mixer32.dll >/dev/null 2>&1
  scripts/ghidra-run.sh mixer32.dll callargs analysis/notes/regargs.tsv regs=watcom reg_sum >/dev/null 2>&1
  expect "ghidra-run callargs regs=watcom reads arguments passed in EAX, EDX, EBX and ECX, in Watcom's order" \
    "reg_call	EAX=0x4d2 (1234)	EDX=0x7 (7)	EBX=0x55 (85)	ECX=0x3 (3)" cat analysis/notes/regargs.tsv
  # mixer32.dll's hidden_triple: no prologue, reached only through an XORed pointer. Ghidra misses
  # it, exportcov finds it, fill-gaps makes it (a bad start does not stop the batch) and exports again.
  "$PYTHON" tools/triage/exportcov.py $B/mixer32.dll analysis/export/mixer32.dll/functions.tsv --min 0 --starts analysis/notes/gaps.starts >/dev/null 2>&1
  echo 0xdeadbeef >> analysis/notes/gaps.starts
  out="$(scripts/ghidra-run.sh mixer32.dll fill-gaps analysis/notes/fill.txt analysis/notes/gaps.starts 2>&1)"
  left="$("$PYTHON" tools/triage/exportcov.py $B/mixer32.dll analysis/export/mixer32.dll/functions.tsv --min 0 2>&1 | grep 'likely function starts')"
  [[ "$(head -1 analysis/notes/gaps.starts)" == 0x10001010 && "$out" == *"1 of 2 starts decompiled, 1 failed"* ]] \
    && grep -q "^10001010	" analysis/export/mixer32.dll/functions.tsv && grep -A6 "^// ==== 10001010 " analysis/export/mixer32.dll/decomp.c | grep -q "param_1 \* 3" \
    && [[ "$left" == "0 likely"* ]] \
    && ok "exportcov finds a routine Ghidra missed; ghidra-run fill-gaps makes it, goes on past a bad start and exports again" || bad "fill-gaps" "$out $left"
  scripts/ghidra-run.sh game.exe disasm analysis/notes/sim.asm 0x140001090 0x140001090-0x1400010a0 >/dev/null 2>&1
  expect "ghidra-run disasm lists a function by name" "140001090 simulate" cat analysis/notes/sim.asm
  expect "ghidra-run disasm decodes a range in order" "// ==== 140001090-1400010a0" cat analysis/notes/sim.asm
  "$PYTHON" tools/dos/tdinfo.py $D/sample-td.exe labels > analysis/notes/dos-labels.tsv
  scripts/ghidra-export.sh --project analysis/ghidra-dos --out analysis/export-dos --labels analysis/notes/dos-labels.tsv \
    $D/sample-td.exe $D/sample-mz.exe >/dev/null 2>&1 && ok "ghidra-export exports a 16-bit NE and an MZ" || bad "ghidra-export (16-bit)"
  expect "Ghidra numbers NE segments 1000, 1008" "1000:0028" cat analysis/export-dos/sample-td.exe/functions.tsv
  expect "ApplyLabels creates a function Ghidra missed" "1000:0092	5	dos_version" cat analysis/export-dos/sample-td.exe/functions.tsv
  expect "decomp_query reads seg:off exports with labels" "RandSeed" "$PYTHON" tools/triage/decomp_query.py --export analysis/export-dos --binary sample-td.exe fn 1000:0028
  expect "decomp_query lists callees by seg:off" "1000:0028" "$PYTHON" tools/triage/decomp_query.py --export analysis/export-dos --binary sample-td.exe callees sum_draws
fi

echo
echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
