"""從桌面的兩個 mixkit 原檔生成解鎖演出用的音效。

搖晃音的設計：原檔本身是三次金屬撞擊（40／92／212ms）。這裡把它拆成三段，
按 `_shakeAngleAt` 的**六次最大偏轉**（p=0.077/0.231/0.385/0.538/0.692/0.846，
換算 55/166/277/388/498/609ms）輪流擺放——撞擊聲對齊看得到的轉向瞬間，
才會讀成「鎖在掙脫」而不是「有個聲音在播」。
"""
import wave, array, math, sys

SR = 44100
DESK = '/Users/yayoi991331/Desktop/'

def load(p):
    w = wave.open(p, 'rb'); n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
    d = array.array('h'); d.frombytes(w.readframes(n)); w.close()
    assert sr == SR, sr
    return [(d[i*ch], d[i*ch+1] if ch > 1 else d[i*ch]) for i in range(n)]

def save(p, frames):
    w = wave.open(p, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    a = array.array('h')
    for l, r in frames:
        a.append(max(-32768, min(32767, int(l))))
        a.append(max(-32768, min(32767, int(r))))
    w.writeframes(a.tobytes()); w.close()

def rms_dbfs(frames):
    s = sum(l*l for l, _ in frames)
    r = math.sqrt(s/len(frames))
    return 20*math.log10(r/32768) if r > 0 else -99

def seg(src, a_ms, b_ms, fade_out_ms=12):
    a, b = int(a_ms*SR/1000), int(b_ms*SR/1000)
    out = src[a:b]
    f = int(fade_out_ms*SR/1000)
    for i in range(min(f, len(out))):
        g = 1 - i/f
        j = len(out)-f+i
        out[j] = (out[j][0]*g, out[j][1]*g)
    return out

# ── 搖晃音 ───────────────────────────────────────────────
gear = load(DESK + 'mixkit-gear-metallic-lock-sound-2858.wav')
strikes = [seg(gear, 33, 90), seg(gear, 88, 152), seg(gear, 205, 292)]

EXTREMES = [55.4, 166.2, 277.0, 387.7, 498.5, 609.2]  # 鎖到達最大偏轉的時刻

def build_rattle(hit_times, total_ms=790):
    n = int(total_ms*SR/1000)
    buf = [[0.0, 0.0] for _ in range(n)]
    for k, t in enumerate(hit_times):
        s = strikes[k % 3]
        # 前段還在「漲起來」，音量跟著視覺的 envelope 走
        p = t/720
        amp = (0.55 + 0.45*min(1.0, p/0.18)) * (0.92 if k % 2 else 1.0)
        off = int(t*SR/1000)
        for i, (l, r) in enumerate(s):
            j = off + i
            if j >= n: break
            buf[j][0] += l*amp
            buf[j][1] += r*amp
    f = int(20*SR/1000)
    for i in range(f):
        g = 1 - i/f
        buf[n-f+i][0] *= g; buf[n-f+i][1] *= g
    return [(b[0], b[1]) for b in buf]

variants = {
    'A_6hits': EXTREMES,
    'B_3hits': EXTREMES[::2],
    'C_4hits': [EXTREMES[0], EXTREMES[2], EXTREMES[3], EXTREMES[5]],
}
for name, hits in variants.items():
    fr = build_rattle(hits)
    save(DESK + f'_preview_lock_rattle_{name}.wav', fr)
    print(f'搖晃 {name}: {len(hits)} 次撞擊, {len(fr)/SR:.3f}s, RMS {rms_dbfs(fr):.1f} dBFS')

# ── 解鎖音：裁掉尾端靜音並淡出 ────────────────────────────
sp = load(DESK + 'mixkit-fairy-arcade-sparkle-866.wav')
unlock = seg(sp, 0, 860, fade_out_ms=90)
save(DESK + '_preview_unlock_sparkle.wav', unlock)
print(f'解鎖: {len(unlock)/SR:.3f}s, RMS {rms_dbfs(unlock):.1f} dBFS')
