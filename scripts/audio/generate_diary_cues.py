#!/usr/bin/env python3
"""Original, deterministic diary UI sounds. No samples or external licenses.

44.1 kHz PCM; gentle struck wood plus damped harmonic bells. Events own timing:
this script never adds a silent pre-roll. Keep the old sounds for branch comparison.
"""
import array
import json
import math
from pathlib import Path
import random
import wave

ROOT = Path(__file__).resolve().parents[2]
RATE = 44100

def note(t, hz, decay, brightness=0.16):
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.003)
    envelope = attack * math.exp(-t / decay)
    return envelope * (math.sin(math.tau * hz * t) + brightness * math.sin(math.tau * hz * 2 * t) * math.exp(-t / 0.035))

def render(name, length, notes, wood=0.0, gain=0.3):
    rng = random.Random(23)
    samples = []
    for i in range(round(length * RATE)):
        t = i / RATE
        signal = sum(amp * note(t - start, hz, decay) for start, hz, decay, amp in notes)
        # Short, low wood transient: no abrasive high-frequency click.
        signal += wood * note(t, 190, 0.017, 0.05)
        signal += wood * 0.035 * rng.uniform(-1, 1) * min(t / 0.002, 1) * math.exp(-t / 0.008)
        tail = min(1.0, max(0, length - t) / 0.030)
        samples.append(signal * gain * tail)
    assert max(map(abs, samples)) < 0.8
    data = array.array('h', [round(max(-1, min(1, x)) * 32767) for x in samples])
    target = ROOT / 'assets' / 'sounds' / f'sfx_diary_{name}.wav'
    with wave.open(str(target), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())
    rms = math.sqrt(sum(x*x for x in samples) / len(samples))
    return {'file': str(target.relative_to(ROOT)), 'duration_ms': round(length*1000),
            'peak_dbfs': round(20*math.log10(max(map(abs, samples))), 2),
            'rms_dbfs': round(20*math.log10(rms), 2)}

if __name__ == '__main__':
    report = [
        render('tap', .115, [(0, 640, .019, .35)], wood=.7, gain=.24),
        render('cancel', .16, [(0, 390, .03, .25)], wood=.45, gain=.22),
        render('success', .40, [(0, 659.25, .075, .62), (.045, 987.77, .085, .38)], wood=.25, gain=.26),
        render('complete', .56, [(0, 523.25, .10, .60), (.045, 659.25, .11, .38), (.09, 783.99, .12, .38)], wood=.50, gain=.28),
    ]
    print(json.dumps(report, indent=2))
