"""Generates the Hermez interface cues (assets/sounds/hermez/*.wav).

Every cue is synthesized here from damped resonances and filtered noise, so
the sounds are original and reproducible. Output: 48 kHz, mono, 16-bit PCM,
no leading silence, peak at -3 dBFS. Tune the recipes and re-run:

    python tool/generate_hermez_sounds.py
"""

import os
import wave

import numpy as np

RATE = 48_000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds", "hermez")
rng = np.random.default_rng(7)  # fixed seed: identical output every run


def t(ms):
    return np.arange(int(RATE * ms / 1000)) / RATE


def env(n, attack_ms, decay_ms):
    x = np.arange(n) / RATE
    a = np.clip(x / max(attack_ms / 1000, 1e-6), 0, 1)
    return a * np.exp(-x / (decay_ms / 1000))


def resonance(ms, freq, decay_ms, attack_ms=0.3):
    x = t(ms)
    return np.sin(2 * np.pi * freq * x) * env(len(x), attack_ms, decay_ms)


def sweep(ms, f0, f1, decay_ms, attack_ms=4.0):
    x = t(ms)
    freq = f0 + (f1 - f0) * (x / x[-1])
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    return np.sin(phase) * env(len(x), attack_ms, decay_ms)


def click(ms, brightness, decay_ms):
    """A filtered noise transient: the contact of two hard parts."""
    n = len(t(ms))
    noise = rng.standard_normal(n)
    # One-pole high-pass then low-pass: shapes the 'material'.
    out = np.zeros(n)
    hp, lp, prev = 0.0, 0.0, 0.0
    a_lp = np.exp(-2 * np.pi * brightness / RATE)
    for i in range(n):
        hp = 0.97 * (hp + noise[i] - prev)
        prev = noise[i]
        lp = (1 - a_lp) * hp + a_lp * lp
        out[i] = lp
    return out * env(n, 0.05, decay_ms)


def mix(length_ms, *parts):
    total = np.zeros(len(t(length_ms)))
    for start_ms, gain, sig in parts:
        s = int(RATE * start_ms / 1000)
        seg = sig[: max(0, len(total) - s)]
        total[s : s + len(seg)] += gain * seg
    return total


def write(name, signal):
    peak = np.max(np.abs(signal)) or 1.0
    signal = signal / peak * (10 ** (-3 / 20))  # -3 dBFS
    # Trim leading near-silence so the cue lands on the event.
    start = int(np.argmax(np.abs(signal) > 1e-3))
    signal = signal[start:]
    fade = min(len(signal), int(RATE * 0.004))  # click-free tail
    signal[-fade:] *= np.linspace(1, 0, fade)
    pcm = (signal * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{name:22s} {len(signal) / RATE * 1000:5.0f} ms")


def main():
    os.makedirs(OUT, exist_ok=True)

    # Tiny precision tick: a small key seating.
    write("select_light.wav", mix(50,
        (0, 1.0, click(50, 6000, 4)),
        (0, 0.5, resonance(50, 3100, 7))))

    # Shell latch: catch, then the body settles.
    write("object_open.wav", mix(160,
        (0, 1.0, click(60, 4200, 6)),
        (0, 0.45, resonance(160, 190, 35, attack_ms=1)),
        (52, 0.55, click(60, 3000, 5)),
        (52, 0.3, resonance(80, 2300, 10))))

    # Softer reverse latch, lower.
    write("object_close.wav", mix(150,
        (0, 0.6, click(60, 2600, 5)),
        (38, 1.0, click(60, 3400, 7)),
        (38, 0.5, resonance(110, 150, 30, attack_ms=1))))

    # Rail seating into its stop.
    write("nav_latch.wav", mix(110,
        (0, 1.0, click(60, 3800, 5)),
        (0, 0.45, resonance(110, 1750, 12)),
        (0, 0.5, resonance(110, 120, 32, attack_ms=1))))

    # Quiet electronic wake: a short rising servo tone.
    write("bot_wake.wav", mix(210,
        (0, 0.35, click(40, 5000, 3)),
        (4, 0.7, sweep(200, 420, 880, 70, attack_ms=6)),
        (4, 0.18, sweep(200, 840, 1760, 50, attack_ms=6))))

    # Energized mechanism: catch plus servo whirr.
    write("bot_engage.wav", mix(190,
        (0, 0.9, click(50, 4500, 5)),
        (6, 0.55, sweep(180, 220, 340, 70, attack_ms=5)),
        (6, 0.2, sweep(180, 660, 1020, 45, attack_ms=5))))

    # Restrained machine start: body thump, rising hum.
    write("run_engage.wav", mix(220,
        (0, 0.8, resonance(220, 95, 45, attack_ms=2)),
        (0, 0.5, click(50, 2800, 6)),
        (10, 0.45, sweep(200, 150, 300, 90, attack_ms=12)),
        (10, 0.15, sweep(200, 450, 900, 60, attack_ms=12))))

    # One clear, calm attention cue.
    write("attention.wav", mix(230,
        (0, 0.4, click(40, 5200, 3)),
        (0, 0.8, resonance(230, 880, 70, attack_ms=3)),
        (0, 0.3, resonance(230, 1320, 50, attack_ms=3))))

    # Soft two-stage resolve (not a notification chime).
    write("success.wav", mix(320,
        (0, 0.35, click(40, 4200, 3)),
        (0, 0.6, resonance(120, 660, 45, attack_ms=3)),
        (95, 0.75, resonance(225, 990, 80, attack_ms=3)),
        (95, 0.2, resonance(225, 1485, 55, attack_ms=3))))

    # Dull mechanical rejection, low and short.
    write("failure.wav", mix(260,
        (0, 0.7, click(80, 1600, 10)),
        (0, 0.9, sweep(260, 190, 120, 70, attack_ms=2)),
        (0, 0.25, sweep(260, 380, 240, 50, attack_ms=2))))

    # Positive latch: seat, then a light bright confirmation.
    write("approval_accept.wav", mix(170,
        (0, 1.0, click(60, 4000, 5)),
        (0, 0.4, resonance(100, 170, 28, attack_ms=1)),
        (40, 0.55, resonance(130, 1100, 45, attack_ms=2))))

    # Neutral closing latch: lower, no tone lift.
    write("approval_reject.wav", mix(150,
        (0, 1.0, click(60, 2800, 6)),
        (0, 0.55, resonance(150, 300, 35, attack_ms=1)),
        (30, 0.4, click(50, 2200, 5))))


if __name__ == "__main__":
    main()
