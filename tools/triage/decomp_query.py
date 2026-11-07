#!/usr/bin/env python3
"""Answer questions about a Ghidra export (scripts/ghidra-export.sh) without reading it whole.

Usage: decomp_query.py [--binary NAME] [--export DIR] [--labels FILE ...] COMMAND ARGS

Commands:
  fn ADDR|NAME          one function's pseudocode, with your labels applied
  callers ADDR|NAME     the functions that call or reference it
  callees ADDR|NAME     the functions it calls (with sizes, labelled ones first)
  find TEXT             the functions whose pseudocode contains TEXT (a string, a constant...)
  strings TEXT          defined strings containing TEXT, and the functions that use each
  writers OFFSET        the functions that store to `+ OFFSET` of a pointer (who sets a field?)
  layout FN[:VAR] ...   a structure's fields from the functions that use it: each offset with
                        its sizes, types, reads, writes and users, then a C struct to start
                        from. VAR is the pointer to it in that function (default param_1)
  biggest [N]           the N largest functions not yet labelled (where the work is)
  stats                 functions, labelled share by count and by size

ADDR is an address as Ghidra prints it (1400be770, 0x1400be770 or FUN_1400be770; for 16-bit
programs seg:off, 1000:873a or FUN_1000_873a). NAME is a
Ghidra name or one of your labels. Labels come from labels/names.tsv (address<TAB>label<TAB>
evidence): add a row every time you identify a function, and every later answer is easier to
read. A file of labels for this binary alone, labels/<binary name>.tsv in the current folder, is
read first (for overlays and DLLs whose addresses overlap). The labels are then read from each
--labels FILE (the first file to name an address wins), else from labels/names.tsv in the current folder
(the project you work in), else from the project's, else from GameFrame's own. `--binary` picks a
binary when the export holds several. The default is the only one, or else the .exe with the most
functions, so a game wins over its small launcher; a note on stderr names the choice. An address
must fall inside a function of that binary, or the query stops and names the other binaries.

`--export` defaults to analysis/export in the project: the folder GAMEFRAME_PROJECT names (a
project's `./gameframe` sets it), else GameFrame's own folder.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The game's project, which a project's own `gameframe` launcher names; GameFrame itself otherwise.
PROJECT = os.environ.get('GAMEFRAME_PROJECT') or ROOT
HEADER = re.compile(r'^// ==== ([0-9a-fA-F:]+) (.*)$')
FUN = re.compile(r'FUN_([0-9a-fA-F]+)(?:_([0-9a-fA-F]{4}))?')


def parse_addr(text):
    """An address as an int: flat (0x1400be770) or segmented (1000:873a -> 0x1000873a)."""
    t = text.lower().removeprefix('fun_').removeprefix('0x').replace('_', ':')
    if ':' in t:
        seg, off = t.split(':')
        return (int(seg, 16) << 16) | int(off, 16)
    return int(t, 16)


def fun_addr(m):
    """The address in a FUN_ match: FUN_1400be770 or FUN_1000_873a."""
    if m.group(2):
        return (int(m.group(1), 16) << 16) | int(m.group(2), 16)
    return int(m.group(1), 16)


def function_count(export_dir, binary):
    """How many functions a binary's export lists, 0 when it has no functions.tsv."""
    path = os.path.join(export_dir, binary, 'functions.tsv')
    if not os.path.exists(path):
        return 0
    with open(path, 'rb') as f:
        return sum(1 for _ in f)


class Export:
    def __init__(self, export_dir, binary=None, labels_file=None):
        names = sorted(os.listdir(export_dir)) if os.path.isdir(export_dir) else []
        if not names:
            sys.exit(f'no export in {export_dir}: run scripts/ghidra-export.sh first')
        if binary is None:
            exes = [n for n in names if n.lower().endswith('.exe')] or names
            binary = max(exes, key=lambda n: function_count(export_dir, n))
            if len(exes) > 1:
                print(f'// {binary}, the largest of {", ".join(exes)}: --binary picks another',
                      file=sys.stderr)
        self.dir = os.path.join(export_dir, binary)
        self.binary = binary
        self.others = [n for n in names if n != binary]
        own = os.path.join(os.getcwd(), 'labels', os.path.splitext(binary)[0] + '.tsv')
        self.labels = load_one(own) if os.path.exists(own) else {}
        self.labels.update({a: n for a, n in load_labels(labels_file).items() if a not in self.labels})
        self.functions = {}   # addr -> (name, size)
        self.segmented = False
        for line in open(os.path.join(self.dir, 'functions.tsv'), encoding='utf-8', errors='replace'):
            cols = line.rstrip('\n').split('\t')
            self.segmented = self.segmented or ':' in cols[0]
            self.functions[parse_addr(cols[0])] = (cols[2], int(cols[1]))
        self.bodies = {}      # addr -> pseudocode
        current, buf = None, []
        for line in open(os.path.join(self.dir, 'decomp.c'), encoding='utf-8', errors='replace'):
            m = HEADER.match(line)
            if m:
                if current is not None:
                    self.bodies[current] = ''.join(buf)
                current, buf = parse_addr(m.group(1)), []
            else:
                buf.append(line)
        if current is not None:
            self.bodies[current] = ''.join(buf)
        self.by_name = {}
        for a, (n, _) in self.functions.items():
            if not n.startswith('FUN_'):
                self.by_name.setdefault(n, a)
                self.by_name.setdefault(n.split('::')[-1], a)

    def fmt(self, addr):
        return f'{addr >> 16:04x}:{addr & 0xFFFF:04x}' if self.segmented else f'{addr:#x}'

    def fun(self, addr):
        return f'FUN_{addr >> 16:04x}_{addr & 0xFFFF:04x}' if self.segmented else f'FUN_{addr:x}'

    def name(self, addr):
        return self.labels.get(addr) or self.functions.get(addr, (self.fun(addr), 0))[0]

    def resolve(self, text):
        t = text.lower().removeprefix('fun_').removeprefix('0x')
        if re.fullmatch(r'[0-9a-f]+|[0-9a-f]{4}[:_][0-9a-f]{4}', t):
            addr = parse_addr(t)
            if addr in self.functions:
                return addr
            starts = [a for a in self.functions if a <= addr]
            if starts and addr < max(starts) + self.functions[max(starts)][1]:
                return max(starts)  # an address inside a function
        for addr, label in self.labels.items():
            if label == text:
                return addr
        for addr, (name, _) in self.functions.items():
            if name == text or name.endswith('::' + text):
                return addr
        others = f' (others: {", ".join(self.others)}; --binary picks one)' if self.others else ''
        sys.exit(f'{text}: no such function in {self.binary}{others}')

    def refs(self, addr):
        """The spellings by which pseudocode refers to a function."""
        name = self.functions.get(addr, ('', 0))[0]
        out = {self.fun(addr)} if self.segmented else {f'FUN_{addr:x}', f'FUN_{addr:08x}'}
        if name and not name.startswith('FUN_'):
            out.add(name.split('::')[-1])
        return out

    def label(self, text):
        """Pseudocode with FUN_ names replaced by labels (kept in a comment)."""
        def sub(m):
            label = self.labels.get(fun_addr(m))
            return f'{label}/*{m.group(0)}*/' if label else m.group(0)
        return FUN.sub(sub, text)


SIZES = {'char': 1, 'byte': 1, 'bool': 1, 'undefined': 1, 'undefined1': 1, 'uchar': 1, 'sbyte': 1,
         'short': 2, 'ushort': 2, 'word': 2, 'undefined2': 2, 'wchar_t': 2, 'wchar16': 2,
         'int': 4, 'uint': 4, 'long': 4, 'ulong': 4, 'dword': 4, 'float': 4, 'undefined4': 4,
         'longlong': 8, 'ulonglong': 8, 'qword': 8, 'double': 8, 'undefined8': 8, 'pointer': 8,
         'float10': 10, 'undefined16': 16}


def size_of(t, ptr):
    t = t.strip()
    if t.endswith('*'):
        return ptr
    return SIZES.get(t, 0)


def accesses(body, var, ptr):
    """(offset, size, type, written) for each use of VAR as a pointer to a structure."""
    decl = re.search(r'([A-Za-z_][\w ]*?\s*\**)\s*\b%s\b\s*[,);]' % re.escape(var), body)
    vtype = decl.group(1).strip() if decl else ''
    elem = vtype[:-1].strip() if vtype.endswith('*') else ''
    scale = size_of(elem, ptr) or 1 if elem else 1
    out = []
    cast = re.compile(r'\*\(([A-Za-z_][\w ]*?(?:\s*\*)*)\s*\*\)\s*\(\s*(\([\w ]+\**\)\s*)?%s\s*\+\s*(0x[0-9a-fA-F]+|\d+)\s*\)'
                      r'(\s*=[^=])?' % re.escape(var))
    for m in cast.finditer(body):
        off = int(m.group(3), 0) * (1 if m.group(2) else scale)
        t = m.group(1).strip()
        out.append((off, size_of(t, ptr), t, bool(m.group(4))))
    if elem:
        for m in re.finditer(r'\b%s\[(0x[0-9a-fA-F]+|\d+)\](\s*=[^=])?' % re.escape(var), body):
            out.append((int(m.group(1), 0) * scale, size_of(elem, ptr), elem, bool(m.group(2))))
        for m in re.finditer(r'(?<![\w)\]])\*%s\b(\s*=[^=])?' % re.escape(var), body):
            out.append((0, size_of(elem, ptr), elem, bool(m.group(1))))
    return out


def load_labels(paths=None):
    labels = {}
    if not paths:
        here = os.path.join(os.getcwd(), 'labels', 'names.tsv')
        project = os.path.join(PROJECT, 'labels', 'names.tsv')
        paths = [next((p for p in (here, project) if os.path.exists(p)), os.path.join(ROOT, 'labels', 'names.tsv'))]
    for path in paths:
        labels.update({a: n for a, n in load_one(path).items() if a not in labels})
    return labels


def load_one(path):
    labels = {}
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            if line.startswith('#') or not line.strip():
                continue
            cols = line.rstrip('\n').split('\t')
            try:
                labels[parse_addr(cols[0])] = cols[1]
            except (ValueError, IndexError):
                pass
    return labels


def main(argv):
    export_dir = os.path.join(PROJECT, 'analysis', 'export')
    binary, labels_file = None, []
    while argv and argv[0].startswith('--'):
        if argv[0] == '--binary':
            binary, argv = argv[1], argv[2:]
        elif argv[0] == '--export':
            export_dir, argv = argv[1], argv[2:]
        elif argv[0] == '--labels':
            labels_file.append(argv[1])
            argv = argv[2:]
        else:
            sys.exit(f'unknown option {argv[0]}')
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    ex = Export(export_dir, binary, labels_file)

    if cmd == 'fn':
        addr = ex.resolve(args[0])
        print(f'// {ex.fmt(addr)} {ex.name(addr)} ({ex.functions[addr][1]} bytes) in {ex.binary}')
        print(ex.label(ex.bodies.get(addr, '// not decompiled (a thunk, or missing: '
                                     'scripts/ghidra-run.sh BINARY decompile OUT ADDR)\n')))
    elif cmd == 'callers':
        addr = ex.resolve(args[0])
        refs = ex.refs(addr)
        hits = [a for a, body in ex.bodies.items() if a != addr and any(r in body for r in refs)]
        for a in sorted(hits):
            print(f'{ex.fmt(a)}  {ex.name(a)}')
        print(f'{len(hits)} functions refer to {ex.name(addr)}', file=sys.stderr)
    elif cmd == 'callees':
        addr = ex.resolve(args[0])
        seen = []
        body = ex.bodies.get(addr, '')
        for m in FUN.finditer(body):
            a = fun_addr(m)
            if a not in seen and a != addr:
                seen.append(a)
        # Functions Ghidra already shows by name (exports, symbols, applied labels).
        for m in re.finditer(r'\b([A-Za-z_][\w:]*)\s*\(', body):
            a = ex.by_name.get(m.group(1))
            if a is not None and a not in seen and a != addr:
                seen.append(a)
        for a in sorted(seen, key=lambda a: (a not in ex.labels, -ex.functions.get(a, ('', 0))[1])):
            print(f'{ex.fmt(a)}  {ex.functions.get(a, ("", 0))[1]:6d} bytes  {ex.name(a)}')
    elif cmd == 'find':
        needle = ' '.join(args)
        for a, body in sorted(ex.bodies.items()):
            if needle in body:
                line = next(l.strip() for l in body.splitlines() if needle in l)
                print(f'{ex.fmt(a)}  {ex.name(a):<40}  {line[:100]}')
    elif cmd == 'strings':
        needle = ' '.join(args).lower()
        for line in open(os.path.join(ex.dir, 'strings.txt'), encoding='utf-8', errors='replace'):
            addr, _, value = line.rstrip('\n').partition('\t')
            if needle in value.lower():
                users = [a for a, body in ex.bodies.items() if value[:60] in body]
                where = ', '.join(ex.name(a) for a in users[:6]) or '(no direct use in pseudocode)'
                print(f'{addr}  {value[:80]!r}  <- {where}')
    elif cmd == 'writers':
        off = int(args[0], 16) if args[0].lower().startswith('0x') else int(args[0])
        pat = re.compile(r'\+ (0x%x|%d)\) = ' % (off, off))
        for a, body in sorted(ex.bodies.items()):
            if pat.search(body):
                print(f'{ex.fmt(a)}  {ex.name(a)}')
    elif cmd == 'layout':
        ptr = 4 if '--ptr4' in args else 8
        fields = {}  # offset -> {(size, type): [reads, writes, users]}
        for spec in (a for a in args if not a.startswith('--')):
            fn, _, var = spec.partition(':')
            addr = ex.resolve(fn)
            for off, size, t, written in accesses(ex.bodies.get(addr, ''), var or 'param_1', ptr):
                entry = fields.setdefault(off, {}).setdefault((size, t), [0, 0, set()])
                entry[1 if written else 0] += 1
                entry[2].add(ex.name(addr))
        if not fields:
            sys.exit('no field accesses found: check the variable name (param_1, this, a local)')
        print(f'{"offset":>8}  {"size":>4}  {"type":24} {"reads":>5} {"writes":>6}  used by')
        for off in sorted(fields):
            for (size, t), (r, w, users) in sorted(fields[off].items()):
                print(f'{off:#8x}  {size:4}  {t:24} {r:5} {w:6}  {", ".join(sorted(users))[:60]}')
        print('\nstruct draft {')
        at = 0
        for off in sorted(fields):
            if off < at:
                print(f'    /* {off:#x}: overlaps the field before (a union, or two sizes of one field) */')
                continue
            if off > at:
                print(f'    undefined1 gap_{at:x}[{off - at:#x}];')
            (size, t), _ = max(fields[off].items(), key=lambda kv: (kv[0][0], kv[1][0] + kv[1][1]))
            size = size or 1
            name = 'ptr' if t.endswith('*') else 'f'
            print(f'    {t:24} {name}_{off:x};{"" if len(fields[off]) == 1 else "  /* also read as " + ", ".join(sorted(x for _, x in fields[off] if x != t)) + " */"}')
            at = off + size
        print('};  /* the size is at least %#x; the allocation call (operator new, malloc) gives the whole size */' % at)
    elif cmd == 'biggest':
        n = int(args[0]) if args else 30
        todo = sorted(((size, a) for a, (_, size) in ex.functions.items()
                       if a not in ex.labels and a in ex.bodies), reverse=True)
        for size, a in todo[:n]:
            print(f'{ex.fmt(a)}  {size:7d} bytes  {ex.name(a)}')
    elif cmd == 'stats':
        total = sum(size for _, size in ex.functions.values())
        done = sum(ex.functions[a][1] for a in ex.labels if a in ex.functions)
        print(f'{ex.binary}: {len(ex.functions)} functions, {len(ex.bodies)} decompiled, '
              f'{len(ex.labels)} labelled ({100 * done / max(total, 1):.1f} % of code by size)')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
