# -*- coding: utf-8 -*-
"""像素风应用图标 v2: 「大富豪」主题 — 金冠 + 扇形双牌(黑桃/红钻) + 星辉。

结合当前游戏: 扑克对局(牌面) + 大富豪身份(王冠) + 格斗的能量感(辉光/火星)。
输出: icon.png(128) icon_192 icon_512 icon_432_fg(前景透明底) icon_432_bg(纯底色)
"""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import Canvas, hexc, shade, finish
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

NAVY = hexc('12122a')
NAVY2 = hexc('20204a')
GOLD = hexc('e8b13c')
GOLD_HI = hexc('ffdf8a')
GOLD_DK = hexc('a87818')
RED = hexc('e0503c')
RED_HI = hexc('ff9a78')
WHITE = hexc('f6f2e8')
INK = hexc('26263e')


def _shear(pts, kx, ky, cx, cy):
    """绕(cx,cy)做斜切(近似的卡片倾斜)"""
    return [(cx + (x - cx) + (y - cy) * kx, cy + (y - cy) + (x - cx) * ky)
            for x, y in pts]


def draw_card(cv, cx, cy, w, h, tilt, back, motif_col, motif='spade'):
    """单张斜置卡: 圆角白卡 + 花色点。tilt=斜切系数(左负右正)。"""
    r = w * 0.14
    card = _shear([(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2),
                   (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)],
                  tilt, tilt * 0.22, cx, cy)
    cv.poly(card, WHITE)
    edge = _shear([(cx - w / 2, cy - h / 2), (cx - w / 2 + w * 0.10, cy - h / 2),
                   (cx - w / 2 + w * 0.10, cy + h / 2), (cx - w / 2, cy + h / 2)],
                  tilt, tilt * 0.22, cx, cy)
    cv.poly(edge, shade(WHITE, 0.82))
    # 花色(黑桃/红方块)
    mc, mh = motif_col, shade(motif_col, 1.3)
    s = w * 0.30
    if motif == 'spade':
        pts = []
        for i in range(22):
            a = math.pi * (0.5 + i / 21.0)
            rr = s * (0.62 + 0.38 * abs(math.sin(a * 2)))
            pts.append((cx + math.cos(a) * rr * 0.78, cy - s * 0.35 + math.sin(a) * rr))
        cv.poly(_shear(pts, tilt, tilt * 0.22, cx, cy), mc)
        stem = _shear([(cx - s * 0.16, cy + s * 0.25), (cx + s * 0.16, cy + s * 0.25),
                       (cx + s * 0.10, cy + s * 0.85), (cx - s * 0.10, cy + s * 0.85)],
                      tilt, tilt * 0.22, cx, cy)
        cv.poly(stem, mc)
        cv.ell(_shear([(cx - s * 0.42, cy - s * 0.62), (cx - s * 0.05, cy - s * 0.30)],
                      tilt, tilt * 0.22, cx, cy), mh)
    else:
        dia = _shear([(cx, cy - s), (cx + s * 0.82, cy), (cx, cy + s), (cx - s * 0.82, cy)],
                     tilt, tilt * 0.22, cx, cy)
        cv.poly(dia, mc)
        cv.poly(_shear([(cx, cy - s * 0.62), (cx + s * 0.46, cy), (cx, cy + s * 0.62),
                        (cx - s * 0.46, cy)], tilt, tilt * 0.22, cx, cy), mh)


def draw_crown(cv, cx, cy, w, h):
    """金色王冠(大富豪身份): 三尖 + 珠顶 + 红宝石 + 底带"""
    left, right = cx - w / 2, cx + w / 2
    top, bot = cy - h / 2, cy + h / 2
    # 冠体(三尖)
    cv.poly([(left, bot), (left, top + h * 0.22), (cx - w * 0.26, top + h * 0.40),
             (cx, top), (cx + w * 0.26, top + h * 0.40), (right, top + h * 0.22),
             (right, bot)], GOLD)
    # 右下受光暗面
    cv.poly([(cx + w * 0.10, bot), (right, top + h * 0.22),
             (right, bot)], GOLD_DK)
    # 底带
    cv.d.rounded_rectangle([left * 4, (bot - h * 0.18) * 4, right * 4, bot * 4],
                           radius=int(h * 0.08 * 4), fill=shade(GOLD, 1.18))
    # 珠顶(三尖顶点)
    for px, py in ((left, top + h * 0.20), (cx, top - h * 0.05), (right, top + h * 0.20)):
        cv.ell([px - w * 0.055, py - w * 0.055, px + w * 0.055, py + w * 0.055],
               GOLD_HI)
    # 冠面红宝石(菱形)
    cv.poly([(cx, cy - h * 0.08), (cx + w * 0.10, cy + h * 0.12),
             (cx, cy + h * 0.30), (cx - w * 0.10, cy + h * 0.12)], RED)
    cv.poly([(cx, cy - h * 0.02), (cx + w * 0.05, cy + h * 0.10),
             (cx, cy + h * 0.20), (cx - w * 0.05, cy + h * 0.10)], RED_HI)


def gen(size, fg_only=False, bg_only=False):
    cv = Canvas(size)
    S = size
    if not fg_only:
        # 底: 深夜蓝 → 中心亮(舞台感)
        cv.d.rectangle([0, 0, S * 4, S * 4], fill=NAVY)
        cv.glow((S * 2 * 4, S * 0.58 * 4), S * 0.72 * 4, NAVY2, rings=4)
    if bg_only:
        img = cv.img.resize((S, S), Image.BOX).convert('RGBA')
        return img
    # 王冠辉光(能量感)
    cv.glow((S * 0.5 * 4, S * 0.34 * 4), S * 0.30 * 4, shade(GOLD, 1.12), rings=3)
    # 扇形双牌: 左黑桃(微左倾) / 右红钻(微右倾)
    draw_card(cv, S * 0.355, S * 0.60, S * 0.34, S * 0.46, -0.10, WHITE, INK, 'spade')
    draw_card(cv, S * 0.645, S * 0.60, S * 0.34, S * 0.46, 0.10, WHITE, RED, 'diamond')
    # 金冠压在双牌上方
    draw_crown(cv, S * 0.5, S * 0.30, S * 0.46, S * 0.30)
    # 星辉火星(格斗能量)
    cv.star4((S * 0.235 * 4, S * 0.28 * 4), S * 0.045 * 4, GOLD_HI, 0.35)
    cv.star4((S * 0.78 * 4, S * 0.24 * 4), S * 0.032 * 4, GOLD_HI, 0.35)
    cv.star4((S * 0.16 * 4, S * 0.72 * 4), S * 0.026 * 4, WHITE, 0.35)
    cv.star4((S * 0.86 * 4, S * 0.66 * 4), S * 0.038 * 4, RED_HI, 0.35)
    pal = [NAVY, NAVY2, GOLD, GOLD_HI, GOLD_DK, RED, RED_HI, WHITE, INK,
           shade(WHITE, 0.82), shade(GOLD, 1.12), shade(NAVY2, 1.25), hexc('0c0c1c')]
    return finish(cv, pal, hexc('0c0c1c'))


def main():
    for name, size in (('icon.png', 128), ('icon_192.png', 192),
                       ('icon_512.png', 512)):
        img = gen(size)
        img.save(os.path.join(ROOT, name))
    # Android 自适应: 前景(无底) / 背景(纯底)
    gen(432, fg_only=True).save(os.path.join(ROOT, 'icon_432_fg.png'))
    gen(432, bg_only=True).save(os.path.join(ROOT, 'icon_432_bg.png'))
    print('icons done')


if __name__ == '__main__':
    main()
