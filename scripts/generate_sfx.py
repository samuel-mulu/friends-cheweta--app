"""Generate the game's sound effects (original, synthesized; no third-party audio).

Usage:  python scripts/generate_sfx.py
Writes 16-bit mono WAV files to assets/sfx/. Deterministic (fixed seed), so
re-running produces identical files.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
rng = random.Random(7)


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, volume=0.5, decay=6.0, harmonics=(1.0, 0.3, 0.12), attack=0.004):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        s = sum(a * math.sin(2 * math.pi * freq * (k + 1) * t) for k, a in enumerate(harmonics))
        out.append(volume * env * s)
    return out


def sweep(f0, f1, seconds, volume=0.6, decay=5.0):
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / RATE
        out.append(volume * math.exp(-decay * t) * math.sin(phase))
    return out


def click(seconds=0.018, volume=0.6, brightness=0.6):
    """Short filtered noise burst: a die face hitting wood."""
    n = int(RATE * seconds)
    out, last = [], 0.0
    for i in range(n):
        env = math.exp(-9 * i / n)
        last = brightness * (rng.uniform(-1, 1)) + (1 - brightness) * last
        out.append(volume * env * last)
    return out


def mix(*tracks):
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def at(offset_s, samples):
    return silence(offset_s) + samples


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.85 / peak if peak > 0.85 else 1.0
    path = os.path.join(OUT, f'{name}.wav')
    with wave.open(path, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(f'{path}  {len(samples) / RATE:.2f}s')


def main():
    # Dice: a rattle of irregular clicks that slows down, plus a soft thump.
    rattle, t, gap = [], 0.0, 0.025
    while t < 0.42:
        rattle.append(at(t, click(volume=rng.uniform(0.35, 0.7), brightness=rng.uniform(0.4, 0.8))))
        t += gap * rng.uniform(0.7, 1.3)
        gap *= 1.12
    write('dice_roll', mix(*rattle, at(0.44, tone(140, 0.12, volume=0.5, decay=28, harmonics=(1.0,)))))

    # Token step: short warm wood tick.
    write('step', mix(tone(880, 0.06, volume=0.35, decay=60, harmonics=(1.0, 0.2)), click(0.012, 0.25, 0.3)))

    # Landing on a safe square: gentle two-note chime.
    write('safe', mix(tone(988, 0.3, 0.35, 9), at(0.06, tone(1319, 0.28, 0.3, 9))))

    # Capture: thud + falling sweep.
    write('capture', mix(tone(110, 0.25, 0.7, 14, (1.0, 0.5)), sweep(520, 140, 0.32, 0.45, 7)))

    # Token reaches home: rising arpeggio.
    write('home', mix(*(at(i * 0.07, tone(f, 0.3, 0.32, 8)) for i, f in enumerate((523, 659, 784, 1047)))))

    # Six / extra roll: quick bright double ping.
    write('extra_roll', mix(tone(1175, 0.12, 0.3, 22), at(0.08, tone(1568, 0.14, 0.3, 20))))

    # Your turn: soft single ping.
    write('your_turn', tone(784, 0.22, 0.32, 12, (1.0, 0.25, 0.05)))

    # Timer running out: dry tick.
    write('tick', mix(click(0.01, 0.4, 0.9), tone(1760, 0.03, 0.15, 90, (1.0,))))

    # Win: short major fanfare.
    notes = ((523, 0.0), (659, 0.12), (784, 0.24), (1047, 0.38))
    write('win', mix(*(at(o, tone(f, 0.55 if f == 1047 else 0.3, 0.33, 4 if f == 1047 else 8)) for f, o in notes),
                     at(0.38, tone(784, 0.55, 0.18, 4))))

    # Lose: two soft descending notes.
    write('lose', mix(tone(440, 0.3, 0.3, 6), at(0.22, tone(349, 0.45, 0.3, 5))))

    # Match start.
    write('match_start', mix(tone(659, 0.18, 0.3, 12), at(0.1, tone(988, 0.3, 0.32, 8))))


if __name__ == '__main__':
    main()
