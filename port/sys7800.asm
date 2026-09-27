; sys7800.asm -- the 7800 side of the XEGS Karateka port (fixed bank).
;
; Assembled by port/build7800.py, which puts equates for every address used
; here in front of this file (hardware, system variables from layout7800.py,
; the game's relocated symbols as G_*, table and image addresses) and the
; generated tables after it. The jump table must stay first: the game is
; linked against its addresses (link7800.py SYS_ENTRIES, in the same order).
;
; Conventions kept from the XEGS: the game's vertical-blank handler expects
; A, X, Y pushed (it ends PLA/TAY/PLA/TAX/PLA/RTI); its display-list handler
; saves its own registers. Both are entered as interrupts, with a return
; frame to our epilogue pushed first, so their RTI comes back here.
;
; ZP_P1 and ZP_P2 are the game's $00/$01 and $02/$03 (the XEGS loader used
; them too). Code that runs inside the NMI saves and restores them.

; ------------------------------------------------------------ jump table
SysZpSwap:
    JMP ZpSwap
SysZpClear:
    JMP ZpClear
SysLoadCommon:
    JMP LoadCommon
SysLoadScene:
    JMP LoadScene
SysWaitLine200:
    JMP WaitFrame
SysReadStick:
    JMP ReadStick
SysBlitBank:
    JMP BlitBank
SysBlitDone:
    JMP BlitDone
SysSetVBV:
    JMP SetVBV
SysOsStub:
    JMP OsStub
SysCommonTail:
    JMP CommonTail
SysSound:
    JMP Sound
SysSetDlist:
    JMP SetDlist
SysRowBase:
    JMP RowBase
SysDliExit:
    JMP DliExit
SysStClr:
    JMP StClr

; ------------------------------------------------------------------ boot
Reset:
    SEI
    CLD
    LDA #$07
    STA INPTCTRL            ; lock: MARIA on, BIOS off
    LDA #$7F
    STA CTRL                ; DMA off while we set up
    LDX #$FF
    TXS
    LDA #$00
    STA AUDV0
    STA AUDV1
    STA CTLSWA              ; the sticks are inputs
; clear console RAM $1800-$27FF with absolute stores: zero page and the
; stack are mirrors inside it, so a pointer kept in zero page would be wiped
; by its own loop
    LDA #$00
    TAX
ClrRam:
    STA $1800,X
    STA $1900,X
    STA $1A00,X
    STA $1B00,X
    STA $1C00,X
    STA $1D00,X
    STA $1E00,X
    STA $1F00,X
    STA $2000,X
    STA $2100,X
    STA $2200,X
    STA $2300,X
    STA $2400,X
    STA $2500,X
    STA $2600,X
    STA $2700,X
    INX
    BNE ClrRam
; clear cartridge RAM $4000-$7FFF
    LDA #$40
    STA ZP_P1+1
    LDA #$00
    STA ZP_P1
    TAY
ClrCart:
    STA (ZP_P1),Y
    INY
    BNE ClrCart
    INC ZP_P1+1
    LDX ZP_P1+1
    CPX #$80
    BNE ClrCart
; system state
    LDA #$0F
    STA S_CONSOL            ; XEGS console keys: none pressed
    LDA #$FF
    STA S_PORTA
    STA S_LATCH             ; no push kept
    STA S_POKEY+9           ; KBCODE: no key
    STA S_POKEY+15          ; SKSTAT: idle
    STA S_DLIST_A+1         ; neither list built yet
    STA S_DLIST_B+1
    STA S_CHOSEN+1          ; nor chosen
    LDA #<VbiDefault
    STA S_VVBLKI
    LDA #>VbiDefault
    STA S_VVBLKI+1
    LDA #<DliDefault
    STA S_VDSLST
    LDA #>DliDefault
    STA S_VDSLST+1
    LDA #$22
    STA S_SDMCTL
    STA S_DMACTL
    LDA #$40                ; the OS leaves the vertical blank enabled, and the
    STA S_NMIEN             ; game enables DLIs with LDA NMIEN / ORA #$80
; the display: a blank list until the game picks one
    LDA #>BLANK_DLL
    STA DPPH
    LDA #<BLANK_DLL
    STA DPPL
    LDA #VBI_NMI
    STA S_NMIVBI
    LDA #$01
    STA S_SHOWBLANK
    LDA #$40
    STA CTRL                ; DMA on, 160A; it stays on (a blank list stands in for "off")
; the XEGS boot ($B7B1): scene 0, all banks, then the title's main entry
    LDA #$00
    STA G_ZD0
    STA S_SCENEBANK
    JSR LoadCommon
    JSR LoadScene
    CLI
    JMP G_ENTRY0

; -------------------------------------------------------------- the NMI
; MARIA raises it at the end of a zone whose DLL entry has the DLI bit set:
; the game's six display-list interrupt lines, then line VBI_LINE (241) of every
; list, which stands in for the XEGS vertical blank (ANTIC's comes at the same
; display-list line). They are told apart by count, and the count cannot drift:
; every list has the same seven NMIs (the blank list in ROM carries six dummy
; DLIs to match; MARIA reads the list's address only at the start of a frame,
; so a switch never changes the frame under way). As a safety net the vertical
; blank is confirmed by MARIA's own flag: line 241 ends two lines before
; vertical blank, so the NMI the count names waits (up to VBI_SPIN turns, about
; 12 lines) for MSTAT to show it; if it never does, the NMI was mid-screen, is
; taken for a DLI, and the count is set so the next NMI is the vertical blank.
; (RIOT's timer did this for a while; RIOT is not safe to use while MARIA
; halts the 6502, so it is not used: FINDINGS "Palette", "No RIOT timer".)
Nmi:
    PHA                     ; the interrupted A (X and Y: see below)
    LDA S_BANK
    PHA                     ; the bank the interrupted code had
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL             ; the handlers live in the scene page
    INC S_NMICOUNT
    LDA S_NMICOUNT
    CMP S_NMIVBI
    BCS NmiVbiCheck
; A DLI. The game's handler ($1026) saves X and Y itself and leaves through
; DliExit (its ending, $1034, patched), so the stack holds only A and the
; bank here, and X and Y are still the interrupted code's.
; The game's DLI and vertical-blank handlers save their working bytes ($14/
; $15, $03/$04) in the same place, so none may run inside another; on the
; XEGS they are lines apart. Two DLIs can be as little as 3 lines apart
; (scene 0's own $19B3), less than the handler takes here, and a DLI inside a
; DLI saved the outer one's pointer as the blitter's: the blitter then drew
; into the engine (FINDINGS "Drawing below the screen"). So a DLI that
; arrives during another runs as soon as that one ends. A vertical blank
; that arrives during a DLI waits for it to end; one that arrives while the
; last is still running (it built a list, which can take more than a frame)
; is dropped, as a late XEGS vertical blank would have been; a DLI during the
; vertical blank is dropped, and so are the blank list's dummy DLIs (the
; XEGS gets none with DMA off).
NmiDli:
    LDA S_INDLI
    ORA S_INVBI
    ORA S_SHOWBLANK
    BNE NmiDliNot
    BIT S_NMIEN
    BPL NmiQuit             ; display-list interrupts off
NmiDliRun:
    INC S_INDLI
    JMP (S_VDSLST)          ; the game's handler, out through DliExit
NmiDliNot:
    LDA S_INDLI
    BEQ NmiQuit             ; in the vertical blank, or the blank list's
    INC S_DLIPEND           ; the last DLI is still running: after it
NmiQuit:
    PLA
    STA S_BANK
    STA BANKSEL
    PLA
    RTI

; the end of a DLI handler: its Y, X and A copy on the stack, above our bank
; and A. X and Y are the interrupted code's again after these pulls.
DliExit:
    PLA
    TAY
    PLA
    TAX
    PLA
    DEC S_INDLI
    LDA S_DLIPEND
    BNE DliAgain
    LDA S_VBIPEND
    BEQ NmiQuit
    LDA #$00
    STA S_VBIPEND
    TXA                     ; the vertical blank that waited: it keeps X and
    PHA                     ; Y on the stack as well
    TYA
    PHA
    JMP NmiVbiRun
DliAgain:
    DEC S_DLIPEND
    JMP NmiDliRun           ; the one that came in meanwhile, a little late

; The NMI the count names as the vertical blank: confirmed by MSTAT, or
; after all a DLI (then X is put back first, as the DLI path needs it).
NmiVbiCheck:
    TXA
    PHA
    LDX #VBI_SPIN
NmiVbiWait:
    BIT MSTAT
    BMI NmiVbi              ; in vertical blank: confirmed
    DEX
    BNE NmiVbiWait
    LDX S_NMIVBI            ; mid-screen after all: a DLI, and the next NMI
    DEX                     ; is the vertical blank
    STX S_NMICOUNT
    PLA
    TAX
    JMP NmiDli
NmiVbi:
    TYA
    PHA                     ; the stack: A, bank, X, Y
    LDA #$00
    STA S_NMICOUNT
    INC S_FRAMES
    LDA S_INVBI
    BNE NmiDone
    LDA S_INDLI
    BEQ NmiVbiRun
    INC S_VBIPEND
    JMP NmiDone
NmiVbiRun:
    INC S_INVBI
    JSR Apply               ; a list chosen too late last frame
    JSR Inputs
    JSR TiaSound            ; last frame's POKEY writes, played on the TIA
    LDA S_NMIEN
    AND #$40
    BEQ NmiOwnFrame         ; vertical-blank interrupts off
    LDA #>NmiVbiDone        ; the game's handler picks its list (SetDlist)
    PHA
    LDA #<NmiVbiDone
    PHA
    PHP
    PHA                     ; the A, X, Y the OS would have pushed
    PHA
    PHA
    JMP (S_VVBLKI)
NmiOwnFrame:
    JSR Frame
NmiVbiDone:
    LDA #$00
    STA S_INVBI
NmiDone:
    PLA
    TAY
    PLA
    TAX
    JMP NmiQuit

; before the game installs its own handler: the part of the OS's vertical
; blank that matters here (copy the display shadows), then its exit
VbiDefault:
    LDA S_SDMCTL
    STA S_DMACTL
    LDA S_SDLST
    STA S_DLIST
    LDA S_SDLST+1
    STA S_DLIST+1
    JSR Frame
    PLA
    TAY
    PLA
    TAX
    PLA
Irq:
    RTI
; before the game installs its own: a DLI handler that does nothing, and
; leaves the way the game's does (A, X, Y pushed, out through DliExit)
DliDefault:
    PHA
    TXA
    PHA
    TYA
    PHA
    JMP DliExit

; ------------------------------------------------------- once per frame
; XEGS console keys from the 7800 switches (active low), by retail
; convention: START (restart) from RESET, SELECT (the game's pause) from
; PAUSE, OPTION (title or scene 6) from SELECT. And the quick-stick latch: the
; latest push of stick 1, handed over by ReadStick when the game next looks.
; Runs in the NMI, so no shared scratch (S_TMP is the loaders' counter).
Inputs:
    LDA SWCHA               ; RIOT, read once a frame in vertical blank (it is
    STA S_RSWCHA            ; not safe while MARIA halts the 6502); ReadStick
    LDA SWCHB               ; uses these
    STA S_RSWCHB
    AND #$08                ; PAUSE -> SELECT
    LSR A
    LSR A
    ORA #$08
    STA S_CONSOL
    LDA S_RSWCHB
    AND #$02                ; SELECT -> OPTION
    ASL A
    ORA S_CONSOL
    STA S_CONSOL
    LDA S_RSWCHB
    AND #$01                ; RESET -> START
    ORA S_CONSOL
    STA S_CONSOL
    LDA S_RSWCHA
    LSR A
    LSR A
    LSR A
    LSR A                   ; stick 1, in the XEGS PORTA bit order
    CMP #$0F
    BEQ InputsDone
    STA S_LATCH
InputsDone:
    RTS

; the game's $0F93 (STA DLISTH / RTS): note it, pick the MARIA list now,
; as ANTIC would have taken the new list at the next frame
SetDlist:
    STA S_DLIST+1
    PHA
    TXA
    PHA
    TYA
    PHA
    JSR Frame
    PLA
    TAY
    PLA
    TAX
    PLA
    RTS

; Frame: choose the list for the next frame from the game's DLIST (building
; it when it changed), then Apply it: at once when called from the game's
; vertical blank (the stand-in DLI below the picture) or while MARIA is in
; vertical blank, since MARIA reads DPPH/DPPL only at the start of a frame;
; from the main program mid-frame, at the next vertical blank. (Applying only
; in MARIA's own vertical blank showed every new frame one frame late, with
; the game already drawing into it: flicker; FINDINGS "Flicker".) Never
; re-entered.
Frame:
    LDA S_BUSY
    BEQ FrameCheck
    RTS
; the game's vertical blank asks for its list every frame, and a new picture
; comes only every 13-17 frames: the same list with the same DMA state is
; already chosen (and its mode-8 rows widened; the game never writes into
; the buffer on screen), so there is nothing to do. This was about 1,100
; cycles a frame, most of it Mode8 (FINDINGS "The NMI's cost").
FrameCheck:
    LDA S_DLIST
    CMP S_CHOSEN
    BNE FrameGo
    LDA S_DLIST+1
    CMP S_CHOSEN+1
    BNE FrameGo
    LDA S_DMACTL
    AND #$20
    CMP S_CHOSEN+2
    BNE FrameGo
    RTS
FrameGo:
    LDA S_DLIST
    STA S_CHOSEN
    LDA S_DLIST+1
    STA S_CHOSEN+1
    LDA S_DMACTL
    AND #$20
    STA S_CHOSEN+2
    INC S_BUSY
    LDA #$00
    STA S_PBLANK
    LDA ZP_P1               ; keep the game's $00-$03
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA S_DMACTL
    AND #$20
    BEQ FrameBlank
    LDX #$00
FrameFind:
    CPX SP_NDL
    BCS FrameBlank          ; a list this scene does not have: blank
    LDA DLT_LO,X
    CMP S_DLIST
    BNE FrameNext
    LDA DLT_HI,X
    CMP S_DLIST+1
    BEQ FrameFound
FrameNext:
    INX
    BNE FrameFind
FrameFound:
    STX S_DLIDX
    STX S_PIDX
    LDA DLT_CTRL,X
    STA S_PCTRL
    LDA DLT_M8,X
    STA S_PM8
    LDA DLT_BUF,X
    BNE FrameB
    LDA S_DLIST_A
    CMP S_DLIST
    BNE FrameBuildA
    LDA S_DLIST_A+1
    CMP S_DLIST+1
    BEQ FrameShowA
FrameBuildA:
    JSR BuildDll
FrameShowA:
    LDA #<DLL_A
    STA S_PDPPL
    LDA #>DLL_A
    STA S_PDPPH
    LDA S_VBI_A
    JMP FramePend
FrameB:
    LDA S_DLIST_B
    CMP S_DLIST
    BNE FrameBuildB
    LDA S_DLIST_B+1
    CMP S_DLIST+1
    BEQ FrameShowB
FrameBuildB:
    JSR BuildDll
FrameShowB:
    LDA #<DLL_B
    STA S_PDPPL
    LDA #>DLL_B
    STA S_PDPPH
    LDA S_VBI_B
    JMP FramePend
FrameBlank:
    LDA #<BLANK_DLL         ; the blank list, in ROM
    STA S_PDPPL
    LDA #>BLANK_DLL
    STA S_PDPPH
    LDA #$40
    STA S_PCTRL
    LDA #$00
    STA S_PM8
    LDA #$01
    STA S_PBLANK
    LDA #VBI_NMI
FramePend:
    STA S_PVBI
    LDA #$01
    STA S_PEND
    LDA S_INVBI
    BNE FrameNow            ; from the game's vertical blank: below the picture
    BIT MSTAT
    BPL FrameDone           ; mid-frame from the main program: at the next one
FrameNow:
    JSR Apply
FrameDone:
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    DEC S_BUSY
    RTS

; show the chosen list (in vertical blank only)
Apply:
    LDA S_PEND
    BEQ ApplyDone
    LDA #$00
    STA S_PEND
    LDA S_PDPPH
    STA DPPH
    LDA S_PDPPL
    STA DPPL
    LDA S_PCTRL
    STA CTRL
    LDA S_PVBI
    STA S_NMIVBI
    LDA S_PBLANK
    STA S_SHOWBLANK
    LDA S_PM8
    BEQ ApplyDone
    LDA S_PIDX
    STA S_DLIDX
    JMP Mode8
ApplyDone:
    RTS

; ------------------------------------------------------ list building
; BuildDll: the DLL for the list at table index S_DLIDX, into its buffer's
; DLL. A descriptor is a run list: kind|$80 (DLI on the run's last line),
; line count, argument; kind 0 blank, 1 mode-8 row (argument 0-2), 2 buffer
; rows from the argument row on; $FF ends it. After the runs comes one blank
; line with the DLI that stands in for the vertical blank, then blanks. It
; runs in the NMI, so its scratch is its own (S_BTMP, not the loaders' S_TMP).
BuildDll:
    LDX S_DLIDX
    LDA DLT_DLO,X
    STA ZP_P1
    LDA DLT_DHI,X
    STA ZP_P1+1
    LDA DLT_BUF,X
    BNE BuildForB
    LDA #<DLL_A
    STA ZP_P2
    LDA #>DLL_A
    STA ZP_P2+1
    LDA #<DLA_BASE
    STA S_ROWBASE
    LDA #>DLA_BASE
    STA S_ROWBASE+1
    JMP BuildGo
BuildForB:
    LDA #<DLL_B
    STA ZP_P2
    LDA #>DLL_B
    STA ZP_P2+1
    LDA #<DLB_BASE
    STA S_ROWBASE
    LDA #>DLB_BASE
    STA S_ROWBASE+1
BuildGo:
    LDA #$00
    STA S_LINES
    STA S_NDLI
BuildRun:
    LDY #$00
    LDA (ZP_P1),Y
    CMP #$FF
    BNE BuildRunGo
    JMP BuildEnd
BuildRunGo:
    STA S_KIND
    INY
    LDA (ZP_P1),Y
    STA S_COUNT
    INY
    LDA (ZP_P1),Y
    STA S_ARG
    LDA ZP_P1
    CLC
    ADC #$03
    STA ZP_P1
    BCC BuildKind
    INC ZP_P1+1
BuildKind:
    LDA S_KIND
    AND #$7F
    BEQ BuildBlankRun
    CMP #$01
    BEQ BuildM8Run
; buffer rows: the first row's DL is ROWBASE + 10 * argument
    LDA S_ARG
    STA S_ROWP
    LDA #$00
    STA S_ROWP+1
    ASL S_ROWP              ; *2
    ROL S_ROWP+1
    LDA S_ROWP
    STA S_BTMP
    LDA S_ROWP+1
    STA S_BTMP+1
    ASL S_ROWP              ; *4
    ROL S_ROWP+1
    ASL S_ROWP              ; *8
    ROL S_ROWP+1
    LDA S_ROWP
    CLC
    ADC S_BTMP              ; *10
    STA S_ROWP
    LDA S_ROWP+1
    ADC S_BTMP+1
    STA S_ROWP+1
    LDA S_ROWP
    CLC
    ADC S_ROWBASE
    STA S_ROWP
    LDA S_ROWP+1
    ADC S_ROWBASE+1
    STA S_ROWP+1
    LDA #$0A
    STA S_STEP
    JMP BuildLines
BuildM8Run:
    LDA S_ARG
    ASL A
    STA S_BTMP
    ASL A
    ASL A
    CLC
    ADC S_BTMP              ; *10
    ADC #<DL_M8
    STA S_ROWP
    LDA #>DL_M8
    ADC #$00
    STA S_ROWP+1
    LDA #$00
    STA S_STEP              ; every line of the row shows the same DL
    JMP BuildLines
BuildBlankRun:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    LDA #$00
    STA S_STEP
BuildLines:
    LDA #$00
    STA S_FLAG
    LDA S_COUNT
    CMP #$01
    BNE BuildLine
    LDA S_KIND              ; the run's last line carries its DLI
    AND #$80
    STA S_FLAG
    BEQ BuildLine
    INC S_NDLI
BuildLine:
    JSR PutEntry
    LDA S_ROWP
    CLC
    ADC S_STEP
    STA S_ROWP
    BCC BuildLineNext
    INC S_ROWP+1
BuildLineNext:
    DEC S_COUNT
    BNE BuildLines
    JMP BuildRun
BuildEnd:
; blanks to the end of the list; line VBI_LINE stands in for the vertical
; blank (where ANTIC's comes), leaving the game's handler the bottom lines and
; the top border to finish in before the next frame's first DLI, as on the
; XEGS (its DLI and VBI handlers share save bytes, so they must not overlap)
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
BuildFill:
    LDA #$00
    LDX S_LINES
    CPX #VBI_LINE
    BNE BuildFillFlag
    LDA #$80
BuildFillFlag:
    STA S_FLAG
    LDA S_LINES
    CMP #DLL_LINES
    BCS BuildDone
    JSR PutEntry
    JMP BuildFill
BuildDone:
    LDX S_DLIDX
    LDA DLT_BUF,X
    BNE BuildDoneB
    LDA S_NDLI
    CLC
    ADC #$01
    STA S_VBI_A
    LDA DLT_LO,X
    STA S_DLIST_A
    LDA DLT_HI,X
    STA S_DLIST_A+1
    RTS
BuildDoneB:
    LDA S_NDLI
    CLC
    ADC #$01
    STA S_VBI_B
    LDA DLT_LO,X
    STA S_DLIST_B
    LDA DLT_HI,X
    STA S_DLIST_B+1
    RTS

; one DLL entry: DLI flag, DL address high, low (never past the list's end)
PutEntry:
    LDA S_LINES
    CMP #DLL_LINES
    BCC PutEntryGo
    RTS
PutEntryGo:
    LDY #$00
    LDA S_FLAG
    STA (ZP_P2),Y
    INY
    LDA S_ROWP+1
    STA (ZP_P2),Y
    INY
    LDA S_ROWP
    STA (ZP_P2),Y
    LDA ZP_P2
    CLC
    ADC #$03
    STA ZP_P2
    BCC PutEntryDone
    INC ZP_P2+1
PutEntryDone:
    INC S_LINES
    RTS

; ------------------------------------------------------------- loading
; the XEGS loader's two entries: $2F5A (common, then the scene) and $2F66
; (the scene's code and data banks)
LoadCommon:
    LDA #ART_BANK
    STA S_BANK
    STA BANKSEL
    LDA #<IMG_SPRITES
    STA ZP_P1
    LDA #>IMG_SPRITES
    STA ZP_P1+1
    LDA #<RAM_SPRITES
    STA ZP_P2
    LDA #>RAM_SPRITES
    STA ZP_P2+1
    LDA #<LEN_SPRITES
    LDX #>LEN_SPRITES
    JSR Copy
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL
    LDX #$00
LoadCommonCarve:
    CPX #N_CCARVE*5
    BCS LoadCommonDone
    JSR CopyEntryC
    JMP LoadCommonCarve
LoadCommonDone:
    RTS

LoadScene:
    LDX G_ZD0
    LDA SCENEBANK_TAB,X
    STA S_SCENEBANK
    LDA #ART_BANK
    STA S_BANK
    STA BANKSEL
    LDA #<IMG_ENGINE1
    STA ZP_P1
    LDA #>IMG_ENGINE1
    STA ZP_P1+1
    LDA #<RAM_ENGINE1
    STA ZP_P2
    LDA #>RAM_ENGINE1
    STA ZP_P2+1
    LDA #<LEN_ENGINE1
    LDX #>LEN_ENGINE1
    JSR Copy
    LDA #<IMG_ENGINE2
    STA ZP_P1
    LDA #>IMG_ENGINE2
    STA ZP_P1+1
    LDA #<RAM_ENGINE2
    STA ZP_P2
    LDA #>RAM_ENGINE2
    STA ZP_P2+1
    LDA #<LEN_ENGINE2
    LDX #>LEN_ENGINE2
    JSR Copy
    JSR CopyFill            ; the fast fill's code (;;; RAMFILL)
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL
    LDX #$06
LoadSceneEngine:
    LDA SP_ENGINE7,X        ; the engine's seven per-scene bytes
    STA RAM_ENGINE7,X
    DEX
    BPL LoadSceneEngine
    LDX #$00
LoadSceneCarve:
    TXA
    CMP SP_NCARVE
    BCS LoadSceneDone
    JSR CopyEntryS
    JMP LoadSceneCarve
LoadSceneDone:
    LDA #$FF
    STA S_DLIST_A+1
    STA S_DLIST_B+1
    STA S_CHOSEN+1          ; the new scene's lists: choose afresh
    STA S_STP               ; and the status bar's cache
    STA S_STP+1
    LDA #$00
    STA S_STDEF
    STA S_STFSEEN
    STA S_STTOUCH
    RTS

; copy entries: source, destination (both little-endian), length (1 byte)
CopyEntryC:
    LDA CCARVE,X
    STA ZP_P1
    LDA CCARVE+1,X
    STA ZP_P1+1
    LDA CCARVE+2,X
    STA ZP_P2
    LDA CCARVE+3,X
    STA ZP_P2+1
    LDA CCARVE+4,X
    JMP CopyEntryGo
CopyEntryS:
    LDA SP_CARVE,X
    STA ZP_P1
    LDA SP_CARVE+1,X
    STA ZP_P1+1
    LDA SP_CARVE+2,X
    STA ZP_P2
    LDA SP_CARVE+3,X
    STA ZP_P2+1
    LDA SP_CARVE+4,X
CopyEntryGo:
    STX S_TMP+3
    LDX #$00
    JSR Copy
    LDA S_TMP+3
    CLC
    ADC #$05
    TAX
    RTS

; Copy A (low) + X (high) bytes from (ZP_P1) to (ZP_P2)
Copy:
    STA S_TMP
    STX S_TMP+1
    LDY #$00
CopyLoop:
    LDA S_TMP
    ORA S_TMP+1
    BEQ CopyDone
    LDA (ZP_P1),Y
    STA (ZP_P2),Y
    INY
    BNE CopyCount
    INC ZP_P1+1
    INC ZP_P2+1
CopyCount:
    LDA S_TMP
    BNE CopyDec
    DEC S_TMP+1
CopyDec:
    DEC S_TMP
    JMP CopyLoop
CopyDone:
    RTS

; ----------------------------------------- the zero-page swap and clear
; The XEGS swaps $00-$7F with $0880-$08FF, and clears $01-$7F, byte by byte
; through $00,X; here each XEGS byte is wherever the layout put it. Table A
; lists those now in zero page (7800 address, XEGS index), table B those in
; the $18xx page (offset, XEGS index).
ZpSwap:
    LDX #N_ZA-1
ZpSwapA:
    LDY ZPT_A,X
    LDA.w $0000,Y
    PHA
    LDY ZPT_AX,X
    LDA SWAPBUF,Y
    LDY ZPT_A,X
    STA.w $0000,Y
    LDY ZPT_AX,X
    PLA
    STA SWAPBUF,Y
    DEX
    BPL ZpSwapA
    LDX #N_ZB-1
ZpSwapB:
    LDY ZPT_B,X
    LDA $1800,Y
    PHA
    LDY ZPT_BX,X
    LDA SWAPBUF,Y
    LDY ZPT_B,X
    STA $1800,Y
    LDY ZPT_BX,X
    PLA
    STA SWAPBUF,Y
    DEX
    BPL ZpSwapB
    LDX #$FF                ; as the XEGS loop leaves it
    RTS

ZpClear:
    LDX #N_ZA-1
ZpClearA:
    LDY ZPT_AX,X
    BEQ ZpClearA1           ; the XEGS loop stops before $00
    LDY ZPT_A,X
    LDA #$00
    STA.w $0000,Y
ZpClearA1:
    DEX
    BPL ZpClearA
    LDX #N_ZB-1
ZpClearB:
    LDY ZPT_BX,X
    BEQ ZpClearB1
    LDY ZPT_B,X
    LDA #$00
    STA $1800,Y
ZpClearB1:
    DEX
    BPL ZpClearB
    LDA #$00
    LDX #$00                ; as the XEGS loop leaves them
    RTS

; ------------------------------------------------ the small replacements
; $2F8A waited for scanline 200: wait for the next vertical-blank stand-in
WaitFrame:
    LDA S_FRAMES
WaitFrameLoop:
    CMP S_FRAMES
    BEQ WaitFrameLoop
    RTS

; $29DC: LDA $04 / STA $1C, then the art bank in if the source is art
BlitBank:
    LDA G_Z04
    STA G_Z1C
    CMP #$80
    BCC BlitBankKeep
    CMP #$A0
    BCC BlitBankArt         ; $80-$9F: the art
    CMP #$C0
    BCS BlitBankKeep
    STX S_BTX               ; $A0-$BF: the scene's data, unless its page map
    SEC                     ; says the page holds art-bank copies of its
    SBC #$A0                ; scene-code sprites (X and Y are the blitter's)
    TAX
    LDA SP_PAGEMAP,X
    LDX S_BTX
    CMP #$00
    BEQ BlitBankKeep
BlitBankArt:
    LDA #ART_BANK
    STA S_BANK
    STA BANKSEL
BlitBankKeep:
    RTS

; $29FF: the scene page back, then LDA $1C / STA $04 / RTS
BlitDone:
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL
    LDA G_Z1C
    STA G_Z04
    RTS

; the OS's SETVBV: A = 6 immediate (X high, Y low); 7 deferred is unused
SetVBV:
    CMP #$06
    BNE SetVBVDone
    STY S_VVBLKI
    STX S_VVBLKI+1
SetVBVDone:
OsStub:
    RTS

; $0FFB: LDA $0F17 / BNE $101F, falling into $1000
CommonTail:
    LDA G_L0F17
    BNE CommonTail1
    JMP G_L1000
CommonTail1:
    JMP G_L101F

; $2422, the sound-effect starter, with $04 kept (FINDINGS, "The linker")
Sound:
    STA S_TMP
    LDA G_Z04
    STA S_SND04
    LDA S_TMP
    JSR SoundBody
    LDA S_SND04
    STA G_Z04
    RTS
SoundBody:
    PHA                     ; the four bytes the jump replaced
    JSR G_L258D
    JMP G_L2426

; the tables the builder generates follow

; ------------------------------------------------------------ sound
; The game plays two voices on POKEY, each a pair of channels joined into a
; 16-bit divider on the 1.79 MHz clock (AUDCTL $78): voice 0 is AUDF1/AUDF2
; with AUDC2, voice 1 AUDF3/AUDF4 with AUDC4, all written to the shadow. Once a
; frame each becomes one TIA channel: a pure tone (distortion $A0) the TIA tone
; nearest its pitch (a binary search over the dividers where the nearest tone
; changes), anything else (the noise, $00) TIA's 9-bit noise at the nearest
; rate, and the 4-bit volume as it is. Tables from port/sndconv.py; runs in the
; NMI, with scratch of its own (S_SN.., not S_TMP).
TiaSound:
    LDX #$00
    JSR TiaVoice
    LDX #$01
    JMP TiaVoice
TiaOff:
    LDA #$00
    STA AUDV0,X
    RTS
TiaVoice:                   ; X = TIA channel, 0 or 1
    TXA
    ASL A
    ASL A
    TAY                     ; the voice's POKEY registers
    LDA S_POKEY+3,Y
    AND #$0F
    BEQ TiaOff
    STA S_SVOL
    LDA S_POKEY+0,Y
    STA S_SN
    LDA S_POKEY+2,Y
    STA S_SN+1
    LDA S_POKEY+3,Y
    AND #$F0
    CMP #$A0
    BNE TiaNoise
    LDA S_SN+1
    BNE TiaTone
    LDA S_SN
    CMP #SND_ULTRA
    BCC TiaOff              ; above 16 kHz: nothing to hear
TiaTone:
    STX S_SCH
    LDX #$00                ; how many boundaries are at or below N
    LDA #$40
    STA S_SSTEP
TiaSearch:
    TXA
    CLC
    ADC S_SSTEP
    TAY
    DEY
    CPY #SND_NB
    BCS TiaLess
    LDA S_SN+1
    CMP SND_NBHI,Y
    BCC TiaLess
    BNE TiaGE
    LDA S_SN
    CMP SND_NBLO,Y
    BCC TiaLess
TiaGE:
    TXA
    CLC
    ADC S_SSTEP
    TAX
TiaLess:
    LSR S_SSTEP
    BNE TiaSearch
    LDA SND_TONE,X          ; mode index << 5 | AUDF
    TAY
    AND #$1F
    STA S_SF
    TYA
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    LDA SND_MODE,Y
    LDX S_SCH
    JMP TiaSet
TiaNoise:
    LDA S_SN+1
    CMP #$07
    BCS TiaNoiseLow         ; N >> 6 >= 28: the slowest
    ASL S_SN
    ROL A
    ASL S_SN
    ROL A                   ; N >> 6
    TAY
    LDA SND_NOISE,Y
    JMP TiaNoiseSet
TiaNoiseLow:
    LDA #$1F
TiaNoiseSet:
    STA S_SF
    LDA #$08                ; 9-bit polynomial noise
TiaSet:
    STA AUDC0,X
    LDA S_SF
    STA AUDF0,X
    LDA S_SVOL
    STA AUDV0,X
    RTS

; the three mode-8 rows (40 wide, 4 colour clocks a pixel) at the top of
; some scenes' lists: the first 30 bytes of the buffer, each 2-bit pixel
; widened to a whole 160A byte. Runs in the NMI on every buffer flip, so it
; widens only the bytes that changed since the last time (both buffers
; normally hold the same status rows), a nibble at a time from two 16-byte
; tables, with scratch of its own (S_M8*; S_TMP is the loaders').
Mode8:
    LDA ZP_P1               ; runs inside the NMI: keep the game's $00/$01
    PHA
    LDA ZP_P1+1
    PHA
    JSR Mode8Go0
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS
Mode8Go0:
    LDX S_DLIDX
    LDA DLT_BUF,X
    BNE Mode8B
    LDA #<FBA_ROW0
    STA ZP_P1
    LDA #>FBA_ROW0
    STA ZP_P1+1
    JMP Mode8Go
Mode8B:
    LDA #<FBB_ROW0
    STA ZP_P1
    LDA #>FBB_ROW0
    STA ZP_P1+1
Mode8Go:
    LDX #$00                ; output index, 4 per input byte
    LDY #$00                ; input index
Mode8Byte:
    LDA (ZP_P1),Y
    CMP S_M8COPY,Y
    BEQ Mode8Next
    STA S_M8COPY,Y
    STA S_M8B
    STY S_M8Y
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    LDA M8NIB_HI,Y
    STA MODE8_ROWS,X
    LDA M8NIB_LO,Y
    STA MODE8_ROWS+1,X
    LDA S_M8B
    AND #$0F
    TAY
    LDA M8NIB_HI,Y
    STA MODE8_ROWS+2,X
    LDA M8NIB_LO,Y
    STA MODE8_ROWS+3,X
    LDY S_M8Y
Mode8Next:
    INX
    INX
    INX
    INX
    INY
    CPY #30
    BNE Mode8Byte
    RTS

;;; SCENEPAGE -- assembled at $9420 and placed in every scene page (free
;;; in all six); runs only with a scene page in (never during a blit); the
;;; jump table must stay first (link7800.py SCENEPAGE_ENTRIES)
ScStClear:
    JMP StClear
ScStPlayer:
    JMP StPlayer
ScStFoe:
    JMP StFoe
ScStFlipL:
    JMP StFlipL
ScStCopy:
    JMP StCopy
ScColA:
    JMP ColA
ScCol68:
    JMP Col68

; The status bar: the game clears the status row ($0B27) and draws the
; player's arrows ($0B3E, $B6 of them) and the foe's ($0B98, $B7), once for
; every picture, into the buffer being drawn -- about a quarter of all the
; drawing in a fight, for a row that changes only when someone is hit or
; heals. What a buffer's row shows is decided by $B6, $B7 and which buffer
; it is (below 3 the arrows are drawn into one buffer only: they blink). So
; each buffer remembers what it shows (S_STP, S_STF), and a picture that
; would draw the same again draws nothing:
;  - the clear: if the player's side matches, defer it (and skip);
;  - the player's arrows: skipped while deferred;
;  - the foe's: skipped if they match too; if not, the clear, the player's
;    arrows and the foe's now, in the game's order;
;  - the picture's end ($B60F): if the foe's arrows were not drawn this
;    picture but the buffer shows some, the clear and the player's arrows.
; Other drawing that reaches the status rows (RowBase, the full clear, the
; buffer copy, a scene load) makes the buffer's memory stale. FINDINGS "The
; health arrows, drawn only when they change".
StIdx:                      ; X = the buffer being drawn: 0 A, 1 B
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE StIdxA
    INX
StIdxA:
    RTS

StClear:
    JSR StIdx
    LDA S_STTOUCH
    BNE StClearNow          ; drawn over since: redraw
    LDA S_STP,X
    CMP G_ZB6
    BNE StClearNow
    LDA #$01
    STA S_STDEF             ; the player's side already shows this
    RTS
StClearNow:
    JSR StWipe
    RTS

StPlayer:
    LDA S_STDEF
    BEQ StDrawP             ; the clear was done: draw
    JSR StIdx
    LDA S_STP,X
    CMP G_ZB6
    BEQ StDone              ; already shown
    JSR StWipe              ; (the health changed since the clear)
StDrawP:
    JSR StIdx
    LDA G_ZB6
    STA S_STP,X
    INC S_STINS
    JSR G_L0B3E
    DEC S_STINS
StDone:
    RTS

StFoe:
    LDA #$01
    STA S_STFSEEN
    LDA S_STDEF
    BEQ StDrawF
    JSR StIdx
    LDA S_STTOUCH
    BNE StFoeRedo
    LDA S_STF,X
    CMP G_ZB7
    BEQ StDone              ; both sides already shown
StFoeRedo:
    JSR StWipe
    JSR StDrawP
StDrawF:
    JSR StIdx
    LDA G_ZB7
    STA S_STF,X
    INC S_STINS
    JSR G_L0B98
    DEC S_STINS
    RTS

StFlipL:                    ; $B60F's first instruction, after the cache
    JSR StFlip
    LDA G_L0AFE
    RTS

StCopy:                     ; $AD80, which copies one buffer into the other
    LDA #$FF
    STA S_STP
    STA S_STP+1
    JMP G_LB60F

StFlip:                     ; the picture is done (before $B60F flips)
    LDA S_STDEF
    BEQ StFlipEnd
    JSR StIdx
    LDA S_STTOUCH
    BNE StFlipRedo
    LDA S_STFSEEN
    BNE StFlipEnd           ; the foe's arrows were drawn or matched
    LDA S_STF,X
    CMP #$FE
    BEQ StFlipEnd           ; none shown, none wanted
StFlipRedo:
    JSR StWipe
    JSR StDrawP
    LDA S_STFSEEN
    BEQ StFlipEnd
    JSR StDrawF
StFlipEnd:
    LDA S_STTOUCH
    BEQ StFlipOk
    JSR StIdx               ; drawn over after the status bar: stale
    LDA #$FF
    STA S_STP,X
StFlipOk:
    LDA #$00
    STA S_STDEF
    STA S_STFSEEN
    STA S_STTOUCH
    RTS

StWipe:                     ; the game's clear, now; nothing shown after it
    JSR StIdx
    LDA #$00
    STA S_STDEF
    STA S_STTOUCH
    LDA #$FF
    STA S_STP,X
    LDA #$FE
    STA S_STF,X
    INC S_STINS
    JSR G_L0B27
    DEC S_STINS
    RTS

; PORTA as the XEGS reads it (stick 1 low nibble, stick 2 high, active
; low, same bit order: SWCHA with its nibbles swapped). With the left
; difficulty switch at A, "quick stick": a push that ended since the last
; look is handed over once when the stick reads centred.
ReadStick:
    LDA S_RSWCHA            ; this frame's reading (Inputs)
    ASL A
    ADC #$80
    ROL A
    ASL A
    ADC #$80
    ROL A
    STA S_PORTA
    LDA S_RSWCHB
    AND #$40
    BEQ ReadStickLive
    LDA S_PORTA
    AND #$0F
    CMP #$0F
    BNE ReadStickLive
    LDA S_LATCH
    CMP #$FF
    BEQ ReadStickLive
    LDA S_PORTA
    AND #$F0
    ORA S_LATCH
    STA S_PORTA
ReadStickLive:
    LDA #$FF
    STA S_LATCH
    LDA S_PORTA
    RTS
;;; END SCENEPAGE
;;; LEVEL1PAGE -- placed in level 1's scene pages only (scenes 1 and 6, the
;;; banks with the column loops), wherever both have room; the scene page's
;;; jump table (ScColA, ScCol68) leads here, and only level 1 calls it
; Level 1's posts and pillars: its scenery code draws each as a column of
; 1- or 2-row pieces, 2 rows apart, in a loop (INC $06 / INC $06 / JSR piece
; / LDA $06 / CMP #lim / BCC), one whole blit call a piece -- about 800
; cycles each for a few bytes, and a pillar off screen is clipped away 50
; times over. The loops call here instead, with A = the limit (layout7800
; COLUMN_LOOPS). The first piece and the last are drawn by the game's
; blitter; the ones between are copies of the first, 2 rows further down
; each time, keeping of the screen exactly the pixels the blitter keeps (in
; its store mode: the first byte's left of the shift, unless clipped at the
; left, and the edge byte's right of it). The last piece being the game's,
; everything a blit leaves behind is as the loop left it. Other cases (the
; OR and AND modes, 3 rows or more, wider than 8 bytes, a template piece
; not wholly on screen) go the game's way, piece by piece. FINDINGS "The
; tiny sprites are columns".
Col68:                      ; the loops through $6E68: blitter C while $52 is
    STA S_CLIM              ; negative or below $14 (keeping $05), else A
    LDA G_Z52
    BMI ColC
    CMP #$14
    BCC ColC
    LDA S_CLIM
    JMP ColA
ColC:
    INC G_Z06
    INC G_Z06
    LDA G_Z05
    PHA
    JSR G_L280C
    PLA
    STA G_Z05
    LDA G_Z06
    CMP S_CLIM
    BCC ColC
    RTS

ColA:
    STA S_CLIM
    STX S_CX
    STY S_CY
    LDA G_Z06
    CLC
    ADC #$02
    STA G_Z06
    JSR G_L284E             ; the first piece
    LDA G_Z06
    CMP S_CLIM
    BCS ColDone             ; the only one
    JSR ColTemplate
    BCS ColPlain
ColNext:
    LDA G_Z06
    CLC
    ADC #$02
    STA G_Z06
    CMP S_CLIM
    BCS ColLast
    JSR ColPiece
    LDA G_Z14               ; the next piece: 2 rows down
    CLC
    ADC #80
    STA G_Z14
    BCC ColNext
    INC G_Z15
    JMP ColNext
ColLast:
    JSR G_L284E             ; the last piece
    JMP ColDone
ColPlain:
    INC G_Z06
    INC G_Z06
    JSR G_L284E
    LDA G_Z06
    CMP S_CLIM
    BCC ColPlain
ColDone:
    LDX S_CX
    LDY S_CY
    RTS

; after the first piece: carry clear if the copy covers it, with S_CNONE
; (nothing drawn: wholly off screen), or the template (S_CH rows of S_CNB
; bytes, S_CK and S_CT) and $14/$15 at the next piece; carry set if not
ColTemplate:
    LDA G_Z0F
    BEQ ColBad
    BMI ColBad              ; the store mode only
    LDA #$00
    STA S_CNONE
    LDA G_Z05
    BMI ColTLeft
    CMP #40
    BCS ColTNone            ; right of the screen
    BCC ColTOn
ColTLeft:
    CLC
    ADC G_Z1F
    BCS ColTOn              ; partly on screen
ColTNone:
    LDA #$01                ; wholly off: the blitter drew nothing
    STA S_CNONE
    CLC
    RTS
ColBad:
    SEC
    RTS
ColTOn:
    LDA G_Z06
    SEC
    SBC #$23                ; the row
    CMP #FB_ROWS
    BCS ColBad
    STA S_CR
    LDA G_Z0D
    CMP #$03
    BCS ColBad              ; at most 2 rows
    STA S_CH
    CLC
    ADC S_CR
    CMP #FB_ROWS
    BCS ColBad              ; to the last row: RowBase may have cut it short
    LDA G_Z05
    CLC
    ADC G_Z1F
    LDX #$00                ; the edge byte: when the sprite ends left of 40
    CMP #40
    BCS ColTNoEdge
    INX
ColTNoEdge:
    STX S_CJ
    TXA
    CLC
    ADC G_Z0E               ; bytes a row: the visible width, and the edge
    BEQ ColBad
    CMP #$09
    BCS ColBad              ; at most 8
    STA S_CNB
    LDX #$0F
    LDA #$00
ColTK0:
    STA S_CK,X
    DEX
    BPL ColTK0
    LDA G_Z10
    LSR A
    TAY                     ; the shift
    LDA G_Z16
    BNE ColTNoFirst         ; clipped at the left: the first byte is all sprite
    LDA G_Z0E
    BEQ ColTNoFirst
    LDA ColMask1,Y
    STA S_CK
    STA S_CK+8
ColTNoFirst:
    LDA S_CJ
    BEQ ColTNoEdgeK
    LDX S_CNB
    LDA ColMask2,Y
    STA S_CK-1,X
    STA S_CK+7,X
ColTNoEdgeK:
    LDA S_CR
    JSR ColRow              ; the first piece's first row
    LDX #$00
    LDY #$00
    LDA S_CH
    STA S_CHH
ColTRow:
    LDA S_CNB
    STA S_CJ
ColTByte:
    LDA S_CK,X
    EOR #$FF
    AND (G_Z14),Y
    STA S_CT,X
    INX
    INY
    DEC S_CJ
    BNE ColTByte
    LDX #$08                ; row 2
    LDY #40
    DEC S_CHH
    BNE ColTRow
    LDA G_Z14               ; the next piece: 2 rows down
    CLC
    ADC #80
    STA G_Z14
    BCC ColTEnd
    INC G_Z15
ColTEnd:
    CLC
    RTS

;;; PART -- placed on its own (no branch crosses into it)
; one piece, at row $06 - $23 from $14/$15, cut at the bottom as RowBase
; cuts it (and skipped, as RowBase sends it to its scratch row, when it
; starts below the bottom or above the top)
ColPiece:
    LDA S_CNONE
    BNE ColPRet
    LDA G_Z06
    SEC
    SBC #$23
    CMP #FB_ROWS
    BCS ColPRet
    STA S_CR
    LDA #FB_ROWS
    SEC
    SBC S_CR                ; rows to the bottom
    CMP S_CH
    BCC ColPFit
    LDA S_CH
ColPFit:
    STA S_CHH
    CLC
    ADC S_CR
    CMP #ST_ROW+1           ; the status bar's cache, as RowBase
    BCC ColPNoSt
    LDA S_STINS
    BNE ColPNoSt
    LDA #$01
    STA S_STTOUCH
ColPNoSt:
    LDX #$00
    LDY #$00
ColPRow:
    LDA S_CNB
    STA S_CJ
ColPByte:
    LDA (G_Z14),Y
    AND S_CK,X
    ORA S_CT,X
    STA (G_Z14),Y
    INX
    INY
    DEC S_CJ
    BNE ColPByte
    LDX #$08
    LDY #40
    DEC S_CHH
    BNE ColPRow
ColPRet:
    RTS

ColMask1:                   ; the blitter's $2981: kept left of the shift
    .byte $00,$C0,$F0,$FC
ColMask2:                   ; its $2985: kept right of it, in the edge byte
    .byte $FF,$3F,$0F,$03

;;; PART
; $14/$15 = row A of the buffer being drawn, at the blit's column $1E
ColRow:
    STA G_Z14
    LDA #$00
    STA G_Z15
    LDA G_Z14
    ASL A
    ROL G_Z15
    ASL A
    ROL G_Z15
    CLC
    ADC G_Z14               ; 5r
    BCC ColRow5
    INC G_Z15
ColRow5:
    ASL A
    ROL G_Z15
    ASL A
    ROL G_Z15
    ASL A
    ROL G_Z15               ; 40r
    CLC
    ADC G_Z1E
    BCC ColRowC
    INC G_Z15
ColRowC:
    LDX #$00                ; the buffer: 0 A, 1 B
    LDY G_Z07
    CPY #$20
    BNE ColRowA
    INX
ColRowA:
    CLC
    ADC ColBaseL,X
    STA G_Z14
    LDA G_Z15
    ADC ColBaseH,X
    STA G_Z15
    RTS
ColBaseL:
    .byte <FBA_ROW0,<FBB_ROW0
ColBaseH:
    .byte >FBA_ROW0,>FBB_ROW0
;;; END LEVEL1PAGE
;;; RAMFILL -- assembled at $7203 (cart RAM free between the engine's two
;;; parts) and copied there at load (CopyFill); the jump table must stay
;;; first (link7800.py RAMFILL_ENTRIES)
; The fills: the game's rectangle ($2CCD) and pattern ($2D03) fills store
; row by row, STA ($14),Y / DEY / BPL, 11 cycles a byte. Here the rows go 4
; at a time into the engine's store block at $2D19 (STA row,X for each of 4
; rows, DEX, BPL), whose row addresses are written in first, so each byte
; costs 5 cycles; the columns loop. A fill never reads the buffer, so the
; order of the stores can't change what it leaves. It leaves $14/$15 at the
; last row and Y = $FF, as the game's loops do. Being in RAM, it jumps
; through its own JMPs (FpJmp, FpGo), written as it goes. FINDINGS "The
; fast fill".
RfPass:
    JMP FillPass
RfPattern:
    JMP FillPat

; the pattern: rows alternate $12 and $02, the last row $02 (the game's X
; counts the rows down: odd $02, even $12). The $12 rows first, then the $02
; rows, each 80 bytes apart, so the last pass ends at the last row
FillPat:
    LDA #80
    STA S_FSTRIDE
    LDA G_Z12
    STA S_FVAL
    LDA G_Z14
    STA S_FP0
    LDA G_Z15
    STA S_FP0+1
    LDA G_Z0D
    LSR A
    STA S_FCOUNT            ; $12 rows: half, rounded down
    BCC FpEvenH             ; an even count: from the first row
    LDA G_Z14               ; odd: from the second (carry set: +40)
    ADC #39
    STA G_Z14
    BCC FpEvenH
    INC G_Z15
FpEvenH:
    JSR FillPass
    LDA G_Z0D
    LSR A
    ADC #$00
    STA S_FCOUNT            ; $02 rows: half, rounded up
    LDA G_Z02
    STA S_FVAL
    LDA G_Z0D
    LSR A
    LDA S_FP0
    LDX S_FP0+1
    BCS FpSecond            ; an odd count: from the first row
    ADC #40                 ; even: from the second
    BCC FpSecond
    INX
FpSecond:
    STA G_Z14
    STX G_Z15
    JSR FillPass
    JMP G_L2D3E

; S_FCOUNT rows of S_FVAL from $14/$15, S_FSTRIDE apart, $0E+1 bytes each;
; leaves $14/$15 at the last row and Y = $FF. The rows over a multiple of 4
; first (entering the block part way), then whole blocks of 4
FillPass:
    LDA S_FCOUNT
    AND #$03
    BEQ FpFull
    EOR #$FF
    SEC
    ADC #$04
    TAX                     ; the first of the block's 4 stores used
    LDA FpPatchLo,X
    STA FpJmp+1
    STX S_FT
    TXA
    ASL A
    ADC S_FT                ; 3 bytes a store
    ADC #<FILL_BLK
    STA FpGo+1
    SEC
    SBC #<FILL_NEXT
    STA FILL_BPL            ; the loop starts at the first store used
    JSR FpOne
FpFull:
    LDA S_FCOUNT
    LSR A
    LSR A
    STA S_FK                ; whole blocks
    BEQ FpDone
    LDA #<FpPatch0
    STA FpJmp+1
    LDA #<FILL_BLK
    STA FpGo+1
    SEC
    SBC #<FILL_NEXT
    STA FILL_BPL
FpFullLoop:
    JSR FpOne
    DEC S_FK
    BNE FpFullLoop
FpDone:
    LDA G_Z14               ; back one stride: the last row
    SEC
    SBC S_FSTRIDE
    STA G_Z14
    BCS FpDoneHi
    DEC G_Z15
FpDoneHi:
    LDY #$FF
    RTS

; one block: its rows' addresses into the store block, then the block (its
; RTS returns from here); $14/$15 move on to the next block's first row
FpOne:
    LDA G_Z14
    LDY G_Z15
FpJmp:
    JMP FpPatch0
FpPatch0:
    STA FILL_BLK+1
    STY FILL_BLK+2
    CLC
    ADC S_FSTRIDE
    BCC FpPatch1
    INY
FpPatch1:
    STA FILL_BLK+4
    STY FILL_BLK+5
    CLC
    ADC S_FSTRIDE
    BCC FpPatch2
    INY
FpPatch2:
    STA FILL_BLK+7
    STY FILL_BLK+8
    CLC
    ADC S_FSTRIDE
    BCC FpPatch3
    INY
FpPatch3:
    STA FILL_BLK+10
    STY FILL_BLK+11
    CLC
    ADC S_FSTRIDE
    BCC FpPatched
    INY
FpPatched:
    STA G_Z14
    STY G_Z15
    LDX G_Z0E
    LDA S_FVAL
FpGo:
    JMP FILL_BLK
FpPatchLo:
    .byte <FpPatch0,<FpPatch1,<FpPatch2,<FpPatch3
;;; END RAMFILL

;;; FAR (RowBase) -- each ;;; FAR piece below is assembled on its own and
;;; placed in a free gap of the fixed bank (the system block above has no room
;;; left); a piece may use equates but not labels from above or from another
;;; piece, and the block above reaches it through equates the build supplies
;
; RowBase: the start of the game's $2D46 (row Y - 35, times 40, into $14/$15;
; the game's code after the call adds the buffer $07 names), with the bottom
; check it lacks. The blitters and fills that call it draw $0D rows 40 bytes
; apart from there; a draw that ran past row 153 wrote over whatever follows
; the buffer (on the 7800, the engine). So $0D is cut to the rows left, and a
; draw that starts at or past the bottom -- or above the top, where Y - 35
; wraps to a large row, as on the XEGS -- draws its one row into the scratch
; row instead, returning straight to $2D46's caller. Nothing that reaches the
; screen changes. Every blit and fill sets $0D afresh before calling here.
RowBase:
    LDA G_Z06
    SEC
    SBC #$23                ; the row
    CMP #FB_ROWS
    BCS RowOff
    STA G_L2DA1             ; the multiplier's input, as the original
    LDA #FB_ROWS
    SEC
    SBC G_L2DA1             ; rows from here to the bottom
    CMP G_Z0D
    BCS RowFits
    STA G_Z0D               ; would run past the bottom: stop there
RowFits:
    LDA G_L2DA1
    CLC
    ADC G_Z0D
    CMP #ST_ROW+1           ; reaches the status rows?
    BCC RowNotStatus
    LDA S_STINS
    BNE RowNotStatus        ; the status bar's own drawing
    LDA #$01
    STA S_STTOUCH           ; the status bar's cache is stale for this buffer
RowNotStatus:
    LDA #$28
    STA G_L2DA2
    JMP G_L2D78             ; row * 40; its RTS goes back into $2D46
RowOff:
    PLA                     ; not back into $2D46: to its caller, with
    PLA                     ; the scratch row as the address
    LDA #$01
    STA G_Z0D
    LDA #<CLIPROW
    STA G_Z14
    LDA #>CLIPROW
    STA G_Z15
    RTS

;;; FAR (StClr)
; the game's full clear ($280F) starts here (its first four bytes, LDA $07 /
; CMP #$20, replaced by JSR SysStClr / NOP): it wipes the buffer's status rows
; too, so the status bar's cache is stale for it
StClr:
    LDA #$01
    STA S_STTOUCH
    LDA G_Z07
    CMP #$20
    RTS

;;; FAR (CopyFill)
; the fast fill's code into cart RAM ($7203), with the art bank in (the
; loader, after the engine's two parts)
CopyFill:
    LDA #<IMG_RAMFILL
    STA ZP_P1
    LDA #>IMG_RAMFILL
    STA ZP_P1+1
    LDA #<RAMFILL_AT
    STA ZP_P2
    LDA #>RAMFILL_AT
    STA ZP_P2+1
    LDA #<LEN_RAMFILL
    LDX #>LEN_RAMFILL
    JMP Copy
