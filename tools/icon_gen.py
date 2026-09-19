# -*- coding: utf-8 -*-
"""大富豪游戏图标生成器: 2048 超采样矢量渲染 -> LANCZOS 缩放各尺寸。
风格: 炫酷宇宙紫底 + 三张鎏金卡牌扇面 + 金色「富」+ 皇冠 + 粒子辉光。
产物: icon.png(1024) icon_512.png icon_432_fg.png icon_192.png icon_432_bg.png
"""
import io
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048                      # 渲染画布
OUT = 1024                    # icon.png 尺寸
GOLD = (232, 180, 74)
GOLD_HI = (255, 226, 140)
GOLD_DK = (150, 100, 26)
RED = (233, 74, 90)
DARK = (13, 9, 32)

random.seed(20260919)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def linear_gradient(size, c0, c1, vertical=True):
    w, h = size
    g = Image.new('RGB', (1, h) if vertical else (w, 1))
    n = h if vertical else w
    px = []
    for i in range(n):
        px.append(lerp(c0, c1, i / max(n - 1, 1)))
    g.putdata(px)
    return g.resize((w, h), Image.BILINEAR)


def radial_gradient(size, inner, outer, cx=0.5, cy=0.5, radius=0.75):
    w, h = size
    g = Image.new('RGB', (w, h))
    px = g.load()
    ccx, ccy, cr = w * cx, w * cy, w * radius
    for y in range(h):
        for x in range(0, w, 4):   # 步进采样后横向放大, 加速
            d = min(math.hypot(x - ccx, y - ccy) / cr, 1.0)
            c = lerp(inner, outer, d)
            for k in range(4):
                if x + k < w:
                    px[x + k, y] = c
    return g


def vgrad_masked(base, mask, c0, c1):
    """把垂直渐变按 mask 贴到 base"""
    g = linear_gradient(mask.size, c0, c1).convert('RGBA')
    g.putalpha(mask)
    base.alpha_composite(g)


# ---------------------------------------------------------------- 背景
def make_bg(size, for_fg_safe=False):
    im = radial_gradient((size, size), (40, 27, 92), (7, 4, 20), 0.5, 0.40, 0.80)
    # 星云辉光: 品红(左下) + 电蓝(右上)
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([size*0.00, size*0.52, size*0.58, size*1.10], fill=(150, 30, 150, 62))
    gd.ellipse([size*0.44, size*0.00, size*1.02, size*0.50], fill=(30, 95, 210, 58))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.10))
    im = Image.alpha_composite(im.convert('RGBA'), glow)
    # 斜向能量线
    lines = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for i in range(9):
        x = size * (0.05 + 0.12 * i) + random.randint(-30, 30)
        ld.line([(x, size), (x + size * 0.34, 0)],
                fill=(140, 110, 255, random.randint(9, 18)), width=random.randint(3, 7))
    lines = lines.filter(ImageFilter.GaussianBlur(3))
    im.alpha_composite(lines)
    # 星点(小而密)
    st = ImageDraw.Draw(im)
    for _ in range(150):
        x, y = random.randint(0, size), random.randint(0, int(size * 0.92))
        r = random.choice([1, 1, 1, 2, 2, 3])
        a = random.randint(50, 170)
        st.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    # 暗角
    vig = Image.new('L', (size, size), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-size * 0.25, -size * 0.25, size * 1.25, size * 1.25], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(size * 0.12))
    dark = Image.new('RGBA', (size, size), (4, 2, 12, 255))
    dark.putalpha(Image.eval(vig, lambda p: 255 - p))
    im.alpha_composite(dark)
    return im.convert('RGBA')


# ---------------------------------------------------------------- 卡牌
def make_card(w, h, radius, dark=False):
    """单张空白卡: 象牙/深紫渐变面 + 鎏金描边。返回 RGBA。"""
    card = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    face = Image.new('L', (w, h), 0)
    fd = ImageDraw.Draw(face)
    fd.rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=255)
    if dark:
        vgrad_masked(card, face, (52, 38, 108), (24, 16, 58))
        inner = (255, 220, 140, 120)
    else:
        vgrad_masked(card, face, (253, 250, 240), (226, 216, 190))
        inner = (255, 238, 180, 160)
    # 金边(内外双描)
    bd = ImageDraw.Draw(card)
    bd.rounded_rectangle([0, 0, w - 1, h - 1], radius, outline=GOLD, width=int(h * 0.02))
    bd.rounded_rectangle([int(h*0.014)] * 2 + [w - int(h*0.014) - 1, h - int(h*0.014) - 1],
                         radius - int(h*0.014), outline=inner,
                         width=max(int(h * 0.005), 2))
    return card


def glyph_mask(text, font_path, size_px, variation=None):
    font = ImageFont.truetype(font_path, size_px)
    if variation:
        try:
            font.set_variation_by_axes(variation)
        except Exception:
            pass
    m = Image.new('L', (size_px * 2, size_px * 2), 0)
    d = ImageDraw.Draw(m)
    d.text((size_px // 2, size_px // 2), text, font=font, fill=255)
    bbox = m.getbbox()
    return m.crop(bbox)


def paste_gradient_glyph(base, glyph, cx, cy, c0, c1, glow_col=None, glow_a=110):
    w, h = glyph.size
    g = linear_gradient((w, h), c0, c1).convert('RGBA')
    g.putalpha(glyph)
    if glow_col:
        gl = Image.new('RGBA', (w * 2, h * 2), (0, 0, 0, 0))
        gm = Image.new('L', (w * 2, h * 2), 0)
        gm.paste(glyph, (w // 2, h // 2))
        gg = Image.new('RGBA', (w * 2, h * 2), tuple(glow_col) + (glow_a,))
        gg.putalpha(gm)
        gl.alpha_composite(gg)
        gl = gl.filter(ImageFilter.GaussianBlur(min(w, h) * 0.10))
        base.alpha_composite(gl, (int(cx - w), int(cy - h)))
    base.alpha_composite(g, (int(cx - w / 2), int(cy - h / 2)))


def heart_shape(w, h):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    r = w * 0.26
    d.ellipse([w*0.04, h*0.06, w*0.04 + 2*r, h*0.06 + 2*r], fill=255)
    d.ellipse([w*0.96 - 2*r, h*0.06, w*0.96, h*0.06 + 2*r], fill=255)
    d.polygon([(w*0.062, h*0.30), (w*0.938, h*0.30), (w*0.5, h*0.94)], fill=255)
    return m


def spade_shape(w, h):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    r = w * 0.27
    # 倒置桃心: 两圆在下半部 + 顶尖三角
    d.ellipse([w*0.03, h*0.30, w*0.03 + 2*r, h*0.30 + 2*r], fill=255)
    d.ellipse([w*0.97 - 2*r, h*0.30, w*0.97, h*0.30 + 2*r], fill=255)
    d.polygon([(w*0.075, h*0.62), (w*0.925, h*0.62), (w*0.5, h*0.03)], fill=255)
    # 底座梯形茎
    d.polygon([(w*0.38, h*0.58), (w*0.62, h*0.58),
               (w*0.68, h*0.95), (w*0.32, h*0.95)], fill=255)
    return m


def diamond_shape(w, h):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    d.polygon([(w*0.5, h*0.04), (w*0.92, h*0.5), (w*0.5, h*0.96), (w*0.08, h*0.5)], fill=255)
    return m


# ---------------------------------------------------------------- 皇冠
def make_crown(w):
    h = int(w * 0.72)
    crown = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    body = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(body)
    base_y = int(h * 0.86)
    d.polygon([(int(w*0.06), base_y), (int(w*0.94), base_y),
               (int(w*0.88), int(h*0.64)), (int(w*0.72), int(h*0.72)),
               (int(w*0.60), int(h*0.40)), (int(w*0.50), int(h*0.52)),
               (int(w*0.40), int(h*0.40)), (int(w*0.28), int(h*0.72)),
               (int(w*0.12), int(h*0.64))], fill=255)
    for cx, cy, r in [(0.12, 0.56, 0.065), (0.40, 0.32, 0.065),
                      (0.60, 0.32, 0.065), (0.88, 0.56, 0.065)]:
        d.ellipse([int(w*(cx-r)), int(h*(cy-r)), int(w*(cx+r)), int(h*(cy+r))], fill=255)
    vgrad_masked(crown, body, GOLD_HI, GOLD_DK)
    dd = ImageDraw.Draw(crown)
    dd.line([(int(w*0.08), base_y - 2), (int(w*0.92), base_y - 2)],
            fill=GOLD_DK + (255,), width=max(int(w*0.02), 3))
    # 宝石
    for cx, col in [(0.31, (60, 200, 255)), (0.50, (255, 80, 90)), (0.69, (60, 200, 255))]:
        r = w * 0.035
        dd.ellipse([int(w*cx - r), int(h*0.72 - r), int(w*cx + r), int(h*0.72 + r)],
                   fill=col + (255,))
        dd.ellipse([int(w*cx - r*0.35), int(h*0.72 - r*0.5), int(w*cx - r*0.1), int(h*0.72 - r*0.2)],
                   fill=(255, 255, 255, 200))
    return crown


# ---------------------------------------------------------------- 粒子
def add_sparks(im, n=26):
    size = im.size[0]
    sp = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(sp)
    placed = 0
    while placed < n:
        x, y = random.randint(int(size*0.06), int(size*0.94)), random.randint(int(size*0.05), int(size*0.9))
        # 避开中央卡面区(保持卡面整洁)
        if size * 0.32 < x < size * 0.68 and size * 0.16 < y < size * 0.78:
            if random.random() < 0.8:
                continue
        gold = random.random() < 0.7
        col = (255, 214, 110) if gold else (110, 220, 255)
        r = random.randint(int(size*0.004), int(size*0.011))
        a = random.randint(120, 230)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (a,))
        if random.random() < 0.5:
            ln = random.randint(int(size*0.02), int(size*0.05))
            d.line([(x, y), (x + ln, y - ln // 2)], fill=col + (a // 2,), width=3)
        placed += 1
    sp = sp.filter(ImageFilter.GaussianBlur(size * 0.003))
    im.alpha_composite(sp)


# ---------------------------------------------------------------- 合成
FONT_FU = 'C:/Windows/Fonts/NotoSerifSC-VF.ttf'
FONT_FU_FALLBACK = 'C:/Windows/Fonts/simhei.ttf'


def compose():
    im = make_bg(S)

    # 卡牌扇面(缩小让皇冠+富字有呼吸空间)
    cw, ch = int(S * 0.365), int(S * 0.52)
    radius = int(ch * 0.075)

    def paste_card(angle, tx, ty, content, dark=False):
        card = make_card(cw, ch, radius, dark=dark)
        content(card)
        rot = card.rotate(angle, expand=True, resample=Image.BICUBIC)
        # 金色外发光(炫酷轮廓光)
        gl = Image.new('RGBA', rot.size, (0, 0, 0, 0))
        alpha = rot.split()[3]
        goldgl = Image.new('RGBA', rot.size, (255, 200, 100, 130 if dark else 100))
        goldgl.putalpha(alpha)
        gl.alpha_composite(goldgl)
        gl = gl.filter(ImageFilter.GaussianBlur(S * 0.016))
        im.alpha_composite(gl, (int(tx), int(ty)))
        # 阴影
        sh = Image.new('RGBA', rot.size, (0, 0, 0, 0))
        alpha2 = rot.split()[3].point(lambda p: int(p * 0.5))
        black = Image.new('RGBA', rot.size, (0, 0, 0, 255))
        black.putalpha(alpha2)
        sh.alpha_composite(black)
        sh = sh.filter(ImageFilter.GaussianBlur(S * 0.022))
        im.alpha_composite(sh, (int(tx + S * 0.010), int(ty + S * 0.018)))
        im.alpha_composite(rot, (int(tx), int(ty)))

    def side_content(is_heart):
        def draw(c):
            w, h = c.size
            shape = heart_shape(int(w*0.36), int(w*0.36)) if is_heart \
                else spade_shape(int(w*0.36), int(w*0.36))
            col = ((255, 120, 130), (170, 20, 45)) if is_heart \
                else ((95, 95, 130), (22, 22, 52))
            paste_gradient_glyph(c, shape, w*0.5, h*0.40, col[0], col[1])
            # 左上角标 mini 花色
            mini = int(w * 0.10)
            ms = heart_shape(mini, mini) if is_heart else spade_shape(mini, mini)
            mcol = ((210, 60, 80), (120, 15, 35)) if is_heart else ((70, 70, 105), (25, 25, 55))
            paste_gradient_glyph(c, ms, w*0.15, h*0.11, mcol[0], mcol[1])
        return draw

    def center_content(c):
        w, h = c.size
        try:
            fu = glyph_mask('富', FONT_FU, int(w * 0.50), variation=[900])
        except Exception:
            fu = glyph_mask('富', FONT_FU_FALLBACK, int(w * 0.50))
        # 卡面顶部聚光
        spot = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(spot)
        sd.ellipse([-w*0.3, -h*0.25, w*1.3, h*0.45], fill=(255, 240, 200, 40))
        spot = spot.filter(ImageFilter.GaussianBlur(w * 0.10))
        c.alpha_composite(spot)
        # 深底上的金色大富字(重辉光)
        paste_gradient_glyph(c, fu, w*0.5, h*0.40, GOLD_HI, (188, 126, 34),
                             glow_col=(255, 195, 80), glow_a=190)
        # 底部花色行(深底上金红相间, 豪华感)
        mini = int(w * 0.10)
        for i, shape in enumerate([spade_shape, heart_shape, diamond_shape, heart_shape]):
            m = shape(mini, mini)
            col = ((255, 214, 110), (188, 126, 34)) if i in (0, 2) \
                else ((255, 120, 140), (200, 40, 70))
            paste_gradient_glyph(c, m, w*(0.28 + 0.1467*i), h*0.76, col[0], col[1])
        # 花色行上方细分隔线
        d = ImageDraw.Draw(c)
        d.line([(w*0.20, h*0.655), (w*0.80, h*0.655)], fill=(232, 180, 74, 220),
               width=max(int(w*0.008), 2))

    fx, fy = S * 0.5, S * 0.53
    paste_card(-15, fx - cw*1.24, fy - ch*0.585, side_content(False))
    paste_card(15, fx + cw*0.24, fy - ch*0.585, side_content(True))
    paste_card(0, fx - cw*0.5, fy - ch*0.68, center_content, dark=True)

    # 皇冠: 悬浮在中央卡正上方(卡外)
    crown = make_crown(int(S * 0.26))
    glow_c = Image.new('RGBA', crown.size, (0, 0, 0, 0))
    ca = crown.split()[3].point(lambda p: int(p * 0.85))
    cg = Image.new('RGBA', crown.size, (255, 210, 100, 255))
    cg.putalpha(ca)
    glow_c.alpha_composite(cg)
    glow_c = glow_c.filter(ImageFilter.GaussianBlur(S * 0.024))
    crown_y = int(fy - ch*0.68 - crown.size[1] + S * 0.028)
    im.alpha_composite(glow_c, (int(S*0.5 - crown.size[0]/2), crown_y))
    im.alpha_composite(crown, (int(S*0.5 - crown.size[0]/2), crown_y))

    add_sparks(im)

    # 圆角玻璃高光 + 收边
    sheen = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon([(-S*0.2, -S*0.1), (S*0.55, -S*0.2), (-S*0.1, S*0.75)],
               fill=(255, 255, 255, 24))
    sheen = sheen.filter(ImageFilter.GaussianBlur(S * 0.03))
    im.alpha_composite(sheen)
    return im


def rounded_crop(im, radius_ratio=0.21, rim=True):
    S2 = im.size[0]
    mask = Image.new('L', (S2, S2), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, S2 - 1, S2 - 1], int(S2 * radius_ratio), fill=255)
    out = Image.new('RGBA', (S2, S2), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    if rim:
        d2 = ImageDraw.Draw(out)
        d2.rounded_rectangle([2, 2, S2 - 3, S2 - 3], int(S2 * radius_ratio),
                             outline=(255, 214, 120, 210), width=max(S2 // 512, 2))
    return out


def save(im, path, size):
    im2 = im.resize((size, size), Image.LANCZOS)
    im2.save(path)
    print(path, im2.size)


def main():
    full = compose()
    # 方形全幅图标(项目 icon / 512): 圆角 + 金边
    rounded = rounded_crop(full)
    save(rounded, 'icon.png', OUT)
    save(rounded, 'icon_512.png', 512)
    save(rounded, 'icon_192.png', 192)
    # Android 自适应前景: 内容缩到 66% 安全区居中(透明底)
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    inner = full.resize((int(S * 0.64), int(S * 0.64)), Image.LANCZOS)
    inner_r = rounded_crop(inner, radius_ratio=0.16, rim=False)
    fg.alpha_composite(inner_r, ((S - inner_r.size[0]) // 2, (S - inner_r.size[1]) // 2))
    save(fg, 'icon_432_fg.png', 432)
    # 自适应背景: 纯渐变底(无卡牌, 避免被前景裁切)
    bg = make_bg(S)
    save(bg, 'icon_432_bg.png', 432)


if __name__ == '__main__':
    main()
