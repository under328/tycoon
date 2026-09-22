# -*- coding: utf-8 -*-
"""像素风应用图标: 深夜蓝底 + 金色黑桃主牌 + 红方块 + 辉光。

输出: icon.png(128) icon_192 icon_512 icon_432_fg(前景透明底) icon_432_bg(纯底色)
"""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import Canvas, hexc, shade
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

NAVY = hexc('14142b')
NAVY2 = hexc('1e1e40')
GOLD = hexc('e8b13c')
GOLD_HI = hexc('ffdf8a')
RED = hexc('e0503c')
WHITE = hexc('f6f2e8')


def draw_spade(cv, cx, cy, r, fill, hi):
    """黑桃(扑克 spade)"""
    pts = []
    for i in range(26):
        a = math.pi * (0.5 + i / 25.0)
        rr = r * (0.62 + 0.38 * abs(math.sin(a * 2)))
        pts.append((cx + math.cos(a) * rr * 0.78, cy - r * 0.35 + math.sin(a) * rr))
    cv.poly(pts, fill)
    # 柄
    cv.rrect([cx - r * 0.16, cy + r * 0.25, cx + r * 0.16, cy + r * 0.85],
             r * 0.14, fill)
    # 高光
    cv.ell([cx - r * 0.42, cy - r * 0.62, cx - r * 0.05, cy - r * 0.3], hi)


def draw_diamond(cv, cx, cy, r, fill, hi):
    cv.poly([(cx, cy - r), (cx + r * 0.82, cy), (cx, cy + r), (cx - r * 0.82, cy)],
            fill)
    cv.poly([(cx, cy - r * 0.7), (cx + r * 0.5, cy), (cx, cy + r * 0.7),
             (cx - r * 0.5, cy)], hi)


def gen(size, fg_only=False, bg_only=False):
    cv = Canvas(size)
    S = size
    if not fg_only:
        # 底: 深夜蓝渐变(四角到中心) + 暗纹
        cv.d.rectangle([0, 0, S * 4, S * 4], fill=NAVY)
        cv.glow((S * 2 * 4, S * 0.92 * 4), S * 0.62 * 4, NAVY2, rings=4)
    if bg_only:
        img = cv.img.resize((S, S), Image.BOX).convert('RGBA')
        return img
    # 辉光
    cv.glow((S * 0.46 * 4, S * 0.44 * 4), S * 0.34 * 4, shade(GOLD, 1.1), rings=3)
    # 主牌: 黑桃(金描) — 稍左上倾斜卡
    draw_spade(cv, S * 0.5, S * 0.46, S * 0.27, hexc('20203a'), shade(GOLD, 1.25))
    # 卡牌外框(金圆角方)
    cv.d.rounded_rectangle([S * 0.16 * 4, S * 0.14 * 4, S * 0.84 * 4, S * 0.80 * 4],
                           radius=S * 0.10 * 4, outline=GOLD, width=max(int(S * 0.045 * 4), 8))
    # 红方块点睛(右下)
    draw_diamond(cv, S * 0.70, S * 0.64, S * 0.10, RED, shade(RED, 1.35))
    # 星光
    cv.star4((S * 0.30 * 4, S * 0.30 * 4), S * 0.05 * 4, GOLD_HI, 0.35)
    cv.star4((S * 0.74 * 4, S * 0.24 * 4), S * 0.035 * 4, GOLD_HI, 0.35)
    cv.star4((S * 0.24 * 4, S * 0.66 * 4), S * 0.03 * 4, WHITE, 0.35)
    pal = [NAVY, NAVY2, GOLD, GOLD_HI, RED, shade(RED, 1.35), WHITE,
           hexc('20203a'), shade(GOLD, 1.25), hexc('0c0c1c'), shade(NAVY2, 1.25)]
    from px import finish
    img = finish(cv, pal) if not fg_only else finish(cv, pal)
    return img


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
