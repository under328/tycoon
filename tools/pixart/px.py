# -*- coding: utf-8 -*-
"""像素画基础设施: 超采样画布 → 缩小 → 调色板量化 → 自动描边 → 导出。

工艺: 全部图元在 SS 倍(默认4x)画布上以矢量方式绘制, BOX 缩小到目标
像素尺寸后, 把每个像素吸附到最近的调色板颜色(无抖动的干净像素面),
最后在透明侧补一圈深色描边(像素格斗游戏标准工艺)。
"""
from PIL import Image, ImageDraw
import math

SS = 4  # 超采样倍率


# ---------------------------------------------------------------- 颜色工具

def hexc(s, a=255):
    """'#rrggbb' / 'rrggbb' → (r,g,b[,a])"""
    s = s.lstrip('#')
    r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
    return (r, g, b, a)


def shade(c, f):
    """颜色明暗缩放 f>1 变亮, f<1 变暗(alpha不变)"""
    r, g, b = c[0], c[1], c[2]
    if f >= 1.0:
        r = int(r + (255 - r) * (f - 1.0))
        g = int(g + (255 - g) * (f - 1.0))
        b = int(b + (255 - b) * (f - 1.0))
    else:
        r, g, b = int(r * f), int(g * f), int(b * f)
    a = c[3] if len(c) > 3 else 255
    return (min(r, 255), min(g, 255), min(b, 255), a)


def mix(c1, c2, t):
    a1 = c1[3] if len(c1) > 3 else 255
    return tuple(int(round(x + (y - x) * t)) for x, y in
                 zip((c1[0], c1[1], c1[2], a1), (c2[0], c2[1], c2[2], a1)))


# ---------------------------------------------------------------- 画布

class Canvas:
    """超采样 RGBA 画布。size = 目标像素尺寸(正方形或二元组)。"""

    def __init__(self, size):
        if isinstance(size, int):
            size = (size, size)
        self.pw, self.ph = size
        self.w, self.h = self.pw * SS, self.ph * SS
        self.img = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img, 'RGBA')

    def poly(self, pts, color):
        self.d.polygon(pts, fill=color)

    def line(self, pts, color, width, joint='curve'):
        self.d.line(pts, fill=color, width=max(int(width), 1), joint=joint)

    def ell(self, box, color):
        self.d.ellipse(box, fill=color)

    def rrect(self, box, rad, color):
        self.d.rounded_rectangle(box, radius=max(rad, 0.1), fill=color)

    def capsule(self, p0, p1, w, color):
        self.line([p0, p1], color, w)
        r = w / 2.0
        for p in (p0, p1):
            self.ell([p[0] - r, p[1] - r, p[0] + r, p[1] + r], color)

    def pie(self, box, a0, a1, color):
        self.d.pieslice(box, a0, a1, fill=color)

    def arc(self, box, a0, a1, color, width):
        self.d.arc(box, a0, a1, fill=color, width=max(int(width), 1))

    def pix(self, x, y, color):
        """目标像素坐标的小方块(超采样块)"""
        self.d.rectangle([x * SS, y * SS, (x + 1) * SS - 1, (y + 1) * SS - 1],
                         fill=color)

    # ---- 复合图元 ----
    def capsule_shaded(self, p0, p1, w, main, dark):
        """四肢: 主色胶囊 + 背光侧暗边(左上受光)"""
        self.capsule(p0, p1, w, main)
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        if nx < 0:  # 法线统一指向背光侧(右下)
            nx, ny = -nx, -ny
        off = w * 0.28
        a = (p0[0] + nx * off, p0[1] + ny * off)
        b = (p1[0] + nx * off, p1[1] + ny * off)
        self.capsule(a, b, w * 0.40, dark)

    def ell_shaded(self, cx, cy, rx, ry, main, dark, hi=None):
        """椭圆体积球: 背光暗边 + 可选高光"""
        self.ell([cx - rx, cy - ry, cx + rx, cy + ry], dark)
        self.ell([cx - rx * 0.88 - rx * 0.10, cy - ry * 0.88 - ry * 0.10,
                  cx + rx * 0.88 - rx * 0.10, cy + ry * 0.88 - ry * 0.10], main)
        if hi:
            self.ell([cx - rx * 0.55, cy - ry * 0.55,
                      cx - rx * 0.10, cy - ry * 0.10], hi)

    def star4(self, c, r, color, ratio=0.28):
        pts = []
        for i in range(8):
            a = math.pi / 4 * i - math.pi / 2
            rr = r if i % 2 == 0 else r * ratio
            pts.append((c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr))
        self.poly(pts, color)

    def glow(self, c, r, color, rings=3):
        """柔光圈(半透明叠层, 量化后形成同心色环)"""
        for i in range(rings, 0, -1):
            rr = r * i / rings
            a = int(80 * (1 - i / (rings + 1)))
            col = (color[0], color[1], color[2], a)
            self.ell([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], col)


# ---------------------------------------------------------------- 量化导出

def nearest(c, palette):
    r, g, b = c[0], c[1], c[2]
    best, bd = None, 1 << 30
    for p in palette:
        dr, dg, db = r - p[0], g - p[1], b - p[2]
        d = dr * dr * 2 + dg * dg * 4 + db * db * 3
        if d < bd:
            bd, best = d, p
    return best


def quantize(img, palette):
    rgb = img.convert('RGBA')
    px = rgb.load()
    w, h = rgb.size
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    po = out.load()
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c[3] >= 110:
                po[x, y] = nearest(c, palette)
    return out


def outline(img, col):
    """透明侧描边(4邻接)"""
    src = img.load()
    w, h = img.size
    out = img.copy()
    po = out.load()
    to_fill = []
    for y in range(h):
        for x in range(w):
            if src[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] != 0:
                    to_fill.append((x, y))
                    break
    for x, y in to_fill:
        po[x, y] = col
    return out


def finish(canvas, palette, outline_col=None):
    small = canvas.img.resize((canvas.pw, canvas.ph), Image.BOX)
    q = quantize(small, palette)
    if outline_col:
        q = outline(q, outline_col)
    return q


def save_sheet(frames, path):
    n = len(frames)
    w, h = frames[0].size
    sheet = Image.new('RGBA', (w, h * n), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (0, i * h))
    sheet.save(path)
    return sheet
