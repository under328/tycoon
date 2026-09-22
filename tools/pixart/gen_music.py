# -*- coding: utf-8 -*-
"""BGM 作曲器: 6 首风格化曲目 → assets/music/*.ogg (44.1k 立体声)。

声部: 脉冲主旋律(颤音) + 三角波贝斯 + 十六分琶音 + 噪声鼓组 + 和声垫。
风格: lobby(安宁五声) table(明亮大调) table_rev(小调急板) rogue(神秘多利亚)
boss(狂暴弗里几亚) fight(格斗摇滚)。
"""
import os
import sys
import math
import numpy as np
from scipy import signal as sg
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'assets', 'music')


# ---------------------------------------------------------------- 合成器

def env_ad(n, a, d, curve=2.0):
    """AD 包络(归一)"""
    t = np.linspace(0, 1, n, endpoint=False)
    na = max(int(a * n), 1)
    nd = n - na
    e = np.empty(n)
    e[:na] = np.linspace(0, 1, na, endpoint=False)
    if nd > 0:
        e[na:] = np.exp(-curve * np.linspace(0, 1, nd))
    return e


def pulse(freq, dur, duty=0.5, vol=0.5, vib=0.0, vib_hz=5.5, detune=0.0):
    """脉冲波(占空比可变) + 颤音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (2 ** (detune / 1200.0))
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * vib_hz * t) * np.minimum(t * 3, 1))
    ph = np.cumsum(f) / SR
    saw = 2 * (ph % 1.0) - 1
    off = ph + duty
    saw2 = 2 * (off % 1.0) - 1
    wav = np.sign(saw - saw2)  # 双锯齿差分=脉冲
    return wav * vol * env_ad(n, 0.02, 0.98)


def tri(freq, dur, vol=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = (freq * t) % 1.0
    wav = 4 * np.abs(ph - 0.5) - 1  # 三角
    return wav * vol * env_ad(n, 0.005, 0.995, curve=1.2)


def noise(dur, vol=0.4, lp=8000, hp=200):
    n = int(dur * SR)
    x = np.random.default_rng(7).uniform(-1, 1, n)
    b, a = sg.butter(2, lp / (SR / 2), 'low')
    x = sg.lfilter(b, a, x)
    b, a = sg.butter(2, hp / (SR / 2), 'high')
    x = sg.lfilter(b, a, x)
    return x * vol * env_ad(n, 0.001, 0.999, curve=3.5)


def kick(dur=0.16, vol=0.9):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 110 * np.exp(-t * 26) + 42
    ph = np.cumsum(f) / SR
    wav = np.sin(2 * np.pi * ph)
    wav *= np.exp(-t * 15)
    return wav * vol


def snare(dur=0.14, vol=0.55):
    body = noise(dur, vol, lp=9000, hp=900)
    tail = kick(0.06, 0.3)
    out = np.zeros(max(len(body), len(tail)))
    out[:len(body)] += body
    out[:len(tail)] += tail
    return out


def hat(dur=0.05, vol=0.22):
    return noise(dur, vol, lp=12000, hp=7000)


def place(buf, snd, at):
    i0 = int(at * SR)
    i1 = min(i0 + len(snd), len(buf))
    if i1 > i0:
        buf[i0:i1] += snd[:i1 - i0]


def midi(deg, octave=0):
    """音级(0=C)→频率"""
    return 440.0 * 2 ** ((deg - 9) / 12.0 + octave)


# ---------------------------------------------------------------- 曲目结构

class Song:
    def __init__(self, bpm, bars, beats=4):
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bars = bars
        self.beats = beats
        n = int(bars * beats * self.spb * SR) + SR * 2
        self.buf = np.zeros(n)

    def t(self, bar, beat=0.0):
        return (bar * self.beats + beat) * self.spb


def compose(name):
    """按名称作曲"""
    if name == 'lobby':
        return _lobby()
    if name == 'table':
        return _table()
    if name == 'table_rev':
        return _table_rev()
    if name == 'rogue':
        return _rogue()
    if name == 'boss':
        return _boss()
    if name == 'fight':
        return _fight()
    raise KeyError(name)


def _render(song, chords, bass_pat, lead_pat, arp_on=True, drum_style='soft',
            pad_on=True, lead_vol=0.30, arp_vol=0.13, bass_vol=0.34):
    """通用渲染: chords=[(bar, [degrees...])] 贝斯/主旋律按事件列表"""
    buf = song.buf
    spb = song.spb
    scale_chords = {bar: ch for bar, ch in chords}
    # 琶音(16 分)
    if arp_on:
        for bar, ch in chords:
            for i in range(16):
                deg = ch[i % len(ch)] + (12 if i % 8 >= 4 else 0)
                snd = pulse(midi(deg, 0), spb / 4 * 0.92, duty=0.25,
                            vol=arp_vol)
                place(buf, snd, song.t(bar, i / 4.0))
    # 垫(和弦长音)
    if pad_on:
        for bar, ch in chords:
            for deg in ch:
                snd = pulse(midi(deg, -1), spb * 4 * 0.98, duty=0.5,
                            vol=0.05, detune=8)
                place(buf, snd, song.t(bar))
                snd2 = pulse(midi(deg, -1), spb * 4 * 0.98, duty=0.5,
                             vol=0.045, detune=-9)
                place(buf, snd2, song.t(bar))
    # 贝斯
    for bar, beat, deg, octv, dur in bass_pat:
        snd = tri(midi(deg, octv), dur * 0.95, vol=bass_vol)
        place(buf, snd, song.t(bar, beat))
    # 主旋律
    for bar, beat, deg, octv, dur in lead_pat:
        if deg is None:
            continue
        snd = pulse(midi(deg, octv), dur * 0.94, duty=0.5, vol=lead_vol,
                    vib=0.006)
        place(buf, snd, song.t(bar, beat))
    # 鼓
    for bar in range(song.bars):
        if drum_style == 'none':
            break
        t0 = song.t(bar)
        if drum_style == 'soft':
            place(buf, kick(), t0)
            place(buf, kick(0.12, 0.5), t0 + spb * 2.5)
            place(buf, snare(), t0 + spb * 2)
            for i in range(8):
                place(buf, hat(), t0 + i * spb / 2)
        elif drum_style == 'drive':
            for i in range(4):
                place(buf, kick(), t0 + i * spb)
                place(buf, snare(), t0 + i * spb + spb / 2)
            for i in range(16):
                place(buf, hat(0.04, 0.16), t0 + i * spb / 4)
        elif drum_style == 'combat':
            place(buf, kick(), t0)
            place(buf, kick(), t0 + spb * 0.75)
            place(buf, snare(), t0 + spb * 0.5)
            place(buf, kick(0.13, 0.7), t0 + spb * 1.5)
            place(buf, snare(), t0 + spb * 2)
            place(buf, kick(), t0 + spb * 2.5)
            place(buf, snare(0.12, 0.5), t0 + spb * 3)
            place(buf, kick(), t0 + spb * 3.25)
            for i in range(8):
                place(buf, hat(0.04, 0.2), t0 + i * spb / 2 + spb / 4)
    return buf


def _finish(buf, name, fade_out=2.0):
    """立体声化(轻延迟) + 软限幅 + 收尾淡出"""
    d = int(0.16 * SR)
    delay = np.zeros(len(buf))
    delay[d:] = buf[:-d] * 0.22
    left = buf + delay
    right = buf * 0.92 + np.roll(buf, d // 2) * 0.18
    stereo = np.stack([left, right], axis=1)
    stereo = np.tanh(stereo * 1.25) * 0.82  # 软限幅
    n = len(stereo)
    fo = int(fade_out * SR)
    stereo[n - fo:] *= np.linspace(1, 0, fo)[:, None]
    fi = int(0.05 * SR)
    stereo[:fi] *= np.linspace(0, 1, fi)[:, None]
    path = os.path.join(OUT, name + '.ogg')
    # 分块写(本机 libsndfile 大缓冲一次性写 OGG 会原生崩溃)
    with sf.SoundFile(path, 'w', samplerate=SR, channels=2, format='OGG',
                      subtype='VORBIS') as f:
        step = SR * 5
        for i in range(0, len(stereo), step):
            f.write(stereo[i:i + step])
    dur = n / SR
    print('%-10s %5.1fs %6.1fKB' % (name, dur, os.path.getsize(path) / 1024))
    return path


# ---------------------------------------------------------------- 六首曲子
# C=0 大调音级; 负数=低八度。和弦用音级列表。



def _double(prog, bass, lead):
    """八度内重复一遍(第二遍移高八度琶音/主旋律不变) — 曲目长度翻倍"""
    p2 = [(b + 16, c) for b, c in prog]
    b2 = [(b + 16, bt, d, o, du) for b, bt, d, o, du in bass]
    l2 = [(b + 16, bt, d, o, du) for b, bt, d, o, du in lead]
    return prog + p2, bass + b2, lead + l2


def _lobby():
    # D 宫五声(安宁): D E F#A B → 音级 2 4 6 9 11
    s = Song(bpm=76, bars=32)
    ch = [2, 6, 9]        # D F# A
    am = [9, 12 + 4 - 12, 4]  # A C# E → 简化 [9,1,4]
    prog = [(0, [2, 6, 9]), (2, [7, 11, 14]), (4, [9, 13, 16]),
            (6, [4, 7, 11]), (8, [2, 6, 9]), (10, [7, 11, 14]),
            (12, [9, 13, 16]), (14, [6, 9, 14])]
    bass = []
    for bar, c in prog:
        bass.append((bar, 0.0, c[0] - 12, -1, s.spb * 3.6))
        bass.append((bar, 3.0, c[0] - 12, -1, s.spb * 0.9))
    lead = [
        (0, 0.0, 14, 0, 1.0), (0, 1.5, 13, 0, 0.5), (0, 2.0, 11, 0, 2.0),
        (2, 0.0, 9, 0, 1.5), (2, 2.0, 11, 0, 0.75), (2, 2.75, 9, 0, 1.25),
        (4, 0.0, 13, 0, 1.0), (4, 1.5, 16, 0, 0.5), (4, 2.0, 14, 0, 2.0),
        (6, 0.0, 11, 0, 1.0), (6, 1.0, 9, 0, 1.0), (6, 2.0, 7, 0, 2.0),
        (8, 0.0, 14, 0, 1.0), (8, 1.5, 16, 0, 0.5), (8, 2.0, 18, 0, 2.0),
        (10, 0.0, 16, 0, 1.5), (10, 2.0, 14, 0, 2.0),
        (12, 0.0, 13, 0, 1.0), (12, 1.0, 11, 0, 1.0), (12, 2.0, 13, 0, 2.0),
        (14, 0.0, 9, 0, 4.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='soft')
    return _finish(buf, 'lobby')


def _table():
    # C 大调明亮(欢快牌局)
    s = Song(bpm=126, bars=32)
    prog = [(0, [0, 4, 7]), (2, [9, 12, 16]), (4, [5, 9, 12]), (6, [7, 11, 14]),
            (8, [0, 4, 7]), (10, [2, 5, 9]), (12, [7, 11, 14]), (14, [0, 4, 7])]
    prog = prog + [(b + 8, c) for b, c in prog[:4]]  # 补到16小节变化
    bass = []
    for bar, c in prog:
        for i in range(4):
            bass.append((bar, i + (0.5 if i % 2 else 0), c[0] - 12, -1,
                         s.spb * 0.42))
    lead = [
        (0, 0.0, 16, 0, 0.5), (0, 0.5, 14, 0, 0.5), (0, 1.0, 12, 0, 1.0),
        (0, 2.0, 16, 0, 1.0), (0, 3.0, 19, 0, 1.0),
        (2, 0.0, 21, 0, 0.75), (2, 0.75, 19, 0, 0.75), (2, 1.5, 16, 0, 1.5),
        (2, 3.0, 14, 0, 1.0),
        (4, 0.0, 17, 0, 0.5), (4, 0.5, 16, 0, 0.5), (4, 1.0, 12, 0, 1.0),
        (4, 2.0, 17, 0, 2.0),
        (6, 0.0, 19, 0, 1.0), (6, 1.5, 18, 0, 0.5), (6, 2.0, 14, 0, 2.0),
        (8, 0.0, 16, 0, 0.5), (8, 0.5, 19, 0, 0.5), (8, 1.0, 24, 0, 2.0),
        (10, 0.0, 21, 0, 1.0), (10, 1.0, 19, 0, 1.0), (10, 2.0, 16, 0, 2.0),
        (12, 0.0, 14, 0, 0.75), (12, 0.75, 16, 0, 0.75), (12, 1.5, 19, 0, 1.5),
        (12, 3.0, 23, 0, 1.0),
        (14, 0.0, 24, 0, 2.0), (14, 2.0, 19, 0, 1.0), (14, 3.0, 16, 0, 1.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='drive',
                  lead_vol=0.26)
    return _finish(buf, 'table')


def _table_rev():
    # A 小调急板(革命/逆风局)
    s = Song(bpm=140, bars=32)
    prog = [(0, [9, 12, 16]), (2, [4, 7, 12]), (4, [0, 4, 7]), (6, [7, 11, 14]),
            (8, [9, 12, 16]), (10, [5, 8, 12]), (12, [7, 11, 14]), (14, [11, 14, 19])]
    prog = prog + [(b + 8, c) for b, c in prog[:4]]
    bass = []
    for bar, c in prog:
        for i in range(8):
            bass.append((bar, i * 0.5, c[0] - 24, 0, s.spb * 0.4))
    lead = [
        (0, 0.0, 21, 0, 0.5), (0, 0.5, 20, 0, 0.5), (0, 1.0, 16, 0, 0.5),
        (0, 1.5, 21, 0, 0.5), (0, 2.0, 23, 0, 1.0), (0, 3.0, 21, 0, 1.0),
        (2, 0.0, 19, 0, 0.75), (2, 0.75, 16, 0, 0.75), (2, 1.5, 12, 0, 1.5),
        (2, 3.0, 19, 0, 1.0),
        (4, 0.0, 24, 0, 0.5), (4, 0.5, 23, 0, 0.5), (4, 1.0, 21, 0, 0.5),
        (4, 1.5, 19, 0, 0.5), (4, 2.0, 21, 0, 2.0),
        (6, 0.0, 23, 0, 1.0), (6, 1.0, 26, 0, 1.0), (6, 2.0, 23, 0, 2.0),
        (8, 0.0, 21, 0, 0.5), (8, 0.5, 24, 0, 0.5), (8, 1.0, 28, 0, 1.5),
        (8, 2.5, 26, 0, 0.5), (8, 3.0, 24, 0, 1.0),
        (10, 0.0, 25, 0, 1.0), (10, 1.0, 24, 0, 0.5), (10, 1.5, 21, 0, 1.5),
        (10, 3.0, 20, 0, 1.0),
        (12, 0.0, 19, 0, 0.5), (12, 0.5, 23, 0, 0.5), (12, 1.0, 26, 0, 1.0),
        (12, 2.0, 23, 0, 2.0),
        (14, 0.0, 28, 0, 2.0), (14, 2.0, 27, 0, 1.0), (14, 3.0, 23, 0, 1.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='combat',
                  lead_vol=0.24, arp_vol=0.10)
    return _finish(buf, 'table_rev')


def _rogue():
    # E 多利亚神秘(命运/肉鸽)
    s = Song(bpm=92, bars=32)
    prog = [(0, [4, 7, 11]), (2, [11, 14, 18]), (4, [2, 5, 9]), (6, [9, 12, 16]),
            (8, [4, 7, 11]), (10, [6, 9, 13]), (12, [2, 5, 9]), (14, [7, 11, 14])]
    prog = prog + [(b + 8, c) for b, c in prog[:4]]
    bass = []
    for bar, c in prog:
        bass.append((bar, 0.0, c[0] - 12, -1, s.spb * 1.9))
        bass.append((bar, 2.0, c[0] - 12, -1, s.spb * 1.9))
    lead = [
        (0, 0.0, 16, 0, 1.5), (0, 1.5, 14, 0, 0.5), (0, 2.0, 11, 0, 2.0),
        (2, 0.0, 18, 0, 1.0), (2, 1.0, 16, 0, 1.0), (2, 2.0, 14, 0, 2.0),
        (4, 0.0, 13, 0, 1.5), (4, 1.5, 12, 0, 0.5), (4, 2.0, 9, 0, 2.0),
        (6, 0.0, 16, 0, 2.0), (6, 2.0, 12, 0, 2.0),
        (8, 0.0, 16, 0, 1.5), (8, 1.5, 18, 0, 0.5), (8, 2.0, 19, 0, 2.0),
        (10, 0.0, 18, 0, 1.0), (10, 1.0, 16, 0, 1.0), (10, 2.0, 13, 0, 2.0),
        (12, 0.0, 14, 0, 1.0), (12, 1.0, 13, 0, 1.0), (12, 2.0, 11, 0, 2.0),
        (14, 0.0, 14, 0, 4.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='soft',
                  lead_vol=0.27, arp_vol=0.09)
    return _finish(buf, 'rogue')


def _boss():
    # 弗里几亚狂暴(BOSS)
    s = Song(bpm=168, bars=32)
    prog = [(0, [4, 7, 12]), (1, [4, 7, 12]), (2, [5, 8, 12]), (3, [5, 8, 12]),
            (4, [0, 4, 7]), (5, [0, 4, 7]), (6, [2, 5, 9]), (7, [2, 5, 9]),
            (8, [4, 7, 12]), (9, [4, 7, 12]), (10, [10, 13, 17]),
            (11, [10, 13, 17]), (12, [5, 8, 12]), (13, [7, 11, 14]),
            (14, [4, 7, 12]), (15, [4, 7, 12])]
    bass = []
    for bar, c in prog:
        for i in range(8):
            bass.append((bar, i * 0.5, c[0] - 24 + (12 if i in (3, 6) else 0),
                         0, s.spb * 0.45))
    lead = [
        (0, 0.0, 16, 0, 0.25), (0, 0.25, 17, 0, 0.25), (0, 0.5, 16, 0, 0.5),
        (0, 1.0, 12, 0, 0.5), (0, 1.5, 16, 0, 0.5),
        (0, 2.0, 19, 0, 0.5), (0, 2.5, 17, 0, 0.5), (0, 3.0, 16, 0, 1.0),
        (2, 0.0, 17, 0, 0.25), (2, 0.25, 18, 0, 0.25), (2, 0.5, 17, 0, 0.5),
        (2, 1.0, 12, 0, 0.5), (2, 1.5, 17, 0, 0.5),
        (2, 2.0, 20, 0, 0.75), (2, 2.75, 19, 0, 0.25), (2, 3.0, 17, 0, 1.0),
        (4, 0.0, 12, 0, 0.5), (4, 0.5, 16, 0, 0.5), (4, 1.0, 19, 0, 0.5),
        (4, 1.5, 24, 0, 0.5), (4, 2.0, 23, 0, 1.0), (4, 3.0, 19, 0, 1.0),
        (6, 0.0, 21, 0, 0.5), (6, 0.5, 19, 0, 0.5), (6, 1.0, 16, 0, 1.0),
        (6, 2.0, 14, 0, 2.0),
        (8, 0.0, 16, 0, 0.25), (8, 0.25, 17, 0, 0.25), (8, 0.5, 16, 0, 0.5),
        (8, 1.0, 19, 0, 0.5), (8, 1.5, 16, 0, 0.5),
        (8, 2.0, 22, 0, 0.5), (8, 2.5, 24, 0, 0.5), (8, 3.0, 22, 0, 1.0),
        (10, 0.0, 20, 0, 0.5), (10, 0.5, 19, 0, 0.5), (10, 1.0, 17, 0, 1.0),
        (10, 2.0, 20, 0, 2.0),
        (12, 0.0, 19, 0, 0.75), (12, 0.75, 20, 0, 0.75), (12, 1.5, 19, 0, 0.5),
        (12, 2.0, 16, 0, 2.0),
        (14, 0.0, 28, 0, 1.0), (14, 1.0, 27, 0, 1.0), (14, 2.0, 24, 0, 1.0),
        (14, 3.0, 19, 0, 1.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='combat',
                  lead_vol=0.24, arp_vol=0.11, bass_vol=0.4)
    return _finish(buf, 'boss')


def _fight():
    # 格斗摇滚(战斗登场)
    s = Song(bpm=152, bars=32)
    prog = [(0, [7, 11, 14]), (2, [5, 9, 12]), (4, [7, 11, 14]), (6, [9, 12, 16]),
            (8, [2, 5, 9]), (10, [4, 7, 12]), (12, [5, 9, 12]), (14, [7, 11, 14])]
    prog = prog + [(b + 8, c) for b, c in prog[:4]]
    bass = []
    for bar, c in prog:
        for i in range(8):
            if i in (0, 3, 6):
                bass.append((bar, i * 0.5, c[0] - 24, 0, s.spb * 0.45))
            else:
                bass.append((bar, i * 0.5, c[0] - 24, 0, s.spb * 0.22))
    lead = [
        (0, 0.0, 14, 0, 0.5), (0, 0.5, 11, 0, 0.25), (0, 0.75, 14, 0, 0.25),
        (0, 1.0, 16, 0, 0.5), (0, 1.5, 18, 0, 0.5), (0, 2.0, 21, 0, 1.0),
        (0, 3.0, 18, 0, 1.0),
        (2, 0.0, 17, 0, 0.5), (2, 0.5, 12, 0, 0.5), (2, 1.0, 17, 0, 0.5),
        (2, 1.5, 21, 0, 0.5), (2, 2.0, 19, 0, 2.0),
        (4, 0.0, 14, 0, 0.5), (4, 0.5, 11, 0, 0.25), (4, 0.75, 14, 0, 0.25),
        (4, 1.0, 16, 0, 0.5), (4, 1.5, 19, 0, 0.5), (4, 2.0, 23, 0, 1.0),
        (4, 3.0, 21, 0, 1.0),
        (6, 0.0, 21, 0, 0.75), (6, 0.75, 19, 0, 0.25), (6, 1.0, 16, 0, 1.0),
        (6, 2.0, 21, 0, 2.0),
        (8, 0.0, 13, 0, 0.5), (8, 0.5, 12, 0, 0.5), (8, 1.0, 9, 0, 1.0),
        (8, 2.0, 13, 0, 2.0),
        (10, 0.0, 12, 0, 0.75), (10, 0.75, 11, 0, 0.25), (10, 1.0, 12, 0, 1.0),
        (10, 2.0, 16, 0, 2.0),
        (12, 0.0, 17, 0, 0.5), (12, 0.5, 19, 0, 0.5), (12, 1.0, 21, 0, 1.0),
        (12, 2.0, 24, 0, 2.0),
        (14, 0.0, 23, 0, 0.5), (14, 0.5, 21, 0, 0.5), (14, 1.0, 19, 0, 0.5),
        (14, 1.5, 18, 0, 0.5), (14, 2.0, 14, 0, 2.0),
    ]
    prog, bass, lead = _double(prog, bass, lead)
    buf = _render(s, prog, bass, lead, arp_on=True, drum_style='combat',
                  lead_vol=0.25, bass_vol=0.4)
    return _finish(buf, 'fight')


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in ('lobby', 'table', 'table_rev', 'rogue', 'boss', 'fight'):
        compose(name)
    print('→', OUT)


if __name__ == '__main__':
    main()
