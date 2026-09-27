#!/usr/bin/env python3
"""
Source for one XEGS Karateka scene, as the original lays it out, that the
toolkit's assembler rebuilds byte for byte.

This is step 3's starting point: nothing is moved yet. Every operand that
points at code, data, zero page, RAM or hardware is written as a symbol, so
that relocating a segment, moving a zero-page variable or renaming a
register later is a change to one definition, not a hunt through bytes.
Moving zero-page variables lengthens instructions, which is why the port is
reassembled rather than patched in place.

Segments (XEGS addresses; the loader's copy order puts the code bank over
the common bank's tail, measured in RAM during scene 1):

    common  $0480-$0FFF  bank 12, first $B80 bytes    shared by all scenes
    code    $1000-$2FFF  the scene's code bank         per scene
    data    $6000-$7FFF  the scene's data bank         per scene
    art     $8000-$9FFF  bank 14, left paged in        shared, never executed
    fixed   $A000-$BFFF  bank 15                       shared

Which bytes are instructions: the static trace (tools/a8dis.py, the entry
points the old build used) plus every instruction the census probe saw
execute (xscene.lua output, *.ex). Where the two disagree about an overlap
the executed instruction wins. Shared segments take the union over all
scenes, so one listing serves every scene.

    python port/xesource.py karateka.car --scene 1 --executed "census/*.ex" -o port/build/scene1

Writes one .asm per segment plus report.txt, then assembles each segment
with the toolkit's asm.py and compares it with the cartridge. Exit status 1
if any segment differs.
"""
import argparse
import glob
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLKIT = os.environ.get("A7800_TOOLKIT",
                         os.path.join(HERE, "..", "..", "a7800-toolkit", "tools"))
sys.path.insert(0, TOOLKIT)
sys.path.append(os.path.join(HERE, "..", "tools"))         # a8dis.py lives there; after
                                                            # the toolkit, whose asm.py wins
import asm      # noqa: E402
import m6502    # noqa: E402
from a8dis import Cart, Scene, walk   # noqa: E402
from reloclist import REGIONS            # noqa: E402

REGION_BASE = {name: lo for name, lo, hi in REGIONS}

BANK = 0x2000
ENTRIES = [(0x7760, "game"), (0x2F5A, "loader"), (0x1000, "vblank"),
           (0x0F00, "dispatch-table"), (0x7FD9, "dispatch-chain"),
           (0x2E00, "scene-init")]

# hardware the game touches (census, all scenes) plus the rest of the blocks,
# so an operand in these ranges always prints as a name
HW = {
    0xD000: "HPOSP0", 0xD010: "TRIG0", 0xD011: "TRIG1", 0xD016: "COLPF0",
    0xD017: "COLPF1", 0xD018: "COLPF2", 0xD019: "COLPF3", 0xD01A: "COLBK",
    0xD01E: "HITCLR", 0xD01F: "CONSOL",
    0xD200: "AUDF1", 0xD201: "AUDC1", 0xD202: "AUDF2", 0xD203: "AUDC2",
    0xD204: "AUDF3", 0xD205: "AUDC3", 0xD206: "AUDF4", 0xD207: "AUDC4",
    0xD208: "AUDCTL", 0xD209: "KBCODE", 0xD20A: "RANDOM", 0xD20E: "IRQEN",
    0xD20F: "SKCTL", 0xD300: "PORTA", 0xD301: "PORTB", 0xD302: "PACTL",
    0xD303: "PBCTL", 0xD400: "DMACTL", 0xD401: "CHACTL", 0xD402: "DLISTL",
    0xD403: "DLISTH", 0xD404: "HSCROL", 0xD405: "VSCROL", 0xD407: "PMBASE",
    0xD409: "CHBASE", 0xD40A: "WSYNC", 0xD40B: "VCOUNT", 0xD40E: "NMIEN",
    0xD40F: "NMIRES", 0xD500: "BANKSEL",
}


def segments(car, scene):
    """[(name, start, bytes)] for the scene's address space."""
    body = car[16:]
    bank = lambda n: body[n * BANK:(n + 1) * BANK]
    sc = Scene(Cart(car, ""), scene)
    return sc, [
        ("common", 0x0480, bank(12)[:0x1000 - 0x0480]),
        ("code", 0x1000, bank(sc.code_bank)),
        ("data", 0x6000, bank(sc.data_bank)),
        ("art", 0x8000, bank(14)),
        ("fixed", 0xA000, bank(15)),
    ]


def static_code(car, scene):
    sc = Scene(Cart(car, ""), scene)
    t = walk(sc, [(Scene.RESIDENT, pc, why) for pc, why in ENTRIES], quiet_banks=True)
    return {pc for (_b, pc) in t.code}


def executed(paths, scene=None):
    """Instruction addresses the census saw run, for one scene or all."""
    out = set()
    for p in paths:
        for line in open(p):
            k, _v = line.split()
            k = int(k)
            s, a = (k >> 16) & 0xFF, k & 0xFFFF
            if scene is None or s == scene:
                out.add(a)
    return out


# Scenes whose banks hold another scene's code at the same addresses, and run
# it where the census filed it under that other scene: scene 6 (Select at the
# title: the fight at the gate) writes $D0 = 1 and plays on in its own banks,
# so the census keyed its fight to scene 1; scene 0's attract sequence runs
# scene 1's opening run and demo fight, which no census run reached (FINDINGS
# "Select, scene 6").
TWIN_OF = {6: 1, 0: 1}


def twin_executed(car, scene, mem, ex_paths, addrs=None):
    """The twin scene's executed instructions (or `addrs`, e.g. its static
    code map) that this scene holds too: the same opcode, and the same
    operand bytes except a JSR/JMP target."""
    twin = TWIN_OF[scene]
    _sc, tsegs = segments(car, twin)
    tmem = {}
    for _n, start, data in tsegs:
        for i, v in enumerate(data):
            tmem[start + i] = v
    out = set()
    for a in (executed(ex_paths, twin) if addrs is None else addrs):
        op = mem.get(a)
        if op is None or op != tmem.get(a):
            continue
        d = decode(tmem.get, a)
        if d is None:
            continue
        n = d[3]
        if op in (0x20, 0x4C) or all(mem.get(a + k) == tmem.get(a + k) for k in range(1, n)):
            out.add(a)
    return out


def seg_of(segs, a):
    for name, start, data in segs:
        if start <= a < start + len(data):
            return name
    return None


def decode(mem_at, pc):
    op = mem_at(pc)
    if op is None:
        return None
    mn, mode, illegal = m6502.OPCODES[op]
    n = 1 + m6502.MODES[mode]
    b = [mem_at(pc + k) for k in range(n)]
    if None in b:
        return None
    opnd = b[1] | b[2] << 8 if n == 3 else (b[1] if n == 2 else None)
    return mn, mode, illegal, n, opnd


def load_reloc(path, scene):
    """{location: (kind, value, region)} for this scene, from port/reloclist.py."""
    out = {}
    if not path:
        return out
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        sc, loc, kind, v, reg = parts[:5]
        t = int(parts[5], 16) if len(parts) > 5 else None
        if sc == "*" or int(sc) == scene:
            out[int(loc, 16)] = (kind, int(v, 16), reg, t)
    return out


def reloc_expr(v, reg):
    """The high byte v as an expression over its region's base symbol."""
    base = REGION_BASE[reg]
    off = v * 256 - base
    return ">R_%s%s$%04X" % (reg, "+" if off >= 0 else "-", abs(off))


class Model(object):
    """One scene's address space, analysed: what is code, what is referenced."""


def analyse(car, scene, ex_paths, reloc_path=None):
    m = Model()
    m.scene = scene
    m.reloc = load_reloc(reloc_path, scene)
    m.sc, m.segs = segments(car, scene)
    segs = m.segs
    mem = {}
    for _n, start, data in segs:
        for i, v in enumerate(data):
            mem[start + i] = v
    m.mem = mem
    at = mem.get

    shared = {"common", "art", "fixed"}
    ex_scene = executed(ex_paths, scene)
    if scene in TWIN_OF:
        ex_scene |= twin_executed(car, scene, mem, ex_paths)
    m.ex_all = ex_all = executed(ex_paths)
    st_scene = static_code(car, scene)
    if scene in TWIN_OF:
        st_scene |= twin_executed(car, scene, mem, ex_paths, static_code(car, TWIN_OF[scene]))
    st_all = set()
    for s in range(7):
        if s == 5:
            continue
        st_all |= static_code(car, s)

    def candidates(seg):
        if seg in shared:
            return ex_all, st_all
        return ex_scene, st_scene

    # choose instruction starts per segment: executed first, then static
    insn = {}                         # addr -> (mn, mode, n, opnd)
    owner = {}                        # byte -> instruction start
    conflicts = []
    for name, start, data in segs:
        if name == "art":
            continue                  # never executed (census): all data
        exe, sta = candidates(name)
        if name == "code":
            # the engine ranges of the code bank are the same bytes in every
            # scene, so they take the union of every scene's code, like the
            # shared segments; the scene's own ranges take the scene's
            eng = lambda p: 0x1000 <= p < 0x1203 or 0x2300 <= p < 0x24A5 or 0x24AC <= p < 0x3000
            exe = {p for p in exe if not eng(p)} | {p for p in ex_all if eng(p)}
            sta = {p for p in sta if not eng(p)} | {p for p in st_all if eng(p)}
        for source, pcs in (("executed", exe), ("static", sta)):
            for pc in sorted(p for p in pcs if start <= p < start + len(data)):
                if pc in insn:
                    continue
                d = decode(at, pc)
                if d is None:
                    continue
                mn, mode, illegal, n, opnd = d
                if illegal and source == "static":
                    continue
                if pc + n > start + len(data):
                    continue
                span = range(pc, pc + n)
                clash = [owner[b] for b in span if b in owner]
                if clash:
                    conflicts.append((pc, source, sorted(set(clash))))
                    continue
                insn[pc] = (mn, mode, n, opnd)
                for b in span:
                    owner[b] = pc
    m.insn, m.owner, m.conflicts = insn, owner, conflicts

    # symbols for every operand target
    refs = defaultdict(set)           # target -> {referring pc}
    for pc, (mn, mode, n, opnd) in insn.items():
        if opnd is None or mode == "imm":
            continue
        tgt = (pc + 2 + ((opnd ^ 0x80) - 0x80)) & 0xFFFF if mode == "rel" else opnd
        refs[tgt].add(pc)
    m.refs = refs

    def base_name(a):
        s = seg_of(segs, a)
        if s:
            return "L_%04X" % a
        if a < 0x100:
            return "Z_%02X" % a
        if a in HW:
            return HW[a]
        if 0xD000 <= a < 0xD600:
            return "HW_%04X" % a
        if a >= 0xC000:
            return "OS_%04X" % a
        return "V_%04X" % a
    m.base_name = base_name

    # a reference into the middle of an instruction becomes label+offset
    def ref_text(a):
        if a in owner and owner[a] != a:
            return "%s+%d" % (base_name(owner[a]), a - owner[a])
        return base_name(a)
    m.ref_text = ref_text

    defined = set()
    for a in refs:
        if seg_of(segs, a) and not (a in owner and owner[a] != a):
            defined.add(a)
        elif a in owner and owner[a] != a:
            defined.add(owner[a])
    m.defined = defined
    # symbol -> original address, for every symbol an operand uses
    m.symbols = {}
    for a in refs:
        t = owner[a] if (a in owner and owner[a] != a) else a
        m.symbols[base_name(t)] = t
    return m


FMT = {"zp": "%s", "abs": "%s", "zpx": "%s,X", "abx": "%s,X", "zpy": "%s,Y",
       "aby": "%s,Y", "izx": "(%s,X)", "izy": "(%s),Y", "ind": "(%s)"}


def emit_range(m, start, end, overrides=None, keep_size=False, extra_labels=(), reloc_value=None,
               skip_labels=()):
    """Source lines for $start to $end-1 of the model's address space.

    overrides: {address: (end_exclusive, [lines])} replaces that range.
    keep_size: every originally absolute operand is forced absolute (.w), so
    a symbol moved into zero page cannot shrink an instruction.
    reloc_value: location -> the relocated byte, written as a number; without
    it relocations are written as >R_region expressions.
    skip_labels: addresses not to label here (their symbols live elsewhere,
    e.g. variables moved to RAM whose bytes stay as initial values).
    Returns (lines, addresses labelled here, relocations written)."""
    overrides = overrides or {}
    mem, insn, reloc = m.mem, m.insn, m.reloc
    local = ({a for a in m.defined if start <= a < end} | {a for a in extra_labels if start <= a < end}) - set(skip_labels)
    body, applied = [], 0
    pc = start
    while pc < end:
        if pc in local:
            body.append("%s:" % m.base_name(pc))
        if pc in overrides:
            stop, lines = overrides[pc]
            body.append("; override $%04X-$%04X" % (pc, stop - 1))
            body += lines
            # a label may go if nothing outside the overrides refers to it
            # (references from code another override replaces don't count)
            inside = [a for a in sorted(local) if pc < a < stop
                      and any(not any(o <= r < ov[0] for o, ov in overrides.items())
                              for r in m.refs.get(a, ()))]
            if inside:
                raise SystemExit("labels inside the override at $%04X: %s"
                                 % (pc, " ".join("$%04X" % a for a in inside)))
            local -= {a for a in local if pc < a < stop}
            pc = stop
            continue
        if pc in insn:
            mn, mode, n, opnd = insn[pc]
            if opnd is None:
                body.append("    " + mn)
            elif mode == "imm":
                if pc + 1 in reloc:
                    kind, v, reg, t = reloc[pc + 1]
                    if reloc_value:
                        body.append("    %s #$%02X" % (mn, reloc_value(pc + 1)))
                    else:
                        body.append("    %s #%s" % (mn, reloc_expr(opnd, reg)))
                    applied += 1
                else:
                    body.append("    %s #$%02X" % (mn, opnd))
            elif mode == "rel":
                tgt = (pc + 2 + ((opnd ^ 0x80) - 0x80)) & 0xFFFF
                body.append("    %s %s" % (mn, m.ref_text(tgt)))
            else:
                t = m.ref_text(opnd)
                wide = n == 3 and (opnd < 0x100 or keep_size)
                body.append("    %s %s" % (mn + (".w" if wide else ""), FMT[mode] % t))
            pc += n
        elif pc in reloc:
            kind, v, reg, t = reloc[pc]
            if reloc_value:
                body.append("    .byte $%02X" % reloc_value(pc))
            else:
                body.append("    .byte %s" % reloc_expr(mem[pc], reg))
            applied += 1
            pc += 1
        else:
            run = []
            while (pc < end and pc not in insn and pc not in reloc and pc not in overrides
                   and (not run or pc not in local) and len(run) < 16):
                run.append(mem[pc])
                pc += 1
            body.append("    .byte " + ",".join("$%02X" % v for v in run))
    return body, local, applied


def build(car, scene, ex_paths, reloc_path=None):
    """The identity build: every segment at its XEGS address, checked byte
    for byte against the cartridge."""
    m = analyse(car, scene, ex_paths, reloc_path)
    files, rebuilt_ok, applied = {}, {}, 0
    for name, start, data in m.segs:
        end = start + len(data)
        body, local, n_app = emit_range(m, start, end)
        applied += n_app
        localnames = {m.base_name(a) for a in local}
        lines = ["; XEGS Karateka, scene %d, segment %s ($%04X-$%04X)" % (scene, name, start, end - 1),
                 "; generated by port/xesource.py -- contains cartridge bytes, do not commit"]
        for nm in sorted(m.symbols):
            if nm in localnames:
                continue
            v = m.symbols[nm]
            lines.append("%s = $%04X" % (nm, v) if v >= 0x100 else "%s = $%02X" % (nm, v))
        for reg in sorted(REGION_BASE):
            lines.append("R_%s = $%04X" % (reg, REGION_BASE[reg]))
        lines.append("    .org $%04X" % start)
        lines += body
        files[name] = lines
        out = asm.Assembler().assemble(lines)
        rebuilt_ok[name] = (out == bytes(data), len(out), len(data))
    owner, insn = m.owner, m.insn
    report = {
        "scene": scene, "code_bank": m.sc.code_bank, "data_bank": m.sc.data_bank,
        "instructions": {n: sum(1 for p in insn if s <= p < s + len(d)) for n, s, d in m.segs},
        "from_executed": sum(1 for p in insn if p in m.ex_all),
        "conflicts": m.conflicts,
        "rebuilt": rebuilt_ok,
        "mid_instruction_refs": sorted(a for a in m.refs if a in owner and owner[a] != a),
        "reloc_applied": applied,
        "reloc_total": len(m.reloc),
        "reloc_stray": sorted(a for a in m.reloc if a in owner and not (insn.get(owner[a], (0, "", 0, 0))[1] == "imm" and a == owner[a] + 1)),
    }
    return files, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("car")
    ap.add_argument("--scene", type=int, required=True)
    ap.add_argument("--executed", action="append", default=[],
                    help="glob of census *.ex files (repeatable)")
    ap.add_argument("--reloc", help="relocation list from port/reloclist.py: "
                    "its high bytes are written as >R_region expressions")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    car = open(args.car, "rb").read()
    paths = [p for g in args.executed for p in glob.glob(g)]
    files, rep = build(car, args.scene, paths, args.reloc)
    os.makedirs(args.out, exist_ok=True)
    for name, lines in files.items():
        with open(os.path.join(args.out, "%s.asm" % name), "w") as f:
            f.write("\n".join(lines) + "\n")
    with open(os.path.join(args.out, "report.txt"), "w") as f:
        f.write("scene %d: code bank %d, data bank %d\n" % (rep["scene"], rep["code_bank"], rep["data_bank"]))
        f.write("instructions per segment: %s\n" % rep["instructions"])
        f.write("of which seen executing: %d\n" % rep["from_executed"])
        f.write("references into the middle of an instruction (self-modification): %s\n"
                % " ".join("$%04X" % a for a in rep["mid_instruction_refs"]))
        f.write("overlap conflicts (%d):\n" % len(rep["conflicts"]))
        for pc, src, clash in rep["conflicts"]:
            f.write("  $%04X (%s) overlaps %s\n" % (pc, src, " ".join("$%04X" % c for c in clash)))
    bad = 0
    for name, (ok, got, want) in rep["rebuilt"].items():
        print("%-7s %s (%d bytes)" % (name, "rebuilds exactly" if ok else "DIFFERS (%d vs %d)" % (got, want), want))
        bad += not ok
    if args.reloc:
        print("relocations written as expressions: %d of %d for this scene; not on an immediate or data byte: %s"
              % (rep["reloc_applied"], rep["reloc_total"], " ".join("$%04X" % a for a in rep["reloc_stray"]) or "none"))
    print("instructions:", rep["instructions"], "| seen executing:", rep["from_executed"],
          "| overlap conflicts:", len(rep["conflicts"]),
          "| self-modified operand refs:", len(rep["mid_instruction_refs"]))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
