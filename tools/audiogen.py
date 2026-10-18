#!/usr/bin/env python3
"""Synthesizes every sound effect and music track the game uses -> assets/audio/*.wav

Nothing is downloaded: each sound is built from oscillators, filtered noise,
envelopes and Karplus-Strong plucked strings (a physical model of a string).

    python3 tools/audiogen.py
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ building blocks
def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, release=0.1, curve=2.0):
    """attack/release envelope over n samples (exponential-ish tail)"""
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0, 1, a)
    tail = np.linspace(1, 0, n - a) ** curve
    e[a:] = tail
    return e


def sweep(f0, f1, dur, wave_fn=np.sin):
    tt = t(dur)
    f = np.geomspace(max(f0, 1), max(f1, 1), len(tt))
    return wave_fn(2 * np.pi * np.cumsum(f) / SR)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass_sweep(x, f0, f1):
    """crude moving band-pass: low-pass minus a lower low-pass, cutoff gliding"""
    n = len(x)
    out = np.zeros(n)
    lo = hi = 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / n)
        a_hi = np.exp(-2 * np.pi * (f * 1.6) / SR)
        a_lo = np.exp(-2 * np.pi * (f * 0.6) / SR)
        hi = (1 - a_hi) * x[i] + a_hi * hi
        lo = (1 - a_lo) * x[i] + a_lo * lo
        out[i] = hi - lo
    return out


def pluck(freq, dur, bright=0.5, decay=0.996):
    """Karplus-Strong plucked string"""
    n = int(SR * dur)
    p = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, p) * bright + rng.uniform(-1, 1, p) * (1 - bright) * 0.3
    out = np.zeros(n)
    for i in range(n):
        v = buf[i % p]
        out[i] = v
        buf[i % p] = decay * 0.5 * (v + buf[(i + 1) % p])
    return out


def bell(freq, dur, partials=((1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12))):
    tt = t(dur)
    s = np.zeros_like(tt)
    for k, amp in partials:
        s += amp * np.sin(2 * np.pi * freq * k * tt) * np.exp(-tt * (2.2 + k * 0.9))
    return s


def croak(dur, base=95, rate=34, rough=0.5):
    """frog croak: a buzzy pulse train through a resonant body"""
    tt = t(dur)
    pulses = (np.sin(2 * np.pi * rate * tt) > 0.2).astype(float)
    tone = np.sign(np.sin(2 * np.pi * base * tt)) * 0.6 + np.sin(2 * np.pi * base * 2.02 * tt) * 0.4
    s = tone * pulses * (1 - rough + rough * rng.uniform(0, 1, len(tt)))
    return lowpass(s, 900)


def reverb(x, wet=0.35, delays=(0.031, 0.047, 0.061, 0.083, 0.11), fb=0.45, tail=1.2):
    n = len(x) + int(SR * tail)
    y = np.zeros(n)
    y[:len(x)] = x
    for d in delays:
        k = int(SR * d)
        comb = np.zeros(n)
        comb[:len(x)] = x
        for i in range(k, n):
            comb[i] += fb * comb[i - k]
        y += wet / len(delays) * comb
    return y


def write(name, x, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name:14s} {len(x) / SR:5.2f}s")


def mixin(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:j] += src[:j - i]


# ------------------------------------------------------------------ sound effects
def sfx():
    print("sound effects:")
    d = 0.16; write("jump", sweep(220, 520, d) * env(int(SR * d), 0.004, 0.1) * 0.6 + lowpass(noise(d), 2500) * env(int(SR * d), 0.002, 0.05) * 0.4)
    d = 0.14; write("land", (sweep(110, 50, d) + lowpass(noise(d), 500) * 0.8) * env(int(SR * d), 0.002, 0.1))
    d = 0.05; write("step", lowpass(noise(d), 1200) * env(int(SR * d), 0.001, 0.04), 0.5)
    d = 0.22; write("swing", bandpass_sweep(noise(d), 500, 2400) * env(int(SR * d), 0.02, 0.15))
    d = 0.38; write("heavy_swing", bandpass_sweep(noise(d), 200, 1400) * env(int(SR * d), 0.06, 0.25) + sweep(140, 70, d) * env(int(SR * d), 0.08, 0.3) * 0.3)
    d = 0.16; write("dodge", bandpass_sweep(noise(d), 1200, 400) * env(int(SR * d), 0.01, 0.1))
    d = 0.18; write("hit", sweep(180, 60, d) * env(int(SR * d), 0.001, 0.12) + lowpass(noise(d), 4000) * env(int(SR * d), 0.0005, 0.04) * 0.9)
    d = 0.45; write("heavy_hit", sweep(120, 35, d) * env(int(SR * d), 0.001, 0.35) * 1.2 + lowpass(noise(d), 2500) * env(int(SR * d), 0.0005, 0.12) + bell(90, d) * 0.3)
    d = 0.35; write("block", bell(880, d, ((1, 1), (2.41, 0.6), (3.9, 0.4), (6.1, 0.2))) * env(int(SR * d), 0.001, 0.3) + lowpass(noise(d), 6000) * env(int(SR * d), 0.0005, 0.03) * 0.5)
    d = 0.28; write("hurt", (sweep(300, 120, d, lambda p: np.sign(np.sin(p))) * 0.4 + lowpass(noise(d), 1500)) * env(int(SR * d), 0.003, 0.2))
    write("croak", croak(0.32) * env(int(SR * 0.32), 0.01, 0.15))
    write("enemy_hurt", croak(0.18, 140, 45) * env(int(SR * 0.18), 0.003, 0.1))
    d = 0.5; write("enemy_die", croak(d, 120, 26) * np.linspace(1, 0.2, int(SR * d)) * sweep(1, 1, d) ** 0 * env(int(SR * d), 0.005, 0.4) + lowpass(noise(d), 800) * env(int(SR * d), 0.002, 0.2) * 0.4)
    d = 0.4; write("cultist_hurt", (sweep(420, 180, d, lambda p: np.sin(p) + 0.3 * np.sin(2 * p)) * 0.6 + lowpass(noise(d), 1800) * 0.4) * env(int(SR * d), 0.003, 0.3))
    d = 0.22; o = np.zeros(int(SR * d)); mixin(o, np.sin(2 * np.pi * 1318 * t(0.1)) * env(int(SR * 0.1), 0.002, 0.08), 0); mixin(o, np.sin(2 * np.pi * 1976 * t(0.12)) * env(int(SR * 0.12), 0.002, 0.1), 0.07); write("orb", o, 0.6)
    d = 0.45; o = np.zeros(int(SR * d))
    for i, f in enumerate((1568, 2093, 2637)): mixin(o, bell(f, 0.3) * 0.5, i * 0.07)
    write("key", o, 0.6)
    d = 0.7; o = np.zeros(int(SR * d))
    for i, f in enumerate((523, 659, 784, 1046)): mixin(o, pluck(f, 0.5, 0.7, 0.995), i * 0.08)
    write("heal", o, 0.6)
    d = 2.2; o = np.zeros(int(SR * d))
    for i, f in enumerate((293.7, 440, 554.4, 659.3, 880)): mixin(o, bell(f, 1.8) * 0.4, i * 0.12)
    o += np.sin(2 * np.pi * 1760 * t(d)) * np.sin(2 * np.pi * 6 * t(d)) * 0.05 * env(int(SR * d), 0.4, 1.4)
    write("memory", reverb(o, 0.5), 0.7)
    write("shrine", reverb(bell(392, 1.4) + bell(588, 1.4) * 0.4, 0.4), 0.7)
    d = 0.9; write("gate", lowpass(noise(d), 260) * env(int(SR * d), 0.08, 0.5) * 2 + sweep(70, 45, d) * env(int(SR * d), 0.1, 0.6) * 0.5)
    d = 0.04; write("menu_move", np.sin(2 * np.pi * 880 * t(d)) * env(int(SR * d), 0.001, 0.03), 0.4)
    d = 0.12; write("menu_select", (np.sin(2 * np.pi * 660 * t(d)) + np.sin(2 * np.pi * 990 * t(d)) * 0.5) * env(int(SR * d), 0.002, 0.1), 0.5)
    d = 1.4; write("death", reverb(sweep(330, 70, d, lambda p: np.sin(p) + 0.4 * np.sin(3 * p)) * env(int(SR * d), 0.01, 1.0), 0.4), 0.7)
    d = 2.0; o = np.zeros(int(SR * d))
    for i, f in enumerate((392, 440, 523.3, 587.3, 784)): mixin(o, pluck(f, 1.2, 0.8, 0.997) * (0.6 + 0.1 * i), i * 0.11)
    write("level_clear", reverb(o, 0.4), 0.75)
    d = 0.6; write("slam", sweep(90, 30, d) * env(int(SR * d), 0.001, 0.5) * 1.3 + lowpass(noise(d), 600) * env(int(SR * d), 0.001, 0.3))
    d = 0.35; write("tongue", sweep(300, 900, d, lambda p: np.sin(p) * 0.5) * env(int(SR * d), 0.005, 0.25) + lowpass(noise(d), 3000) * env(int(SR * d), 0.002, 0.08) * 0.3)
    d = 0.6; write("crate", lowpass(noise(d), 700) * env(int(SR * d), 0.001, 0.4) + pluck(110, d, 0.9, 0.98) * 0.5)


# ------------------------------------------------------------------ music
PENTA = [0, 2, 4, 7, 9]                                   # major pentatonic (D)


def note(root, degree, octave=0):
    o, k = divmod(degree, 5)
    return root * 2 ** ((PENTA[k] + 12 * (o + octave)) / 12)


def frog_chorus(length, bpm, gain=0.25):
    """the 'brekekekex - koax - koax' rhythm: a fast 4-croak run then two long croaks"""
    out = np.zeros(int(SR * length))
    beat = 60 / bpm
    bar = beat * 4
    k = 0
    while k * bar < length:
        b0 = k * bar
        for i in range(4):
            mixin(out, croak(0.07, 150, 50, 0.3) * env(int(SR * 0.07), 0.004, 0.05) * gain, b0 + i * beat * 0.25)
        mixin(out, croak(0.2, 95, 30, 0.4) * env(int(SR * 0.2), 0.01, 0.12) * gain * 1.1, b0 + beat * 2)
        mixin(out, croak(0.2, 90, 30, 0.4) * env(int(SR * 0.2), 0.01, 0.12) * gain * 1.1, b0 + beat * 3)
        k += 1
    return out


def drone(length, root, gain=0.18):
    tt = t(length)
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * tt)
    s = (np.sin(2 * np.pi * root * tt) + 0.6 * np.sin(2 * np.pi * root * 1.5 * tt + 0.5) +
         0.3 * np.sin(2 * np.pi * root * 2.003 * tt)) * (0.6 + 0.4 * lfo)
    return lowpass(s, 600) * gain


def melody(length, root, bpm, pattern, gain=0.35, octave=1, bright=0.6):
    out = np.zeros(int(SR * length))
    beat = 60 / bpm
    pos = 0.0
    i = 0
    while pos < length - 0.5:
        deg, dur = pattern[i % len(pattern)]
        if deg is not None:
            mixin(out, pluck(note(root, deg, octave), min(dur * beat * 1.8, 2.5), bright, 0.997) * gain, pos)
        pos += dur * beat
        i += 1
    return out


def drums(length, bpm, gain=0.4):
    out = np.zeros(int(SR * length))
    beat = 60 / bpm
    kick = sweep(110, 40, 0.25) * env(int(SR * 0.25), 0.001, 0.2)
    taiko = (sweep(160, 70, 0.4) + lowpass(noise(0.4), 400) * 0.5) * env(int(SR * 0.4), 0.001, 0.3)
    hat = lowpass(noise(0.05), 7000) * env(int(SR * 0.05), 0.001, 0.04) * 0.3
    k = 0
    while k * beat < length:
        if k % 4 in (0, 2): mixin(out, kick * gain, k * beat)
        if k % 8 == 3 or k % 8 == 7: mixin(out, taiko * gain * 0.9, k * beat)
        mixin(out, hat * gain, k * beat + beat * 0.5)
        k += 1
    return out


def fade_loop(x, fade=0.4):
    """crossfade the tail into the head so the track loops seamlessly"""
    n = int(SR * fade)
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return x[:-n]


def music():
    print("music:")
    D = 146.83
    L = 48.0
    marsh_pat = [(0, 1), (2, 1), (4, 2), (3, 1), (2, 1), (0, 2), (None, 1), (5, 1), (4, 1), (2, 1), (3, 2), (0, 2), (None, 2)]
    m = drone(L, D / 2) + melody(L, D, 72, marsh_pat, 0.3) + frog_chorus(L, 72, 0.12)
    m += reverb(melody(L, D, 72, [(7, 4), (5, 4), (6, 4), (4, 4)], 0.12, 1, 0.3), 0.5)[:int(SR * L)]
    write("music_marsh", fade_loop(m), 0.6)

    title_pat = [(4, 2), (3, 1), (2, 1), (0, 4), (None, 2), (2, 1), (3, 1), (4, 2), (5, 2), (4, 4), (None, 2)]
    tm = drone(40, D / 2, 0.22) + reverb(melody(40, D, 60, title_pat, 0.35, 1, 0.5), 0.45)[:int(SR * 40)]
    write("music_title", fade_loop(tm), 0.6)

    Dm = 146.83
    boss_pat = [(0, 0.5), (0, 0.5), (3, 0.5), (0, 0.5), (4, 1), (2, 0.5), (1, 0.5), (0, 0.5), (0, 0.5), (5, 0.5), (4, 0.5), (3, 1), (2, 1)]
    bm = drone(32, Dm / 2, 0.25) + drums(32, 132, 0.5) + melody(32, Dm, 132, boss_pat, 0.32, 0, 0.8) + frog_chorus(32, 132, 0.1)
    write("music_boss", fade_loop(bm), 0.65)

    cave_pat = [(0, 2), (None, 1), (2, 1), (1, 2), (None, 2), (4, 1), (3, 1), (2, 2), (None, 4)]
    cm = drone(44, D / 2, 0.24) + reverb(melody(44, D * 0.75, 64, cave_pat, 0.3, 1, 0.4), 0.55)[:int(SR * 44)]
    write("music_hollow", fade_loop(cm), 0.6)


if __name__ == "__main__":
    sfx()
    music()
