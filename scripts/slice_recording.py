#!/usr/bin/env python3
"""Turn a recording of someone typing into a Clackey sound pack.

    python3 scripts/slice_recording.py <recording> "<Pack Name>" [--downs 8] [--ups 5] [--credit "text"]
    python3 scripts/slice_recording.py <mouse recording> --mouse [--credit "text"]   # shared click sounds

Works with anything macOS can decode (WAV, FLAC, AIFF, MP3, M4A...). The file is converted
to 44.1 kHz mono with `afconvert`, then:

  1. find keystroke onsets: sharp jumps in short-time energy above the noise floor
  2. classify: a loud onset after a quiet gap is a key press ("down"); a quieter onset
     30-250 ms after a press is its release ("up")
  3. keep only well-isolated events (nothing else ringing over them), drop loudness
     outliers, and pick the most consistent ones
  4. the lowest, longest-ringing presses are likely the spacebar
  5. trim each slice where it decays into the noise floor, fade the edges, and normalize

Output: Resources/Packs/<Pack Name>/{down,up,space}-N.wav plus CREDITS.txt.
Re-run with different --downs/--ups or thresholds if a slice sounds off; listen to the results
in Clackey (Sound Pack menu) or with `afplay`.
"""
import argparse
import math
import os
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HOP = 44            # ~1 ms analysis frames
PRE_ROLL = 0.004    # keep 4 ms before the onset so the attack isn't clipped


def load_mono(path):
    """Decode any macOS-supported audio to 44.1 kHz mono 16-bit and return floats."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "in.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", "-c", "1", path, out],
                       check=True, capture_output=True)
        with wave.open(out) as w:
            n = w.getnframes()
            data = struct.unpack(f"<{n}h", w.readframes(n))
    return [v / 32768.0 for v in data]


def frame_energy(x):
    return [math.sqrt(sum(v * v for v in x[i:i + HOP]) / HOP) for i in range(0, len(x) - HOP, HOP)]


def find_onsets(env, sensitivity):
    # Onset gate uses the median level; the true room-noise floor (used for trimming) is the
    # 10th percentile, since continuous typing keeps the median well above the noise.
    floor = statistics.median(env) + 1e-6
    onsets = []
    last = -10_000
    for i in range(10, len(env)):
        recent = sum(env[i - 10:i - 2]) / 8 + 1e-6
        if env[i] > floor * sensitivity and env[i] > recent * 4 and i - last > 25:
            # walk forward to the local peak (within 6 ms) for a stable loudness measure
            peak = max(env[i:i + 6])
            onsets.append({"frame": i, "peak": peak})
            last = i
    room = sorted(env)[len(env) // 10] + 1e-6
    return onsets, room


def slice_event(x, env, floor, ev, next_frame, max_len):
    start = max(0, ev["frame"] * HOP - int(PRE_ROLL * SR))
    hard_end = min(len(x), next_frame * HOP - int(0.002 * SR), start + int(max_len * SR))
    # end once the ring has decayed 30 dB below its peak (or into the room noise) for 8 ms,
    # never before 50 ms
    gate = max(floor * 2.5, ev["peak"] * 10 ** (-30 / 20))
    end = hard_end
    f = ev["frame"] + 50
    while f < hard_end // HOP - 8:
        if max(env[f:f + 8]) < gate:
            end = f * HOP + 8 * HOP
            break
        f += 1
    seg = x[start:end]
    fade_in, fade_out = int(0.001 * SR), int(0.006 * SR)
    for i in range(min(fade_in, len(seg))):
        seg[i] *= i / fade_in
    for i in range(min(fade_out, len(seg))):
        seg[-1 - i] *= i / fade_out
    return seg


def has_second_hit(seg):
    """True if another keystroke starts inside the slice's tail (sharp rise after the peak)."""
    env = frame_energy(seg)
    if len(env) < 30:
        return False
    pk = max(env)
    ipk = env.index(pk)
    for i in range(ipk + 15, len(env)):
        before = min(env[max(0, i - 10):i]) + 1e-6
        if env[i] > pk * 0.3 and env[i] / before > 4:
            return True
    return False


def brightness(seg):
    """Zero-crossing rate: a cheap proxy for spectral brightness."""
    return sum(1 for a, b in zip(seg, seg[1:]) if (a < 0) != (b < 0)) / max(1, len(seg))


def write(path, seg, peak):
    m = max((abs(v) for v in seg), default=0) or 1.0
    s = peak / m
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * s)) * 32767)) for v in seg))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recording")
    ap.add_argument("name", nargs="?", default="Mouse")
    ap.add_argument("--mouse", action="store_true",
                    help="recording of mouse clicks -> Resources/Mouse/mousedown-N / mouseup-N")
    ap.add_argument("--downs", type=int, default=8)
    ap.add_argument("--ups", type=int, default=5)
    ap.add_argument("--spaces", type=int, default=2)
    ap.add_argument("--sensitivity", type=float, default=6.0, help="onset threshold × noise floor")
    ap.add_argument("--credit", default="", help="attribution / license line for CREDITS.txt")
    ap.add_argument("--out", default=os.path.join(ROOT, "Resources", "Packs"))
    a = ap.parse_args()
    if a.mouse:
        a.spaces = 0
        a.downs = min(a.downs, 4)
        a.ups = min(a.ups, 4)

    x = load_mono(a.recording)
    env = frame_energy(x)
    onsets, floor = find_onsets(env, a.sensitivity)
    print(f"{len(x) / SR:.1f}s audio, noise floor {20 * math.log10(floor):.1f} dBFS, {len(onsets)} onsets")
    if len(onsets) < 6:
        sys.exit("Too few keystrokes found. Try a lower --sensitivity.")

    # Classify presses and releases.
    downs, ups = [], []
    for i, ev in enumerate(onsets):
        prev = onsets[i - 1] if i else None
        nxt = onsets[i + 1]["frame"] if i + 1 < len(onsets) else len(env)
        ev["gap_after"] = nxt - ev["frame"]
        ev["next"] = nxt
        gap_before = ev["frame"] - prev["frame"] if prev else 10_000
        if a.mouse and prev and prev in downs and 30 <= gap_before <= 250:
            ups.append(ev)          # mouse release can be as loud as the press: pair by timing
        elif prev and 30 <= gap_before <= 250 and ev["peak"] < prev["peak"] * 0.7 and prev in downs:
            ups.append(ev)
        elif gap_before >= 120:
            downs.append(ev)

    # Keep isolated events with typical loudness (drop the outliers at both ends).
    def pick(events, count, min_gap, max_len):
        good = [e for e in events if e["gap_after"] >= min_gap]
        if len(good) < count:
            good = sorted(events, key=lambda e: -e["gap_after"])[:max(count * 2, 1)]
        good.sort(key=lambda e: e["peak"])
        trimmed = good[len(good) // 10: len(good) - len(good) // 10] or good
        med = statistics.median(e["peak"] for e in trimmed)
        trimmed.sort(key=lambda e: abs(math.log(e["peak"] / med)))   # most typical first
        chosen = []
        for e in trimmed:                       # skip slices with another key bleeding in
            seg = slice_event(x, env, floor, e, e["next"], max_len)
            if not has_second_hit(seg):
                chosen.append((e["frame"], seg, e))
            if len(chosen) == count:
                break
        chosen.sort(key=lambda c: c[0])
        return [c[1] for c in chosen], [c[2] for c in chosen]

    down_segs, down_evs = pick(downs, a.downs + a.spaces * 3, 130, 0.18)
    # Spacebar candidates: darkest + longest of the isolated presses.
    scored = sorted(zip(down_segs, down_evs), key=lambda p: brightness(p[0]) / (len(p[0]) ** 0.5))
    space_segs = [s for s, _ in scored[:a.spaces]]
    rest = [s for s, _ in scored[a.spaces:]]
    rest.sort(key=len)
    down_segs = rest[len(rest) - a.downs:] if len(rest) > a.downs else rest
    up_segs, _ = pick(ups, a.ups, 90, 0.12) if ups else ([], [])

    up_ratio = statistics.median(u["peak"] / max(1e-6, d["peak"]) for u, d in zip(ups, downs)) if ups else 0.5
    up_peak = max(0.22, min(0.5, 0.7 * up_ratio))

    d = os.path.join(ROOT, "Resources", "Mouse") if a.mouse else os.path.join(a.out, a.name)
    down_name, up_name = ("mousedown", "mouseup") if a.mouse else ("down", "up")
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for i, s in enumerate(down_segs, 1):
        write(os.path.join(d, f"{down_name}-{i}.wav"), s, 0.55 if a.mouse else 0.7)
    for i, s in enumerate(up_segs, 1):
        write(os.path.join(d, f"{up_name}-{i}.wav"), s, up_peak * (0.8 if a.mouse else 1))
    for i, s in enumerate(space_segs, 1):
        write(os.path.join(d, f"space-{i}.wav"), s, 0.75)
    with open(os.path.join(d, "CREDITS.txt"), "w") as f:
        f.write((a.credit or f"Source: {os.path.basename(a.recording)}") + "\n"
                "Sliced with scripts/slice_recording.py\n")
    ms = lambda segs: ", ".join(f"{len(s) / SR * 1000:.0f}" for s in segs)
    print(f"{a.name}: {len(down_segs)} down [{ms(down_segs)} ms], {len(up_segs)} up [{ms(up_segs)} ms], "
          f"{len(space_segs)} space [{ms(space_segs)} ms] -> {d}")


if __name__ == "__main__":
    main()
