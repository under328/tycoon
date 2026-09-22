# -*- coding: utf-8 -*-
"""生成 9 组格斗场景像素背景(480×270, 2x 超采样渲染后量化)。

主题对应商城头像/地下城: 森林/洞穴/熔岩/冰原/墓地(本地试炼五组)
+ 荒野(龙珠)/木叶村(忍者)/怪盗殿堂(P5)/宇宙殖民地(高达)。
图层: 天空渐变(抖动) → 天体 → 远景剪影 → 中景结构 → 地面 → 前景 → 大气粒子。
"""
import os
import sys
import math
import random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import Canvas, hexc, shade, SS
from PIL import Image, ImageDraw

W, H = 480, 270
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'assets', 'fight', 'bg')


BAYER2 = ((0, 2), (3, 1))


def _interp_stops(cols, n=12):
    """色标线性插值成 n 级渐变"""
    out = []
    for i in range(n):
        f = i / (n - 1) * (len(cols) - 1)
        b = min(int(f), len(cols) - 2)
        t = f - b
        c1, c2 = cols[b], cols[b + 1]
        out.append((int(c1[0] + (c2[0] - c1[0]) * t),
                    int(c1[1] + (c2[1] - c1[1]) * t),
                    int(c1[2] + (c2[2] - c1[2]) * t), 255))
    return out


def dither_band(cv, x0, x1, y0, y1, cols, rng):
    """垂直渐变 + 2x2 Bayer 有序抖动(平滑无条带)"""
    grad = _interp_stops(cols, 14)
    n = len(grad)
    for yy in range(y0, y1):
        f = (yy - y0) / max(y1 - y0 - 1, 1)
        idx = f * (n - 1)
        base = int(idx)
        frac = idx - base
        for xx in range(x0, x1):
            bump = 1 if BAYER2[yy % 2][xx % 2] / 4.0 < frac else 0
            cv.pix(xx, yy, grad[min(base + bump, n - 1)])


def stars(cv, n, rng, y_max, col=None, tw=None):
    for i in range(n):
        x = rng.randrange(0, W)
        y = rng.randrange(0, y_max)
        c = col[i % len(col)] if col else hexc('ffffff')
        if tw and rng.random() < 0.3:
            cv.d.rectangle([x * SS, y * SS, x * SS + SS - 1, y * SS - 1 + SS], fill=c)
        else:
            cv.pix(x, y, c)


def mountains(cv, base_y, amp, col, col2, rng, n=7, seed=None):
    rng = random.Random(seed) if seed else rng
    peaks = []
    x = 0
    while x < W:
        peak = base_y - rng.randint(int(amp * 0.3), amp)
        peaks.append((x, peak))
        x += rng.randint(60, 130)
    poly = [(0, base_y)] + peaks + [(W, base_y), (W, H), (0, H)]
    cv.poly(poly, col)
    for xx, yy in peaks:
        if rng.random() < 0.6:
            cv.poly([(xx, yy), (xx + 14, yy + 12), (xx + 5, yy + 12)], col2)


def ground(cv, y0, col, col2, rng, tex=0.35):
    cv.d.rectangle([0, y0 * SS, W * SS, H * SS], fill=col)
    for i in range(int((H - y0) * W * tex * 0.1)):
        x = rng.randrange(0, W)
        y = rng.randrange(y0, H)
        cv.pix(x, y, col2)
    # 地平线亮线
    cv.d.rectangle([0, y0 * SS, W * SS, y0 * SS + SS], fill=shade(col2, 1.4))


def vignette(cv, strength=0.35):
    small = Image.new('L', (12, 7), 0)
    sp = small.load()
    for yy in range(7):
        for xx in range(12):
            dx = (xx / 11.0 - 0.5) * 2
            dy = (yy / 6.0 - 0.5) * 2
            r = min((dx * dx + dy * dy) ** 0.5, 1.0)
            sp[xx, yy] = int(255 * max(0.0, r - 0.55) / 0.45 * strength)
    mask = small.resize((W * SS, H * SS), Image.BILINEAR)
    ov = Image.new('RGBA', (W * SS, H * SS), (4, 2, 10, 0))
    ov.putalpha(mask)
    cv.img.alpha_composite(ov)


def new_bg(pal):
    """返回 (画布, rng)"""
    rng = random.Random(42)
    cv = Canvas((W, H))
    # 把画布的 SS 换成 2(背景细节密度更适合 2x)
    return cv, rng


# ---------------------------------------------------------------- 各场景

def bg_forest():
    cv, rng = new_bg(None)
    pal = ['0a1a14', '10301e', '1a4a2c', '2a6640']
    dither_band(cv, 0, W, 0, H, [hexc(c) for c in pal], rng)
    # 月
    cv.ell([330 * SS, 34 * SS, 396 * SS, 100 * SS], hexc('e8f0d8'))
    cv.ell([344 * SS, 40 * SS, 370 * SS, 66 * SS], hexc('f8fdf0'))
    # 远山
    mountains(cv, 150, 60, hexc('123822'), hexc('1e5233'), rng, seed=1)
    # 树冠剪影(多层)
    for layer, (col, base) in enumerate([(hexc('0d2c1a'), 190), (hexc('0a2415'), 215)]):
        x = -20
        while x < W + 20:
            r = rng.randint(26, 44)
            cy = base - r // 2 - rng.randint(0, 14)
            cv.ell([(x - r) * SS, (cy - r) * SS, (x + r) * SS, (cy + r) * SS], col)
            x += r + rng.randint(8, 26)
    # 地面
    ground(cv, 228, hexc('14361f'), hexc('1e4a2c'), rng)
    # 萤火虫
    for i in range(26):
        cv.pix(rng.randrange(0, W), rng.randrange(60, 220), hexc('d8f090'))
    vignette(cv)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('e8f0d8', 'f8fdf0', '123822', '1e5233', '0d2c1a', '0a2415',
             '14361f', '1e4a2c', 'd8f090')]


def bg_cave():
    cv, rng = new_bg(None)
    pal = ['0c0a18', '181030', '241848', '342060']
    dither_band(cv, 0, W, 0, H, [hexc(c) for c in pal], rng)
    # 洞顶钟乳石
    x = 0
    while x < W:
        ln = rng.randint(18, 56)
        w0 = rng.randint(10, 22)
        cv.poly([(x - w0, 0), (x + w0, 0), (x + rng.randint(-4, 4), ln)],
                hexc('1c1434'))
        x += rng.randint(30, 60)
    # 石笋
    x = 10
    while x < W:
        ln = rng.randint(20, 60)
        w0 = rng.randint(12, 26)
        base = 236
        cv.poly([(x - w0, base), (x + w0, base), (x, base - ln)], hexc('201640'))
        x += rng.randint(50, 90)
    # 火把(两簇)
    for tx in (90, 380):
        cv.capsule((tx * SS, 150 * SS), (tx * SS, 172 * SS), 4 * SS, hexc('6a4a28'))
        for i in range(3):
            cv.poly([(tx - 7, 150), (tx + 7, 150), (tx + rng.randint(-3, 3), 128 - i * 6)],
                    hexc('ff9a3c' if i else 'ffd166'))
        cv.glow((tx * SS, 140 * SS), 30 * SS, hexc('ff9a3c'), rings=3)
    ground(cv, 236, hexc('2c2050'), hexc('3c2c64'), rng)
    # 矿物微光
    for i in range(20):
        cv.pix(rng.randrange(0, W), rng.randrange(120, 230), hexc('7ec8ff'))
    vignette(cv, 0.45)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('1c1434', '201640', '6a4a28', 'ff9a3c', 'ffd166', '181028', '281844',
             '7ec8ff', 'ffffff')]


def bg_lava():
    cv, rng = new_bg(None)
    pal = ['1c0a08', '3a100a', '571c0e', '742a10']
    dither_band(cv, 0, W, 0, 200, [hexc(c) for c in pal], rng)
    # 远处火山
    cv.poly([(80, 200), (200, 60), (240, 90), (330, 200)], hexc('2a0e0a'))
    cv.poly([(188, 70), (212, 70), (206, 100), (196, 100)], hexc('ff7f3c'))
    cv.glow((200 * SS, 74 * SS), 26 * SS, hexc('ff7f3c'), rings=3)
    # 熔岩湖地面
    cv.d.rectangle([0, 200 * SS, W * SS, H * SS], fill=hexc('a8441a'))
    for i in range(90):
        x = rng.randrange(0, W)
        y = rng.randrange(202, H)
        w = rng.randint(8, 40)
        cv.d.rectangle([x * SS, y * SS, (x + w) * SS, (y + 3) * SS],
                       fill=hexc('ffd97a' if rng.random() < 0.4 else 'ffab3c'))
        if rng.random() < 0.5:
            cv.glow(((x + w // 2) * SS, (y + 1) * SS), 10 * SS, hexc('ff9a3c'), rings=2)
    # 黑岩裂块
    for i in range(14):
        x = rng.randrange(0, W)
        y = rng.randrange(208, H - 8)
        cv.poly([(x, y), (x + rng.randint(14, 40), y + rng.randint(-4, 4)),
                 (x + rng.randint(6, 20), y + rng.randint(6, 12))], hexc('241008'))
    cv.glow((200 * SS, 90 * SS), 90 * SS, hexc('ff7f3c'), rings=3)
    # 火星
    for i in range(40):
        cv.pix(rng.randrange(0, W), rng.randrange(0, 200), hexc('ffb84e'))
    vignette(cv, 0.3)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('2a0e0a', 'ff7f3c', '8a3410', 'ffb84e', '241008', 'ffd166', 'ffffff')]


def bg_ice():
    cv, rng = new_bg(None)
    pal = ['0a1428', '10233f', '1a3a5c', '2a527c']
    dither_band(cv, 0, W, 0, H, [hexc(c) for c in pal], rng)
    # 极光
    for i in range(3):
        col = [hexc('4ecf9a'), hexc('4ea8cf'), hexc('8fd8ff')][i]
        yy = 40 + i * 16
        x = 0
        while x < W:
            w = rng.randint(30, 70)
            cv.poly([(x, yy), (x + w, yy - rng.randint(10, 26)),
                     (x + w + 20, yy + 6), (x + 14, yy + 10)], col)
            x += w + rng.randint(10, 40)
    # 冰峰
    mountains(cv, 170, 90, hexc('18344e'), hexc('b8dcf0'), rng, seed=7)
    # 冰原地面
    ground(cv, 232, hexc('c8dcec'), hexc('9ab8d4'), rng)
    # 冰晶
    for i in range(12):
        x = rng.randrange(10, W - 10)
        y = rng.randrange(180, 232)
        h = rng.randint(16, 40)
        cv.poly([(x, y), (x + 8, y), (x + 4, y - h)], hexc('d8ecf8'))
        cv.poly([(x + 1, y), (x + 4, y), (x + 3, y - h // 2)], hexc('ffffff'))
    # 雪点
    for i in range(70):
        cv.pix(rng.randrange(0, W), rng.randrange(0, H), hexc('e8f4fc'))
    vignette(cv, 0.25)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('4ecf9a', '4ea8cf', '8fd8ff', '18344e', 'b8dcf0', 'c8dcec', '9ab8d4',
             'd8ecf8', 'ffffff', 'e8f4fc')]


def bg_graveyard():
    cv, rng = new_bg(None)
    pal = ['0c0c1a', '141428', '20203c', '2c2c50']
    dither_band(cv, 0, W, 0, H, [hexc(c) for c in pal], rng)
    # 月(冷绿)
    cv.ell([360 * SS, 30 * SS, 428 * SS, 98 * SS], hexc('cfe8c0'))
    cv.ell([376 * SS, 36 * SS, 402 * SS, 62 * SS], hexc('e8f8dc'))
    # 远处枯树剪影
    for tx in (40, 130, 300, 430):
        rng2 = random.Random(tx)
        for b in range(5):
            a = math.radians(-90 + rng2.randint(-50, 50))
            ln = rng2.randint(24, 56)
            cv.capsule((tx * SS, 200 * SS),
                       ((tx + math.cos(a) * ln) * SS,
                        (200 + math.sin(a) * ln) * SS), 3 * SS, hexc('0a0a14'))
    # 墓碑
    for i, (x, s) in enumerate([(70, 1.0), (180, 0.8), (260, 1.2), (360, 0.9), (430, 0.7)]):
        w = int(18 * s)
        h = int(34 * s)
        y = 238
        cv.rrect([(x - w) * SS, (y - h) * SS, (x + w) * SS, y * SS], int(8 * s) * SS,
                 hexc('3a3a56'))
        cv.rrect([(x - w + 3) * SS, (y - h + 3) * SS, (x - w + 7) * SS, y * SS],
                 2 * SS, hexc('4e4e70'))
        cv.pix(x, y - h // 2, hexc('0c0c1a'))
        cv.pix(x + 3, y - h // 2, hexc('0c0c1a'))
    ground(cv, 238, hexc('2e2e4c'), hexc('42426a'), rng)
    # 鬼火
    for i in range(8):
        cv.glow((rng.randrange(0, W) * SS, rng.randrange(140, 230) * SS), 8 * SS,
                hexc('7dd8a0'), rings=2)
    vignette(cv, 0.5)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('cfe8c0', 'e8f8dc', '0a0a14', '3a3a56', '4e4e70', '1a1a30', '2a2a44',
             '7dd8a0', 'ffffff')]


def bg_waste():
    """龙珠风荒野: 绿天 + 奇岩柱"""
    cv, rng = new_bg(None)
    pal = ['7ec86c', '9ad878', 'b8e48c', 'd4f0a8']
    dither_band(cv, 0, W, 0, 190, [hexc(c) for c in pal], rng)
    cv.d.rectangle([0, 190 * SS, W * SS, H * SS], fill=hexc('e8c86a'))
    # 奇岩柱(叠层)
    for i, (x, h, w) in enumerate([(60, 120, 34), (120, 80, 24), (330, 140, 40),
                                   (400, 90, 26), (250, 60, 20)]):
        base = 232
        cv.poly([(x - w, base), (x - w + 6, base - h), (x - w // 2, base - h - 10),
                 (x + w // 3, base - h + 6), (x + w, base - h // 2), (x + w, base)],
                hexc('a06a3c'))
        cv.poly([(x - w + 6, base - h), (x - w // 2, base - h - 10),
                 (x + w // 3, base - h + 6), (x, base - h + 20)], hexc('c8945c'))
    # 白云(圆润)
    for i in range(5):
        x = rng.randrange(0, W)
        y = rng.randrange(20, 120)
        for j in range(4):
            r = rng.randint(10, 22)
            cv.ell([(x + j * 14 - r) * SS, (y - r // 2) * SS,
                    (x + j * 14 + r) * SS, (y + r // 2) * SS], hexc('ffffff'))
    ground(cv, 232, hexc('d8b862'), hexc('c0a04a'), rng, tex=0.5)
    vignette(cv, 0.18)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('e8c86a', 'a06a3c', 'c8945c', 'ffffff', 'd8b862', 'c0a04a')]


def bg_village():
    """木叶风: 黄昏村屋顶 + 火影岩"""
    cv, rng = new_bg(None)
    pal = ['58306c', '8a4a7c', 'e08a5c', 'f8b87c']
    dither_band(cv, 0, W, 0, 170, [hexc(c) for c in pal], rng)
    # 夕阳
    cv.ell([370 * SS, 110 * SS, 450 * SS, 190 * SS], hexc('ffd166'))
    cv.ell([386 * SS, 126 * SS, 414 * SS, 154 * SS], hexc('fff0b8'))
    # 火影岩(剪影山 + 面孔凹槽)
    cv.poly([(0, 170), (90, 92), (200, 76), (300, 96), (360, 170), (360, 200),
             (0, 200)], hexc('5a4a3c'))
    for i, fx in enumerate((110, 165, 220)):
        cv.ell([fx * SS, 108 * SS, (fx + 34) * SS, 138 * SS], hexc('483a2e'))
        cv.ell([(fx + 6) * SS, 116 * SS, (fx + 13) * SS, 123 * SS], hexc('2e241c'))
        cv.ell([(fx + 21) * SS, 116 * SS, (fx + 28) * SS, 123 * SS], hexc('2e241c'))
    # 村屋顶群
    x = 0
    while x < W:
        w = rng.randint(46, 90)
        hh = rng.randint(26, 52)
        yb = 218 + rng.randint(0, 14)
        wall = hexc('2c2434')
        cv.d.rectangle([x * SS, (yb - 8) * SS, (x + w) * SS, 234 * SS], fill=wall)
        cv.poly([(x - 4, yb - 8), (x + w // 2, yb - 8 - hh), (x + w + 4, yb - 8)],
                hexc('3c3448'))
        cv.poly([(x + 2, yb - 8), (x + w // 2, yb - hh + 4), (x + w - 2, yb - 8)],
                hexc('504464'))
        cv.d.rectangle([x * SS + 8 * SS, (yb - 4) * SS, (x + 12) * SS, yb * SS],
                       fill=hexc('ffd166'))  # 亮窗
        x += w + rng.randint(10, 40)
    ground(cv, 234, hexc('5e4434'), hexc('725243'), rng)
    # 归鸟
    for i in range(5):
        bx = rng.randrange(0, W)
        by = rng.randrange(30, 90)
        cv.capsule((bx * SS, by * SS), ((bx + 5) * SS, (by - 3) * SS), SS,
                   hexc('2e2038'))
        cv.capsule((bx * SS, by * SS), ((bx - 5) * SS, (by - 3) * SS), SS,
                   hexc('2e2038'))
    vignette(cv, 0.2)
    return cv, [hexc(c) for c in pal] + [hexc(c) for c in
            ('ffd166', 'fff0b8', '5a4a3c', '483a2e', '2e241c', '3c3448', '504464',
             '4a3428', '5e4434', '2e2038', 'ffffff')]


def bg_palace():
    """P5 怪盗殿堂: 红黑赌场大厅"""
    cv, rng = new_bg(None)
    # 上下红黑渐变
    dither_band(cv, 0, W, 0, H // 2, [hexc(c) for c in ('5a0a1e', '7a1028', '9a1632')],
                rng)
    cv.d.rectangle([0, (H // 2) * SS, W * SS, H * SS], fill=hexc('1c0a12'))
    # 大理石地(菱格)
    for y in range(H // 2, H, 8):
        off = (y // 8 % 2) * 8
        for x in range(-8, W, 16):
            cv.d.rectangle([(x + off) * SS, y * SS, (x + off + 15) * SS,
                            (y + 7) * SS],
                           fill=hexc('2a0f1a' if (x // 16 + y // 8) % 2 else '38141f'))
    # 廊柱
    for i, x in enumerate((60, 170, 310, 420)):
        cv.rrect([(x - 16) * SS, 40 * SS, (x + 16) * SS, 150 * SS], 4 * SS,
                 hexc('8a1830'))
        cv.rrect([(x - 10) * SS, 44 * SS, (x - 4) * SS, 146 * SS], 2 * SS,
                 hexc('a82a44'))
    # 拱顶
    cv.arc([40 * SS, 44 * SS, 440 * SS, 244 * SS], 180, 360, hexc('6e1226'), 10 * SS)
    cv.arc([72 * SS, 44 * SS, 408 * SS, 212 * SS], 180, 360, hexc('8a1830'), 6 * SS)
    # 吊灯(烛焰)
    for i, x in enumerate((120, 240, 360)):
        cv.capsule((x * SS, 30 * SS), (x * SS, 66 * SS), 2 * SS, hexc('c89a3c'))
        for j in range(3):
            cv.ell([(x + j * 8 - 8 - 3) * SS, (66 + j * 6 - 4) * SS,
                    (x + j * 8 - 8 + 3) * SS, (66 + j * 6 + 4) * SS], hexc('ffd166'))
    # 长楼梯(中央透视)
    cv.poly([(180, 150), (300, 150), (340, 230), (140, 230)], hexc('4a1626'))
    for i in range(5):
        yy = 152 + i * 16
        x0 = 180 + (140 - 180) * 0 - i * 8
        cv.d.rectangle([(180 - i * 9) * SS, yy * SS, (300 + i * 9) * SS,
                        (yy + 6) * SS], fill=hexc('5e1c30'))
    # 蓝色心之火
    cv.glow((240 * SS, 128 * SS), 20 * SS, hexc('3cc8f0'), rings=3)
    vignette(cv, 0.4)
    return cv, [hexc(c) for c in ('5a0a1e', '7a1028', '9a1632', '1c0a12', '2a0f1a',
            '38141f', '8a1830', 'a82a44', '6e1226', 'c89a3c', 'ffd166', '4a1626',
            '5e1c30', '3cc8f0', 'ffffff')]


def bg_colony():
    """宇宙殖民地: 星海 + 太空站舷窗 + 地球弧线"""
    cv, rng = new_bg(None)
    dither_band(cv, 0, W, 0, H, [hexc(c) for c in ('05060f', '0a0d1e', '101530')], rng)
    stars(cv, 90, rng, H, col=[hexc('ffffff'), hexc('9fd8ff'), hexc('ffe9a0')])
    # 地球弧线(底部)
    cv.ell([-60 * SS, 240 * SS, 300 * SS, 600 * SS], hexc('123a6c'))
    cv.ell([-44 * SS, 222 * SS, 284 * SS, 580 * SS], hexc('2a6aa8'))
    for i in range(6):  # 云带
        x0 = rng.randrange(-20, 250)
        y0 = rng.randrange(255, 265)
        cv.ell([x0 * SS, y0 * SS, (x0 + rng.randint(40, 90)) * SS,
                (y0 + rng.randint(6, 14)) * SS], hexc('cfe4f0'))
    # 太空站结构(右)
    cv.d.rectangle([330 * SS, 30 * SS, 480 * SS, 120 * SS], fill=hexc('2c3448'))
    cv.d.rectangle([330 * SS, 30 * SS, 480 * SS, 40 * SS], fill=hexc('48546e'))
    for i in range(4):  # 舷窗
        cv.ell([(352 + i * 34) * SS, 66 * SS, (372 + i * 34) * SS, 92 * SS],
               hexc('101828'))
        cv.ell([(355 + i * 34) * SS, 69 * SS, (369 + i * 34) * SS, 85 * SS],
               hexc('7ec8ff'))
    cv.d.rectangle([366 * SS, 120 * SS, 396 * SS, 200 * SS], fill=hexc('2c3448'))
    cv.d.rectangle([402 * SS, 120 * SS, 432 * SS, 200 * SS], fill=hexc('232a3c'))
    # 探照灯
    cv.poly([(370, 120), (300, 250), (360, 250)], hexc('7ec8ff'))
    cv.img.putalpha(255)
    # 甲板(底部战斗地面)
    cv.d.rectangle([0, 232 * SS, W * SS, H * SS], fill=hexc('1a2030'))
    for x in range(0, W, 24):
        cv.d.rectangle([x * SS, 232 * SS, (x + 18) * SS, 234 * SS], fill=hexc('38445e'))
        cv.pix(x + 8, 246, hexc('38445e'))
    vignette(cv, 0.35)
    return cv, [hexc(c) for c in ('05060f', '0a0d1e', '101530', '123a6c', '2a6aa8',
            'cfe4f0', '2c3448', '48546e', '101828', '7ec8ff', '232a3c', '1a2030',
            '38445e', 'ffffff', '9fd8ff', 'ffe9a0')]


BGS = {
    'forest': bg_forest,
    'cave': bg_cave,
    'lava': bg_lava,
    'ice': bg_ice,
    'graveyard': bg_graveyard,
    'waste': bg_waste,
    'village': bg_village,
    'palace': bg_palace,
    'colony': bg_colony,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    from px import finish
    sheet_cols = 3
    thumb = Image.new('RGBA', (W // 2 * 3 + 24, H // 2 * 3 + 32),
                      (16, 14, 28, 255))
    for i, (name, fn) in enumerate(BGS.items()):
        cv, pal = fn()
        img = finish(cv, sorted(set(pal)))
        img.save(os.path.join(OUT, name + '.png'))
        t = img.resize((W // 2, H // 2), Image.NEAREST)
        thumb.paste(t, (8 + (i % 3) * (W // 2 + 4), 8 + (i // 3) * (H // 2 + 8)))
        print('bg done:', name)
    thumb.save(os.path.join(OUT, '_contact.png'))


if __name__ == '__main__':
    main()
