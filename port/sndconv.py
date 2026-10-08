#!/usr/bin/env python3
"""Karateka's POKEY sound on TIA: the conversion rule, and WAVs to judge it by.

    python port/sndconv.py work/analysis/pkyattract/pokey.log -o work/analysis/snd \
        [--offsets 0,274,522] [--frames 0-2500]

The game plays two voices, each a pair of POKEY channels joined into a 16-bit
divider on the 1.79 MHz clock (AUDCTL $78): a distortion ($A0 pure tone, or $00
noise), a 4-bit volume and a divider N, pitch 1789790 / (2 (N + 7)). TIA has two
channels, so each voice gets one:

  - a tone becomes the nearest TIA tone (AUDC 4, C or 6) to its pitch moved by
    a global offset in cents (TIA's pitches are sparse and fixed, so the offset
    that best fits the score onto them is a choice, not a correction);
  - noise becomes TIA's 9-bit noise (AUDC 8) at the nearest rate;
  - the volume passes through (both are 4-bit and linear).

Input: probes/xe-pokey.log lines "frame flip reg value pc". Output: orig.wav
(the POKEY model) and tia<offset>.wav per offset, in the output directory.
"""
import argparse
import math
import os
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
# (the WAVs only: the build's tables don't use the toolkit)
sys.path.insert(0, os.path.join(HERE, "..", "..", "a7800-toolkit-local", "tools"))
import tracker as T  # noqa: E402

POKEY_CLOCK = 1789790.0
TONE_MODES = (0x4, 0xC, 0x6)
NOISE_MODE = 0x8
FRAME_RATE = 60.0


def frames(path, lo=0, hi=None):
    """The POKEY registers at the end of each frame: {frame: [9 registers]}."""
    regs, out, last = [0] * 9, {}, None
    for line in open(path):
        f, _k, r, v, _pc = line.split()
        f = int(f)
        if last is not None and f != last:
            out[last] = list(regs)
        regs[int(r, 16)] = int(v, 16)
        last = f
    if last is not None:
        out[last] = list(regs)
    first, end = min(out), max(out)
    full, cur = [], [0] * 9
    for f in range(first, end + 1):
        cur = out.get(f, cur)
        if f >= lo and (hi is None or f < hi):
            full.append(cur)
    return full


def voices(regs):
    """The two voices of one frame: (distortion byte, volume, 16-bit divider)."""
    return [(regs[c] & 0xF0, regs[c] & 0x0F, regs[h] * 256 + regs[l])
            for l, h, c in ((0, 2, 3), (4, 6, 7))]


def pokey_pitch(n):
    return POKEY_CLOCK / (2 * (n + 7))


# TIA pitch: the clock over (AUDF + 1) and the waveform's period in divider
# ticks, as measured on MAME (the toolkit's tracker.py after its 2026-09-25
# correction -- it had AUDC C and 6 an octave low, FINDINGS "TIA sound"; the
# public toolkit doesn't carry it yet, so the build keeps its own copy of the
# three tone modes and the clock)
TIA_CLOCK = 31400.0                     # NTSC
TIA_PERIOD = {0x4: 2, 0xC: 6, 0x6: 31}


def tia_pitch(audc, audf):
    return TIA_CLOCK / ((audf + 1) * TIA_PERIOD[audc])


def tia_tones():
    """The TIA tones, highest first, one per distinct pitch (AUDC 4 before C
    before 6 where two modes give the same one)."""
    seen, out = set(), []
    for fr, a, f in sorted(((tia_pitch(a, f), TONE_MODES.index(a), f) for a in TONE_MODES
                            for f in range(32)), key=lambda t: (-t[0], t[1])):
        key = round(fr, 6)
        if key not in seen:
            seen.add(key)
            out.append((fr, TONE_MODES[a], f))
    return out


def ultrasonic_n(offset):
    """Dividers below this play above 16 kHz after the offset: silent."""
    return int(POKEY_CLOCK * 2 ** (offset / 1200.0) / (2 * 16000.0) - 7) + 1


def noise_audf(n):
    """TIA noise AUDF for a POKEY noise divider, by N >> 6 (the runtime table)."""
    k = n >> 6
    if k >= 28:
        return 31
    rate = POKEY_CLOCK / (k * 64 + 32 + 7)
    return max(0, min(31, int(round(TIA_CLOCK / rate - 1))))


def tables(offset):
    """The runtime tables for the port (build7800.py places them).

    SND_NBLO/HI: the dividers at which the nearest TIA tone changes, ascending
    (N below the first -> tone 0, the highest); SND_TONE: each tone packed as
    mode index << 5 | AUDF; SND_MODE: the AUDC of each mode index; SND_NOISE:
    noise AUDF by N >> 6. "=" entries are equates, not data."""
    tones = tia_tones()
    shift = 2 ** (offset / 1200.0)
    nb = []
    for (f1, _a1, _x1), (f2, _a2, _x2) in zip(tones, tones[1:]):
        fb = math.sqrt(f1 * f2) / shift            # the boundary, as a POKEY pitch
        nb.append(max(0, min(0xFFFF, int(math.ceil(POKEY_CLOCK / (2 * fb) - 7)))))
    return {
        "SND_NBLO": bytes(n & 0xFF for n in nb),
        "SND_NBHI": bytes(n >> 8 for n in nb),
        "SND_TONE": bytes(TONE_MODES.index(a) << 5 | f for _fr, a, f in tones),
        "SND_MODE": bytes(TONE_MODES),
        "SND_NOISE": bytes(noise_audf(k * 64) for k in range(28)),
        "=SND_NB": len(nb),
        "=SND_ULTRA": ultrasonic_n(offset),
    }


_TI = {}


def tone_index(n, offset):
    """What the runtime search returns for a divider: how many boundaries are
    at or below it."""
    if (n, offset) not in _TI:
        t = tables(offset)
        nb = [lo | hi << 8 for lo, hi in zip(t["SND_NBLO"], t["SND_NBHI"])]
        _TI[(n, offset)] = sum(1 for b in nb if n >= b)
    return _TI[(n, offset)]


def to_tia(dist, vol, n, offset, tones):
    """One voice as TIA (AUDC, AUDF, AUDV)."""
    if vol == 0:
        return 0, 0, 0
    if dist == 0xA0:
        if n < ultrasonic_n(offset):          # ultrasonic (N = 0): silent
            return 0, 0, 0
        _ft, a, f = tones[tone_index(n, offset)]
        return a, f, vol
    # noise: TIA's 9-bit polynomial clocked at 31400 / (AUDF + 1)
    return NOISE_MODE, noise_audf(n), vol


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(T.SAMPLE_RATE)
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))


def render_pokey(fr):
    per = int(T.SAMPLE_RATE / FRAME_RATE)
    out = [0.0] * (per * len(fr))
    for v in range(2):
        st = None
        for i, regs in enumerate(fr):
            dist, vol, n = voices(regs)[v]
            if vol == 0 or (dist == 0xA0 and pokey_pitch(n) > 16000):
                continue
            s, st, _e = T.pokey_channel(3 if v else 1, dist | vol, 0, 0x78, per, state=st,
                                        rate=POKEY_CLOCK / (n + 7))
            g = vol / 15.0 * 0.4
            for k in range(per):
                out[i * per + k] += s[k] * g
    return out


def render_tia(fr, offset):
    per = int(T.SAMPLE_RATE / FRAME_RATE)
    tones = tia_tones()
    out = [0.0] * (per * len(fr))
    for v in range(2):
        phase = 0.0
        for i, regs in enumerate(fr):
            a, f, vol = to_tia(*voices(regs)[v], offset=offset, tones=tones)
            if vol == 0:
                continue
            s, phase = T.channel(a, f, per, phase)
            g = vol / 15.0 * 0.4
            for k in range(per):
                out[i * per + k] += s[k] * g
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--offsets", default="0,274,522")
    ap.add_argument("--frames", default="0-")
    a = ap.parse_args()
    lo, _, hi = a.frames.partition("-")
    fr = frames(a.log, int(lo or 0), int(hi) if hi else None)
    os.makedirs(a.out, exist_ok=True)
    write_wav(os.path.join(a.out, "orig.wav"), render_pokey(fr))
    for off in (int(x) for x in a.offsets.split(",")):
        write_wav(os.path.join(a.out, "tia%+d.wav" % off), render_tia(fr, off))
    print("%d frames (%.1f s) -> %s" % (len(fr), len(fr) / FRAME_RATE, a.out))


if __name__ == "__main__":
    main()
