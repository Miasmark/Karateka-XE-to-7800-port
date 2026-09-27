# Karateka XEGS → 7800 Port — Findings & Plan

Working folder: `Karateka-Port/` (tools copied from kareteka-disasm, ROM in `work/`).
Source ROM: `work/Karateka.car` — 131,088 bytes = 16-byte CART header + 16 × 8K banks.

## What has been established

### 1. The cartridge format
- CART header: `43415254` ("CART"), type `0x0E` (XEGS 128K cart).
- Address space: cart appears at `$8000–$BFFF` (16K window).
- **Bank 15 is fixed** at `$A000–$BFFF` (contains the boot code + vectors).
- **Banks 0–14 rotate** through `$8000–$9FFF`; write low 4 bits of any value
  to `$D500–$D5FF` to select. Bank 0 is all `0xFF` (padding).
- Vectors (end of bank 15): `NMI=$B7B1`, `RESET=$0400`, `IRQ=$BFE0`.
  RESET points into RAM — the cart boots by copying code into RAM and jumping there.

### 2. It is "a disk that happens to be silicon"
The boot chain (traced with `a8dis.py`, matches repo docs):
```
$B7B1  set SDLST=$BFE1 (blank screen), DMA off
       → select bank 13 → copy 8K $8000→$1000 → run $2F5A → JMP $7760
```
`$B2CC` is a plain 8K block mover (`LDA ($00),Y / STA ($02),Y` loop).
The game then runs **entirely from RAM**: ~31K in use, three banks resident
at once (code bank → `$1000`, data bank → `$6000`, common bank 12 → `$0480`).

### 3. Scene → bank map (from `a8dis.py --scene N`)
| Scene | code bank | data bank | traced code |
|-------|-----------|-----------|-------------|
| 1 | 7 → `$1000` | 8 → `$6000` | 11,444 bytes |
| 2 | 1 | 2 | ~9,600 |
| 3 | 5 | 6 | ~8,300 |
| 4 | 3 | 4 | ~7,900 |
| 5 | 13 | 11 | ~9,200 |
| 6 | 9 | 10 | ~6,700 |
| 7/8 | invalid (bank 169/1 mod 16) | — | 2 bytes — **scene table wraps; ring of 6 stages** |

Bank 12 (common, entropy 0.37) holds the **Forth interpreter core** — the
game is an indirect-threaded Forth image; 6502 tracing only reaches ~75 bytes
from the cart vectors because everything else is a thread of addresses.

### 4. The RAM problem (the big one)
- Atari 8-bit: ~31K RAM live (code `$1000`, data `$6000`, common `$0480`).
- Atari 7800: **4K RAM** (`$1800–$20FF` + mirrors). Code+data per scene = 16K.
- **User's thesis (sound):** most of what's copied to RAM is read-only
  (graphics, Forth dictionaries, level data). ROM reads are fast enough;
  only genuinely *written* state needs to live in 7800 RAM.
- Evidence so far: static scan of bank 13 found only 3 apparent absolute
  stores into the data-bank region (`$6000–$7FFF`) — likely false positives
  from byte-scanning; needs verification with the tracer, not a byte sweep.
- 190/1024 blocks are low-entropy (sprite sheets: figure-on-black = mostly
  zeros); 105 blocks are high-entropy = **compressed/encrypted** — these must
  be decoded before any port can use them. **Status correction:** a later
  direct Shannon-entropy check over 128-byte blocks found zero blocks above
  7.2 bits per byte, so do not restart work from the 105-block count. See
  `notes/scene-cache-and-compression.md`.

### 5. Hardware mapping (from repo docs, `porting-karateka.md`)
| Chip | Verdict |
|------|---------|
| POKEY `$D200` → cart POKEY `$4000` | **Nearly free** — same chip, same registers; 64 accesses visible on cart image |
| PIA `$D300` → RIOT `$0280` / TIA `$0C–0D` | Rename — 15 sites, same info, different bits |
| ANTIC (54 accesses) | **Rebuild** — no display-list DMA on MARIA; HSCROL/VSCROL (21 sites) have no counterpart |
| GTIA (54 accesses) | **Rebuild** — no hardware collision; every `HITCLR` read becomes coordinate arithmetic |
| OS ROM deps | Only 2 on the cart image |

### 6. The trap that broke every prior build
NTSC 7800 hashes the cart and checks a signature at `$FF80–$FFF7`;
a failing cart boots into **2600 mode** (black screen, no error).
`tools/sign7800.py` re-signs (Rabin hash, e=2). Every build path must sign.

### 7. Pacing finding (relevant to the port)
The 8-bit game runs 10 routines from the VBLANK handler every frame;
the 7800 game parcels logic across frames (9 entity slots, 13-frame loop).
**Take the 8-bit frame structure** — it's what makes the game feel
controllable — but **not its memory model**.

## Current build status and remaining work

Completed and verified:

- The 7800 boot stub selects SuperGame bank 0 and jumps to the relocated
  scene-0 entry at `$B760`, bypassing the XEGS copy-to-RAM boot loader.
- The signed ROM has a valid signature and `RESET=$CC00`.
- Boot/title/attract output is pixel-identical to the previous working
  copy-to-RAM build for the sampled title sequence.
- Scene-bank pairing and the `$4800-$5FFF` gameplay framebuffer have been
  documented in `notes/scene-cache-and-compression.md` and
  `notes/4800-5fff-framebuffer.md`.

Known critical gaps:

- The old `$2F5A`/`$9F5A` runtime loader remains in the scene banks. Its
  XEGS bank numbers and bulk-copy destinations have not yet been replaced by
  a SuperGame paging dispatcher.
- Scene 6 mapping is inconsistent: step 0 places it in SuperGame bank 6,
  while the older `SCENE_MAP` and graphics patching still use bank 5.
- The gameplay framebuffer writer still targets XEGS `$4800-$5FFF`; on the
  7800 this is cartridge space, so it needs a MARIA rendering replacement.
- Display-list construction is still a placeholder.
- Full gameplay, scene transitions, combat, collisions, scrolling, audio,
  input, interrupts, RAM/DMA limits, and hardware testing remain unverified.

## Completed implementation steps

### Step 1 — paging dispatcher, unified mapping, code-preserving graphics
- `tools/build_final.py` now wedges a fixed-bank scene dispatcher at
  `$CC0A` (`LDA $D0 / AND #$07 / TAX / LDA table,X / STA $8000 / RTS`)
  with the page table `[0,1,2,3,4,0,6]` at `$CC16`. Boot sets `$D0=0`,
  calls the dispatcher, then jumps to the scene main entry.
- The stale fixed-bank boot copy sequence (`$F7C9`) and every paged
  `$9F5A` loader body were replaced with dispatcher calls, so the XEGS
  bulk-copy path can no longer run.
- `SCENE_MAP` scene 6 was corrected to SuperGame bank 6 (matching step 0);
  scene 6 graphics now patch bank 6 instead of the codeless bank 5.
- Converted-graphics patching now skips bytes the scene traces reach as
  code, preserving data-bank code such as the `$7760` main entries.
- Verified: build green, signature VALID, `RESET=$CC00`, title animation
  frames pixel-identical to the previous build.
- New finding: after the title animation the screen now goes black with
  the CPU hung at `$AD3C`, falling into `JSR $284E` — an untranslated
  code-bank self-reference (`$2857` should be `$9857` in-window). The old
  gray attract screen is therefore believed to have been a crash artifact
  (old livestate showed the CPU executing signature bytes at `$BFE1`),
  not a working attract mode. Do not "fix" this by re-overwriting code
  with graphics.
- Precise next step: full absolute-address relocation for scene code/data
  (`$1xxx-$2xxx` to `$8xxx-$9xxx`, `$6xxx-$7xxx` to `$Axxx-$Bxxx`,
  common `$0480-$247F` to fixed `$C000-$DFFF`, fixed `$Axxx-$Bxxx` to
  `$Exxx-$Fxxx`), applied at decoded instruction sites, plus a home for
  CartWin bank-14 window references.

### Step 2 — absolute-address relocation into the window
- New `step8_relocate_scene_addresses` rewrites absolute operands only at
  decoded instruction sites from the per-scene traces (never a blind
  sweep), verifying opcode and operand before touching a byte.
- Result: 1,972 sites relocated, 166 already correct, 289 skipped
  (bytes installed by other steps, or sources with no fixed home).
- Verified: build green, signature VALID, `RESET=$CC00`, title animation
  still pixel-identical (frames 0-5, now fully 0 px differ).
- New finding: the hang moved from `$AD3C` into real relocated code at
  `$9837` — the framebuffer clear loop (`STA $FF00,Y` with `STA $9839`
  self-patching the store address). On ROM the self-patch is ignored, so
  the loop spins forever. This confirms
  two follow-ups: the `$4800` framebuffer needs its MARIA rewrite, and
  self-modifying code needs RAM shadows or branch-based variants — ROM
  execution cannot honor either as-is.

### Step 3 — clear neutralization, table completion, animated attract
- New `step9_framebuffer_clear`: the two per-bank JMP vector tables
  (`$9800`, `$9E00`) have their code-band targets relocated (verified JMP
  opcode + in-range target per slot), and the self-patching framebuffer
  clear routine (signature `A5 07 C9 20`, 63 bytes) becomes RTS + NOPs in
  all six scene banks. Clearing a nonexistent bitmap is meaningless; the
  routine's callers recompute `$14/$15` themselves.
- Fixed a build-script bug found by the new guards: scene 5 shares SG
  bank 0, so the per-scene loop patched bank 0 twice; step 9 now visits
  each SG bank once.
- Verified: build green, signature VALID, title animation still
  pixel-identical — and the attract mode now animates past the old hang
  (grayscale demo frames render and change frame to frame).
- New finding: execution then crashes with the window reading `$00` and
  PC in the signature zone. Mechanism: the blitter's self-modifying
  stores (`STA $AB11` etc.) write into `$8000-$FFFF`, where every store
  is a SuperGame bank switch — e.g. storing `$05` selects the empty bank
  5, unmapping the running code. An inventory of ~100 self-modifying
  stores per scene (blitter patch sites `$2ADA/$2B10/$2DA1`-family plus
  clear-loop patching) is the input to the framebuffer rewrite: each
  needs a RAM shadow or a branch-based variant, which simultaneously
  fixes rendering state and stops spurious bank switches.
- Also verified this turn: step 8's uniform band mapping is sound for
  code/data bands (whole banks move together, so embedded data follows
  correctly), and common-band variables below `$1000` were correctly left
  to step 3's RAM mapping (step 8 skips already-rewritten sites).

### Step 4 — decoded-site translation framework (kills sweep corruption)
- Root cause found: steps 1-4 swept the ROM linearly, reading every byte
  as a possible opcode. A real instruction's bytes overlap misdecoded
  "instructions", and the overlapping writes clobber each other — e.g.
  `STA $0C4C / ASL A` became `STA $0C4C / JSR ...`. Translation counts
  were mostly false positives (step 3: 3303 claimed; only 279 real).
- All address translation (steps 1-4) now happens ONLY at decoded
  instruction-operand sites from the scene traces plus the boot walk
  (`translate_decoded_sites`), verifying opcode and operand before each
  write. New counts: POKEY 10, hardware 56, RAM 279, bank-switch 25.
- Step 5's byte-pair scan made non-overlapping (adjacent matches can no
  longer clobber each other): 372 translations (was 394).
- Step 6 fallout fixed: the joystick routine was previously *created* by
  sweep luck (its `LDA $D300` was never decoded); step 6 now matches the
  original XEGS bytes (`AD 00 D3...` at XEGS `$AD09` = fixed `$ED09`).
- Verified: build green, signature VALID, title animation pixel-identical,
  attract reaches the same stage and crashes with the same self-mod
  bankswitch signature (`$BFE0` after window reads `$00`). No regression;
  corruption eliminated at the source.
- Known limit (by design): undecoded code keeps original operands instead
  of being corrupted. Coverage-bound misses remain possible and will
  surface as wrong behavior, never as silent corruption.

### Step 5 — minimal RAM shadows (self-mod writes stop crashing)
- New `step10_ram_shadows`, fully derived from traces (no hand lists):
  store targets with decoded readers get RAM shadows at `$2600+` (all
  accesses redirected); write-only STA/STX/STY are NOPed; write-only RMW
  is shadowed (preserves N/Z flag semantics); JSR/JMP targets untouched;
  dead-code sites skipped by the opcode guard.
- Result: 26 shadows (`$2600-$2619`), 158 redirected, 146 NOPed. The
  dispatcher initializes every shadow from the fresh scene's ROM bytes on
  each switch (exact XEGS RAM-copy values); `$BFE7` (read by undecoded
  code, ROM home destroyed by signing) gets immediate-init from source.
- Verified: build green, signature VALID, title animation pixel-identical
  (now fully 0 px differ). Post-title no longer crashes: PC stays in the
  plot loop (`$991A-$9999`) with bank intact for 1000+ frames (was: window
  zeros + `$BFE0` park). Late frames are black — display, not logic.
- New finding: a 60 s run never leaves attract and never writes `$D0`;
  the button routine never executes in the observed windows, so the
  demo→gameplay handoff path is still unexercised (next work).

### Step 6 — button routine translated, input verified end to end
- New `step11_button_routine`: the undecoded console/button routine
  (fixed `$EF51-$EFD4`) gets 11 surgical patches with byte verification
  (`LDA $D01F`→`LDA $0282` ×4, `JMP $2E00`→`JMP $9E00` ×3,
  `STA $0F12`→`STA $2512` ×2, `JSR $24D7`→`JSR $94D7`,
  `STX $D01F`→`STX $0282`). Previously it read garbage console state and
  jumped into a RAM mirror (the observed `$E014` park).
- Verified: build green, signature VALID. Input reaches the game:
  fire held → INPT4 reads `$00` (pressed) and the button-state byte `$DB`
  takes `$80` (vs `$00` hands-off). SWCHB reads `$FD`/`$FE` correctly
  with Select/Reset held.
- The START press (`$D0=1`, scene-1 load) has not been observed yet:
  `$D0` stayed `$00` under fire/Select/Reset, and the button routine did
  not execute in 2399 sampled frames. On XEGS the handoff needs the
  console START value through this routine; whether the demo-end flow
  calls it (and when) is the next trace target. No crash in any input
  run — worst case observed is continued attract.

### Step 7 — demo-end handoff traced to missing CartWin bank 14
- 14,390-frame run: `$D0` never changes after boot; the dispatch chain
  (`$B4F5/$B880/$BFD9/$B80D/$EF66`) never executes — not a long demo,
  the dispatch condition never fires.
- `$D0` writers found: `$7808`/`$7286` (data bank) plus window `$AF77`/
  `$AFC3`/`$AFCA` (bank 14). The button routine's only caller is
  `$BFD9` (data bank: save regs, `JSR $EF66`, restore, `JMP $B80D`),
  itself called from `$B4F5/$B502/$B880/...` — none of which ever run.
- Decisive input test: fire held → INPT4 reads `$00` and `$DB` takes
  `$80` (vs `$00` hands-off). Input reaches game logic, but `$DB`'s
  consumer (hold-counter at XEGS `$B640`) has no decoded callers and never
  runs. Correction to an earlier hypothesis: `$B640` is fixed bank-15
  code (present in the image at `$F640`), not missing CartWin bank-14
  code — the earlier "cartridge window" labels from `where()` cover all
  of `$8000-$FFFF`, hiding fixed `$A000-$BFFF`. Zero decoded PCs fall in
  the true window (`$8000-$9FFF`), so no evidence anywhere says bank 14
  bytes execute; the missing piece is CALLERS (undecoded dispatch paths),
  not a missing bank. The spare-bank-5 + trampoline plan is shelved;
  the VBLANK frame call below is the actual unblocker.

### Step 8 — NMI is dead; VBLANK chain must move to the main loop
- Root cause of the stalled demo, proved three ways over 7000+ frames:
  the NMI vector region (`$B7xx`/`$F7xx`) executes exactly once (boot
  sampling), and POKEY gets zero writes — the entire 10-routine VBLANK
  chain (music `$104E`, input poll `$0FA2`, scene state `$0F66`,
  display pick `$0F87`, ...) never runs.
- Why: on XEGS the handler runs per-frame via NMI; the 7800 has no
  VBLANK NMI (NMI is MARIA's per-zone display interrupt only), and our
  NMI vector still points at `$B7B1` (window graphics on the 7800).
  The title animation is 100% main-line driven.
- Consequence: music, VBLANK input polling, the scene state machine,
  and display-list selection all need a once-per-frame call from the
  main loop (frame-synced via MSTAT), not an interrupt. That call is
  the prerequisite for demo advance, input consumption, and music.
- Next step: build the main-loop frame call (MSTAT sync + JSR into the
  relocated VBLANK chain in fixed/window banks) and verify music
  (POKEY writes resume) and state advance (`$D0`/phase bytes move).

### Step 9 — frame gate built; MSTAT dead, timer owned, nondeterminism
- `step12_frame_gate`: 52-byte fixed routine + 24 hooked `JSR $9995`
  sites (verified bytes, all six scene banks). Gate preserves A/flags/zp
  exactly like XEGS NMI preemption, fires the selective chain
  (music/countdown/state/input, display routines excluded to protect
  MARIA palette state), then tail-calls the pixel routine. Title intact.
- MSTAT (`$28`) reads `$00` at every sample, including VBLANK phase, so
  the MSTAT edge gate never fires (chain: 0 POKEY writes / 1700 frames).
  Whether MAME models the bit with DMA off, or plot never overlaps
  VBLANK, is undecided — either way MSTAT is unusable as a frame clock.
- RIOT timer hijack rejected with evidence: the game itself writes
  `$0296` (alternating `$F6`/`$64` — its own delay pacing), and XEGS RAM
  vars in `$0284-$02FF` collide with 7800 RIOT registers. Related find:
  `$0296` is one of several XEGS `$028x` RAM vars with no 7800 RAM home
  (step 3 blanket-excludes `$0280-$02FF`); they need explicit shadows.
- PROVEN run-to-run nondeterminism: identical build, identical inputs,
  animation frames diverge after ~frame 115 (12798 px differ at F0/F1 on
  rerun) while frames 100-110 match exactly. The demo is free-running
  (no VSYNC/WSYNC strobes exist in the image) with no frame pacing, so
  tiny timing differences accumulate into phase drift — and likewise
  explain crash-timing variance. Title verification stays valid only for
  the deterministic prefix (~frames 100-115).
- LASTV (`$2635`) initialized to `$00` in the dispatcher to remove one
  confirmed entropy source (was garbage `$E3`); placement verified
  outside step-3-mapped and footprint-used RAM.
- Standing next steps: (a) true frame tick — best candidate is DLI-based
  NMI once display lists exist, which also fixes pacing determinism;
  (b) `$028x` RAM-var shadows; (c) remaining undecoded window stores
  behind the `$BFE0` crash.

### Step 10 — $028x verdict: no shadows needed, tap discipline confirmed
- Trusted write-tap over `$0280-$02FF` (tap validity proven: it captured
  the boot `STA $D0`): ZERO game writes in 30 s unthrottled. The
  alternating `$0296` reads are MAME RIOT-model behavior on untouched
  timer regs, not game writes — the earlier linear-scan `$028x` hits
  re-examined as data false positives (sprite/table bytes containing
  opcode-shaped sequences).
- Therefore no `$028x` shadows to install (nothing writes them); reads
  of untouched regs return model values, a latent quirk for undecoded
  code, not a live bug. Timer hijack stays rejected.
- Tap discipline re-proven the hard way: a window (`$8000-$FFFF`) tap
  breaks banking (title renders black with it installed), so its two
  logged stores (dispatcher `$8000←$01`, `$F112` from `$04BA`) are
  discarded as artifacts, not findings.
- Methodology correction: `-script` probes attach ~240 frames late (7800
  BIOS splash), so all probe frame numbers are relative to cart boot,
  not power-on. Boot stub executes exactly once (no crash-reboot loop).
  The `$D0` tap confirms scene number never changes: still attract-only.

### Step 11 — display is configured; crash forensics; mirror decision
- Display finding: the game DOES drive MARIA — DLL `$1F84`, per-frame
  `CTRL $43/$40` toggling, per-frame DLISTL (`$22`), WSYNC strobes, and
  occasional scroll-reg writes were all captured live. Title DL walked
  (16 zones, RAM objects at `$1984+`). Title→black decoded exactly:
  frame 241 writes `CTRL=$60` + `DPPH=$00` from RAM-executed code
  (`$23C7`/`$0485`) — crash artifacts blanking the screen, not an
  intentional blank.
- Crash sequence nailed (dense per-frame sampling): `$2401-$240F`
  (SP=$FD balanced) through F249, then `$C001`-JAM (`$02` opcode) with
  SP=$FF — i.e. a stray RTS popping `$C001`, after a bad bankswitch
  zeroed the window (`$A5→$00` between F180-250).
- Root-cause neighborhood: the game constructs helper routines in RAM
  `$2407+` at runtime (frame-14 `$FB35`-path fills + `$BBEE` copy +
  patches; frame counter `$2406` ticks there per frame). Their baked-in
  operands (`LDA $2436,Y`, `ADC $6200,X`) assume XEGS RAM copies that
  don't exist on 7800 (`$2436` RAM is boot-fill garbage, `$6200` is
  cartridge space). No ROM template exists (constructed, not copied).
- `$9400`-trampoline (`JMP $2422`) + unrelocated `JSR $2400` sites in
  banks 2-4 mapped as further crash feeders for non-title scenes.
- Step 13 (this turn): NMI+IRQ vectors now point at a fixed-bank RTI
  stub (`$CD94`) — XEGS `$BFE0` was a bare RTS, and the signature zone
  made any BRK/IRQ unrecoverable. Verified vectors + title intact.
- DECISION — selective RAM mirror (next implementation): at scene
  switch the dispatcher already copies shadows; extend it to mirror
  DECODED-CODE bytes of the scene's code bank into RAM `$1800-$27FF`
  (same offsets the XEGS loader used), leaving non-code offsets alone
  for step-3 variables/shadows. This reproduces XEGS loader semantics
  for exactly the executable slice: undecoded `JSR $24xx` calls land on
  real code, constructed-code reads (`$2436`) hit real bytes, and
  self-modifying writes work natively — while step-3 variables and
  `$26xx` shadows keep their RAM. Constraint: mirror must skip
  non-code offsets (else it clobbers step-3 variables); `$1000-$17FF`
  calls stay unmappable (not RAM) and need trampolines if observed.

## Open questions (not yet answered)
1. Which blocks, if any, are packed/encrypted rather than merely dense lookup
   tables or graphics? Use the row-correlation method from
   `kareteka-disasm/docs/porting-karateka.md`, not another Shannon sweep; see
   `notes/scene-cache-and-compression.md`.
2. What exactly is written to RAM per level — needs a dynamic run in MAME
   with the probes, not static scanning.
3. Does the Forth dictionary itself live in the data banks (likely — bank 12
   header words point into `$70xx/$71xx/$79xx…` regions)?
4. 7800 cart mappers: does any existing mapper give >4K RAM? (Decision
   deferred per user: extra RAM only if absolutely necessary.)

## Step-by-step plan

### Phase A — Understand the image (static)
1. **Run `tools/forth.py` on `work/Karateka.car`** — decompile the Forth
   image; generate entry points (`patches/karateka-entries.py` pattern) and
   re-run `disasm.py` with them to push coverage past 18.3%.
2. **Classify every 256-byte block**: code / Forth dictionary / sprite sheet /
   compressed / padding. Build `annotations.json` from `templates/annotations.json`.
3. **Crack the compression**: take one high-entropy block, check for the
   EOR/ROL/SBC/ROR self-decryptor idiom the docs mention; if it's real
   compression, identify the codec before porting anything that uses it.

### Phase B — Measure what must live in RAM (dynamic)
4. **Boot the cart in MAME** (`mame xegs -cart work/Karateka.car` — MAME
   0.289 has the `xegs` machine; BIOS `c101687.rom` already in folder).
   Adapt probes from `kareteka-disasm/probes/` (they target the 7800 game;
   addresses differ for the 8-bit cart).
5. **Watchpoint every RAM window** (`$1000–$9FFF`, `$0480–$04FF`) during a
   full playthrough; log all writes. Output: a per-address write map that
   answers "what actually changes per level" — the user's core question.
6. Decide from data: which blocks are read-only (stay in ROM) vs written
   (must fit in 4K RAM). If written-state > 4K, *then* evaluate mappers
   with extra RAM (Bankset, etc.) — last resort.

### Phase C — Restructure for 4K RAM
7. Reorganize level data so per-level state fits in 4K: Forth dictionaries
   stay in ROM (read-only), variables compacted into zero-page + `$1800` block.
8. Map the 6-stage ring: each stage's ROM banks + which bank is paged when.

### Phase D — ANTIC → MARIA (the real work)
9. Convert display lists → MARIA display lists; bitmap backgrounds → direct
   mode or character-mode equivalents; scrolling → redraw logic driven by
   the odometer-style travel budget (`$18B3–$18BD` equivalents).
10. Replace every GTIA collision read with coordinate comparison (the 7800
    port's weak hit detection came from skipping this — do it properly).
11. Port POKEY driver base `$D200`→`$4000`; port PIA→RIOT joystick reads.

### Phase E — Build & verify
12. Assemble with `tools/asm.py`; verify with `tools/verify.py` +
    `tools/selftest.py`; **sign with `tools/sign7800.py`** (else black screen
    on hardware); test in MAME `a7800`/`a7800p` with the existing probes.

### Working rules
- One phase-step per session; write results to `work/` as JSON/CSV so
  progress survives restarts.
- Static scan counts are upper bounds — confirm anything load-bearing by
  running it (MAME), per `docs/method.md`.
- Every "dead region" claim needs a positive control (see
  `docs/karateka-from-siblings.md` — a wrong zero is worse than no answer).

## 2026-09-24 — re-evaluation against the running original

Measured, not inferred. MAME 0.287 throughout; scratch probes kept in the
session scratchpad (`kport/`).

### The original runs in MAME after all
- `mame xegs -cart work/Karateka_16header.bin -rompath roms` boots and plays
  (story text, title, the cliff fight). Only the `.car` header was refused
  ("Cart type 14 unsupported"); the raw 128K image is accepted. The earlier
  "no runtime evidence is possible" conclusion in
  `notes/scene-cache-and-compression.md` is withdrawn.
- Run it windowless with a scratch `-inipath` whose `ui.ini` holds
  `skip_warnings 1`, plus `-video none`: `xegs` is flagged as imperfect
  graphics and otherwise waits for a keypress on a warning screen.
  Snapshots still work with `-video none`.
- Fire (P1 Button 1) starts a game from attract; `$D0` goes 0 → 1 at
  frame 1865 in the measured run.

### The source image is not pristine
`work/Karateka.car` differs from the original (`karateka/Karateka.car`,
SHA-256 `484b3264…cb1c`, the same bytes as `Karateka_Atari_USA.zip`) in six
bytes: bank 11 `$8001-$8008`, the scene-0 data jump table at RAM
`$6000-$6008`, where three `JMP` targets (`$600A`, `$60D2`, `$60E3`) were
changed to `$F7CD`. A port patch was saved into the build's input on Sep 21.
`Karateka_16header.bin` is the untouched original without its 16-byte
header.

### The current build does not run
`build/KaratekaXE.a78` in MAME (NTSC BIOS): black screen at every sample
from frame 300 to 3600, CPU looping `$0000` (BRK) → IRQ → RTI stub `$CD94`.
The "attract mode runs stably" status in `BUILD_NOTES.md` does not describe
this build: its boot stub now starts scene 1 directly (a diagnostic), and
`build_manifest.json`'s output hash is stale.

### Zero page $00-$3F was never remapped
The original writes **all 64 bytes of `$00-$3F`** during play (≈7 million
writes in 7,000 frames), plus 130 bytes of `$40-$FF`. Step 3 maps only
`$0200-$0FFF`. On the 7800, `$00-$3F` are TIA and MARIA registers: `$01` is
INPTCTRL, `$24` WSYNC, `$2C` DPPH, `$3C` CTRL. The step-11 observation
"frame 241 writes CTRL=$60 + DPPH=$00" is most likely the game's own
zero-page variables landing on MARIA, not a crash artifact. It also means
194 zero-page bytes are in use against the 7800's 192 (`$40-$FF`), so some
must move to absolute RAM, which lengthens their instructions: that cannot
be done by in-place operand rewriting.

Stack use is `$01E4-$01FF` (28 bytes), inside the 7800's RAM stack page.

### What the original writes during play (scene 1, OS and loader excluded)
| Region | Addresses written | What it is |
|---|---|---|
| `$4808-$5FEF` | 6,120 | framebuffer A (40 bytes × 153 rows) |
| `$3010-$47F7` | 6,120 | **framebuffer B**: the game double-buffers; the earlier note found only A |
| `$0880-$08FF` | 128 | a table built at runtime (PC `$2E60`) |
| `$2409-$2421` | 25 | code constructed at runtime |
| `$1000-$2FFF` other | ~26 | self-modified operands (`$28FA`, `$291D-$2926`, `$2ADA`, `$2B10`, `$2DA1`, …) |
| `$0480-$0FFF` other | ~23 | variables and self-modified bytes |
| `$0200-$047F` | 11 | OS vectors and shadows (`VDSLST`, `VVBLKI`, `SDMCTL`, `SDLSTL/H`, …) |
| `$6000-$7FFF` | 2 | `$7096-$7097` only: the data bank is otherwise read-only |

So about 12.5K must be writable, 12,240 bytes of it the two bitmaps. That
cannot fit in the 7800's 4K; it fits in the 16K of a SuperGame+RAM cartridge
(`a78_sg_ram` in MAME).

### Hardware the original touches during play
| Register | Use |
|---|---|
| POKEY `$D200-$D207`, `$D208`, `$D20E-$D20F` | music (4 channels), IRQ/SKCTL setup |
| GTIA `$D016-$D019` COLPF0-3 | written together by the DLI handler at `$1152`, about 3 times a frame |
| GTIA `$D010` TRIG0 | the fire button, read every frame (`$0FB4`) |
| GTIA `$D01F` CONSOL | console keys (`$AF66`, `$AFD1`) |
| PIA `$D300` | joystick (`$AD09`) |
| ANTIC `$D402/3` DLISTL/H | display-list flip every frame (`$0F8D`) |
| ANTIC `$D40A` WSYNC, `$D40B` VCOUNT, `$D40E` NMIEN, `$D400` DMACTL | DLI timing, a raster wait (`$2F8A`), setup |

**None of these during play:** player/missile graphics, collision registers
(`$D000-$D00F` reads), `HITCLR`, `HSCROL`/`VSCROL`. Collision is computed in
software and nothing scrolls. The "rebuild GTIA collision" and "scrolling
becomes a redraw" items in the older assessments do not apply to the
cartridge's play.

### Display
Display lists at `$19B3` and `$1908`, one per buffer, flipped each frame:
24 blank lines, three ANTIC mode 8 rows (a low-resolution band), then
mode E (160 × 1-line, 2 bits per pixel) from `$4808` / `$3010` with a second
LMS at the 4K boundary, DLIs on several lines, and a 7-line mode-E status
bar from `$5ED8` / `$46E0`. Mode E's byte layout (four 2-bit pixels, the
leftmost in bits 7-6, `00` = background) is MARIA 160A's, so MARIA can
display the game's bitmaps as they are, from constant display lists in ROM.
The notes `antic-maria-dl-translation.md` and `maria-dl-implementation-plan.md`
describe MARIA's DL format incorrectly and should not be built from.

### Corrections to earlier entries
- "Bank 12 holds a Forth interpreter": no sign of it. The 7800 version's
  `NEXT` signature does not occur in the XEGS image; the traced code is
  ordinary 6502. Forth is the 7800 version's architecture, not this one's.
- The `$4800-$5FFF` note is right about buffer A and incomplete: there are
  two buffers.

### Where the renderer reads its art (same day)
Write tap on `$3000-$5FFF` during play, recording the writer's PC and the
source pointer `$03/$04`:

- Sources are the scene data bank's RAM copy (`$66xx-$6Bxx`), a common-bank
  table (`$0Bxx`), **and cartridge ROM directly**: `$83xx-$9Axx`, bank 14,
  which stays paged in at `$8000`. The game already draws from ROM where
  its layout allows; the copying to RAM comes from the loader, which is
  shaped like the disk version's (a disk game has to load into RAM), not
  from any need of ANTIC's. ANTIC can fetch from ROM as well.
- What has to be RAM is the picture itself: the fighters are composited over
  the background in software, with masks, into two alternating bitmaps.
  About 415 bytes are written per frame on average, 2,233 at most, so it
  redraws the changed areas, not the whole screen. The finished screen
  exists nowhere in ROM.
- Values written are mostly `$00`, `$AA`, `$55`, `$FF` (solid fills in one
  colour) plus composited sprite bytes.

Consequence: displaying from ROM on MARIA needs the compositing replaced by
display lists (fighters as objects, background as objects), not just the
display lists moved. Keeping the compositor needs ~12K of cartridge RAM.

### Retail 7800 cartridge layouts (MAME's software list)
Retail boards carried POKEY or RAM, never both:
- SuperGame + 16K RAM at `$4000` (`a78_sg_ram`): Summer Games, Winter
  Games, Impossible Mission (Epyx, 1987), Tower Toppler (1988), Jinks (1989).
- POKEY: Ballblazer (`a78_pokey`), Commando (`a78_sg_pokey`).
Decision (user, 2026-09-24): stay within retail layouts, so POKEY music
converts to TIA.

### Collision is already software (same day)
No instruction anywhere in the 128K image addresses the GTIA collision
registers (`$D000-$D00F`) or `HITCLR` (`$D01E`), not even as a byte
pattern in data (a sweep of every bank for absolute-mode reads and writes:
0 hits). With the fight's runtime tap also showing zero reads, the XEGS
game detects hits in software, so its collision code is portable game
logic, not a hardware dependency to rebuild. The remaining gap is access
through a pointer (`LDA ($zp),Y` aimed at `$D00x`); the per-scene runs will
tap `$D000-$D00F` reads to close it. The "54 GTIA accesses" in the older
static count are colour, console and trigger registers.

Route decided (user, 2026-09-24): SuperGame + 16K RAM at `$4000` (the
Summer Games board), the game's own compositor kept, POKEY music rearranged
for TIA.

### Step 1 test cartridge: MARIA shows the game's bitmap (same day)
`port/bitmap_testcart.py` builds a 128K SuperGame + 16K RAM cartridge (header
flags `$0006`) from one captured frame of the original (frame 4000 of the
scripted fight; `xcap.lua` records RAM and the DLIST/colour writes with
their scanlines). It copies both framebuffers into cartridge RAM
(XEGS address + `$1000`) and shows the frame through ROM display lists: one
1-line zone per XEGS scanline, each drawn line two 20-byte 160A objects
pointing at the bitmap row, mode-8 rows widened into 40 bytes, and the
DLI colour changes turned into a palette per line (3 palettes for this
frame).

- **Pixel check:** against the original's screenshot, aligned
  (7800 x+8, y+2), all 71,680 overlapping pixels agree under a one-to-one
  colour mapping (6 colours, 0 disagreements). The colour bytes carry over
  unchanged; MAME's two palettes differ by a few RGB units.
- One wrong turn: placing each colour change one line after its DLI line
  was two lines early (128 sky pixels on two rows). The logged write line
  (`VCOUNT*2`) + 1 is right.
- **CPU left per frame (MAME a7800):** counting loop, 8 cycles a pass:
  2,788 passes with the bitmap displayed (≈22,300 cycles), ≈3,719 with
  MARIA DMA off (≈29,750). The display costs about 25% of the CPU.
- **The original, for comparison:** MAME's `xegs` cannot give this number.
  The same counting loop hijacked into the running original showed ANTIC
  DMA costing only ~3% (3,584 vs 3,686 passes), where the ANTIC rules
  give ~29% for this display list (40 playfield cycles per mode-E line ×
  153 lines, 9 refresh cycles on every one of 262 lines, DL fetches):
  MAME does not model ANTIC's cycle stealing. Computed from those rules,
  the original has ≈21,200 cycles a frame. So the 7800 leaves about the
  same CPU time as the XEGS did, a little more. To be confirmed in Altirra
  (cycle-accurate) and on hardware; MAME's MARIA timing is also a model.

### Step 2: census of every reachable scene (same day)
`xscene.lua` (scratchpad `kport/`), one run per scene, 6,000 frames each,
the same scripted input. Scenes other than 1 are reached by substituting
the scene number for the game-start write of `$D0 = 1` (at `$7808`); the
loader then brings in that scene's banks. Scenes 2, 3 and 4 accept it and
write their own number back; scene 6 runs 41 frames and hands over to
scene 1 (a lead-in); scene 5 shares scene 0's banks (13/11) and stays black
when forced, so it wants its own entry, probably the ending. Scenes 2 and 3
fell back to scene 1 partway through (the scripted player dying, most
likely).

- **Collision: closed.** 0 reads of `$D000-$D00F` in any scene. The tap
  sees every access however it is addressed, so the pointer case is
  covered too.
- **Writes outside the framebuffers, all scenes together: 238 addresses**
  above `$01FF`: OS vectors/shadows (`$0200-$0244`), a 22-byte-stride
  table at `$0480-$06DA`, the 128-byte table `$0880-$08FF`, variables at
  `$0AF6-$0F14` and `$1193-$1196`, constructed code `$2409-$2421`,
  self-modified operands in `$2839-$2E0D`, and 3 bytes of the data bank
  (`$7096-$7097`, `$76FF`).
- **Zero page: 208 bytes** written across the scenes (all 64 of `$00-$3F`,
  144 of `$40-$FF`); scene 1 alone uses 196. The 7800 has 192 bytes of
  zero-page RAM, so some variables must move to absolute RAM. That
  lengthens instructions, so the port reassembles rather than patching
  bytes in place.
- **Stack:** lowest SP `$EB`.
- **Code already executes from cartridge ROM:** 1,470-1,610 distinct
  instructions per fight scene are in fixed bank 15 (`$A000-$BFFF`).
  Bank 14 (`$8000-$9FFF`) never executes; it is art. The "data" bank
  holds code too (157-1,155 instructions per scene).
- **Colours:** at most 4 colour sets in any frame of any scene (MARIA has
  8 palettes), COLBK always `$00`, colour changes on up to 3 lines per
  frame, and the lines vary (98-202).
- **Display lists:** the game flips between fixed DLs at `$1908-$1B04`,
  which are never written, so they are data loaded with the common bank.
  Each can become a MARIA DLL built at assembly time and held in ROM,
  with DLI bits where the ANTIC list has them, and a MARIA DLI handler
  rewriting a palette where `$1152` rewrites COLPF0-2.
- **New:** scene 0 (title and story) writes CONSOL `$D01F` ~580,000 times.
  That is the built-in keyclick speaker used as a sound source, and it
  needs a TIA replacement alongside the POKEY music. **Wrong (2026-09-26):** every one of those
  writes is `$08` from `$AFD1` (`LDX #$08 / STX $D01F`), the end of the
  console-key routine, which resets CONSOL (speaker off) on each call and is
  called in tight loops while the game waits for a key. A constant never
  toggles the speaker, so the XEGS game makes no speaker sound, and nothing
  is missing on the 7800. See "The silent Akuma fight". TRIG1 (`$D011`) is
  read in scene 1.

Measured by the scripted run only: paths it never took (winning a fight,
the hawk, the princess, scene 5) are not in the executed set yet.

### Player health, and recording a full playthrough (same day)
- **`$00B6` is the player's health.** It is 14 at the start of a life, one
  less per hit, and 0 is dead. Found by matching RAM against the
  status-bar arrows read from the bitmap (correlation 0.973 over 830
  samples; the next best byte managed 0.57).
- `probes/xe-invincible.lua` refuses any write that lowers it (outside
  scene 0), so hits cost nothing; raises (new life, refill) pass. Tested:
  18,000 frames of the scripted player, health never below 14, and it
  then won its way along the cliff to the gate and the Akuma cutscene
  (which runs inside scene 1: `$D0` stays 1).
- `Record Karateka XE.bat` records a human session of the original
  (`inp\xe-NN-inv.inp`, cheat on by default; `KXE_CHEAT=0` for none).
  `Play Karateka XE Recording.bat` replays one, reloading the cheat for
  `*-inv` names, since a recording made under the cheat diverges without
  it from the first hit. Both skip MAME's imperfect-graphics warning with a
  copy of MAME's own `ui.ini` plus `skip_warnings 1` in `mame-ini\`
  (searched first).

### Health, instant deaths and the gate (same day)
From the user's recording `inp/xe-01-inv.inp` (1,261 s, ~75,600 frames;
scene 1, scene 2, a death, scene 1 again, scene 2 again, the gate) and
targeted replays of it.

**Health is symmetrical.** `$B6` player, `$B7` enemy; maxima `$B0`/`$B1`.
Damage: `$0BDD` (player: `DEC $B6`, and at 0 clears the alive flag `$5D`)
and `$0BEE` (enemy: `DEC $B7`, clears `$5E`). Refill: `$0C1E`/`$0C30`
count up **until health equals the maximum** (equality, not less-than).
Each new opponent lowers the player's maximum and raises the enemy's
(`$78F0` in scene 1: `DEC $B0 / INC $B1`, floor 10) and caps `$B6` at the
new maximum through `$7BB6` (`$7BB8 STA $B6`); scene 2 does the same at
`$77AF`/`$7927`.

**Version 1 of the cheat was wrong.** Blocking every lowering of `$B6`
also blocked that cap, so `$B6` sat above `$B0`, the refill never met its
equality test, and health ran to 255 (then the wrap to 0 was blocked too).
It also missed the instant deaths, which are decided before `$B6` is
written: the player died at frames 16,044 and 41,429 with health pegged at
255.

**Three instant deaths, found by replaying to each and reading the stack:**
1. *Hit while unprotected* (running, walking; the hawk as well). The hit
   dispatcher `$B14A` sends victim states 6-8, `$0B-$0D` and `$22`+ to
   `$B12A`: `LDA $62 / CMP $22 / BEQ $B131`, and `$B131` sets `$B6 = 0`,
   `$5D = 0` and starts the death sequence (`JMP $A540`). The call chain
   was `$77F8 → $79C0 → $B277 → $B2BE → $B14A` in scene 1 and
   `$7811 → $7AD3 → $B277 …` in scene 2.
2. *The gate* (scene 2, the portcullis). `$A9` = gate triggered, `$A7` =
   how far down, `$62` = player position. `$79C1-$79D3` crush when the gate
   is triggered, `$A7 >= $82` and `$62` is `$1F-$21`; `$79F3` then sets
   health to 2 (1 if below 3) and `$7B08-$7B16` take one away at a time
   while the player lies under it. The check at `$7C11` only redraws the
   gate over a dead player.
3. *Driven off the cliff* (scenes 1, 6, and the same code in scene 5's
   bank). `$A2` set means over the edge; the main loop then clears `$5D`
   (`$7914 LDA $A2` … `$791E STA $5D`; `$758D` … `$7597` in bank 11).
   Found when a scripted player holding right in fighting stance (which
   kicks rather than walks) was pushed back over the edge: game over,
   "the end", without passing through `$B131`.

**Version 2, `probes/xe-easy.lua`,** changes five single instructions:
the damage `DEC $B6` at `$0BE5` keeps the old value; the `BEQ` at `$B12E`
is fetched as `BIT $01`; `LDA $A7` at `$79C5` (scene 2) reads 0;
`LDA $A2` at `$7914` (scenes 1, 6) and `$758D` (scene 5) reads 0; writes
of `$B7` above 1 store 1 (not in scene 0, where `$B7` is something else:
clamping it there kept the title from ever starting a game, 40,000 frames).
Tested with scripted players: 40,000 frames reached scene 3 (scene 2 at
frame 10,168, scene 3 at 21,157) with 20 foes killed, 0 deaths and the
gate defused once; a hold-right run that died off the cliff without the
cliff block ran 12,000 frames with it, past the Akuma cutscene, without
dying. The unprotected-hit block has not yet been seen to fire in a test
(no scripted run was hit while running).

The recording batch now uses version 2 (`*-easy.inp`); version 1 stays
for replaying `xe-01-inv.inp`.

### The ending, and coverage from two human playthroughs (same day)
`inp/xe-01-easy.inp` (512 s, easy mode) reaches the ending: scene 1 at
frame 160, scene 2 at 5,045, scene 3 at 8,738, **scene 4 at 24,549, which
holds the finale**: the last fights, the hawk, Akuma defeated, Mariko
freed, and the epilogue text ("and so this adventure ends…"). Scene 5
(scene 0's banks) appeared in no run, human or scripted; it may be unused.

Easy mode during that run: 159 hits absorbed, the gate check defused once,
362 cliff checks neutralised, 11 foes killed. The instant-death block fired
196 times, in bursts every 6-18 frames with the victim in states
`$22-$29` and `$07`. That is more than hits on the player explain, so the
`$62 = $22` test at `$B12A` is probably not "the victim is the player"
as first read; the block may also spare guards that would have died
outright. The user reports running past guards a couple of times, which
the real game cannot do (a running player dies at the first contact),
so the run passed through states the original never produces. Read its
coverage with that in mind. The user also notes that kicking needs a long
press on the stick, which made the hawk hard. That is the XEGS input
design (held frames are counted, `$0FB0`), and the port has to keep it.

**Coverage, instructions executed** (census probe over the scripted runs,
`xe-01-inv.inp` and `xe-01-easy.inp`; window bank excluded):

| Scene | Scripted | + recording 1 | + recording 2 | Union | Static trace | Executed, not in static trace |
|---|---|---|---|---|---|---|
| 0 | 1,112 | +142 | +0 | 1,254 | 5,591 | 94 |
| 1 | 4,194 | +1,170 | +15 | 5,379 | 5,784 | 154 |
| 2 | 3,911 | +1,194 | +143 | 5,248 | 5,777 | 78 |
| 3 | 3,806 | +0 | +789 | 4,595 | 5,187 | 82 |
| 4 | 2,006 | +0 | +1,695 | 3,701 | 5,089 | 76 |
| 6 | 475 | +0 | +0 | 475 | 4,546 | 26 |

The last column is what a static trace alone would have missed: computed
jumps and code built at runtime. 76 of those instructions are common to
every scene (the code-bank region; most likely the routine built at
`$2409-$2421`). Static trace ∪ executed is the code map step 3 starts
from; static-only bytes are plausible code, not proven.

### Why a kick needs a long press: the stick is read every 6-10 frames (same day)
Replaying `inp/xe-01-easy.inp` with a read tap on PORTA (the game's reads are
at `$AD09`; `$C1F3`/`$C200`/`$C4ED`/`$C51A` are the OS) and the stick as
held each frame (MAME port `:ctrl1:joy:JOY`):

| Scene | Frames | Frames with a read | Median gap | Commonest gaps |
|---|---|---|---|---|
| 1 | 4,885 | 407 | 6 | 5, 6, 4, 8 |
| 2 | 3,693 | 371 | 7 | 7, 6, 8, 5 |
| 3 | 15,811 | 1,637 | 10 | 10, 8, 9, 11 |
| 4 | 6,452 | 215 | 7 | 7, 9, 6 |

The stick is read when the player's fighter reaches a decision point, not
every frame. Of 562 stick pushes, 199 (35%) ended between two reads and were
never seen: pushes of 1-3 frames were missed 55 times in 67, 4-7 frames 105
in 205, 13 frames or more almost never. (Some pushes fell in cutscenes, where
nothing reads the stick, so 35% is an upper bound.) The same kind of problem
as the 7800 version's lag (13-14 frames between reads there), milder.

**Trial fix on the original, `probes/xe-easy-latch.lua`:** sample the stick
every frame, keep the latest push, and when the game reads a centred stick
hand it the kept push once, then clear it; a push still held is read live.
A tap therefore arrives once at the next decision point and a hold still
reads as a hold, which is what the withdrawn 7800 button latch got wrong.
Scripted test, fighting stance, a 2-frame right tap every 25 frames for
6,900 frames: without it the game read 1 of 276 taps, with it 276 of 276,
and play carried on normally. `Record Karateka XE (quick stick).bat` records
with it (`*-easylatch.inp`) so it can be judged by feel before the port
commits to it; the 7800 difficulty switch could select original or quick.

### Step 3 begins: scene 1 as source that rebuilds exactly (same day)
`port/xesource.py` writes one scene's address space as assembler source:
segments `common` ($0480-$0FFF, bank 12's first $B80 bytes: the code bank
overwrites the rest, confirmed against RAM in scene 1), `code` ($1000),
`data` ($6000), `art` (bank 14 at $8000, never executed) and `fixed`
(bank 15 at $A000). Instructions come from the static trace plus every
instruction the census saw run; every operand pointing at code, data,
zero page, RAM or hardware becomes a symbol (`L_xxxx`, `Z_xx`, `V_xxxx`,
register names), references into the middle of an instruction become
`label+n`. Output goes to `port/build/` (ignored: it contains cartridge
bytes). **Scene 1: all five segments rebuild byte for byte** with the
toolkit's `asm.py`: 6,426 instructions, 5,625 of them seen executing,
12 self-modified operand references ($2839, $28FA-B, $291D-E, $2926,
$2ADA-B, $2AFF-$2B00, $2B11, $7C50).

**Census correction.** Keying executed code by `$D0` misfiled a few frames
at every scene change: the game writes `$D0` before the loader has
replaced the banks, so the old scene's last instructions were filed under
the new scene. That showed up as 24 impossible overlaps in scene 1's data
bank. The census now keys by the scene the loader actually loaded (the
`$D0` read at `$2F75`, taking effect when `$2F84` runs); the overlaps are
gone. Two remain, and they are real: `$2925/$2926` and `$2B10/$2B11`,
self-modifying code whose instruction boundaries change at run time.
These routines go to RAM in the port. It also corrects scene 6: it is not
a 41-frame lead-in. Loaded by force it runs the whole 4,103 frames; it
sets `$D0 = 1` straight away, which the old keying mistook for a return
to scene 1.

### All scenes rebuild exactly; the code banks share an engine (same day)
With the census rerun keyed by the loaded scene (all seven runs: five
scripted, both recordings), `port/xesource.py` generates every scene, and
**all six (0, 1, 2, 3, 4, 6) rebuild byte for byte in all five segments.**
The only overlapping instructions left in any scene are the two
self-modifying spots (`$2925/$2926`, `$2B10/$2B11`; none in scene 0).

Coverage, corrected (supersedes the table above, which was keyed by `$D0`):

| Scene | Scripted | + recording 1 | + recording 2 | Union | Static trace | Executed, not in static trace |
|---|---|---|---|---|---|---|
| 0 | 1,219 | +35 | +0 | 1,254 | 5,591 | 92 |
| 1 | 4,028 | +1,246 | +15 | 5,289 | 5,784 | 76 |
| 2 | 3,914 | +1,193 | +150 | 5,257 | 5,777 | 76 |
| 3 | 3,809 | +0 | +786 | 4,595 | 5,187 | 76 |
| 4 | 1,910 | +0 | +1,704 | 3,614 | 5,089 | 76 |
| 6 | 3,168 | +0 | +0 | 3,168 | 4,546 | 58 |

The code the static trace cannot see is the same 76 instructions in every
gameplay scene.

**The code banks share an engine.** Of each code bank's 8,192 bytes,
4,935 are identical in all six scenes: `$1000-$1202` (515 bytes),
`$2300-$24A4` (421) and `$24AC-$2FFF` (2,900). That covers the drawing
code with every self-modified operand (`$2839-$2B11`), the constructed
routine's neighbourhood and the loader. Seven bytes at `$24A5-$24AB`
differ per scene. So a code bank is ~4.9K of shared engine plus ~3.2K of
scene code at `$1203-$22FF`. The port can hold the engine once (its
self-modifying part in RAM) and give each scene page only its own code
and data.

### ROM size decided: 128K (same day)
Retail SuperGame+RAM boards (header `$0006`, from the Rom Library dumps):
Summer Games, Winter Games, Impossible Mission and Jinks are 128K; Tower
Toppler is **64K**, so 64K + RAM is also a retail layout. The unique content
comes to ~83K even with scene 6 stored as a 231-byte patch on scene 1, so
64K would need ~20K of it to be unread. The only size between 64K and 128K
(144K, 9 banks) puts its extra bank at `$4000`, where this board has its
RAM. **Decision (user, 2026-09-24): 128K**, eight 16K banks, bank 7 fixed
at `$C000`, 16K RAM at `$4000`. Pages 6-7 are headroom.

Budget, visible at once: ~28.8K shared (XEGS bank 15 8K, art bank 14 8K,
engine 4.9K, common 2.9K, display lists ~3.5K, 7800 boot/sound/glue ~1.5K)
plus ~11.3K per scene (code 3.3K, data 8K), against ~39K available (16K
fixed, 16K page, ~3.8K cartridge RAM beside the framebuffers, ~3.5K console
RAM). The split is settled by the read census (every byte each scene reads,
running now): dead XEGS boot/loader code and unread data are the slack.

### Read census: a dummy-read trap, and the shared segments (same day)
A read tap over `$0480-$BFFF` for every scene (`xreads.lua`) first reported
every byte of scenes 0-3's code and data banks as read. Wrong: the 6502
makes a dummy read of the destination on `STA (zp),Y`, so the loader's copy
loop at `$B2CC` "reads" each byte it writes, and since the scene key
changes only when the copy is done, those reads landed on the previous
scene. The OS's RAM clear at power-on does the same to scene 0. The census
now ignores reads made by `$B2CC-$B2EA` and by the OS (PC ≥ `$C000`).
Anything measuring reads on a 6502 needs that filter.

Unaffected by it (ROM the loader never writes), the two shared ROM
segments, union over scenes 0-4 and 6, all seven runs:

| Segment | Read | Never read |
|---|---|---|
| XEGS bank 15 (`$A000-$BFFF`) | 6,495 of 8,192 | 1,697 |
| art bank 14 (`$8000-$9FFF`) | 7,581 of 8,192 | 611 |

(The first pass also showed the common bank and the engine as read in
full; they are loader destinations too, so those figures were inflated
in the same way and wait for the filtered rerun.)

Art per scene, in 256-byte pages: scene 0 reads one page (`$80`); scenes
1-3 read 30-32 of 32; scene 4, 26; scene 6, 22. The fighters' art is
common to every fight, so art cannot be split per scene to any useful
degree.

Filtered rerun (loader and OS reads excluded), union of all seven runs:

| Segment | Size | Read | Never read |
|---|---|---|---|
| XEGS bank 15 (`$A000-$BFFF`) | 8,192 | 6,289 | 1,903 |
| art bank 14 (`$8000-$9FFF`) | 8,192 | 7,581 | 611 |
| common (`$0480-$0FFF`) | 2,944 | 2,185 | 759 |
| engine (the shared code-bank ranges) | 3,836 | 3,158 | 678 |

| Scene | Own code read (of 4,356) | Data bank read (of 8,192) |
|---|---|---|
| 0 | 816 | 1,709 |
| 1 | 777 | 6,690 |
| 2 | 1,758 | 6,960 |
| 3 | 2,132 | 5,353 |
| 4 | 2,742 | 4,657 |
| 6 | 441 | 2,144 |

(The engine is 3,836 bytes, the three identical ranges; the "4,935
identical bytes" above also counted short scattered matches.) Unread is a
lower bound on what is unused, not proof: ~130,000 frames of play, no
scene 5. So the layout below does not depend on dropping any of it.

### The banking layout (128K SuperGame + 16K RAM)

The art and the scene data cannot share a page: 8K + 8K + the scene's own
code (4.4K) is more than 16K. But nothing needs to see both at once except
the drawing code, and that is the shared engine. So art gets a page of its
own, and the engine selects the art page for a blit whose source is art and
puts the scene page back before returning.

| Bank / area | Address | Contents | Size |
|---|---|---|---|
| bank 7 (fixed) | `$C000-$FFFF` | XEGS bank 15 8K, common 2.9K, engine 3.8K (its self-modifying routines copied to RAM at boot), 7800 boot, DLI handler, TIA sound driver, page-switch wrapper | ~16K: tight |
| banks 0-5 | `$8000-$BFFF` | one per scene (0, 1, 2, 3, 4, 6): the scene's own code 4.4K, its data bank 8K, and a copy of the display lists 3.5K | ~15.9K each |
| bank 6 | `$8000-$BFFF` | art bank 14 at `$8000-$9FFF`, its XEGS address, plus the display lists again | ~11.5K |
| cartridge RAM | `$4000-$7FFF` | framebuffers A and B (12.2K), the engine's self-modifying routines, the routine built at `$2409`, the `$0880` table | ~16K |
| console RAM | `$1800-$27FF` | the moved zero-page overflow, the variables (~250 bytes of the common/data banks' written bytes), two display list lists (one per buffer, DLI bits patched when the game changes display list), latch and sound state | ~2.5K of 4K |
| zero page / stack | `$40-$FF`, `$140-$1FF` | the game's zero page (208 bytes used: 16 must move out), the stack (lowest SP `$EA`) | |

The display lists sit in every page that can be selected while the screen is
being drawn, because MARIA reads them in the middle of the frame.

**Every bank is used.** Scene 6 is scene 1 with 231 bytes changed, so its page
can become scene 1's plus a patch applied at load, which frees one bank if the
fixed bank runs out. The fixed bank is the tight spot: slack there comes from
the XEGS-only code that can go (boot `$B7B1`, the copy routine `$B2CC`, the
loader `$2F5A`, the OS vertical-blank glue), then from the unread bytes if the
coverage is widened enough to trust them.

To check before building on it: that no single blit reads both art and scene
data (the blitter has one source pointer, `$03/$04`, plus mask tables in the
common bank, which is in the fixed bank), and that nothing outside the
engine reads the art directly.

### The art bank checks out (same day)
Probe `xpages.lua` (scratchpad `kport/`), scenes 1, 2, 3, 4, 6 scripted plus
`xe-01-easy.inp`, keyed by the loaded scene. Code split by where it will
live: fixed bank (common, engine, XEGS bank 15) or scene page (the scene's
own code, its data bank).

1. **No scene-page code reads the art.** Zero art reads by code at
   `$1203-$22FF`, `$24A5-$24AB` or `$6000-$7FFF`, in any scene.
2. **Stretches of fixed-bank code that read art also touch scene-page
   bytes, and three of the four causes are artifacts:**
   - `RTS`/`RTI` end with a throwaway read at the return address; returning
     into the scene page counts as a scene-page read (`$2A03`, `$2D02`,
     `$B884`, `$BCA5`, all `RTS`). A probe that keeps only the last read of a
     stretch sees nothing else, because the `RTS` always comes last.
   - ANTIC's display-list fetches go through MAME's CPU address space and a
     read tap files them under whatever instruction is running: 24,405 such
     "reads" of `$1900-$1BFF`, the XEGS display lists, which MARIA's
     replace.
   - Real ones, 2,041: `$0FA2` (the vertical-blank button routine) reading
     `$7FE7` from the scene data bank (1,966, an interrupt landing in the
     middle of a blit); blits whose sprite is in the scene's own code or
     data (`$291A` from `$16xx`/`$18xx`, `$29EB`/`$2AFC` from `$7Exx-$7Fxx`);
     and `$2573` reading scene tables `$2036-$2156` between blits.
3. **A blit's source never crosses between regions.** The source pointer
   (`$03/$04`) was loaded ~1.1 million times and stepped within a blit
   (`INC`/`DEC $04`) ~40,000 times across all runs; no step ever moved it
   between art (`$80-$9F`), scene data (`$60-$7F`) and elsewhere.

**Rule for the port:** one bank per blit, chosen from the high byte of the
source pointer (`$80-$9F` → the art bank, otherwise the scene page), and the
scene page restored when the blit returns; the frame interrupt selects the
scene page on entry and restores the previous one on exit (or `$7FE7` moves
to RAM at scene load). Nothing else sees the art.

Two general lessons for read probes on MAME: exclude `RTS`/`RTI` throwaway
reads (track the opcode from the instruction fetch), and expect video DMA to
appear as reads by whatever instruction happens to be running.

### Finding the addresses stored in data: an origin tracer (same day)
Relocation needs every byte that holds part of an address, not only the
instruction operands (those are symbols already). `xorigin.lua` follows
each loaded value back to the byte it came from, through register
transfers, arithmetic, stores to RAM and pushes, and when a value is used
as an address, (zp),Y / (zp,X) pointers, `JMP (vector)`, `RTS` to a pushed
address, or a self-modified absolute operand, it records the origins of the
high and low halves and where they pointed. `port/origin_report.py` sorts
the origins into immediates (`LDA #n` operands, which become `#>label` /
`#<label`), table bytes (which become `.byte >label` entries) and addresses
built in RAM (to read by hand).

**Wrong turn:** the first version took an instruction's data address to
be its last observed read. MAME routes ANTIC's DMA, display-list and
screen fetches, through the same address space, so those reads land in
the middle of CPU instructions and were taken for operands: it reported
5,924 "table" origins, with art bytes pointing at the framebuffers and the
display list at `$1908` as the origin of hundreds of pointers. Corrected:
effective addresses are now computed from the opcode, its operand bytes and
X/Y/SP at the instruction fetch, the way the CPU forms them, and never taken
from observed reads. A short scene-1 run then gives 16 immediates, 169
table bytes and 1 built-in-RAM origin; the first table found is the high
bytes at `$0715`+ in the common bank, one per 22-byte fighter record at
`$0480-$06B1` (the 22-byte-stride writes seen in the census).

General rule, now twice learned: on MAME's Atari 8-bit, a read tap sees
ANTIC's DMA as reads by whatever instruction is running. Filter by
address or compute addresses; never infer an instruction's operands from
the reads around it.

### Where the analysis harness lives (2026-09-25)
A session restart wiped the scratchpad that held the probes, run scripts and
census data used above. They are rebuilt as project files so it cannot
happen again: `probes/xe-census.lua` (writes, reads, executed code, hardware
and colour timing per loaded scene, with the loader/OS dummy-read filter),
`probes/xe-origin.lua` (the origin tracer, effective addresses computed),
`probes/optable.lua` (generated by `port/mkoptable.py` from the toolkit's
6502 table), and `port/run-probe.sh`, which runs any probe over the
standard set (scripted scenes 1, 2, 3, 4, 6 and both recordings) into
`work/analysis/<name>/` (ignored). The runner exits non-zero only on a Lua
error, not on the empty search that made earlier batches report "failed".

### The relocation list (2026-09-25)
Full origin trace (`probes/xe-origin.lua` via `port/run-probe.sh`; the
census rerun alongside reproduced the earlier frame counts exactly),
reported by `port/origin_report.py` into `work/analysis/origin/report.txt`:
71 immediates, 539 table bytes and 1 address built in RAM, as high-byte
origins. Checking each origin's value against the pointer it fed splits
them:

- **482 direct** (447 table bytes, 35 immediates): the stored byte *is* the
  pointer's high byte. These relocate mechanically (`>label` in place of a
  number). Among them: art pointer tables in bank 15 (`$A02A-$A053`,
  `$A0D2-$A0FB`, `$A24C-$A271`, `$BD23-$BD2D` …), dispatch tables in the
  engine (`$25E3-$264F`, `$2701-$27AE`, `$119D-$11C6`), per-scene pointer
  tables in the scene data (e.g. scene 4 `$7DE0-$7FA3`), and the framebuffer
  bases as immediates (`$2818` = `#$30` for buffer B, `$2829` = `#$48` for A,
  `$AD97/$AD9F/$ADB3/$ADBB` in bank 15).
- **128 derived** (92 table, 36 immediate): the value changed between origin
  and use. Three patterns, to be read by hand:
  1. offset-encoded tables. The fighter-record table `$0715-$0731` holds
     `$00-$02` for records at `$04xx-$06xx`: a base of `$04` is added in the
     code, and the base is what relocates;
  2. base + offset arithmetic. `#$28` (the 40-byte row stride), `#$00`,
     small art bytes: the tracker keeps the origin of the loaded operand
     when a base is added to it, so the offset is credited instead of the
     base;
  3. misattributions. `$7962-$7969` hold opcode-like values (`$C9 $20 $F0`)
     and `$7BEA-$7BF7` hold `$FF`: not address bytes.
- **1 built in RAM:** the stack at `$01FF` during the XEGS boot (an RTS trick
  at `$BFE0`), which the 7800 does not use.

Coverage caveat as before: this is what the recorded runs used. The safety
net is end-to-end: the port is checked against the original frame by frame
(same inputs, framebuffer contents compared), which catches any address the
list missed.

### Reviewing the derived origins, and a layout correction (2026-09-25)
**The small-sprite block is written to.** The table at `$0715` is
offset-encoded: `LDA $06F4,X / ADC #$80 / STA $03 / LDA $0714,X / ADC #$04 /
STA $04` (`$0796-$07A3`), so every small sprite's address is an offset from
`$0480`, and the base is the immediates at `$079B` and `$07A2`. The code
also writes into those sprites' headers (clips a height at `$07BD`, draws,
restores at `$07C4`), so the 616-byte block `$0480-$06E7` needs RAM.

**Framebuffer constants.** Shifting both buffers by +$1000 (A `$4808`→`$5808`,
B `$3010`→`$4010`) keeps their spacing and each byte's position within its
page, so row arithmetic and buffer-to-buffer copies still work and only
high-byte constants change. Every executed immediate in `$30-$5F` was read
in context; the framebuffer ones are the base `#$30`/`#$48`, the end
`#$47`/`#$5F` (only compared, so the origin trace cannot see them) and the
row base `ADC #$30`/`ADC #$48`: `$2817 $2820 $2828 $2831 $2D65 $2D73` in the
engine and `$AD96 $AD9E $ADA9 $ADB2 $ADBA $ADC5` in bank 15. The rest are
coordinates and animation states.

**Blit sources in the scene page** (`probes/xe-blitsrc.lua`: every byte
read through `($03),Y`, computed at the fetch; scripted scenes plus the
ending recording). The "art bank for `$80-$9F`" rule needs every scene
sprite outside `$8000-$9FFF` in the scene page, which leaves only 8K for
12.4K. Measured:

| Scene | Scene-code sprites read | Scene-data sprites read | Also |
|---|---|---|---|
| 0 | 227 (pages `$21-$22`) | 867 (`$61-$7E`) | 78 bytes of the XEGS OS font (`$F8xx`), 530 of the small-sprite block |
| 1 | 0 | 2,600 (`$60-$7E`) | framebuffer B (buffer copy) |
| 2 | 971 (`$12-$18`) | 3,301 (`$60-$7F`) | both framebuffers |
| 3 | 1,327 (`$12-$18`) | 2,822 (`$60-$7F`) | 256 bytes of the OS font (`$FD-$FE`) |
| 4 | 1,577 (`$12-$1F`) | 2,449 (`$60-$76`) | |
| 6 | 0 | 509 (`$66-$6C`) | |

Scene-data sprites cover nearly the whole data bank, so the data bank stays
whole at `$A000-$BFFF`. The scene-code sprites are few (~4.1K over all
scenes) and move to the fixed bank, each at its own address. (The reads of
the XEGS OS ROM noted here were first taken for its font. They are not; see
"The OS ROM reads" below.)

**Corrected layout:**

| Where | What |
|---|---|
| fixed bank `$C000-$FFFF` | XEGS bank 15 (8K), the read-only part of the common bank (~2.2K), the scene-code sprites of scenes 0, 2, 3, 4 (~4.1K), 7800 system code (boot, NMI/DLI handler, bank wrappers, dispatcher, TIA sound, stick latch) |
| cartridge RAM `$4000-$7FFF` | framebuffer B `$4010-$57F7`, A `$5808-$6FEF`, **the whole engine** (3.8K, at `$7000`, copied at boot: its self-modifying code and the routine built at `$2409` run as on the XEGS) |
| banks 0-5, `$8000-$BFFF` | one per scene: its own code at `$8000`, its data bank at `$A000`, the display lists |
| bank 6, `$8000-$BFFF` | the art at `$8000-$9FFF` (its XEGS address), the engine's boot copy, the display lists |
| console RAM | the common bank's written parts (small-sprite block, the `$0880` table, variables), the two display list lists, the zero-page overflow, latch and sound state |

Blit rule: source page `$80-$9F` → art bank, `$A0-$BF` → scene page,
`$C0`+ → fixed, below `$80` → RAM. No two sources share a page range.

### Relocation written into the source (2026-09-25)
Every move in the layout is a whole number of pages, so an address's low
byte never changes and relocation is only "add the region's page delta to
its high bytes". `port/reloclist.py` merges the origin trace's direct
origins with the cases read by hand (the twelve framebuffer constants and
the small-sprite base at `$07A2`) into `work/analysis/reloc.txt`: 488 high
bytes, 270 in shared segments and 23-85 per scene. By region pointed into:
scene data 196, art 151, scene code 55, engine 60, common 10, framebuffers
12, the small-sprite block 1, and 4 into the XEGS OS ROM (the font-glyph
pointers, to be pointed at the port's own glyphs).

`port/xesource.py --reloc` writes each of them as an expression over its
region's base symbol (`.byte >R_sdata+$0D00`, `LDA #>R_fbA+$1700`), region
bases defined as `R_<region>` equates. **All six scenes still rebuild byte for
byte, with every relocation (293-355 per scene) landing on an immediate or
a data byte.** A mistake in scene keys was caught on the way: scene 0's
origins are keyed `0*65536+address`, which is just the address, so they
first read as shared; the list now treats an untagged byte in a
scene-specific region as scene 0's.

Regions (XEGS ranges that move as one piece): `sprites $0480-$06E7`,
`common $06E8-$0FFF`, `engine1 $1000-$1202`, `scode $1203-$22FF`,
`engine2 $2300-$24A4`, `scode2 $24A5-$24AB`, `engine3 $24AC-$2FFF`,
`fbB $3000-$47FF`, `fbA $4800-$5FFF`, `sdata $6000-$7FFF`, `art $8000-$9FFF`,
`bank15 $A000-$BFFF`, `os $C000-$FFFF`.

### The OS ROM reads: checksums, and a bug that draws garbage (2026-09-25)
The four places that point into the XEGS operating system ROM, which were
first taken for its font. (The OS character set lives at `$E000-$E3FF`;
these addresses are OS code.)

- **Three checksums of the OS ROM, all in scene 3, all disabled.** `$7315`
  sums `$FD08-$FE07` and compares with `#$77`; `$69D9` EORs and adds
  `$C482-$C581` against `#$7C`; `$7974` sums `$C214-$C313` against `#$05`.
  In the first two a `JMP` placed right after the `CMP` skips the `BEQ` and the
  failure path (`$7328 JMP $7340`, `$69F0 JMP $69FC`, failure at `$69F5`
  setting `$A4/$A5`); in the third, `LDA $84` overwrites the flags before any
  branch. Copy protection or a genuine-hardware check from the disk version,
  switched off when the game went to cartridge. The port drops the loops.
- **A bug that draws OS code as a sprite.** The engine table at `$25C0`
  holds addresses (`$25F8`, `$25FC`, …); it is read one byte out of step,
  so one entry's low byte (`$F8`) becomes a pointer's high byte and the
  blitter draws from `$F820-$F876`. In the title and story sequence this
  happens at frames 105, 111, 609, 615 and 651 (5-61 screen bytes each).
  **Visible in the original:** with those writes suppressed, 277 pixels
  change on the title screen (a blotch beside "KARATEKA" and a dotted line
  under "Copyright 1988 Atari Corporation") and 5 in the story text (dashes
  under "craggy c…", moving up as it scrolls).

The game's stylised lettering is its own art, drawn by the same blitter
into the same bitmap as everything else: no OS font or text mode is
involved. **Decision (user, 2026-09-25): no graphics corruption; bugs in the game are
fixed in the port.** The `$25C0` read is fixed rather than reproduced, and the
frame comparison lists those title/story pixels as a known, deliberate
difference. The dots are the CPU writing OS bytes into the bitmap, so they
are not MAME's XEGS rendering faults; but because that machine's graphics are
imperfect, the port is checked against the original's **framebuffer bytes in
RAM**, never against MAME's rendered XEGS picture.

### The display lists, and the layout that holds (2026-09-25)
**The conflict.** MARIA reads the display lists on every line, whatever bank
is selected, so they must exist at the same addresses in the art bank and
every scene page. But the blit rule needs art and scene sprites in opposite
halves of the window, which leaves no range free in both. 21 of the 32
scene-data pages hold sprites in some scene (`$60-$6E`, `$75-$76`,
`$7C-$7F`; union over scenes), too many to share a half with ~3.1K of
display lists. RAM is full, and with the common bank in it the fixed bank is
~1K short.

**The fix: display lists in the fixed bank, the common bank in each scene
page.** Checked first, with `probes/xe-artblit.lua` (every instruction's
effective address computed at its fetch, interrupts excluded, scripted
scenes plus the ending recording): **while a blit reads art (`$29D8` to
`$29FB` with the source pointer in `$80-$9F`), the game touches only zero
page, the framebuffers, the engine and the art, and runs only engine code.**
No common bank, scene code, scene data or bank 15. The only art read
outside such a blit is the XEGS loader's copy loop (`$B2DA`), which the port
replaces. So `$29D8`/`$29FB` are the whole bank-switching hook.

The health-arrow sprites the blitter reads from the common bank
(`$0B12-$0B24`, pointer built by `LDA #$12 / LDA #$0B` at `$0B70`/`$0B74`;
both `#$0B` immediates, `$0B75` and `$0BBB`, are in the relocation list) move
with the scene-code sprites to the fixed bank.

The scene-code sprites share: every address read as a sprite in more than
one scene holds identical bytes (1,131 addresses, 0 differing), so one copy
serves every scene: 2,047 bytes, in runs `$1203-$1523`, `$1530-$15B2`,
`$1600-$18A1`, `$18BF-$18D7`, `$1C80-$1CED`, `$1F00-$1F28`, `$1FD7-$1FFC`,
`$2193-$2275`.

| Bank / area | Contents | Size |
|---|---|---|
| fixed `$C000-$FFFF` | XEGS bank 15 at `$C000` (it may grow: unrolled copy loops and zero-page movers; nothing points into it), 7800 system code, **the display lists**, scene-code and arrow sprites (page-aligned copies), vectors | ~15.5K |
| banks 0-5 (scene pages) | scene code `$1203-$22FF` at `$8203` (+`$7000`), **common `$06E8-$0FFF` at `$96E8`** (+`$9000`), scene data at `$A000` (+`$4000`) | ~14.9K each |
| bank 6 (art) | art at `$8000-$9FFF` (unchanged), the engine's boot image, the initial copies of the RAM-resident data | ~12.5K |
| cartridge RAM | framebuffer B `$4010`, A `$5808` (+`$1000`), engine at `$7000`/`$7300` (+`$6000`/+`$5000`) | 16K |
| console RAM | zero-page movers, OS-page shadows, the small-sprite block (`$0480-$06E7` → `$1B80`), carved-out variables and the `$0880` swap buffer, system state, mode-8 expansion rows, the two display list lists | ~2.5K of 3.7K |

The NMI selects the scene page on entry and restores the previous bank on
exit, so the interrupt handlers (which live in the common bank now) always
see their code.

### The linker (2026-09-25)
`port/layout7800.py` holds the map (regions, carve-outs, sprite copies,
zero-page allocation, hardware and OS-page mapping, replacements);
`port/link7800.py` assembles every region of every scene at its 7800
address from the source generator's analysis, computing each relocated high
byte from its pointer's target. **It links all six scenes**: every chunk
outside bank 15 assembles to exactly its original size with every label where
the layout says, and the shared chunks (bank 15, engine, art, small-sprite
block) assemble identically for every scene. Bank 15 grows by 528 bytes
(`$C000-$E20F`: the six unrolled record copies and 18 zero-page bytes moved
to absolute RAM). The engine's seven per-scene bytes `$24A5-$24AB` are the
only difference allowed.

Found on the way:

- **Code crossing a region boundary:** one place in any scene. The
  vertical-blank step at `$0FFB` starts in the common bank (`LDA $0F17 /
  BNE $101F`) and runs on into the engine at `$1000`; contiguous in XEGS RAM,
  apart on the 7800. Its 5 bytes become a jump to a system routine that does
  the same and continues in the engine.
- **The garbage-dots bug is a zero-page clash, not a bad table read.**
  `$2422` is the sound-effect starter (`LDA #$15 / JSR $2422`); it uses
  `$04/$05` as its own pointer into the sound table at `$25C0` and leaves the
  first entry's low byte, `$F8`, in `$04`, the high byte of the blitter's
  source pointer. Text is drawn while the typing sounds start, and a text
  blit that reloads only `$03` then reads from `$F8xx`. Fixed in the port:
  `$2422`'s first 4 bytes become a jump to a routine that keeps `$04` around
  the original.
- **OS references that never ran:** scene 0's `LDA #$14 / JSR $F946` (the
  middle of an OS screen-editor loop, `DEX / DEX / DEX / BPL / RTS`, on a
  path no run took) and scene 3's `LDX $FEA8` / `ROL $0278` (data the static
  trace misread as code). They get a system entry that returns and a sink byte.
- **A shared table cannot point per scene.** Bank 15's tables at
  `$B827-$B82A` and `$BE6E-$BE74` point at scene-code sprites, which live in
  the fixed-bank copy in scenes 2-4 and are ordinary scene code in scenes 0,
  1, 6. Only runs that reached scenes 2-4 ever used those entries, so a
  pointer stored in a shared chunk always resolves to the copy.
- **The engine's code map must be shared too.** Scene 6's analysis decoded
  the engine's (identical) bytes around `$10FE` differently from scene 0's,
  because only scene 6 had run that IRQ path; the engine ranges now take the
  union of every scene's code, as the common bank and bank 15 do.
- The source generator had been importing `Karateka-Port/tools/asm.py`, the
  old copy, ahead of the toolkit's; the toolkit's now wins.

### The first 7800 build boots and draws the title (2026-09-25)
**Result: scene 0 runs on the 7800 (MAME `a7800`) and its title frame is the
original's, byte for byte,** except where the original's garbage-dots bug
draws (buffer B rows 56-60 around the "TM" spot, rows 133-134 under the
copyright lines), which the port fixes. Compared as framebuffer bytes, not
screenshots: `probes/fbdump.lua` on both machines, `port/fbcompare.py`
(rows and columns that differ, plus a side-by-side PNG). The story scroll that
follows runs and reads correctly (not yet compared byte for byte).

**Room in the fixed bank.** The NMI redesign overflowed it. Freed:
- dead XEGS code removed from bank 15 (which may change size, since
  nothing points into it): the 8K copy routine `$B2CC-$B2EB` (only the boot
  and the loader call it) and the cartridge boot `$B7B1-$B7DA`. Bank 15 is now
  `$C000-$E1D7` and the system jump table starts at `$E1D8`.
- the common-bank carve list and the scene-to-bank table moved into every
  scene page after the zero-page tables at `$9300` (the loaders always run
  with a scene page in).
- the empty DL and the three mode-8 row DLs (32 bytes) moved to a gap
  between the sprite copies, `$F8B4`.
The system block (code plus the per-row DLs, 3,060 bytes of it) ends at
`$F4E1`, so about 30 bytes are spare before the sprite copies at `$F503`.
**This is tight.** The TIA sound driver will not fit in the fixed bank.
Code that never switches banks can live in the scene pages (about 1K free in
each) instead.

**Bugs found booting, all in the port's system code:**
- **MAME never raises the DLI of a DLL's last line.** The vertical-blank
  stand-in was on line 242 of 243, and no NMI ever came. It works on any
  earlier line.
- **Interrupt code clobbering foreground scratch.** `Inputs` (in the NMI)
  used `S_TMP`, the loaders' byte counter, so an NMI during the engine copy
  cut it short at `$7169` and the game later ran into zeros. The list
  builder used `S_TMP` too. Now `Inputs` uses none, and the builder has its
  own `S_BTMP`.
- **The game's DLI and VBI handlers must never nest.** Both save `$14/$15`
  and `$03/$04` in the same four bytes (`$1193-$1196`) on entry and restore
  them on exit (`$1169`/`$117E`). On the XEGS the vertical blank ends long
  before the next frame's first DLI. On the port, a VBI that ran long
  (building a list takes more than a frame) let the next frame's DLIs in,
  and the VBI then "restored" the DLI's values into `$14/$15`. That
  pointer is the end marker of the screen-clear loop at `$2835`, which then
  ran on and wiped the engine at `$7000`. Now:
  - The VBI DLI sits on the first blank line after the list's content, not
    the last line. That leaves the whole bottom border and top border to
    finish in.
  - A VBI that arrives during a game DLI waits until the DLI ends.
  - A DLI that arrives during the VBI is dropped.
  - A VBI that arrives while the last one is still running is dropped, as a
    late XEGS VBI would be.
  This replaces the "VBI on the last line" design in the previous entries.
- **Self-modifying code writes a zero-page operand.** The blitter picks its
  write mode by storing an opcode (ORA, AND, STA or NOP) at `$2925` and
  `$2B10`. It also stores the operand, `LDA #$14 / STA $2926` (`$289B`) and
  `$2A6D`→`$2B11`, which is the address of `$14`. `$14` moved to `$D5`, so on
  the port those blits read the TIA instead of the framebuffer. The
  capitals B and A drew as solid blocks, and strokes of the logo's "t" were
  lost. Both immediates are now linked as `#<Z_14`. A scan of every scene
  for stores into operand bytes finds only these two zero-page cases. The
  others are low bytes of JSR targets (`$28BB`, `$28BE`, `$2A8D`, `$2A90`,
  from the table at `$298D`), which relocation keeps since it moves only
  high bytes.

**How the title difference was run down**, since the same method will serve
the other scenes:
1. `blitlog.lua` showed every blit had the same source, header and zero page
   on both machines.
2. `fbwrites.lua` logged every framebuffer write in order, and the first
   differing write came in blit 4.
3. `blittrace.lua` traced that blit on both, interrupts excluded, with the
   destination pointer. The first difference was the value `ORA ($14),Y`
   read.
4. `bytewatch.lua` and `p7800-watch.lua` showed who wrote the ORA's
   operand.

**Speed: MAME's `xegs` is not a fair clock.**
- **Measurements.** `probes/cycles.lua` sums 6502 cycle counts per executed
  instruction. MAME's `xegs` executes 28,665 of the frame's 29,868 cycles:
  it doesn't steal ANTIC DMA cycles, as noted earlier. The port under
  `a7800` executes 22,928: 18,985 in the main program and 3,943 in the NMI
  (the original: 2,690).
- **Real-XEGS estimate.** A real XEGS loses about 10K cycles a frame to
  ANTIC (40 bytes a line for 192 lines, plus display-list and refresh
  cycles). That leaves its main program about 17K. **So the port should run
  at least as fast as the real machine**, even though it runs visibly slower
  than MAME's `xegs`. The title's busy loop runs at 64% of MAME-`xegs`
  speed, and the title and the story scroll take correspondingly longer.
  Frame-by-frame comparison against MAME's `xegs` therefore has to be keyed
  on the game's own progress, not on frame numbers.
- **To trim later.** The port's NMI costs about 1,250 more cycles a frame:
  - the wrapper around each of the six DLIs;
  - `Frame` on every VBI, to follow the game's buffer flip.

**Harness** (all in the project): `port/run7800.sh` and `port/runxe.sh` run
a probe windowless against the build or the original. The build writes
`work/karateka7800.sym` (system symbols) and `work/karateka7800.zp` (zero-page
map) for the probes. The probes:
- 7800-only: `p7800-events.lua` (system-routine entries), `p7800-run.lua`
  (state every 20 frames and writes into the ROM window), `p7800-crash.lua`
  (the last N fetches before a jump into RAM, a BRK or JAM, or a deep stack),
  `p7800-watch.lua`, `p7800-peek.lua`, `p7800-ramcheck.lua`, `p7800-rate.lua`.
- Either machine: `fbdump.lua`, `blitlog.lua`, `blittrace.lua`,
  `fbwrites.lua`, `bytewatch.lua`, `pccount.lua`, `pchist.lua`,
  `cycles.lua`, `xe-snap.lua`.

### The story scroll matches too (2026-09-25)
Compared at the same points in the game's own progress rather than at the
same frame: `probes/fbdumpkey.lua` dumps both framebuffers at the Nth
call of `$0862` (buffer flip and frame wait). At flips 10, 20, 40, 60, 80, 100 and
120 (the title through the scrolling story text) the buffers match except
for 3 bytes in one text row, which scroll up with the text. Every differing
framebuffer write was traced (`fbwrites.lua` grouped by blit, then
`blittrace.lua` with the source pointer). The whole difference is the
garbage-dots bug:
- The first differing blit (the original's 117th) has its source pointer
  change to `$F820` partway through the glyph, so it reads OS ROM.
- The 130th blit reads OS ROM for 110 steps.
- The 131st differs by one byte only because it ORs over the 130th's
  garbage.
The port draws the intended glyphs.

The port makes two more blits than the original at the start of the story (the
glyph at `$0522` three times where the original draws it once). They
write nothing, and every framebuffer write lines up one for one after them
(225,282 writes compared). This is likely a wait-for-time loop that simply
goes round more or fewer times at a different speed. Not a difference on
screen.

### Scene 1 runs and matches (2026-09-25)
Scene 1 (the first courtyard fight) plays on the 7800 build. Driven by the
same scripted player on both machines, its framebuffers match the
original's byte for byte at every flip checked through flip 800. That
covers the fight, the player's death and the restart that follows. It took
four fixes and two changes to the comparison method.

**Fixes:**
- **NMIEN is write-only on the XEGS.** Scene 1's start (`$0E97`) enables DLIs
  with `LDA NMIEN / ORA #$80 / STA NMIEN`. The XEGS reads `$FF` there, so this
  also turns the vertical blank back on (the loader had turned both off).
  The port's NMIEN is a readable shadow, which returned 0, so the VBI stayed
  off and the game waited forever at `$0E1A` for the VBI to clear `$0F0F`.
  `$0EA1` is now `LDA #$FF / NOP`. (Scene 0 had worked only because
  `S_NMIEN` starts at `$40`.) A static scan of every scene found no other
  read of a write-only register. The genuine hardware reads are TRIG0/1,
  CONSOL, KBCODE, IRQST (in an IRQ path the 7800 never takes), SKSTAT,
  PORTA and VCOUNT, and the port maps all of them.
- **Mode8 was half the CPU.** In play the NMI took 11,800 cycles a frame
  (the original: 2,300). Nearly all of it went to `Mode8`, which widened the
  30 status-row bytes pixel by pixel on every buffer flip. It also used
  `S_TMP`, the loaders' counter, inside the NMI, the same bug as `Inputs`.
  Now it widens only bytes that changed since the last flip, a nibble at a
  time from two 16-byte tables (in the `$F8B4` gap, after the small DLs),
  with its own scratch. The NMI is down to 4,400 cycles a frame and the main
  program gets 17,800. **That's more than a real XEGS's main program has**
  (MAME's `xegs` gives it 26,000 only because it steals no DMA cycles).
- **An untraced blit source: the player's death.** Every census run used a
  health cheat, so the player never died. The death routine `$6C52` (scene
  data, scenes 0 and 1) sets the source with `LDA #$1E / STA $04` and never
  ran, so it was never relocated. Its sprites are scene code at `$1E00`
  (19×4), `$1E4E` (15×7), `$1EB9` (12×2) and `$1ED3` (13×4). Scene code
  sits at `$8203+` in the scene page, which is the art bank's half of the
  blit rule, so the blitter read art and drew garbage past the framebuffer
  into the engine at `$7000`. The fix:
  - The loader now copies `$1E00-$1F08` to RAM at `$1900` when scene 1
    loads (a scene carve; carves can now come from scene code, and long
    ones are split into 255-byte entries).
  - The `$0880` swap buffer moved from `$1A00` to `$1880` to make room.
  - The immediate is a MANUAL relocation.

  A scan of every scene for `LDA #imm / STA $04` found two more unrelocated
  sources on untraced paths, scene 4's `$703B` (`#$60`) and `$7CD4`
  (`#$6F`). Both point into scene data and are now relocated. Scene 0 has
  unrelocated copies of scene 1's routines in its data, but the title never
  runs them. **Wrong:** the attract sequence runs them after the cutscene
  (the opening run and a demo fight), and they froze the port there; see
  "Story crash" below.

**The comparison method:**
- **Input keyed on game progress.** MAME latches inputs at frame
  boundaries, and those fall at different points of the game on machines
  of different speed. `playkey.lua` counts buffer flips instead:
  - `$0862` in the title and story; `$B60F` in play (bank 15, `$D752` on
    the 7800).
  - `INJECT=1` feeds the stick and fire straight into the game's reads
    (PORTA/TRIG0; SWCHA/INPT4, with the left difficulty forced to B).
  - It dumps the framebuffers and zero page at chosen flips.
- **Fire held for one flip, not two (`SHORT=1`).** The VBI times each press
  in frames (`$0FB0-$0FF8`): 20 frames or more makes the other move
  (`$46`, the kick), shorter makes `$47`. Two flips last about 20 frames on
  MAME's fast `xegs` and about 30 on the port, so the same script made
  different moves. **This is the long-press kick.** It is real time, so the
  port keeps it faithfully.
- **A flip counts when its instruction runs.** When an interrupt arrives
  just as MAME fetches the key opcode, MAME fetches it again after the RTI.
  The probe counted such a flip twice (the original's "missing" buffer
  toggle at flip 652). A key fetch now only arms the count, and the next
  fetch confirms it.

Dead ends, for the record:
- The divergence at flip 653 looked like real-time pacing. `$24A4` loads
  frame-wait counts `$0AFC/$0AFD` from the music data, and `$B60F` skips
  the flip while `$0AFE` is set. It was only the double count.
- MAME's Lua API has no CPU clock scale, so MAME's `xegs` can't be slowed to
  match.

### Scenes 2, 3, 4 and 6 match too (2026-09-25)
The same comparison (`playkey.lua` with `SCENE=n`, which substitutes the
scene for the game-start `$D0 = 1` as the census does; `INJECT=1 SHORT=1`)
at flips 195, 200, 210, 250, 300, 400, 500, 600 and 800:
- **Scenes 2, 3 and 4:** both framebuffers identical at every point. In
  scene 2 the scripted player dies and the game goes back to scene 1, the
  same on both. **Correction (2026-09-26):** scene 4 started this way never
  gets going. The player stands in the right-hand doorway on both machines
  (the scene needs what the end of scene 3 hands over), so scene 4's
  comparison covered only that frozen opening. See "The princess room".
- **Scene 6:** identical. It hands on to scene 1 before flip 200.
- **Scene 1:** identical through flip 2000.

**One more fix, found in scene 3: a sprite that starts inside the engine.**
Scene 3's floor stripes (a 9×22 sprite drawn while the room is revealed)
start at `$1200`. Their header `09 16 AA` is the last three bytes of the
engine's first part (`$1000-$1202`) and their pixels are the first bytes of
scene code. That is contiguous in XEGS RAM but apart on the 7800: the
engine is in cartridge RAM at `$7000`, and `$7203-$72FF` is an empty gap.
The port drew the header's size and blank stripes. No code refers to
`$1200-$1202` and they aren't code, so the fixed-bank copy of scenes 2-4's
sprites now starts at `$1200` (`$F500`, three bytes that were free) instead
of `$1203`. All six scenes hold the same header bytes there, and scene 1
never blits from `$1200` (checked over 50,604 blits).

A note on the method: blit counts per flip were equal on both machines,
which is what pointed at the data rather than at timing.

### The keyboard comes out; the console buttons by retail convention (2026-09-25)
The 7800 has no keyboard, so every keyboard read and the code only they
reach is removed (the user's call). The original reads keys through the
POKEY keyboard interrupt (`$10FD`: IRQST, then KBCODE into `$DD`, with
`$DF = $FF` as "a key came"). The vertical blank's key repeat reads SKSTAT
(`$1004`). The key codes the game checks:
- **Walking mode (`$AE78`):** Space (`$21`), + and * (`$06`/`$07`, walk
  left and right).
- **The move dispatch (`$AEBA-$AF33`)** compares the key in A against Q A Z
  and W S X (moves by key) and B (`$15`, bow, at `$AF20`). The same path
  also reads the joystick's fire flags `$47`/`$46`. With no key, A is 0.
- **Play (`$B71E`):**
  - Esc (`$1C`) pauses.
  - J/K (`$01`/`$05`) switch between joystick and keyboard control (`$C4`).
  - Ctrl-R (`$A8`) skips to the next scene and Ctrl-N (`$A3`) sets the
    enemy's health to 1, both developer cheats.
- **The ending (scene 4, `$7883`)** waits for Ctrl-R to restart.

**Removed:**
- In the move dispatch, the key tests only. A is now always 0 there
  (`LDA #$00` in place of the `$DF` test, since the old path left A = 0), and
  the joystick branches stay. So the bow by joystick (up and fire, which the
  user confirmed) still works.
- The whole `$B71E` key handler, the Esc check at `$B773` and the Esc pause
  loop `$B785`.
- In the engine, the key repeat and the interrupt's reads. The interrupt is
  now `PHA / PLA / RTI`; the 7800 raises no IRQ anyway.
- The ending's Ctrl-R wait. Its loop now only runs the console check
  (`$B603` → `$AF66`), where START restarts.

Bank 15 shrank by 330 bytes (it now ends at `$E0D9`), and the system jump
table moved down to `$E0DA`. The fixed bank now has about 1K spare.
`$AEB1/$AEB3` looked keyboard-only but is the common exit for every move
(`$AED2`, `$AEF9`, `$AF1D`, ...). The linker's check on labels inside a
removed range caught it. That check now ignores references that come from
code another removal replaces.

**Console buttons.** The game's own console keys (`$AF66`, called during
play and at the ending):
- START (CONSOL bit 0) restarts at scene 1.
- SELECT (bit 1) is a pause (press to pause, press again to resume).
- OPTION (bit 2) switches between the title and scene 6.

The 7800 buttons now map by retail convention: Reset → START, Pause →
SELECT (the game's own pause), Select → OPTION. Checked:
`probes/p7800-pausetest.lua` presses Pause at frame 3500 in scene 1, and the
game stops advancing; a second press at 4000 resumes it. Scenes 1-4 still
match the original byte for byte at every checkpoint after the change.
Not yet checked: restarting from the ending with Reset (no run reaches the
ending yet), and Select.

`playkey.lua` now takes the play flip key from the build's symbol file
(`K_B60F`, which the build writes), since bank 15 moves.

### TIA sound (2026-09-25)
**How the game plays.** Captured with `probes/xe-pokey.lua` (title and
play). AUDCTL is `$78` from every scene start: channels 1+2 and 3+4 are each
joined into a 16-bit divider on the 1.79 MHz clock. So the game has exactly
two voices, pitch 1789790 / (2 (N + 7)). The only writer is the engine at
`$10C1-$10DD`. For each voice X it writes:
- the distortion `$2410,X`, to the low channel with volume 0 and to the high
  channel ORed with the volume envelope `$240E,X`;
- the divider, `$2412,X` (low byte) and `$2414,X` (high byte).

It writes about 2.4 times a frame. Distortion `$A0` (pure tone) carries the
music and most effects, and `$00` (poly noise) some effects in play.
Volumes run 1-15.

**The music is tuned about 38 cents flat of A440 throughout** (20 notes,
A1 to F5).

**The port:** `TiaSound` (`sys7800.asm`), run once a frame in the vertical
blank NMI, turns each voice's shadow registers into one TIA channel:
- A tone becomes the nearest TIA tone (AUDC 4, C or 6). A binary search runs
  over the 88 dividers where the nearest tone changes, and a packed table
  gives each tone's mode and AUDF.
- Noise becomes AUDC 8 at the nearest rate (a table by N >> 6).
- A tone above 16 kHz (N below 49) is silent.
- The volume passes through.

`port/sndconv.py` makes the tables (296 bytes, placed by the build in free
gaps among the sprite copies) and renders WAVs by the same rule.
`build7800.py --snd-offset CENTS` transposes the whole score, since TIA's
pitches are fixed and sparse. Recorded from MAME, the port at offset 0
follows the original's pitch track (bass 54 and 72 Hz exactly, the opening
E2 at 78 Hz against 80).

**Choosing the key** (15 notes that sound more than 40 frames, weighted by
use):

| offset | weighted mean error | notes merged | worst common note |
|---|---|---|---|
| 0 (original key) | 25 cents | none | 59 cents |
| +780 | 11 cents | 69 frames' worth | 43 cents |
| -918 | 16 cents | none | 52 cents |

At 0 the melody is mostly within ±25 cents. A#4 is +73, and in the bass
A2 is +77 and E2 is -59. AUDC 6's pitches are about two semitones apart
there, a TIA limit. The default is 0 until the user picks. Recordings to
compare are in `work/analysis/snd/`: `mame/xe.wav` (the original) and
`keys/port0.wav`, `port780.wav`, `port-918.wav`.

**A toolkit bug found on the way, and fixed.** The toolkit's TIA model
(`tracker.py`) had AUDC C, D, 6, A, E and F an octave low. It took "÷6" as a
square stepping every 6 ticks (a period of 12), and "÷31" likewise. The
port's first recording played an octave above the model's render, which
exposed it. Every AUDC was then measured with single-tone cartridges
(`mktone.py --tia`, new) and autocorrelation:
- `$4`/`$5`: 2 ticks;
- `$C`/`$D`: 6;
- `$6`/`$A`: 31, 18 high and 13 low;
- `$E`: 93;
- `$1`: 15;
- `$2`/`$3`: 465;
- `$7`/`$9`: 31;
- `$F`: 93;
- `$8`: 511.

`tracker.py`, `docs/audio.md` and a new self-test (`t_tia_periods`) are
corrected in `a7800-toolkit-local`, not yet committed or carried to the
public repo.
- Hand-written songs now play as written.
- Captures made before the fix name those modes' pitches an octave low, so
  they should be made again.
- `sim.py`'s POKEY mismatches are unrelated: it compares register logs,
  not pitches.

### MARIA's DMA in play, measured (2026-09-25)
`probes/p7800-dma.lua` works out, per 100 frames of play:
- the 6502 cycles actually executed: base counts, plus taken branches, plus
  page crossings worked out from the operands and index registers at each
  fetch;
- the slow-access penalty: TIA and RIOT run at 1.19 MHz, which costs +0.5
  cycle per access;
- **measured DMA = 29,868 − executed − slow.**

It also prices the display list list on screen with `dmabudget.py`'s
constants. The scripted player drove the game with `INJECT=1 SHORT=1`.

| scene | lines drawn | executed | slow | measured DMA | frame | model |
|---|---|---|---|---|---|---|
| 1 | 177 | 22,298 | 125 | **7,445** | 25% | 7,897 |
| 2 | 135 | 23,725 | 125 | **6,017** | 20% | 6,472 |
| 3 | 105 | 24,751 | 125 | **4,991** | 17% | 5,455 |
| 4 | 105 | 24,751 | 125 | **4,992** | 17% | 5,455 |

- Within a scene it varies by about ±5 cycles between blocks. It depends
  only on how many lines show bitmap: every line is its own zone with two
  20-byte objects, about 41 cycles a drawn line and 7 a blank one.
- **The model overstates by a near-constant 455-465 cycles** (6-9%) in every
  scene. That looks like a fixed per-frame term, about 4 scanlines, not a
  per-line one. Not chased.
- **A real XEGS's ANTIC would take about 8,700 a frame** for scene 1's
  screen: 41 cycles per mode-E line, plus refresh on all 262 lines. So MARIA
  steals less than ANTIC did. MAME's `xegs` charges none of it.
- These are MAME's timings; real hardware is the check still to do.

### Flicker: the new frame was shown a frame late (2026-09-25)
**Reported from the Analogue Pocket** (openFPGA 7800 core): the screen
flickered, as if some objects were not drawn every frame. The byte
comparisons could not catch this. They check what is in the buffers, not
which one is on screen.

**The cause.** The game double-buffers: it draws into the hidden buffer,
then switches the display in its vertical blank (DLISTL/H, taken by ANTIC at
once). The port's `Frame` applied a new list at once only if MARIA was in
vertical blank (MSTAT bit 7), and otherwise waited for the next vertical
blank. The game's VBI runs at the port's stand-in DLI below the picture,
where MSTAT does not yet show vertical blank. So every switch waited a frame,
and for that frame the screen showed the buffer the game was already
redrawing.

**Measured** with `probes/p7800-shown.lua` (writes into the buffer on screen,
while on screen) against `probes/xe-shown.lua`:
- the original: 0 in every 100 frames of play;
- the port: 2,400-7,700 writes, in 3-7 frames of every 100, about one per
  buffer flip.

**The fix.** `Frame` applies at once when called from the game's vertical
blank (`S_INVBI` set), and keeps the MSTAT test only for calls from the main
program mid-frame. This is safe because MARIA reads DPPH/DPPL only at the
start of a frame. At the stand-in point the rest of the frame is blank lines,
so the new list starts exactly at the next frame, as ANTIC's would.

**After the fix:** 0 visible writes over 3,200 frames of scene 1 play.
- 1,390 writes landed in the old buffer after that frame's switch, below the
  picture. The first version of the probe miscounted them as visible, because
  it moved its idea of "shown" at MAME's frame boundary rather than at the
  switch.
- Scenes 1-4 still match the original byte for byte.

### Hanging notes and the palette: the NMI count drifted (2026-09-25)
Two more reports from the Pocket:
- a note hangs after a button press in the intro or between scenes, until
  the next part loads;
- the enemy's health arrows (bottom right) and the fighters' outlines are
  sometimes the wrong colour (grey or blue).

Both came from how the port told the vertical-blank NMI from the DLIs: by
counting NMIs in the frame against `S_NMIVBI`.

**The hanging note.** Pressing fire in the title music:
- The original holds the last note 32 frames, then its next scene's setup
  (`$0E46`) zeroes POKEY.
- The port held it 269 frames.

During the gap the port's frame counter stood still. `S_NMICOUNT` was 89,
past the blank loading list's `S_NMIVBI` of 1, because that list had taken
over mid-frame. An exact match (`BEQ`) then waited for the count to wrap:
256 NMIs, one per frame, over 4 seconds with no vertical blank, so no music
driver and no progress. A first fix (`BCS`, "at or past") cured that case.

**The palette.** `probes/p7800-palette.lua` against `probes/xe-palette.lua`:
- The original writes COLPF0-3 three times a frame: from the VBI (its DLI
  counter `$0F14` at 0, the top band), then at counter values 3 and 6. The
  values match the port's.
- The port wrote only two sets, and `probes/nmicount.lua` showed 5 game DLIs
  a frame against the original's 6.

`probes/p7800-nmitrace.lua` showed the count one out of step, and stable that
way:
- the game's last DLI (line 193) was taken for the VBI;
- the real stand-in (line 205) arrived while that "VBI" still ran, and was
  dropped;
- so every DLI ran one index late, and the last colour set (the bottom band,
  the health arrows) never happened.

Once a list change mid-frame puts the count one out, it never recovers, since
every frame has the same number of NMIs. (The grey itself is partly the
game's own: its counter-3 set writes COLPF1 = `$08` instead of `$88` in
about 2-4% of frames on both machines.)

**The fix: no counting.** The RIOT timer, unused by the port until now, tells
the NMIs apart:
- Every vertical blank arms `T1024T` with 28 (28,672 cycles, just short of a
  frame's 29,868).
- An NMI that finds `TIMINT` bit 7 set is the vertical blank.
- The stand-in moved to a fixed line, `VBI_LINE` (241). ANTIC's VBI comes at
  display-list line 240, so this restores the original's timing: about 52
  lines to the next frame's first DLI, and the handlers need about 2,300
  cycles.
- Every list's last DLI is at line 193, 48 lines ahead. The build now refuses
  any list whose last DLI is within 16 lines of `VBI_LINE`.
- `S_NMICOUNT` is kept only for the probes.

**Checked after the change:**
- 6 game DLIs and 1 VBI a frame;
- three colour sets at counter values 0, 3 and 6 with the original's values;
- 0 writes into the shown buffer;
- a note held 37 frames after a press (original: 32);
- scenes 1-4 byte for byte.

### No RIOT timer; the NMI count made unable to drift (2026-09-25)
**RIOT is not safe while MARIA runs DMA** (the user pointed to
7800.8bitdev.org, "RIOT limitations and workarounds"). MARIA halts the 6502
but not the 6532, so an access under way when a halt begins loses its
address and write-enable partway through. Some consoles are affected and some
are not, and it is worse with heavier DMA. The timer design wrote `T1024T`
at line 241 and read `TIMINT` at every NMI, all during DMA. It is gone. The
port now uses RIOT only for the joystick and console switches, and reads
them once a frame in vertical blank.

**The design now:**
- **Every list has the same seven NMIs.** All 20 XEGS lists have exactly six
  DLIs (at lines 31, 84-85, 112-126, 137-138, 180-190 and 193), plus the
  stand-in at `VBI_LINE` (241). The build refuses any list that differs.
- **The blank list is in ROM** (`BLANK_DLL`, 37 entries). It has six dummy
  DLIs on the usual lines and the stand-in at 241. The dummy DLIs skip the
  game while it is shown (`S_SHOWBLANK`), since the XEGS gets no DLIs with
  DMA off. Being in ROM, it is never rebuilt over a list on screen, which was
  one way the count used to drift. MARIA reads DPPH/DPPL only at the start of
  a frame, so switching lists cannot change the frame under way.
- **A safety net for the count.** The NMI the count names as the vertical
  blank waits for MSTAT bit 7, up to 110 turns (about 10 lines).
  - Measured: it arrives after 4 turns, every frame.
  - If it never comes, the NMI was mid-screen. It is handled as a DLI, and the
    count is set so the next NMI is the vertical blank. Any slip then heals
    within a frame. No corrections were seen in 6,000 frames.
- **RIOT only in vertical blank.** `Inputs` (vertical blank) keeps SWCHA and
  SWCHB in `S_RSWCHA/B`. `ReadStick` uses that copy, so a stick reading is up
  to a frame old; the XEGS reads live.

**A correction on MARIA's DLIs: a zone's DLI comes as the zone starts, not
at its last line.** The first ROM blank list merged blank lines into 16-line
zones and flagged the zone covering 226-241 for the vertical blank. Its NMI
came about 17 lines before vertical blank, at the zone's start, so the MSTAT
wait never succeeded and no vertical blank ran. The game lists never showed
this, because their zones are one line tall. Flagged zones must be exactly
the flagged line; the blank list now uses one-line flagged zones with 16-line
fillers between. (`probes/p7800-mstat.lua` measured MSTAT: vertical blank is
about 20 lines a frame.)

**The comparison method, again.** With the vertical blank at line 241 the
port and MAME's `xegs` agree less well on where the VBI falls against the
main loop. The game's VBI turns the trigger into the short-press flag `$47`,
and the main loop then took it one flip earlier on the port (flip 221,
against 222). The scene then diverged: timing, not a fault.
- `playkey.lua FIREFLAG=1` now presses fire by setting `$47` at the start of
  the flip on both machines (unless `$46` is set, as the VBI does).
- With `INJECT=1` it also feeds the port's stick copy, and only once the
  cartridge runs. A first version tapped those RAM bytes from power-on, and
  the 7800 BIOS, which uses the same RAM, hung at `$F96E`.

**Checked:**
- scenes 1-4 byte for byte (flips 300-800, and 250/500/800);
- 6 DLIs and 1 VBI a frame, confirmed every frame;
- the three colour sets as on the original;
- 0 writes into the shown buffer;
- a note held 36 frames after a press (original: 32).

**The post-death title** (reported: the lower half of the last 'a' missing
on the Pocket) could not be reproduced. At that point both framebuffers
match the original byte for byte, and MAME shows the logo whole on both
machines (the original shows no copyright lines there either). The logo sits
across the second DLI line, so a DLI landing on the wrong band could hide
part of it; the count drift was that kind of fault. Retest on the Pocket
pending.

### Story crash: the attract sequence past the census (2026-09-25)
Reported from the Pocket: the story scroll stops at "Defeat Akuma and
rescue the..." and the machine stops responding. Every census run pressed
fire during the story, so nothing after about line 17 of the story was ever
traced: not the rest of the scroll, not the cutscene, not what follows. Each
fix below let the no-input run get a little further, to the next untraced
fault.

**The chain, in order:**
1. **The story text table.** `$7983` loads line pointers from `$7BCC,X` /
   `$7BE6,X` into `$E5/$E6`. The census relocated only the lines it saw, so
   lines 18-25 were read out of cartridge RAM. Fix: `MANUAL_TABLES` in
   `reloclist.py` (split tables relocated whole).
2. **The hyphen glyph lies past the sprite block.** The glyph sits at
   `$06E8-$06F5`, just after the block's end at `$06E8`. Fix: the build
   appends that tail to the sprite image (`SPRITE_TAIL`), and `LEN_SPRITES`
   covers it.
3. **A write to `$6009` as the story ends (`$740A`).** On the XEGS that is
   RAM. On the 7800 it lands in ROM, and any write to `$8000-$BFFF` switches
   the bank, so the next fetch came from bank 7. Fix: carved to `$1AA0` for
   scene 0.
4. **The cutscene's sprites.** They are drawn from scene code and from bank
   15's hi-byte tables, which were unrelocated or in a bank the blitter
   doesn't read. The fixes:
   - `ART_COPIES` (scene 0's sprites copied into the art bank);
   - a per-scene page map (`SP_PAGEMAP`, `$81A0`): the blitter reads a
     `$A0-$BF` source from the art bank when the page is marked;
   - `SCENE_TABLES`: per-scene copies of bank 15's hi-byte tables at `$81C0`.
   A linker slip came with the last one: bank 15's references still
   resolved to its own local table. The table ranges now go into
   `assemble_chunk`'s carved set, so references go through the resolver.
5. **After the cutscene the port froze at `$7043`.** The engine code in
   cartridge RAM at `$7000` had turned into `$AA` bytes.
   - A write tap found the blitter (`$7927`) copying straight past the end
     of buffer A (`$6FEF`) into the engine.
   - The stack at the first bad write gave the caller: scene 0's `$6D91`,
     `LDA #$6A / STA $04`, a sprite at `$6A31` in scene data. It was never
     relocated, so the blitter read a "sprite" out of framebuffer A (`$6A31`
     on the 7800). The garbage height ran the copy off the end.
   - This is the code the earlier scan dismissed ("the title never runs
     them"). After the cutscene the attract sequence plays the opening run
     and a demo fight with scene 0's bank, and most of scene 0's data
     (`$63C4-$73EC`) and part of its scene code are scene 1's, at the same
     addresses. They differ only in JSR operands: scene 0 calls the engine
     at `$284E` where scene 1 has `$2803`, and at `$2B82` for `$2809`.
6. **Fix, part one: scene 1's relocations applied to scene 0.**
   `reloclist.py` gives scene 0 a copy of every scene 1 entry whose
   surroundings (16 bytes either side, JSR/JMP operands aside) are the same
   in both scenes. That is 27 entries: `$6C58`, `$6D38`, `$6D92`, `$6DD9`,
   the `$6E0C` table, `$7061` and `$71C3-$71C7`.
   - `$6C58` is the death-sprite pointer. In scene 1 those sprites are
     carved into RAM at `$1900`, since scene code sits in the art bank's
     half of the blit rule. Scene 0 now gets the same carve.
7. **Fix, part two: scene 0's own opening-run code.** The next freeze had
   the same cause: `$773C` → `$6383` draws the scenery from a split table,
   lows at `$6353` and highs at `$635F` (12 entries, X 12-23), never
   relocated. A new scan, `probes/scanhi.py`, finds pointer high bytes a
   scene loads and stores to `$04`, `$E6` or `$15`, as immediates or from
   tables, that `reloc.txt` doesn't cover. In scene 0 it turned up:
   - the `$6353/$635F` table (`MANUAL_TABLES`);
   - blit sources at `$78D5` (`#$7E`) and `$7934` (`#$7F`);
   - four text pointers (`#$62` into `$E6`) in stubs at `$620E/$622C`. These
     stubs are called only from a block after `$7790`'s unconditional JMP,
     so they are probably dead code. They print a hidden developer message.
   The scan's remaining hits are tails of shorter tables that it over-reads.

**Result:**
- The no-input run loops cleanly through title, story, cutscene, opening
  run, demo fight (the player loses) and back to the title, 15,000 frames
  without a fault.
- Fire pressed in the story (twice, including at "Defeat Akuma"), the
  cutscene, the opening run, the demo fight and the title starts scene 1
  every time.
- `port/regress.sh` (new; it reuses the original's dumps) still shows
  scenes 1-4 byte for byte identical.

**Still open:**
- **The original crashes here on MAME's `xegs`.** After its cutscene
  (f4686-4739), `$ADCA`'s buffer copy runs away past `$5FF0`, and the PC
  later reads `$0000`. The port runs the same copy without trouble. The
  suspect is `$04` changed under the copy by nested DLI/VBI timing on
  MAME's `xegs`, which lacks ANTIC DMA. Not confirmed, and not a port
  fault. It is why no reference run reaches this part of the game.
- **Other scenes have untraced stretches too.** `scanhi.py` over scenes 1-6
  flags partly relocated tables. Some are the over-read tails of shorter
  tables, but several look real:
  - scene 1 `$7623` (`$762F-$763A` relocated, `$7623-$762E` not) and
    `$7C17`;
  - scene 2 `$7117` and `$B097`/`$BCDE`, which are bank 15 addresses;
  - scene 4 `$1D34` (24 entries, none relocated) and `$7DDF`, `$7EA3`,
    `$7F0F`, `$7E22`, `$7F82`;
  - scene 6, which holds scene 1's code like scene 0 does, with none of it
    relocated (`$6C57`, `$71C3`, `$7623`, `$7C17`).
  Each needs its real length and index range read from the code before it
  is relocated. Scenes 1-4 still match on the scripted runs, so these are
  paths that those runs don't take.

### sys7800.asm lost and rebuilt from the transcript (2026-09-25)
An inline edit did `s.index('BlitBank:')`, meaning to cut from that routine
to the next one. It matched `SysBlitBank:` first and deleted most of the
file. Nothing was committed yet. The file was rebuilt by replaying the
session transcript: the last full Write of the file, then every later Edit,
`sed -i` and inline Python step that touched it, in order, stopping before
the damaging edit. Python `assert`s became `_ =` so a step's replacement
still ran.
- **Checked:** the head and tail matched the parts that survived.
- **Checked:** the assembled bytes equal the last good build, apart from
  operands of symbols that moved.

The replay script and a checkpoint of the source now sit in
`../Karateka-Port-checkpoints/` (dated folders, no ROM data), until the port
is committed.

### Pocket retest: the post-death 'a' is gone (2026-09-25)
The user could no longer reproduce the missing lower half of the logo's last
'a' after the palette fix. So it was most likely the same fault: the NMI
count drifting, so that a DLI's colour change landed on the wrong band (the
logo crosses the second DLI line). Closed unless it comes back.

**A lead for the partly relocated tables (user):**
- In levels 2 and 3 the game keeps sending enemy after enemy while the
  player stays away from the right-hand side. Their heads come from a
  roster the game cycles through, so the tables `scanhi.py` flags in scenes
  2 and 3 may be the later entries of that roster.
- The scripted runs never go that far down the roster.
- Testing it by hand needs an easier build.

### A build without MAME: the patch kit (2026-09-25)
The user asked for a build that doesn't depend on MAME. A script should chop
the cartridge up, put it back together in the right order, apply a BPS or
an ABP (with options such as invincible and easy mode), add the .a78 header
and sign it. `port/mkkit.py` now writes that kit to `dist/karateka7800-kit/`:
- `make.py`, the one command:
  `python make.py Karateka.car [--with invincible,easy] [-o out.a78]`,
  or `--list` for the options;
- `kit.json`: the original's identity, the chop map and the header fields;
- `karateka7800.bps`: the chopped original to the port's 128K body;
- `karateka7800-options.abp`: the options, in the Anchored Bundle of
  Patches format;
- copies of `bps.py` and `abp.py` (from Anchored-Bundle-of-Patches, MIT)
  and `sign7800.py` (from the toolkit).

make.py needs only Python 3. It:
1. checks the dump (the .car, or the same 128K bare) by SHA-256;
2. chops it into the 7800's order;
3. applies the BPS, then any options;
4. signs and verifies, and adds the header.
With no options it also confirms the result equals the release build.

**The chop map is derived, not written by hand.** The first try matched
whole pages, and it left 860 original 8-byte runs as literals in the
patch. The loader copies some material to addresses that aren't
page-aligned with where the cartridge holds it: the common block is at
`$A268` in the cartridge and runs at `$06E8`. The map now has two passes:
- **Alignment.** Each 32-byte block of the port votes for the offset into
  the original where its 8-byte runs occur. Runs found in more than four
  places don't vote. Neighbouring blocks with the same offset merge. That
  gives 420 pieces in place.
- **Completion.** Original material the port uses that the first pass
  placed nowhere goes into the chopped image's unused space: 372 pieces,
  32.6K. These are images that start mid-block, and code too dense with
  changed operands to vote.

**The BPS uses all four beat actions.** `bps.py`'s `create` only writes in
place (SourceRead/TargetRead). With that, the reassembled fixed bank would
ride along as literal bytes. `mkkit.py` has its own encoder:
- SourceRead: 54.9K;
- SourceCopy, original material at another offset: 20.2K;
- TargetCopy, the port's tables repeated across scene banks: 46.3K;
- literal: 9.7K, the port's own code and tables plus changed operands.
The patch is 20.4K. `bps.py`'s apply reads all four actions, and nothing
else has applied the patch yet.

**Checks in `mkkit.py`, each of which fails the run:**
- the kit, run in a separate process on the .car, rebuilds
  `work/karateka7800.a78` byte for byte;
- no literal run of 8+ bytes in the patch occurs in the original;
- every option set applies, edits only its own sections (besides the
  signature), re-signs and verifies;
- each option site holds the instruction it is meant to patch.

**The options.** They are the xe-easy.lua playthrough aid made into
patches. Every scene bank except bank 0 carries them; bank 0 is the title
and attract sequence, which stay as the original.
- **invincible** (knob "player"):
  - `DEC $B6 / BNE` at `$0BE5` becomes `BEQ` to the RTS. Z is always set
    there by the preceding `LDA #$00`, so A, X and Y leave as before.
  - The instant-death `BEQ` at bank 15 `$B12E` becomes `NOP NOP`.
  - The gate's `LDA $A7` (scene 2) becomes `LDA #$00`.
  - The cliff's `LDA $A2` (scenes 1 and 6) becomes `LDA #$00`.
- **easy** (knob "foes"): the foe's `DEC $B7` at `$0BF6` becomes
  `STA $B7`. A is 0 there and Z stays set, so any hit is a last hit.

The build now writes the sites' 7800 addresses to
`work/karateka7800.sites.json` (`PATCH_SITES` in `build7800.py`), taken
from each scene's resolver as a label plus an offset. A first version asked
the resolver for `$B12E` itself. That address is inside a routine, so the
resolver returned bank 15's plain offset (`$D12E`). The routine really sits
at `$D208`, because bank 15 was reassembled and instructions changed
length. Only labels map exactly.

**Checked in MAME** (`CART=` now selects the cartridge for `run7800.sh`),
scripted fights, invincible+easy against the plain build:
- no damage write from `$9BE5` at all (plain: health down to 7 in scene 2);
- the first hit sets the foe's health to 0 (`$9BF6`), and the game then
  sets up the next foe as usual.

**Still needs MAME, for development only:** regenerating the kit from
source needs the census and origin data in `work/analysis`, which came
from MAME runs of the original. The kit itself needs none of it.

### Flashing black after the story (2026-09-25)
Reported from the Pocket: once the text scroll ends, every screen flashes
black constantly. MAME showed the same, once looked at frame by frame (the
earlier checks sampled one frame in 100). `probes/p7800-blanklog.lua` logs
the list on screen each frame. After the story the port showed the blank
list for about 8 frames in every 18.

**Cause:** `Frame` falls back to the blank list when the game asks for a
list its scene doesn't have. Each scene's lists came from the census, which
never got past the story. Scene 0 lacked `$19B3`, the play screen, which
the attract sequence's opening run and demo fight use.

**Fix:** the build now gives each scene every list another scene's census
saw, whenever this scene holds a valid list at that address (it parses, has
six DLIs, and ends above the vertical blank line; `build7800.py`
`shared_display_lists`).
- Scene 0 gains `$19B3`. It is scene 0's own version, whose third DLI is
  ten lines lower than scene 1's.
- Scene 4 gains `$1A0A`, and scene 6 gains `$1A5E` and `$1B04`.
- **Dead end:** first I required the list to describe identically in both
  scenes. Scene 0's `$19B3` differs from scene 1's, so it wasn't added.

**Result:**
- **Attract loop:** no blank frames in 15,000 frames, beyond the 13 at
  power-on before the game picks its first list.
- **Play:** the only blanks come with a scene load (DMA off, and the
  loader's own list `$2F48`), as on the original.

### Drawing below the screen, and a DLI inside a DLI (2026-09-25)
With `$19B3` on screen the attract sequence crashed at about f5200: the
engine at `$7000` was overwritten again. Two faults, both in the original,
both fatal only on the 7800.

**1. No bottom check on the row address.**
- `$2D46` computes row Y−35, times 40, plus the buffer. The blitters (two)
  and the fills then draw `$0D` rows, 40 bytes apart. Nothing stops a draw
  past row 153. `$2DA4` clamps only the top, and only for fills.
- A sprite partly below the screen wrote past the buffer. On the XEGS that
  lands in scene-data RAM at `$6000`. From buffer B it lands in the top of
  buffer A, which is visible. On the 7800 it lands in the engine.
- A draw starting above the top wraps to a large row and also runs past the
  end. On the XEGS none of it shows.

**Fix:** `$2D46`'s first 16 bytes (up to the multiply) become
`JSR SysRowBase`. `RowBase` then:
- cuts `$0D` to the rows left above the bottom;
- sends a draw that starts at or past the bottom (or wraps) to a 48-byte
  scratch row (`S_CLIPROW`), one row only, returning straight to the
  caller;
- leaves the game's own code after the multiply to add the buffer base.

Every blit and fill sets `$0D` afresh, and only the engine's own loops read
it, so capping it per call is safe. Nothing that reaches the screen changes.
The once-per-call check costs almost nothing. A per-row check would have
cost about 30 cycles on every row of every sprite.

**Room:** the fixed bank's system block had 16 bytes left. The build now
assembles everything after `;;; FAR` in `sys7800.asm` separately, places it
in a free gap (RowBase: 47 bytes at `$FE25`) and hands its labels to the
main block as equates. The jump table gains `SysRowBase`, last, so no other
entry moves.

**2. A DLI inside a DLI.** Even with the clipping, the blitter wrote
`$71D7` at f4264. Its registers made no sense for that address: `$06` =
`$77` (row 84), buffer B, 43 rows. A trace of saves and restores showed the
cause:
1. The blitter sets `$14/$15`.
2. A DLI saves them (`$7169`), and its body (`$7125`) sets them to its own
   pointer.
3. A second DLI arrives before the first ends. It saves that pointer and
   restores it.
4. The first DLI restores the same wrong pointer. The blitter then draws
   into the engine.

Scene 0's `$19B3` has two DLIs only 3 lines apart (scene 1's are 13
apart), which is less than the handler takes on the 7800 with the NMI
dispatch on top. The port already kept a DLI out of the VBI and made a VBI
wait for a DLI, but it never guarded DLI-in-DLI. This is probably the same
fault behind the original's own crash after the cutscene on MAME's `xegs`
("Story crash", still open), where `$04` changes under the `$ADCA` copy.

**Fix:** a DLI that arrives while one is running sets `S_DLIPEND` and runs
as soon as the first ends. The game's handler counts its own DLIs, so the
late one still does its band's work, a few lines late.

**Checked:**
- attract loop, no input: 15,000 frames without a fault; the cutscene, the
  opening run and the demo fight all draw correctly;
- no blitter write past either buffer (`$6FF0-$7FFF`, `$57F8-$5807`), in
  the attract loop or in scripted play in scenes 1-4 (`p7800-firstover.lua`
  now takes `WLO/WHI/BLITONLY` and reports when playkey ends the run);
- six game DLIs and one VBI every frame, cutscene included (`nmicount.lua
  NOPLAY=1`);
- scenes 1-4 byte for byte (`port/regress.sh`);
- the kit rebuilt and re-proved.

### How much of the screen the game redraws (2026-09-26)
The user asked whether the whole screen is written every frame.
`probes/p7800-fbwork.lua` counts framebuffer writes by routine, per buffer
flip (a DPPH change), over 600 frames:

| span | flips | bytes written per flip | distinct bytes touched, both buffers |
|---|---|---|---|
| scene 1, scripted fight | 45 | 2,947 | 7,736 of 12,240 |
| scene 2, scripted fight | 44 | 3,840 | 7,132 |
| attract demo fight | 35 | 3,875 | 7,996 |
| story scroll | 58 | 7,045 | 12,160 |

- **In play the game redraws only what changes.** A buffer is 6,120
  bytes, and about half of it is rewritten per flip. The rest (sky,
  mountain, most of the floor) is drawn once when the scene is set up.
  `$280F` clears a buffer and `$ADCA` copies one buffer into the other.
- **The writers in play, largest first:**
  - rectangle fill `$2CE6` (erasing the last positions; 1.2-1.8K a flip);
  - blitter A's stores `$2927/$2946` (1.0-1.4K);
  - blitter B `$2B12/$2B3E` (0.3-0.5K);
  - the pattern fill `$2D20/$2D29` (the striped floor, about 0.35K).
- **The story rewrites nearly everything:** the scroll (`$0845`) moves
  about 5,800 bytes per flip.
- **A new picture every 13-17 frames in these scripted fights.** MARIA
  shows the finished buffer every frame and re-reads all of it each time,
  whether or not it changed.

### Empty zones for the sky? Measurements (2026-09-26)
The user suggested giving MARIA nothing to draw on the top lines in play,
which seem to hold only a colour fill. That saves about 34 cycles a line: a
zone with the row's two 20-byte objects costs about 41, an empty zone about
7.

**What the rows hold** (`probes/p7800-rowuse.lua`: every row of the buffer
going on screen, at every flip, grouped by the scene in play):
- **Scene 1** (566 flips):
  - rows 0-15 are uniform `$AA` in 97-100% of flips;
  - rows 16-46 are `$AA` in 70-95% (something passes through them the
    rest of the time; not identified);
  - rows 47 and down are nearly always mixed.
- **The sky isn't background.** `$AA` is pixel value 2, a playfield
  colour, and COLBK is always black. An empty zone shows MARIA's BACKGRND,
  so BACKGRND would have to be the sky colour for those lines, switched at
  the band's own DLIs. Any value-0 pixel in that band would then also turn
  sky-coloured, so it only works while every row of the band is uniform.
  In scene 1's list, the first bitmap band is rows 0-37: 38 lines, about
  1,300 cycles a frame.
- **Scenes 2-4** (the fortress) have content in their top rows. Only
  scattered rows are always zero (2-4 per band edge, about 8-10 rows in
  all). **Wrong, corrected in "The top band, measured in real play"**
  (the fork's FINDINGS): the same logs show rows 0-23 (scene 2) and 0-47
  (scenes 3 and 4) uniform `$00` in every picture but the first after a
  scene load; the user pointed out that the fortress rooms are black above.

**Whether freed cycles help** (`probes/p7800-idle.lua`: turns of the flip
wait loops at `$D6F9/$D70B`, 7 cycles each). In play the game waits only
500-700 cycles a frame, about 2%. It is CPU-bound, so any DMA saved goes
straight into drawing, and new pictures come sooner. The exceptions are
scene setups (up to 35% waiting in scene 3's first seconds).

### The NMI's cost, trimmed (2026-09-26)
Kept fallback: `../Karateka-Port-checkpoints/2026-09-26_KEEP_before-nmi-trim/`
(source, both cartridges, the kit), until this build proves itself on
hardware.

**Measured first** (`probes/p7800-nmiprof.lua`): every instruction from
the NMI's entry to its final RTI, charged to the nearest system label or
to the game's code by region. A first version never saw the final RTI and
counted everything as NMI. It had looked up the RTI's address at script
load, before the cartridge is mapped.

**Scene 1 play, before:** 4,860 cycles a frame in the NMI:
- the game's own handlers: about 2,270 (the DLI body at `$1026` and the
  sound work it calls, and the VBI);
- the port's overhead: about 2,590:
  - Mode8, 880 (its 30-byte compare, run every frame);
  - entry, exit and DLI dispatch for 7 NMIs, about 990;
  - Frame/SetDlist, about 300;
  - inputs, sound and Apply, about 270.

**1. Frame does nothing when nothing changed.** The game's VBI asks for its
list every frame, but a new picture comes only every 13-17 frames. Frame
now records the list and DMA bit it last chose (`S_CHOSEN`) and returns at
once on a repeat. Power-on and every scene load clear the record.
- Safe because the game never writes into the buffer on screen: 0 writes
  over 15,000 frames of the attract loop and scripted play in scenes 1-4
  (`p7800-shown.lua`, now with `NOPLAY`).
- Scene 1: 4,860 → 3,816. Story: 3,931 → 3,679.

**2. The DLI goes straight to the game's handler.**
- **Before:** the NMI saved A, X and Y, switched banks, and built a fake
  interrupt frame so the handler's RTI came back into the port. The
  handler then saved A, X and Y again.
- **Now:** the NMI saves only A and the bank, and jumps to the handler.
  The handler's ending (`$1034`, `PLA/TAY/PLA/TAX/PLA/RTI`) is patched to
  `JMP SysDliExit`. `DliExit` pops the handler's copies (X and Y are the
  interrupted code's again), runs a waiting DLI or VBI, and makes the one
  RTI.
- **The VBI** saves X before the confirming spin, since the spin uses X.
  It gives X back if the NMI turns out to be a DLI, and saves Y once the
  VBI is confirmed.
- **`DliDefault`** now pushes A, X and Y and leaves through `DliExit`.
- **The bank switch stays:** the DLI handler reads the scene page
  (`$90xx`, from the sound code at `$7546-$75B7`;
  `probes/p7800-dlireads.lua`).
- Scene 1: 3,816 → **3,567**. Story: 3,679 → 3,441.

**Result:** scene 1's NMI went from 4,860 to 3,567 cycles a frame (−27%).
The main program's share went from 16,660 to 18,008 (+8%). The game is
CPU-bound (it waits about 2% of a frame), so new pictures come about that
much sooner.

**Room in the fixed bank.** The system block now also takes pieces placed
in free gaps: each `;;; FAR` piece in `sys7800.asm` is assembled on its own
(RowBase, ReadStick).
- The build assembles in two passes: first the main block with placeholder
  far addresses, then each piece against the main block's labels, then the
  main block again. Every reference between them is an absolute address
  above `$E000`, so nothing changes size, and the build checks that.
- **A bug caught on the way:** the free-space searches ran up to `$FFF8`,
  across the NTSC signature (`$FF80-$FFF7`), which the signer writes after
  everything is placed. A far piece briefly landed at `$FF76`. All searches
  now stop at `SIG_START` (`$FF80`). The kept build had nothing above
  `$FE53`.

**Checked:**
- scenes 1-4 byte for byte (`port/regress.sh`);
- attract loop, 15,000 frames, no fault and no blank frames beyond
  power-on;
- no blitter write past either buffer;
- six DLIs and one VBI a frame. The only drops are the one long VBI at the
  story-to-cutscene change (it builds the new scene's lists and overruns a
  frame), the same in the kept build.
- **Colour timing** (`probes/p7800-palline.lua`, lines from emulated time;
  this MAME's Lua has no scanline call):
  - the middle band's colours change on the same line as before;
  - the low band's, the health arrows, one line earlier. Neither build
    reaches the handler's `STA WSYNC` on the DLI's own line, because the
    handler runs sound work first. The new dispatch (about 40 cycles to the
    handler) is closer to the XE OS's (about 20) than the old (about 100).
  - Screenshots of both builds at the same flips in scenes 1, 2 and 4 are
    pixel-identical. The hardware test is the real check here.

### The princess room: recording a 7800 session (2026-09-26)
Reported from the Pocket: the princess room seems to cause a crash.

- **Scripted, scene 4 (the finale), invincible + easy:** it got as far as
  the palace door and walked into it for 32,000 frames without a fault.
  The door and the hawk need kicks and positioning, beyond `playkey.lua`
  (the user's point), so a human recording is the way through.
- **The patch kit's new knob "start":** `start-level2`, `start-level3`
  and `start-finale` rewrite the operand of the title's game start
  (`LDA #$01 / STA $D0` at XE `$7806`, site `game-start`, bank 0 `$B807`)
  to 2, 3 or 4. The title and attract sequence are unchanged, and dying
  still returns to scene 1. Checked: a fire press at the title of a
  `start-finale` cartridge starts scene 4.
- **`Record Karateka 7800.bat` / `Play Karateka 7800 Recording.bat`:** the
  first makes the cartridge with the kit (`K78_WITH`, default
  `start-finale,invincible`), keeps it as `inp\NAME.a78` beside
  `inp\NAME.inp` (both git-ignored) and records in a window. The second
  plays a recording back on its own cartridge.
- **Next:** the user's recording, replayed under the crash probes.

**Correction, the same day: `start-finale` doesn't work, and it's removed.**
The user's first recording with it froze as soon as fire was pressed. A
replay (`CART=inp\princess.a78` with `EXTRA="-input_directory ../../../inp
-playback princess.inp"`; paths with a space must be relative) showed no
crash. The game runs scene 4, but the player stands in the right-hand
doorway and never moves.
- **The original does the same** with the swap: the scene 4 regression
  images show that pose at every flip.
- **The natural arrival** (`xe-01-easy.inp`, frame 24,549, snapshots via
  `probes/xe-snapplay.lua`) is different. Scene 3's handover
  (`JSR $2400`; `$0AFC=$AA`, `$0AFE=$FF` hold the flip for about 170
  frames; `$B0=8`; `$D0=4`; `JMP $2E00`) keeps scene 3's last picture up
  while scene 4 is drawn. The player then stands mid-room over the last
  guard and walks right.
- **RAM at the start of scene 4, natural against swapped**
  (`probes/xe-scenedump.lua`): dozens of zero-page and swap-buffer bytes
  differ, the player's position among them.
- **Dead end:** setting just the handover's three values (`playkey.lua
  HANDOVER=1`) still left the player in the doorway.
- **What replaces it:** `start-level2` and `start-level3` stay (both start
  cleanly), and `Record Karateka 7800.bat` now defaults to
  `start-level3,invincible`: play on through level 3 into the finale.
  Checked on the port: a start-level3 cheat cartridge plays scene 3 (the
  scripted player stays there for 40,000 frames; the doors need a real
  player).

**The crash itself (user recording `7800-02`, 738 s, start-level3 +
invincible).**
- **Replay:** scene 4 begins at frame 42,000. The player reaches the far
  door, and at 43,493 the engine at `$7000` is overwritten. The blitter
  (`$7927`) wrote `$7000`, called from scene 4's finale code
  (`$7AE4` ← `$7A19` ← `$77F3`).
- **The sprite pointer was `$16B0`,** an XEGS scene-code address: entry 24
  of the `$1D0F/$1D34` table ($16AE, past its header), whose high byte was
  never relocated. On the 7800 `$16AE` is console RAM. Its "header" gave
  width 0, and a zero width makes the row loop run 256 bytes, through the
  end of buffer A into the engine.
- **Why unrelocated:** the census playthrough freed Mariko one way. The
  finale's frame tables (`$7DDF`, `$7E22`, `$7EA3`, `$7F0F`, `$7F82` in
  scene data, `$1D34` in scene code) were relocated only for the entries
  that run drew. The `probes/scanhi.py` report of 2026-09-25 had listed
  them as open.

**Fixed:**
- `MANUAL_TABLES` relocates the six tables whole. A new region "auto"
  relocates each entry by the region its target is in; art entries
  (`$8000`) don't move.
- **Two finale frames the blitter couldn't reach:**
  - `$1CEE` (5×2): the `$1C80` fixed-bank copy now runs to `$1CF9`;
  - `$1F29` (43×4): the art bank at `$BB29`, page `$BB` marked in scene
    4's page map. Its fixed-bank slot holds the TIA tables.
- **A second, older fault:** the shared fixed-bank copy of `$1600-$18A1`
  (scenes 2, 3 and 4) is scene 2's bytes. From `$16FE` on, scene 4's
  differ (its own finale frames). The build let that pass ("the same where
  read"), which was only as good as the census's reading, so frames like
  `$1772` and `$181E` drew scene 2's bytes. Now:
  - scene 4 has its own copy of `$16FE-$18A1` in the art bank
    (`$BCFE-$BEA1`, pages `$BC-$BE`, not drawn from in scene 4's own data);
  - the build refuses any shared copy whose scenes differ anywhere in it.
    Only this one group did.
- **Checked:** `probes/checktables.py` follows every entry of the seven
  tables through the cartridge the way the blitter reads. All 125 real
  sprites read identically to the original's; 46 entries are art or not
  sprites (absurd headers: never drawn). Scenes 1-4 are still byte for
  byte.

**Replaying on a rebuilt cartridge doesn't work.** The two replays differ
from frame 20: the BIOS's signature check takes a different time for a
different cartridge, so the game starts at another moment and the recorded
inputs miss. So recordings are tied to their cartridge.
`probes/p7800-inputlog.lua` carries one across instead:
- MODE=log, on the old cartridge under playback: saves a state at SAVEAT
  and logs every SWCHA/SWCHB/INPT4/5 read per frame after it;
- MODE=feed, on the new cartridge started from that state: answers those
  reads frame by frame.
The code addresses are the same in both builds; only scene 4's tables and
the copies moved.

**Verified with the hand-off.**
- **Setup:** state saved at frame 43,000 of `7800-02` on its own cartridge,
  and the reads that followed logged. Starting MAME with `-state` never ran
  a frame here, so `M:load()` from Lua at the second frame does it.
- **Old cartridge + logged inputs:** the blitter's stray write at frame
  494 after the state, which is 43,494, the recording's own crash. So the
  hand-off is faithful.
- **Fixed cartridge + the same inputs:** no stray write through 1,500
  frames. The fight in Akuma's hall ends, the player goes through the door
  and walks through the next room towards Mariko at the far door.
- **Still open:** the rest of the finale (Mariko, the epilogue, a restart)
  needs a new recording on a new cartridge. The other partly relocated
  tables `scanhi.py` lists (scene 1 `$7623/$7C17`, scene 2 `$7117`, scene
  6, scene 4's text table `$6323`) are still unchecked.

### The other half-relocated tables: can anything reach them? (2026-09-26)
The user asked for the conditions that would read the unrelocated entries,
before fixing anything. (Their own test: level 2's enemies left to spawn
indefinitely, no crash, so not the enemy heads.) New helper:
`probes/callers.py SCENE ADDR` (every JSR/JMP to an address, with the code
before it). Every site `scanhi.py` still flags, read from its code:

- **Scene 1 `$7623`** (`$7683`, via the vector `$7600`, from `$7B95`):
  32-entry tables `$7603/$7623` (column `$7643`, row `$7663`). It draws
  entries X+1 and X+2 with X = `$99`. `$99` is set to 11 when the scene
  starts (`$77D1`), stepped by 2 each frame (`$7A86`) and cleared at 23 or
  more (`$7A4D`). So only entries 12-23 are ever read, exactly the
  relocated ones. (A "`STY $99`" at bank 15 `$B83D` is table data.)
  **Unreachable.**
- **Scene 1 `$7C17`** (`$7C4A`, 17 entries): called with fixed X = 0, 1-7,
  10-16. The unrelocated entries are 8 and 9. **Unreachable.**
- **Scene 1 `$71C3`, `$6E0C`; scene 2 `$7117`, `$7DDC`; scene 3 `$6AA8`:**
  complete tables (5, 18, 11, 6 and 15 entries). The flagged bytes are the
  next tables, which the scan over-reads.
- **Scene 2 `$B097` and `$BCDE`** (bank 15): not tables at all; those
  bytes are 6502 code, the same in every scene. They are read only from
  `$70B7` and `$7CB4`, stale copies of the real routines at `$7137` and
  `$7DB4`. Neither was ever executed or has a caller. **Dead code.**
- **Scenes 2 and 3, `$21BC`** (`LDX #$0F / STX $E6`): never executed, and
  the bytes around it store into ROM and jump into data. **Dead.**
- **Scene 4 `$6323`** (the epilogue's line table, `$6203`, live): its one
  unrelocated entry is line 10 (`$6315`, an empty line and end marker).
  The loop at `$6334` draws X = 0-9 (`CPX #$0A`). **Unreachable.**
- **Scene 6**: unrelocated copies of scene 1's routines (`$6C57`, `$71C3`,
  `$7623`, `$7C17`). Scene 6 is the 41-frame lead-in, and it clears `$99`
  to 0, so `$7683` doesn't run. None of its table entries was relocated by
  the census, which means none of those routines ran there. **Unreachable
  as long as the lead-in stays a lead-in.**

Result: no remaining flagged table can be read past its relocated part on
any path in the code.

**The console's Select at the title** leads to scene 6. **Correction, the
same day:** I first read the run log's "scene 5" as scene 5. That column
is the bank in use, and scene 6 lives in bank 5. `$D0` goes 6, then 1
(below). "The keyboard comes out" was right.
- It's a fight at the gate with two fighters in stance, the right-hand one
  apparently on joystick 2.
- `probes/p7800-select.lua` presses Select by answering SWCHB reads.
  6,000 frames idle and 15,000 frames with the scripted player fighting on
  joystick 1: no crash, no stray blitter write.
- **Not yet compared** with the original: scene 5 against MAME's `xegs`,
  and joystick 2.

### Select, scene 6: a whole mode the census filed under scene 1 (2026-09-26)
The user recorded the Select mode in MAME (`7800-03`): the scene stays put
at the gate in the first level, and winning behaves normally. The replay
was clean: 5,856 frames, no stray writes. The original does the same with
OPTION (`probes/xe-option.lua`, which answers its CONSOL reads): the same
fight, with `$D0 = 1`.

**Correction to "can anything reach them?":** scene 6 isn't a 41-frame
lead-in.
- Bank 15's console handler (`$AF66`): START → scene 1; SELECT → pause;
  OPTION from the title (`$7FE7` = 0) → `$D0 = 6`.
- Scene 6 sets up the fight, then writes `$D0 = 1` (`$B71B` on the 7800,
  frame 44 after the press) **without reloading**. It plays on in its own
  banks (bank 5 on the 7800).
- The census keys what it sees by `$D0`, so it filed scene 6's fight under
  scene 1. In scene 6 that code looked like never-run data, and the build
  copied it raw.

**Measured** (`probes/twindiff.py`: where scene 6 holds scene 1's original
bytes, its built bank should hold scene 1's built bytes): 245 bytes
differed. They were raw zero-page operands (`STA $03`, which on the 7800
is a TIA register), unrelocated pointers, and the flags at
`$7096`/`$7097`. Scene 6 had no carve for those, so a write went to
`$B096`/`$B097`: a bank switch, as with `$6009` in the story. That the
scripted and recorded fights didn't crash was luck of the paths they took.

**Fix:**
- **`xesource.py` `TWIN_OF = {6: 1, 0: 1}`:** a scene with a twin also
  takes the twin's executed and static code map wherever it holds the same
  instruction (same opcode and operands; a JSR/JMP target may differ).
- **`reloclist.py`:** scene 1's relocations are applied to scenes 0 and 6
  wherever the bytes around them agree (the scene 0 rule, generalised).
- **`CARVE_SDATA[6]`:** `$7096-$7097` and the death sprites, as scene 1.
- **Result:** scene 6 differs from scene 1's build in one byte, at `$79EF`,
  inside dead code (scene 6's own version jumps away just before it).
  Scene 0's four remaining hits are coincidences (different instructions
  that share one byte value).
- **The zero-page map moved:** usage now counts scene 6's code, so
  operands changed in every bank. That's consistent, and checked.

**Checked:**
- scenes 1-4 byte for byte;
- the title and story as before (3 bytes per buffer at flips 40-120, the
  same in the previous build: the original's garbage-dot bug, which the
  port fixes);
- attract loop 15,000 frames and Select-mode scripted fight 15,000 frames,
  no stray writes;
- the kit rebuilt.

### The silent Akuma fight (2026-09-26)
The user's recording `7800-04` (761 s) reaches the good ending: the
princess room and the epilogue now run. But the Akuma fight was silent,
and sound came back once he fell.

**Measured** (`probes/soundlog.lua`: per frame, the game's POKEY
registers as written, via the port's shadow `$1E17` or the original's
registers, and the TIA): through the whole fight (frames 36,000-40,400)
the game wrote no audible POKEY setting at all. The TIA faithfully played
nothing.
- **Not the console speaker.** `probes/writecount.lua` on CONSOL: on both
  machines only `$08` from `$AFD1`. The XE's ~70,000 writes per 200 frames
  at the ending are the same routine polling for a key. (Correction to the
  step 2 note, above.)
- **The cause, the tune table** at `$2422`/`$25C0`: 29 interleaved pointers
  (low, high), `$FFFF` after. The census heard tunes 0, 12 and 17-28. The
  high bytes of 1-11 and 13-16 stayed XEGS engine addresses (`$25FC`,
  `$2606`, `$260E`, `$2618`, `$261E`). On the 7800 those are console RAM in
  the middle of DLL_B, so those tunes played display-list bytes as notes:
  silence.
- **The tune table fix was real but not this fight's fix.** `MANUAL_TABLES`
  takes a stride: `("*", 0x25C0, 0x25C1, 29, "auto", 2)` relocates the whole
  table (now `$75F8-$764A` in the engine's RAM copy). The table has 28 tunes;
  the 29th "entry" is tune 0's first list word (`$2000`), also a pointer, so
  relocating it is right anyway.

**Correction: the first verification tested the wrong fight.** The hand-off
(a state saved at frame 36,000 of `7800-04`, loaded onto the fixed cartridge,
with `p7800-inputlog.lua`'s `PATCH` writing the table's high bytes) reported
sound in "the fight": 0 blocks before, 166, 33, 33 ... after. It wasn't
Akuma. The fixed build's zero-page map differed from the state's, so the
game restarted at level 1 and the sound was a level 1 fight
(`akuma-fight-MAME.wav` too). The user saw the fight still silent on MAME
and on the Pocket, and their timeline (bird, door, boss music, two bumps and
the kick, then silence until the joyous prelude) exposed it. A hand-off is
only valid between builds with the same code addresses and zero-page map.

**The real cause: the music data below the table.** The format, from the
driver (`$2422` starts a tune, `$2441` reads its list, `$24E3` steps each
frame, `$2505` plays a note, `$259D` loads a header; `$258D` swaps zero page
`$00-$07` with `$3000-$3007`, the sequencer's own copy):
- tune table `$25C0` (28 words) → a **tune list**: words, each a pattern
  reference, or `$xxFF` end (`$24D7` stops), or 4-byte `$xxFE lo hi`
  (frame wait into `$0AFC/$0AFD`) and `$xxFD lo hi` (delay into
  `$0F15/$0F16`);
- a **pattern reference** (a word: the stream, `$2451` → `$00/$01`);
- the **stream**: its first word points at its **header** (tempo `$240B`,
  voice settings, `$259D` → `$02/$03`), then notes of 3 bytes (length,
  voice 1, voice 2: `$2300` table offsets, 0 rest, `$FF` hold), `$FE n`
  (header index `$240A`), `$FF` (next list entry, `$248C`).

The pattern references at `$2000-$2009` and the streams are scene code
(`$1203-$2300`), different in every scene; the lists are in the shared
engine. The census relocated only what its runs played. Akuma's music is
tunes 13-16: list `$261E` → `$2000` → (scene 4) `$200A` → header `$20C0`.
None of those three pointers was relocated, so on the 7800 the sequencer
read `$2000` (console RAM) as the reference, and from there garbage: tempo 0
(`$2420` counting down from 256), note lengths like `$F2`, and voices held
at silence. The sequencer owns the voices while `$2409` is `$FF`, so the
hits' sounds were never heard either: the whole fight was silent.

**Fix:** `reloclist.music_pointers()` walks the tune data of every scene
(table → lists → references → streams → headers) and relocates each
pointer the census missed. A reference whose stream does not parse (a
valid header pointer, even voice offsets, an `$FF` end within 400 notes) is
not that scene's music and is left alone: `$2000-$2009` hold other bytes in
scenes that don't use every tune. Scene 0's streams end at `$2178`, just
before code the census executed at `$2179`. 14 new entries:
- shared lists: `$2601`, `$2603`, `$260B`, `$2613`, `$2615`, `$261F`
  (tunes 1-5, 6-7, 8 and 13-16);
- scene 4: `$2001`, `$200B` (Akuma's reference and header);
- scene 0: `$2003`, `$2005`, `$2007`, `$202A`, `$20C9`, `$211D`.

`probes/tunewalk.py SCENE` checks the linked build against the walk; it
reported 8 wrong pointers in scene 4 before the fix and none after.

**Verified on the recording's own cartridge.** `inp/7800-04mf.a78` is
`7800-04tf.a78` with only those 8 bytes changed (every scene 4 pointer),
re-signed; `inp/7800-04mf.inp` is the recording, which stays in sync to the
ending. Frames with TIA sound per 500, frames 35,000-40,500 (Akuma's health
from `$14` down):
- `7800-04tf` (table fix only): 0 in every block until he falls;
- `7800-04mf`: 439, 295, 57, 76, 51, 90, 104, 85, 70, 82, 84.
The first thousand frames are near-continuous (music), the rest come in
bursts (the blows).
(`work/analysis/r4mf/akuma-mf.wav`.)

The rebuilt cartridge differs from the last one in exactly those 14 bytes.
Scenes 1-4 are still byte for byte; the kit is rebuilt.

### Resources left for enhancements (2026-09-26)
Measured on the current build.
- **ROM:** each bank's free space as the build leaves it.
- **RAM:** `probes/p7800-ramuse.lua`, writes after power-on over the
  attract loop and scripted play in scenes 1-4, read against the layout.
  "Never written" is not "free": data copied in at power-on, assigned
  variables that are rarely written, and the mirrors of page zero and the
  stack were all taken out.

**ROM** (128K; bigger boards are outside the retail layouts):

| bank | free | notes |
|---|---|---|
| fixed (`$C000-$FFFF`) | ~109 bytes, in scraps of 26 or fewer | runs whatever bank is mapped: bank 15, the system code, the display lists, the sound tables, sprite copies |
| scene banks 0-5 | ~930-970 each | 712 of it at `$9420-$96E7`; readable only while that scene's page is in, and the blitter reads `$80-$9F` from the art bank, so code or data, not sprites |
| art bank 6 | 1,878 | `$B179+951`, `$BEA2+350`, `$BBD7+295`, `$B8D8+236`; the blitter can read it (pages above `$A0` through a scene's page map) |

**Console RAM** (4K at `$1800-$27FF`), free:
- `$184E-$187F` (50);
- `$1A09-$1A7F` (119);
- `$1AA1-$1B7F` (223);
- `$1EAF-$1EFF` (81);
- `$1F78-$203F` (200);
- `$2100-$213F` (64);
- `$27B9-$27FF` (71).

That's about 808 bytes, plus `$1900-$1A08` (265) in scenes 2-4 only (the
death-sprite carve of scenes 0, 1 and 6). The stack is written down to
`$01D2` (nested interrupts), so `$0140-$01BF` or so (~128 bytes) is spare
with a margin.

**Zero page:** all 192 bytes (`$40-$FF`) are assigned; the overflow is at
`$1800-$184D`.

**Cartridge RAM** (16K at `$4000-$7FFF`), free: `$7203-$72FF` (253, between
the engine's two parts), `$57F8-$5807` (16), `$6FF0-$6FFF` (16) and
`$4008-$400F` (8).

**CPU:** a frame is 29,868 cycles.
- MARIA's DMA: 5.0-7.4K (17-25%, by how many lines show bitmap).
- The NMI: about 3.6K in play (the game's own handlers about 2.3K).
- The main program: about 18K.
- The game waits only about 2% of a frame in play. It is CPU-bound, so
  any added work slows how often it draws a new picture, about 1% per 300
  cycles a frame.
- Known savings: the empty sky zones in scene 1 (about 1,300 cycles a
  frame); more NMI trimming (the bank switch, the gate checks: a few
  hundred).

**Sound:** both TIA channels carry the game's two POKEY voices whenever
music plays; there is no free channel.

**Display:** the game uses at most 4 of MARIA's 8 palettes in a frame, and
only 160A (3 colours + background per palette). Each line is two 20-byte
objects. Another object on a line costs about 2 cycles of DMA, plus 0.74 a
byte.

### Where level 1's drawing time goes (2026-09-26)
The user suspected the cliff (left) and the arch (right).
`probes/p7800-drawprof.lua` times every call of the blitters (`$284E`,
`$2B82`, `$2B8B`), the fills (`$2CCD`, `$2D03`) and the clear (`$280F`)
from entry to return. It uses emulated time, so MARIA's DMA counts as it
does for the game, minus any NMI inside the call, and also counts the
cycles executed. Calls are keyed by sprite, and the sprites were rendered
to identify them.

Scene 1, scripted fight, 89 flips; drawing takes about 225,000 cycles a
flip (about 20,000 a frame):

| what | cycles a flip | share | calls a flip | a call (executed) |
|---|---|---|---|---|
| player's health arrows (`$FE12`, 7×1) | 35,400 | 15.7% | 11 | 3,260 (2,360) |
| rectangle fills (erasing) | 23,100 | 10.3% | 4 | 5,480 (3,680) |
| foe's health arrows (`$FE1C`, 7×1) | 20,800 | 9.3% | 8 | 2,700 (1,920) |
| fence rail piece (`$AB8E`, 1×4) | 20,100 | 8.9% | 14 | 1,420 (1,030) |
| the cliff (`$AA7D`, 29×6) | 13,800 | 6.1% | 0.8 | 17,560 (12,650) |
| striped floor (pattern fill) | 10,400 | 4.6% | 2.5 | 4,150 (2,690) |
| arch beam (`$AB94`, 4×15) | 4,900 | 2.2% | 0.8 | |

- **The health arrows are the biggest item:** a quarter of all drawing.
  Every new picture fills the status row (rows 181-188, full width) and
  redraws every arrow, and each 7-byte arrow costs about 2,000-2,400
  executed cycles (the blitter's per-row setup and pixel shift), though
  health changes only on a hit.
- **The cliff and the arch** are real but smaller: about 6% and about 3%
  (beam alone).
- **The fence rail's small pieces** add up to about 9%.

**Follow-up, the same day: blows still reported silent.** The user
reports, with a fixed build: the fight's prelude plays, then nothing until
the victory music.
- **Every current cartridge has the fixed table:** `75 75 75 75`, the
  stable build and the fork's. Every recording's cartridge made before the
  fix has `75 25 25 25`.
- **All sound goes through one routine**, the driver's per-frame copy of
  its voices into POKEY (`$70C8-$70DA`, XE `$10C8`;
  `probes/p7800-pokeywriters.lua`). Blows don't start tunes: a level 1
  fight starts only tune 26, once (`probes/p7800-tunelog.lua`).
- **MAME, the fixed build, from the `akuma` state with the recorded
  inputs:**
  - 31 blows land (health drops), 13 of them with sound within 10 frames.
    Ordinary fights in `7800-04` (level 3): 28 of 73. The same ratio.
  - Sound in 10.8% of the fight's frames, against 9.0% in level 3 fights.
  - The same TIA settings: AUDC 8, AUDF 2/5/8/3, volumes mostly 1-4.
- **Audio** (`run7800.sh` now takes `WAV=file` to record it): RMS per
  second through the fight is 600-2,800, the same as a level 3 fight.
  Files: `work/analysis/akWav/akuma.wav` and
  `work/analysis/l3Wav/level3.wav`.
- **So in MAME the fixed build plays the fight's sound.** Where the user
  heard silence (the Pocket or MAME, and whether other fights' blows were
  audible on the same setup) is the open question.

### regress.sh could compare stale dumps (2026-09-27, correction)
Found in the fork (`../karateka-enh-port/FINDINGS.md`, "The column
routine"). `regress.sh` compared whatever `fbk*.bin` its output folders
held, so a port run that died before writing them was compared using the
last run's files and passed. It now deletes the port's dumps before
running. The results recorded here came from builds whose other runs went
to completion.

## The fork's speed-ups, merged (2026-09-27)
The user tested the enhancement fork's builds on the Pocket (running their
port of the MiSTer 7800 core), found no issue, and asked for them in the
stable port. None of them changes the picture: every buffer is byte for
byte what the original draws. The details, measurements and checks are in
`../karateka-enh-port/FINDINGS.md`. In short:
- **The health bars are drawn only when they change** (a per-buffer cache
  in the scene pages at `$9420`). Every picture used to clear the status
  row and redraw every arrow, about a quarter of a fight's drawing.
- **The row address, faster:** the game's general 8×8 multiply `$2D78`
  (about 290 cycles, paid by every draw call) became a fixed × 40 (about
  60).
- **Level 1's columns:** posts and pillars drawn as loops of 1- and 2-row
  pieces (one blit call a piece, clipped away whole when off screen) go
  through a routine that draws the first and last pieces with the blitter
  and copies the rest. It lives in scenes 1 and 6's pages only (the
  build's `;;; LEVEL1PAGE`, placed in parts).
- **The fast fill:** the rectangle and pattern fills' store loops run from
  cart RAM at `$7203` (copied at every scene load), 4 rows at a time,
  column by column: 5 cycles a byte against 11.

**Level 1, scripted fight, pictures per 1,000 frames:** 89 before, 123 now
(about 38% more). The fills and the row address help every level.

**The merge:** `build7800.py`, `layout7800.py`, `link7800.py` and
`sys7800.asm` came from the fork whole. The only lines unique to this side
were ones the fork had rewritten. The probes are synced both ways; this
side kept its newer `run7800.sh` (WAV) and `soundlog.lua`. The build here
gives the fork's cartridge byte for byte, including the option cartridges
from the kit.

**Checked here:**
- `regress.sh`: 13 comparisons byte for byte, fresh dumps;
- `p7800-colcheck.lua`: 1,275 columns and 12,179 blits, 0 wrong;
- `p7800-fillcheck.lua`: 4,758 fills, 0 wrong;
- `p7800-firstover.lua`: 15,000 attract frames, no stray write.

Checkpoint before the merge: `../Karateka-Port-checkpoints/2026-09-27_KEEP_before-merge`
(the source, both cartridges, the kit), kept until this build proves
itself on hardware. The fork continues with the display rework (MARIA
drawing the fighters).
