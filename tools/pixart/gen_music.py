# -*- coding: utf-8 -*-
"""BGM 作曲器 v2: 6 首曲目 → assets/music/*.ogg (44.1k 立体声)。

v2 全面升级(针对"听感差、没动力"的反馈):
- 音色: FM 电钢(和弦)/失谐双锯主音(滤波+延迟颤音)/加压低音/垫弦/钟琴
- 鼓组: 底鼓带瞬态击、军鼓含腔体、开闭踩镲力度分层, 每 4/8 小节过门
- 空间: 施罗德混响(梳状+全通)黏合, 乐器声像展开, 软限幅母带
- 结构: intro→A→B→A'→过门 分段编排, 段内乐器增减有起伏; 摇摆律动(对局曲)
曲目: lobby(首页·温暖邀约) table(对局·轻快竞技) table_rev(革命·急进小调)
rogue(肉鸽·神秘推进) boss(BOSS·狂暴) fight(格斗·热血摇滚)
"""
import os
import math
import numpy as np
from scipy import signal as sg
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'assets', 'music')
RNG = np.random.default_rng(20260925)


# ---------------------------------------------------------------- 音色引擎

def midi_hz(semi):
    return 440.0 * 2 ** ((semi - 69) / 12.0)


def lowpass(x, fc):
    fc = min(fc, SR * 0.45)
    b, a = sg.butter(2, fc / (SR / 2), 'low')
    return sg.lfilter(b, a, x)


def highpass(x, fc):
    b, a = sg.butter(2, fc / (SR / 2), 'high')
    return sg.lfilter(b, a, x)


def bandpass(x, lo, hi):
    b, a = sg.butter(2, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], 'band')
    return sg.lfilter(b, a, x)


def _adsr(n, a_s, d_s, sustain, rel_s):
    e = np.full(n, sustain)
    na, nd, nr = int(a_s * SR), int(d_s * SR), int(rel_s * SR)
    na, nd, nr = min(na, n), min(nd, max(n - na, 0)), min(nr, n)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nd:
        e[na:na + nd] = np.linspace(1, sustain, nd)
    if nr:
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def saw_ph(f_v, n, detune_cents=0.0):
    """频率可随时间变的锯齿(相位累积)"""
    ph = np.cumsum(f_v * 2 ** (detune_cents / 1200.0)) / SR
    return 2 * (ph % 1.0) - 1


def tri(f, n):
    t = np.arange(n) / SR
    ph = (f * t) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def inst_lead(f, dur, vel=1.0):
    """主音: 双失谐锯 + 三角, 低通 2.4k, 0.18s 后起颤音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f_v = np.full(n, f) * (1 + 0.0035 * np.sin(2 * np.pi * 5.3 * t)
                           * np.clip((t - 0.18) * 4, 0, 1))
    x = (saw_ph(f_v, n, 7) + saw_ph(f_v, n, -7)) * 0.36 + tri(f, n) * 0.28
    x = lowpass(x, 2400)
    e = _adsr(n, 0.012, 0.25, 0.78, min(0.09, dur * 0.3))
    return np.tanh(x * 1.2) * e * vel * 0.30


def inst_ep(f, dur, vel=1.0):
    """FM 电钢: 载波正弦 + 2 倍频调制(快衰减) — 温暖有击键感"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 2.2 * np.exp(-t * 9.0)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 2.0 * t))
    click = RNG.uniform(-1, 1, n) * np.exp(-t * 900) * 0.22
    e = _adsr(n, 0.004, 0.4, 0.42, min(0.12, dur * 0.3))
    return (x + click) * e * vel * 0.26


def inst_pluck(f, dur, vel=1.0):
    """拨弦: FM 3 倍频, 亮而短"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 1.6 * np.exp(-t * 14.0)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.0 * t))
    e = _adsr(n, 0.003, 0.22, 0.2, min(0.08, dur * 0.3))
    return x * e * vel * 0.20


def inst_glock(f, dur, vel=1.0):
    """钟琴: 非整数倍频 FM 泛音, 清脆点缀"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 1.2 * np.exp(-t * 6.0)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.53 * t))
    e = _adsr(n, 0.002, 0.5, 0.25, 0.1)
    return x * e * vel * 0.12


def inst_bass(f, dur, vel=1.0):
    """低音: 正弦下限 + 锯齿层低通 520, 轻饱和"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * 0.62 + saw_ph(np.full(n, f), n) * 0.38
    x = lowpass(x, 520)
    e = _adsr(n, 0.006, 0.18, 0.66, min(0.05, dur * 0.25))
    return np.tanh(x * 1.6) * e * vel * 0.34


def inst_pad(freqs, dur, vel=1.0):
    """垫弦: 每音双失谐锯, 慢起音"""
    n = int(dur * SR)
    x = np.zeros(n)
    for f in freqs:
        x += saw_ph(np.full(n, f), n, 9) + saw_ph(np.full(n, f), n, -11)
    x = lowpass(x / (len(freqs) * 2), 950)
    e = _adsr(n, 0.38, 0.5, 0.8, min(0.5, dur * 0.35))
    return x * e * vel * 0.11


def inst_stab(freqs, dur, vel=1.0):
    """铜管式刺击: 双失谐锯, 快起快收(单频自动包列表)"""
    if isinstance(freqs, (int, float)):
        freqs = [freqs]
    n = int(dur * SR)
    x = np.zeros(n)
    for f in freqs:
        x += saw_ph(np.full(n, f), n, 6) + saw_ph(np.full(n, f), n, -6)
    x = lowpass(x / (len(freqs) * 2), 1900)
    e = _adsr(n, 0.008, 0.14, 0.5, min(0.06, dur * 0.4))
    return np.tanh(x * 1.3) * e * vel * 0.22


# ---------------------------------------------------------------- 鼓组

def kick(vel=1.0):
    n = int(0.30 * SR)
    t = np.arange(n) / SR
    f = 150 * np.exp(-t * 30) + 44
    ph = np.cumsum(f) / SR
    x = np.sin(2 * np.pi * ph) * np.exp(-t * 9.5)
    click = highpass(RNG.uniform(-1, 1, n), 3000) * np.exp(-t * 700) * 0.5
    return np.tanh((x + click) * 1.4) * vel * 0.88


def snare(vel=1.0):
    n = int(0.20 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 192 * t) * np.exp(-t * 26) * 0.5
    noise = bandpass(RNG.uniform(-1, 1, n), 900, 7000) * np.exp(-t * 21)
    return (body + noise) * vel * 0.52


def hat(open_=False, vel=1.0):
    dur = 0.24 if open_ else 0.05
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = highpass(RNG.uniform(-1, 1, n), 7800 + vel * 2200)
    return x * np.exp(-t * (7 if open_ else 90)) * vel * 0.20


def shaker(vel=1.0):
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    x = bandpass(RNG.uniform(-1, 1, n), 4500, 9500)
    return x * np.exp(-t * 46) * vel * 0.13


def tom(freq=110.0, vel=1.0):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = freq * np.exp(-t * 9) + freq * 0.62
    ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph) * np.exp(-t * 15) * vel * 0.5


# ---------------------------------------------------------------- 混响/母带

def reverb_send(x):
    """施罗德混响(只输出湿声): 4 并联梳状 + 级联全通"""
    y = np.zeros_like(x)
    for d in (1116, 1188, 1277, 1356):
        a = np.zeros(d + 1)
        a[0], a[-1] = 1.0, -0.772
        y += sg.lfilter([1.0], a, x)
    y *= 0.25
    for d, g in ((225, 0.7), (556, 0.7), (441, 0.7), (341, 0.7)):
        a = np.zeros(d + 1)
        a[0], a[-1] = 1.0, -g
        b = np.zeros(d + 1)
        b[0], b[-1] = -g, 1.0
        y = sg.lfilter(b, a, y)
    return y


# ---------------------------------------------------------------- 音序器

INSTR = {'lead': inst_lead, 'ep': inst_ep, 'pluck': inst_pluck,
         'glock': inst_glock, 'bass': inst_bass, 'stab': inst_stab}
PAN = {'lead': 0.0, 'ep': -0.25, 'pluck': 0.3, 'glock': 0.45,
       'bass': 0.0, 'stab': -0.1}
WET = {'lead': 0.30, 'ep': 0.34, 'pluck': 0.30, 'glock': 0.45,
       'bass': 0.05, 'stab': 0.22}


class Song:
    def __init__(self, bpm, bars, swing=0.0):
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bars = bars
        self.swing = swing
        n = int(bars * 4 * self.spb * SR) + SR
        self.dryL = np.zeros(n)
        self.dryR = np.zeros(n)
        self.send = np.zeros(n)

    def _t(self, beat):
        b = beat
        if self.swing > 0:
            frac = (b * 4) % 4
            if abs(frac - 1.0) < 0.01:   # 16 分反拍(第 2/4 个十六分)
                b += self.swing / 12.0
        return b * self.spb

    def _mix(self, beat, snd, pan, wet):
        i0 = int(self._t(beat) * SR)
        i1 = min(i0 + len(snd), len(self.dryL))
        if i1 <= i0:
            return
        seg = snd[:i1 - i0]
        l = math.cos((pan + 1) * math.pi / 4)
        r = math.sin((pan + 1) * math.pi / 4)
        self.dryL[i0:i1] += seg * l
        self.dryR[i0:i1] += seg * r
        self.send[i0:i1] += seg * wet

    def note(self, beat, kind, f, dur=1.0, vel=1.0):
        self._mix(beat, INSTR[kind](f, dur * self.spb * 1.02, vel),
                  PAN[kind], WET[kind])

    def chord(self, beat, kind, freqs, dur=1.0, vel=1.0):
        for f in freqs:
            self.note(beat, kind, f, dur, vel)

    def pad(self, beat, freqs, dur=4.0, vel=1.0):
        self._mix(beat, inst_pad(freqs, dur * self.spb, vel), -0.05, 0.4)

    def drum_pat(self, start_bar, pattern, bars=None, vel=1.0):
        """16 步鼓 pattern(字符串列表, 每小节 16 字符)。
        K=底鼓 S=军鼓 h=闭镲 H=开镲 b=沙锤 T=桶鼓 .=休止"""
        bars = bars if bars is not None else len(pattern)
        for bi in range(bars):
            row = pattern[bi % len(pattern)]
            for si in range(16):
                ch = row[si % len(row)]
                beat = (start_bar + bi) * 4 + si / 4.0
                v = vel * (0.82 if si % 2 else 1.0)
                if ch == 'K':
                    self._mix(beat, kick(v), 0.0, 0.02)
                elif ch == 'S':
                    self._mix(beat, snare(v), 0.08, 0.16)
                elif ch == 'h':
                    self._mix(beat, hat(False, v), 0.3, 0.10)
                elif ch == 'H':
                    self._mix(beat, hat(True, v), 0.3, 0.12)
                elif ch == 'b':
                    self._mix(beat, shaker(v), -0.3, 0.12)
                elif ch == 'T':
                    self._mix(beat, tom(120 - (si % 4) * 14, v), 0.0, 0.2)

    def fill(self, bar):
        for i in range(4):
            self._mix(bar * 4 + 3 + i / 4.0,
                      tom(150 - i * 22, 0.9 - i * 0.12), 0.0, 0.2)

    def render(self, name):
        wet = reverb_send(self.send)
        left = self.dryL + wet
        right = self.dryR + wet
        stereo = np.stack([left, right], axis=1)
        stereo = np.tanh(stereo * 1.15) * 0.85
        peak = np.abs(stereo).max()
        if peak > 0:
            stereo *= 0.90 / peak
        n = len(stereo)
        fo = int(0.30 * SR)
        stereo[n - fo:] *= np.linspace(1, 0, fo)[:, None]
        fi = int(0.02 * SR)
        stereo[:fi] *= np.linspace(0, 1, fi)[:, None]
        stereo = stereo[:n - SR]   # 去掉尾音余量, 循环点干净
        path = os.path.join(OUT, name + '.ogg')
        with sf.SoundFile(path, 'w', samplerate=SR, channels=2,
                          format='OGG', subtype='VORBIS') as f:
            step = SR * 5
            for i in range(0, len(stereo), step):
                f.write(stereo[i:i + step])
        print('%-10s %5.1fs %6.1fKB' %
              (name, len(stereo) / SR, os.path.getsize(path) / 1024))
        return path



def new_song(bpm, bars, swing=0.0):
    return Song(bpm, bars, swing)


# ---------------------------------------------------------------- 乐理工具

MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]
DOR = [0, 2, 3, 5, 7, 9, 10]
PHR = [0, 1, 3, 5, 7, 8, 10]


def deg(scale, root, d, octv=0):
    while d >= len(scale):
        d -= len(scale)
        octv += 1
    while d < 0:
        d += len(scale)
        octv -= 1
    return midi_hz(root + scale[d] + 12 * octv)


def ch(scale, root, d, octv=0, seventh=False):
    ns = [d, d + 2, d + 4] + ([d + 6] if seventh else [])
    return [deg(scale, root, x, octv) for x in ns]


def main():
    import gen_songs
    os.makedirs(OUT, exist_ok=True)
    for fn in gen_songs.ALL:
        fn()
    print('->', OUT)


if __name__ == '__main__':
    main()
