# -*- coding: utf-8 -*-
"""BGM 作曲 v2 — 六首曲目谱面(由 gen_music.py 的音色引擎渲染)。

谱面记法: 音符=(拍, 时值, 音级, 八度) — 音级走音阶, 和弦给 [度..]
鼓 pattern 字符串 16 步/小节: K底鼓 S军鼓 h闭镲 H开镲 b沙锤 T桶鼓 .休止
"""
from gen_music import (MAJ, MIN, DOR, PHR, deg, ch, new_song)


def _play(s, start_bar, notes, kind='lead', scale=None, root=None,
          oct_shift=0, vel=1.0):
    for (b, d, dg, oc) in notes:
        s.note(start_bar * 4 + b, kind, deg(scale, root, dg, oc + oct_shift),
               d, vel)


def _comp(s, start_bar, bars, prog, scale, root, vel=0.72, beat2=2.5):
    """EP 和弦伴奏: 每小节正拍 + 切分反拍"""
    for i in range(bars):
        dg = prog[(start_bar + i) % len(prog)]
        freqs = ch(scale, root, dg, 0)
        s.chord(start_bar * 4 + i * 4, 'ep', freqs, 1.5, vel)
        s.chord(start_bar * 4 + i * 4 + beat2, 'ep', freqs, 1.2, vel * 0.8)


def _bass_line(s, start_bar, bars, prog, scale, root, style='half',
               vel=0.9):
    """低音: half=根音2拍+五音2拍; eight=八分根音蹦跳"""
    for i in range(bars):
        dg = prog[(start_bar + i) % len(prog)]
        t0 = start_bar * 4 + i * 4
        if style == 'half':
            s.note(t0, 'bass', deg(scale, root, dg, -1), 2, vel)
            s.note(t0 + 2, 'bass', deg(scale, root, dg + 4, -1), 2, vel * 0.8)
        else:   # eight: 根-根-五-根 蹦跳
            root_f = deg(scale, root, dg, -1)
            fifth_f = deg(scale, root, dg + 4, -1)
            for k in range(8):
                f = fifth_f if k in (3, 6) else root_f
                s.note(t0 + k * 0.5, 'bass', f,
                       0.42 if k in (1, 4, 7) else 0.46, vel * 0.92)


def _arp(s, start_bar, bars, prog, scale, root, octv=1, vel=0.55):
    """拨弦八分琶音(和弦音上行走)"""
    for i in range(bars):
        dg = prog[(start_bar + i) % len(prog)]
        tones = ch(scale, root, dg, octv)
        seq = [tones[0], tones[1], tones[2], tones[1]]
        t0 = start_bar * 4 + i * 4
        for k in range(8):
            s.note(t0 + k * 0.5, 'pluck', seq[k % 4] if k % 2 == 0
                   else seq[(k + 2) % 4], 0.45, vel * (0.9 if k % 2 else 1.0))


# ---------------------------------------------------------------- 首页

def lobby():
    """首页: C 大调 104BPM 温暖邀约 — 钢琴+垫弦开场, 主旋律歌唱, B 段琶音扬起"""
    sc, rt = MAJ, 60          # C
    s = new_song(104, 32)
    prog_a = [0, 4, 5, 3, 0, 2, 3, 4]          # C G Am F C Em F G
    prog_b = [5, 3, 0, 4, 5, 3, 1, 4]          # Am F C G Am F Dm G
    prog_o = [0, 4, 5, 3, 0, 3, 4, 4]          # 尾声回落
    # A 段主旋律(8 小节, 强拍落和弦音)
    mel_a = [
        (0, 1.5, 2, 1), (1.5, .5, 4, 1), (2, 1, 5, 1), (3, 1, 4, 1),
        (4, 1, 1, 1), (5, .5, 6, 0), (5.5, .5, 1, 1), (6, 1, 1, 1), (7, 1, 6, 0),
        (8, 2, 0, 1), (10, 1, 5, 0), (11, 1, 0, 1),
        (12, 1.5, 5, 0), (13.5, .5, 0, 1), (14, 1, 0, 1), (15, 1, 1, 1),
        (16, 1, 2, 1), (17, 1, 4, 1), (18, 1, 5, 1), (19, 1, 4, 1),
        (20, 1.5, 4, 1), (21.5, .5, 2, 1), (22, 1, 1, 1), (23, 1, 2, 1),
        (24, 1, 0, 1), (25, 1, 1, 1), (26, 1, 0, 1), (27, 1, 5, 0),
        (28, 2, 4, 0), (30, 1, 6, 0), (31, 1, 1, 1),
    ]
    # intro 0-3: 垫弦 + EP + 轻鼓
    for i, dg in enumerate(prog_a[:4]):
        s.pad(i * 4, ch(sc, rt, dg, 0), 4.0, 0.9)
    _comp(s, 0, 4, prog_a, sc, rt, 0.6)
    _bass_line(s, 0, 4, prog_a, sc, rt, 'half', 0.7)
    s.drum_pat(0, ['K...b.b.K...b.b.'], 4, 0.7)
    # A 4-11: 旋律 + 全奏
    _play(s, 4, mel_a, 'lead', sc, rt, 0, 1.0)
    _comp(s, 4, 8, prog_a, sc, rt)
    _bass_line(s, 4, 8, prog_a, sc, rt, 'half')
    s.drum_pat(4, ['K.h.h.h.S.h.h.h.'] * 3 + ['K.h.h.h.S.h.hHTT'], 8)
    s.fill(7)
    # A' 12-19: 旋律重奏 + 琶音
    _play(s, 12, mel_a, 'lead', sc, rt, 0, 0.92)
    _arp(s, 12, 8, prog_a, sc, rt, 1, 0.5)
    _comp(s, 12, 8, prog_a, sc, rt, 0.65)
    _bass_line(s, 12, 8, prog_a, sc, rt, 'half')
    s.drum_pat(12, ['K.h.h.h.S.h.h.h.'] * 3 + ['K.h.h.h.S.h.hHTT'], 8)
    s.fill(15)
    # B 20-27: 扬起 — 上行琶音句 + 开镲
    for i, dg in enumerate(prog_b):
        s.pad(20 * 4 + i * 4, ch(sc, rt, dg, 0), 4.0, 1.0)
    for i in range(8):
        dg = prog_b[i]
        tones = ch(sc, rt, dg, 1)
        t0 = 20 * 4 + i * 4
        for off, dur, ti in [(0, .5, 0), (.5, .5, 1), (1, 1, 2),
                             (2, .5, 0), (2.5, .5, 1), (3, 1, 2)]:
            s.note(t0 + off, 'lead', tones[ti % len(tones)], dur, 0.85)
        s.note(t0 + 3, 'glock', deg(sc, rt, dg, 2), 1, 0.8)
    _comp(s, 20, 8, prog_b, sc, rt, 0.7)
    _bass_line(s, 20, 8, prog_b, sc, rt, 'half')
    s.drum_pat(20, ['K.h.h.h.S.h.H.h.'] * 7 + ['K.h.h.h.S.h.TTTT'], 8)
    s.fill(27)
    # outro 28-31: 收回落, 属和弦悬回主和弦(循环点)
    for i, dg in enumerate(prog_o):
        s.pad(28 * 4 + i * 4, ch(sc, rt, dg, 0), 4.0, 0.85)
    _comp(s, 28, 4, prog_o, sc, rt, 0.6)
    _bass_line(s, 28, 4, prog_o, sc, rt, 'half', 0.75)
    s.drum_pat(28, ['K.......b.......'], 4, 0.55)
    s.note(28 * 4, 'glock', deg(sc, rt, 0, 2), 3, 0.7)
    s.note(30 * 4, 'glock', deg(sc, rt, 4, 2), 3, 0.6)
    return s.render('lobby')


# ---------------------------------------------------------------- 对局

def table():
    """对局: G 大调 120BPM 摇摆律动 — 弹跳 riff 钩子 + 抒展 B 段 + 桥段推升"""
    sc, rt = MAJ, 67          # G
    s = new_song(120, 32, swing=1.0)
    prog_a = [0, 4, 5, 3, 0, 4, 3, 4]          # G D Em C G D C D
    prog_c = [5, 3, 1, 4]                      # Em C Am D
    # A 段 riff 钩子(G 大调五声: G A B D E)
    riff = [
        (0, .5, 4, 0), (.5, .5, 4, 0), (1, 1, 0, 0), (2, .5, 2, 0),
        (2.5, .5, 1, 0), (3, 1, 0, 0),
        (4, .5, 2, 0), (4.5, .5, 2, 0), (5, 1, 4, 0), (6, 1, 5, 0), (7, 1, 4, 0),
        (8, .5, 5, 0), (8.5, .5, 5, 0), (9, 1, 4, 1), (10, .5, 5, 0),
        (10.5, .5, 4, 0), (11, 1, 2, 0),
        (12, 1, 3, 1), (13, .5, 2, 1), (13.5, .5, 1, 1), (14, 1, 0, 1),
        (15, 1, 1, 1),
        (16, .5, 4, 0), (16.5, .5, 4, 0), (17, 1, 0, 0), (18, .5, 2, 0),
        (18.5, .5, 1, 0), (19, 1, 0, 0),
        (20, .5, 2, 0), (20.5, .5, 2, 0), (21, 1, 4, 0), (22, 1, 5, 0),
        (23, 1, 4, 0),
        (24, 1, 4, 1), (25, 1, 5, 1), (26, 1, 7, 1), (27, 1, 8, 1),
        (28, 2, 7, 1), (30, 1, 5, 1), (31, 1, 4, 1),
    ]
    # B 段抒情旋律
    mel_b = [
        (0, 1.5, 4, 1), (1.5, .5, 5, 1), (2, 1, 6, 1), (3, 1, 5, 1),
        (4, 1, 5, 1), (5, 1, 6, 1), (6, 1, 4, 1), (7, 1, 5, 1),
        (8, 2, 4, 1), (10, 1, 2, 1), (11, 1, 4, 1),
        (12, 1, 5, 1), (13, 1, 4, 1), (14, 2, 2, 1),
        (16, 1, 4, 0), (17, 1, 4, 1), (18, 2, 6, 1),
        (20, 1, 5, 1), (21, .5, 6, 1), (21.5, .5, 5, 1), (22, 1, 4, 1),
        (23, 1, 4, 1),
        (24, 1, 3, 1), (25, 1, 4, 1), (26, 1, 5, 1), (27, 1, 6, 1),
        (28, 1, 5, 1), (29, 1, 6, 1), (30, 2, 4, 1),
    ]
    # intro 0-1: 鼓 + 贝斯点入
    s.drum_pat(0, ['K.h.S.h.K.h.S.hH'], 2, 0.85)
    _bass_line(s, 0, 2, [0, 4], sc, rt, 'eight', 0.8)
    # A 2-9: riff
    _play(s, 2, riff, 'lead', sc, rt, 0, 1.0)
    _comp(s, 2, 8, prog_a, sc, rt, 0.68)
    _bass_line(s, 2, 8, prog_a, sc, rt, 'eight')
    s.drum_pat(2, ['K.h.h.h.S.h.h.h.'] * 7 + ['K.h.h.h.S.h.hHTT'], 8)
    s.fill(9)
    # B 10-17: 抒情
    _play(s, 10, mel_b, 'lead', sc, rt, 0, 0.95)
    _arp(s, 10, 8, prog_a, sc, rt, 1, 0.5)
    _comp(s, 10, 8, prog_a, sc, rt, 0.6)
    _bass_line(s, 10, 8, prog_a, sc, rt, 'half')
    s.drum_pat(10, ['K.h.h.h.S.h.H.h.'] * 7 + ['K.h.h.h.S.h.TTTT'], 8)
    s.fill(17)
    # A' 18-25: riff + 琶音对位
    _play(s, 18, riff, 'lead', sc, rt, 0, 0.95)
    _arp(s, 18, 8, prog_a, sc, rt, 1, 0.5)
    _comp(s, 18, 8, prog_a, sc, rt, 0.68)
    _bass_line(s, 18, 8, prog_a, sc, rt, 'eight')
    s.drum_pat(18, ['K.h.K.h.S.h.K.h.'] * 7 + ['K.h.h.h.S.h.hHTT'], 8)
    s.fill(25)
    # 桥 26-29: 推升(沙锤渐密)
    for i, dg in enumerate(prog_c):
        s.pad(26 * 4 + i * 4, ch(sc, rt, dg, 0), 4.0, 0.9)
    _comp(s, 26, 4, prog_c, sc, rt, 0.7)
    _bass_line(s, 26, 4, prog_c, sc, rt, 'eight')
    s.drum_pat(26, ['K...b...K.b.b...', 'K...b...K.b.b.b.',
                    'K.b.b.b.K.bSbSbS', 'KKbKSKbSKKS.KKS.'], 4, 0.9)
    # 终段 30-31: riff 回句收束
    _play(s, 30, [(0, .5, 4, 0), (.5, .5, 4, 0), (1, 1, 0, 0),
                  (2, 1, 2, 0), (3, 1, 1, 0),
                  (4, 1, 2, 0), (5, 1, 4, 0), (6, 2, 4, 0)],
          'lead', sc, rt, 0, 1.0)
    _bass_line(s, 30, 2, [4, 4], sc, rt, 'eight')
    s.drum_pat(30, ['K.h.h.h.S.h.h.hH', 'KKS.KKS.K.S.HTT.'], 2, 0.95)
    return s.render('table')


# ---------------------------------------------------------------- 革命对局

def table_rev():
    """革命: A 小调 150BPM 急进 — 八分低音 + 小调五声 riff + 铜管刺击"""
    sc, rt = MIN, 57          # A
    s = new_song(150, 32)
    prog = [0, 5, 3, 4, 0, 5, 4, 4]           # Am F C G Am F G G
    riff = [
        (0, .5, 0, 1), (.5, .5, 0, 1), (1, 1, 2, 1), (2, .5, 4, 1),
        (2.5, .5, 3, 1), (3, 1, 2, 1),
        (4, .5, 4, 1), (4.5, .5, 4, 1), (5, 1, 5, 1), (6, 1, 4, 1), (7, 1, 2, 1),
        (8, 1, 5, 1), (9, .5, 4, 1), (9.5, .5, 5, 1), (10, 1, 7, 1),
        (11, 1, 5, 1),
        (12, 1.5, 4, 1), (13.5, .5, 3, 1), (14, 1, 2, 1), (15, 1, 0, 1),
    ]
    for rep in range(3):
        b0 = rep * 10
        _play(s, b0, riff, 'lead', sc, rt, 0, 1.0 if rep < 2 else 0.9)
        for i in range(10):
            dg = prog[(b0 + i) % len(prog)]
            s.chord(b0 * 4 + i * 4 + 1.5, 'stab', ch(sc, rt, dg, 0), 0.8, 0.8)
        _bass_line(s, b0, 10, prog, sc, rt, 'eight', 1.0)
        s.drum_pat(b0, ['K.h.K.h.S.h.K.h.'] * 7 + ['K.h.K.h.S.h.SHTT'],
                   10, 0.95)
        s.fill(b0 + 9)
    # 桥 30-31: 紧张收束回循环
    for i, dg in enumerate([5, 4]):
        s.chord(30 * 4 + i * 4, 'stab', ch(sc, rt, dg, 0), 2.0, 1.0)
    _play(s, 30, [(0, .5, 7, 1), (.5, .5, 5, 1), (1, 1, 4, 1), (2, 2, 2, 1)],
          'lead', sc, rt, 0, 1.0)
    _bass_line(s, 30, 2, [5, 4], sc, rt, 'eight', 1.0)
    s.drum_pat(30, ['K.S.K.S.K.S.HTT.', 'KKS.KKS.KKSSHTHT'], 2, 1.0)
    return s.render('table_rev')


# ---------------------------------------------------------------- 肉鸽

def rogue():
    """肉鸽: D 多利亚 96BPM 神秘推进 — 拨弦点描 + 手鼓 + 笛句若现"""
    sc, rt = DOR, 62          # D
    s = new_song(96, 24)
    prog = [0, 3, 0, 6, 0, 3, 5, 3]           # Dm G Dm C Dm G Am G
    mel = [
        (0, 1.5, 0, 1), (1.5, .5, 2, 1), (2, 1, 3, 1), (3, 2, 2, 1),
        (4, 1, 0, 1), (5, .5, 2, 1), (5.5, .5, 3, 1), (6, 2, 4, 1),
        (8, 1.5, 4, 1), (9.5, .5, 3, 1), (10, 1, 2, 1), (11, 1, 0, 1),
        (12, 1, 4, 0), (13, 1, 3, 0), (14, 2, 2, 0),
        (16, 1, 0, 1), (17, .5, 2, 1), (17.5, .5, 3, 1), (18, 1, 5, 1),
        (19, 1, 4, 1),
        (20, 1.5, 3, 1), (21.5, .5, 2, 1), (22, 2, 0, 1),
    ]
    for rep in range(3):
        b0 = rep * 8
        _play(s, b0, mel, 'lead', sc, rt, 0, 0.9 if rep else 0.8)
        _arp(s, b0, 8, prog, sc, rt, 0, 0.5)
        _comp(s, b0, 8, prog, sc, rt, 0.55)
        _bass_line(s, b0, 8, prog, sc, rt, 'half', 0.85)
        s.drum_pat(b0, ['K...b...K.b.b...'] if rep < 2 else
                   ['K.b.b...K.b.b.b.'], 8, 0.8)
        s.fill(b0 + 7)
    return s.render('rogue')


# ---------------------------------------------------------------- BOSS

def boss():
    """BOSS: E 弗里几亚 158BPM 狂暴 — 双底鼓 + 铜管刺击 + 高音嘶吼"""
    sc, rt = PHR, 52          # E
    s = new_song(158, 32)
    prog = [0, 0, 1, 0, 0, 5, 1, 0]           # E E F E E C F E
    riff = [
        (0, .5, 0, 1), (.5, .25, 1, 1), (.75, .25, 0, 1), (1, .5, 3, 1),
        (1.5, .5, 0, 1), (2, .5, 1, 1), (2.5, .5, 0, 1), (3, 1, 3, 1),
        (4, .5, 0, 1), (4.5, .25, 1, 1), (4.75, .25, 0, 1), (5, .5, 3, 1),
        (5.5, .5, 5, 1), (6, 1, 3, 1), (7, 1, 1, 1),
        (8, .5, 7, 1), (8.5, .5, 5, 1), (9, .5, 3, 1), (9.5, .5, 5, 1),
        (10, 1, 7, 1), (11, 1, 5, 1),
        (12, 1, 5, 1), (13, .5, 3, 1), (13.5, .5, 5, 1), (14, 2, 3, 1),
        (16, .5, 0, 1), (16.5, .5, 0, 1), (17, 1, 3, 1), (18, 1, 5, 1),
        (19, 1, 3, 1),
        (20, .5, 3, 1), (20.5, .5, 3, 1), (21, 1, 5, 1), (22, 1, 7, 1),
        (23, 1, 5, 1),
        (24, 1.5, 5, 1), (25.5, .5, 3, 1), (26, 1, 5, 1), (27, 1, 7, 1),
        (28, 1, 5, 2), (29, 1, 3, 2), (30, 2, 0, 1),
    ]
    for rep in range(3):
        b0 = rep * 10
        _play(s, b0, riff, 'lead', sc, rt, 0, 1.0)
        for i in range(10):
            dg = prog[(b0 + i) % len(prog)]
            s.chord(b0 * 4 + i * 4, 'stab',
                    [deg(sc, rt, dg, 0), deg(sc, rt, dg + 4, 0)], 0.9, 1.0)
        _bass_line(s, b0, 10, prog, sc, rt, 'eight', 1.05)
        s.drum_pat(b0, ['K.K.S.K.K.h.S.h.', 'K.K.S.h.K.h.S.HH'], 10, 1.0)
        s.fill(b0 + 9)
    _play(s, 30, [(0, .5, 0, 1), (.5, .5, 1, 1), (1, .5, 0, 1),
                  (1.5, .5, 1, 1), (2, 2, 0, 1)], 'lead', sc, rt, 0, 1.0)
    _bass_line(s, 30, 2, [0, 0], sc, rt, 'eight', 1.05)
    s.drum_pat(30, ['K.K.K.K.S.S.S.S.', 'KKS.KKS.KKS.HTHT'], 2, 1.05)
    return s.render('boss')


# ---------------------------------------------------------------- 格斗

def fight():
    """格斗: A 小调 140BPM 热血摇滚 — 力度和弦 + 呼应短句 + 军鼓推进"""
    sc, rt = MIN, 57          # A
    s = new_song(140, 32)
    prog = [0, 5, 3, 4, 0, 5, 3, 4]           # Am F C G 循环
    riff = [
        (0, .5, 0, 1), (.5, .5, 3, 1), (1, .5, 5, 1), (1.5, .5, 3, 1),
        (2, 1, 0, 1), (3, 1, 3, 1),
        (4, .5, 5, 1), (4.5, .5, 3, 1), (5, 1, 5, 1), (6, .5, 7, 1),
        (6.5, .5, 5, 1), (7, 1, 3, 1),
        (8, 1, 7, 0), (9, .5, 5, 0), (9.5, .5, 3, 0), (10, 1, 5, 0),
        (11, 1, 0, 0),
        (12, .5, 2, 1), (12.5, .5, 3, 1), (13, 1, 2, 1), (14, 1, 0, 1),
        (15, 1, 3, 1),
    ]
    for rep in range(3):
        b0 = rep * 10
        _play(s, b0, riff, 'lead', sc, rt, 0, 1.0)
        for i in range(10):
            dg = prog[(b0 + i) % len(prog)]
            s.chord(b0 * 4 + i * 4 + 0.5, 'stab',
                    [deg(sc, rt, dg, 0), deg(sc, rt, dg + 4, 0)], 0.7, 0.9)
        _bass_line(s, b0, 10, prog, sc, rt, 'eight', 1.0)
        s.drum_pat(b0, ['K.h.K.h.S.h.K.h.'] * 9 + ['K.h.h.h.S.h.TTTH'],
                   10, 0.95)
        s.fill(b0 + 9)
    _play(s, 30, [(0, .5, 0, 1), (.5, .5, 3, 1), (1, .5, 5, 1),
                  (1.5, .5, 7, 1), (2, 2, 5, 1)], 'lead', sc, rt, 0, 1.0)
    _bass_line(s, 30, 2, [0, 0], sc, rt, 'eight', 1.0)
    s.drum_pat(30, ['K.h.K.h.S.h.K.h.', 'KKS.KKS.KKS.HTHT'], 2, 1.0)
    return s.render('fight')


ALL = [lobby, table, table_rev, rogue, boss, fight]
