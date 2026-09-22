# -*- coding: utf-8 -*-
"""人形骨架与共享部件库(发型/脸/四肢绘制器)。

坐标: 128×128 目标画布, 地面 y=118, 角色朝右(敌人侧)。
pose = 一组关节地标(128 基准坐标); Rig 把它绘制到超采样画布。
"""
import math
from px import hexc, shade, SS

# ---------------------------------------------------------------- 基准骨架

BASE = {
    'hip': (60.0, 86.0),
    'neck': (60.0, 58.0),
    'headc': (60.0, 41.0), 'head_rx': 14.5, 'head_ry': 15.5,
    's_f': (66.0, 60.0), 'e_f': (73.0, 72.0), 'h_f': (74.0, 82.0),
    's_b': (54.0, 60.0), 'e_b': (47.0, 72.0), 'h_b': (46.0, 82.0),
    'hip_f': (65.0, 86.0), 'knee_f': (67.0, 101.0), 'foot_f': (69.0, 116.0),
    'hip_b': (55.0, 86.0), 'knee_b': (53.0, 101.0), 'foot_b': (51.0, 116.0),
}


def lerp(a, b, t):
    return a + (b - a) * t


def plerp(p, q, t):
    return (lerp(p[0], q[0], t), lerp(p[1], q[1], t))


def shift(pose, dx, dy):
    out = {}
    for k, v in pose.items():
        out[k] = (v[0] + dx, v[1] + dy) if isinstance(v, tuple) else v
    return out


def update(pose, **kw):
    out = dict(pose)
    out.update(kw)
    return out


# ---------------------------------------------------------------- 姿态库

def pose_idle(t=0.0):
    bob = math.sin(t * math.tau) * 1.4
    sway = math.sin(t * math.tau)
    return update(BASE,
                  headc=(BASE['headc'][0], BASE['headc'][1] + bob * 0.5),
                  neck=(BASE['neck'][0], BASE['neck'][1] + bob * 0.3),
                  h_f=(BASE['h_f'][0] + sway * 1.2, BASE['h_f'][1] + bob),
                  h_b=(BASE['h_b'][0] - sway * 1.2, BASE['h_b'][1] + bob),
                  e_f=(BASE['e_f'][0] + sway * 0.8, BASE['e_f'][1] + bob * 0.6),
                  e_b=(BASE['e_b'][0] - sway * 0.8, BASE['e_b'][1] + bob * 0.6))


def pose_attack(f):
    if f == 0:  # 蓄力后仰
        p = shift(BASE, -5, 0)
        return update(p, h_f=(58, 70), e_f=(60, 64), h_b=(44, 78), e_b=(48, 68),
                      foot_f=(74, 116), knee_f=(72, 101))
    if f == 1:  # 突进
        p = shift(BASE, 8, -2)
        return update(p, h_f=(94, 62), e_f=(82, 62), h_b=(52, 76), e_b=(44, 70),
                      foot_f=(82, 116), knee_f=(76, 102), foot_b=(40, 116),
                      headc=(66, 39))
    if f == 2:  # 重击
        p = shift(BASE, 14, -3)
        return update(p, h_f=(104, 58), e_f=(86, 59), h_b=(56, 74), e_b=(46, 70),
                      foot_f=(88, 116), knee_f=(80, 103), foot_b=(34, 117),
                      headc=(68, 38), neck=(66, 56))
    p = shift(BASE, 2, -1)  # 收招
    return update(p, h_f=(78, 72), e_f=(72, 66), h_b=(48, 80), e_b=(46, 70))


def pose_skill(f):
    if f == 0:
        p = shift(BASE, -3, 2)
        return update(p, h_f=(66, 72), e_f=(64, 66), h_b=(54, 72), e_b=(56, 66),
                      knee_f=(64, 102), foot_f=(66, 116), knee_b=(50, 102),
                      headc=(59, 43))
    if f == 1:
        p = shift(BASE, 0, 0)
        return update(p, h_f=(76, 68), e_f=(70, 66), h_b=(58, 68), e_b=(52, 66),
                      headc=(60, 40))
    if f == 2:
        p = shift(BASE, 6, -2)
        return update(p, h_f=(96, 60), e_f=(82, 61), h_b=(50, 72), e_b=(44, 68),
                      foot_f=(80, 116), headc=(64, 39))
    p = shift(BASE, 3, 0)
    return update(p, h_f=(86, 64), e_f=(76, 63), h_b=(48, 76), e_b=(44, 70))


def pose_defend(f):
    dy = 2 + f * 2
    p = shift(BASE, -2, dy)
    return update(p, h_f=(66, 62 - f * 2), e_f=(72, 68), h_b=(52, 62 - f * 2),
                  e_b=(48, 68), knee_f=(64, 102 + f), knee_b=(50, 102 + f),
                  foot_f=(68, 116), foot_b=(48, 116),
                  headc=(59, 42 + dy * 0.5))


def pose_ult(f):
    if f == 0:  # 蓄力下蹲
        p = shift(BASE, -4, 6)
        return update(p, h_f=(52, 84), e_f=(52, 74), h_b=(68, 84), e_b=(68, 74),
                      knee_f=(66, 104), foot_f=(72, 116), knee_b=(48, 104),
                      foot_b=(44, 116), headc=(57, 46), neck=(57, 62), hip=(60, 90))
    if f == 1:  # 爆发起身
        p = shift(BASE, 0, -8)
        return update(p, h_f=(74, 50), e_f=(72, 58), h_b=(46, 50), e_b=(48, 58),
                      headc=(60, 32), neck=(60, 49), foot_f=(72, 116),
                      foot_b=(50, 116), knee_f=(70, 102), knee_b=(50, 102))
    if f == 2:  # 全力突进
        p = shift(BASE, 16, -4)
        return update(p, h_f=(108, 56), e_f=(88, 58), h_b=(60, 70), e_b=(48, 70),
                      foot_f=(90, 116), knee_f=(82, 104), foot_b=(30, 117),
                      headc=(70, 37), neck=(68, 55))
    p = shift(BASE, 4, 0)  # 收势
    return update(p, h_f=(84, 60), e_f=(76, 62), h_b=(44, 60), e_b=(46, 64),
                  headc=(62, 40))


def pose_transform(f):
    if f == 0:
        return pose_idle(0.0)
    if f == 1:
        p = shift(BASE, -2, 4)
        return update(p, h_f=(58, 74), e_f=(58, 66), h_b=(62, 74), e_b=(62, 66),
                      knee_f=(65, 103), knee_b=(51, 103), headc=(59, 43))
    if f == 2:
        p = shift(BASE, 0, -4)
        return update(p, h_f=(78, 52), e_f=(74, 58), h_b=(42, 52), e_b=(46, 58),
                      headc=(60, 34), neck=(60, 50))
    if f == 3:
        p = shift(BASE, 0, -2)
        return update(p, h_f=(92, 54), e_f=(80, 56), h_b=(28, 54), e_b=(40, 56),
                      foot_f=(80, 116), foot_b=(42, 116), knee_f=(74, 102),
                      knee_b=(48, 102), headc=(60, 36), neck=(60, 52))
    if f == 4:
        return update(BASE, h_f=(84, 58), e_f=(78, 52), h_b=(36, 58), e_b=(42, 52),
                      headc=(60, 39))
    return pose_idle(0.5)


def pose_hit(f):
    dx = -6 - f * 6
    p = shift(BASE, dx, f * 2)
    return update(p, h_f=(60 + f * 4, 66), e_f=(62, 62), h_b=(38 - f * 2, 70),
                  e_b=(44, 64), headc=(56 - f * 2, 42), neck=(57 - f * 2, 59),
                  foot_b=(44 - f * 2, 116))


# ---------------------------------------------------------------- Rig 绘制器

class Rig:
    """把 128 基准坐标的角色绘制到超采样画布(自动 ×SS×scale)。"""

    def __init__(self, cv, scale=1.0, origin=(0.0, 0.0)):
        self.cv = cv
        self.k = SS * scale
        self.ox, self.oy = origin[0] * SS * scale, origin[1] * SS * scale

    def P(self, p):
        return (self.ox + p[0] * self.k, self.oy + p[1] * self.k)

    def W(self, w):
        return w * self.k

    def poly(self, pts, c):
        self.cv.poly([self.P(p) for p in pts], c)

    def ell(self, cx, cy, rx, ry, c):
        p = self.P((cx, cy))
        self.cv.ell([p[0] - rx * self.k, p[1] - ry * self.k,
                     p[0] + rx * self.k, p[1] + ry * self.k], c)

    def rrect(self, x0, y0, x1, y1, rad, c):
        p0, p1 = self.P((x0, y0)), self.P((x1, y1))
        self.cv.rrect([p0[0], p0[1], p1[0], p1[1]], rad * self.k, c)

    def capsule(self, a, b, w, c):
        self.cv.capsule(self.P(a), self.P(b), self.W(w), c)

    def capsule_sh(self, a, b, w, main, dark):
        self.cv.capsule_shaded(self.P(a), self.P(b), self.W(w), main, dark)

    def arc(self, cx, cy, r, a0, a1, c, w):
        p = self.P((cx, cy))
        rr = r * self.k
        self.cv.arc([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], a0, a1, c,
                    self.W(w))

    def pie(self, cx, cy, r, a0, a1, c):
        p = self.P((cx, cy))
        rr = r * self.k
        self.cv.pie([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], a0, a1, c)

    def star4(self, c, r, col, ratio=0.28):
        self.cv.star4(self.P(c), self.W(r), col, ratio)

    def glow(self, c, r, col, rings=3):
        self.cv.glow(self.P(c), self.W(r), col, rings)

    def head_ell(self, p, main, dark, hi=None):
        hc = self.P(p['headc'])
        rx, ry = p['head_rx'] * self.k, p['head_ry'] * self.k
        self.cv.ell_shaded(hc[0], hc[1], rx, ry, main, dark, hi)


# ---------------------------------------------------------------- 四肢/躯干

def draw_arm(rig, s, e, h, pal, back=False):
    suit = pal['suit_b'] if back else pal['suit']
    fore = pal.get('fore_b' if back else 'fore', suit)
    rig.capsule_sh(s, e, 8.5, suit, shade(suit, 0.60))
    rig.capsule_sh(e, h, 7.5, fore, shade(fore, 0.60))
    glove = pal['glove']
    rig.ell(h[0], h[1], 4.6, 4.6, glove)
    rig.ell(h[0] - 1.3, h[1] - 1.3, 1.8, 1.8, shade(glove, 1.35))


def draw_leg(rig, hip, knee, foot, pal, back=False):
    suit = pal['suit_b'] if back else pal['suit']
    pants = pal.get('pants_b' if back else 'pants', suit)
    rig.capsule_sh(hip, knee, 10.5, suit, shade(suit, 0.60))
    rig.capsule_sh(knee, foot, 9.0, pants, shade(pants, 0.60))
    fx, fy = foot
    boot = pal['boot']
    rig.rrect(fx - 6.5, fy - 5.0, fx + 6.5, fy + 1.0, 2.4, boot)
    rig.rrect(fx - 6.5, fy - 1.8, fx + 6.5, fy + 1.0, 1.6, shade(boot, 0.6))


def draw_torso(rig, p, pal):
    hip, neck = p['hip'], p['neck']
    dx, dy = neck[0] - hip[0], neck[1] - hip[1]
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln, dx / ln
    hw_top, hw_bot = 11.0, 13.5
    a = (hip[0] + nx * hw_bot, hip[1] + ny * hw_bot)
    b = (hip[0] - nx * hw_bot, hip[1] - ny * hw_bot)
    c = (neck[0] - nx * hw_top, neck[1] - ny * hw_top)
    d = (neck[0] + nx * hw_top, neck[1] + ny * hw_top)
    rig.poly([a, b, c, d], pal['suit'])
    # 背光暗侧(右下)
    rig.poly([b, c, (lerp(b[0], c[0], 0.42) + nx * -hw_bot * 0.30,
                     lerp(b[1], c[1], 0.42))], pal['suit_b'])
    rig.poly([b, (lerp(b[0], a[0], 0.55), lerp(b[1], a[1], 0.55)),
              (lerp(b[0], c[0], 0.45), lerp(b[1], c[1], 0.45))], pal['suit_b'])
    # 腰带
    ty = lerp(hip[1], neck[1], 0.28)
    tx = lerp(hip[0], neck[0], 0.28)
    belt_w = lerp(hw_bot, hw_top, 0.28)
    ang = math.atan2(dy, dx) - math.pi / 2
    pts = []
    for sgn in (-1, 1):
        for t in (0, 1):
            bx = lerp(tx, lerp(b[0], a[0], 0.5), t)
            by = lerp(ty, lerp(b[1], a[1], 0.5), t)
            pts.append((bx + nx * belt_w * sgn * (1 - t * 0.15),
                        by + ny * belt_w * sgn * (1 - t * 0.15)))
    rig.poly([(tx - belt_w, ty - 3), (tx + belt_w, ty - 3),
              (tx + belt_w, ty + 3), (tx - belt_w, ty + 3)], pal['belt'])


# ---------------------------------------------------------------- 发型库

def hair_dome(rig, p, rx_extra=1.0, bottom=None, color=None):
    """发穹顶: 只覆盖 头顶→眉线 以上(不吞掉眼睛)。"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    col = color
    if bottom is None:
        bottom = -4.0  # 相对头中心: 眉上方
    top = -ry - 1.0
    c_y = hc[1] + (top + bottom) / 2.0
    h_half = (bottom - top) / 2.0
    rig.ell(hc[0], c_y, rx + rx_extra, h_half, col)
    return hc, rx, ry


def hair_spiky(rig, p, pal, spikes=7, reach=1.0):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hi = pal.get('hair_hi', shade(h, 1.6))
    hair_dome(rig, p, 1.2, -5.0, h)
    for i in range(spikes):
        a = math.pi * (0.06 + 0.88 * i / (spikes - 1))
        bx = hc[0] + math.cos(a) * (rx - 2)
        by = hc[1] - 3 + math.sin(a) * (ry - 5)
        tx = hc[0] + math.cos(a) * (rx + 7.5 * reach)
        ty = hc[1] - 5 + math.sin(a) * (ry + 9.0 * reach)
        w = 3.4 - abs(math.cos(a)) * 1.2
        nxa, nya = math.sin(a) * 0.9, -math.cos(a) * 0.55
        rig.poly([(bx - nxa * w, by - nya * w), (bx + nxa * w, by + nya * w),
                  (tx, ty)], h)
        if i % 2 == 0:
            rig.poly([(bx + 0.5, by - 1), (bx + 1.6, by),
                      (lerp(bx, tx, 0.5), lerp(by, ty, 0.5))], hi)


def hair_long(rig, p, pal, t=0.0, length=34, bangs=True):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hi = pal.get('hair_hi', shade(h, 1.7))
    sway = math.sin(t * math.tau) * 2.0
    hair_dome(rig, p, 2.2, -6.0, h)
    for side in (-1, 1):
        top = (hc[0] + side * (rx + 0.5), hc[1] + 1)
        mid = (hc[0] + side * (rx + 7), hc[1] + length * 0.55)
        tip = (hc[0] + side * (rx + 5) + sway * side * 0.4, hc[1] + length)
        rig.poly([(top[0] - 2.4, top[1] - 2), (top[0] + 2.6, top[1] - 2),
                  (mid[0] + 5, mid[1]), (tip[0] + 3, tip[1]),
                  (tip[0] - 1, tip[1] + 2), (mid[0] - 1, mid[1] + 1)], h)
        rig.capsule((mid[0] - 2, mid[1] - 6), (tip[0] - 1, tip[1] - 3), 2.0, hi)
    if bangs:
        for i in range(4):
            bx = hc[0] - rx + 2.5 + i * (2 * rx - 5) / 3
            rig.poly([(bx - 2.4, hc[1] - ry * 0.42), (bx + 2.4, hc[1] - ry * 0.42),
                      (bx + 0.2, hc[1] + ry * 0.06)], h)


def hair_topknot(rig, p, pal):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hair_dome(rig, p, 1.0, -5.0, h)
    rig.rrect(hc[0] - 3.4, hc[1] - ry - 8.5, hc[0] + 3.4, hc[1] - ry - 1.5, 2.0, h)
    rig.rrect(hc[0] - 3.8, hc[1] - ry - 4.6, hc[0] + 3.8, hc[1] - ry - 2.8, 1.0,
              pal.get('accent', hexc('e0a83c')))
    for i in range(3):
        x = hc[0] - rx + 2 + i * (2 * rx - 4) / 2
        rig.poly([(x - 1.6, hc[1] - 4), (x + 1.6, hc[1] - 4), (x, hc[1] + 6)], h)


def hair_mane(rig, p, pal):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hair_dome(rig, p, 1.4, -5.0, h)
    for a_deg in (-82, -58, -34, -12, 10, 32, 56, 80):
        a = math.radians(a_deg)
        bx = hc[0] + math.cos(a) * (rx - 1)
        by = hc[1] - 3 + math.sin(a) * (ry - 4)
        tx = hc[0] + math.cos(a) * (rx + 6.0)
        ty = hc[1] - 3 + math.sin(a) * (ry + 7.0)
        rig.capsule((bx, by), (tx, ty), 3.0, h)


def hair_medium(rig, p, pal, t=0.0):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hair_dome(rig, p, 1.8, -5.0, h)
    sway = math.sin(t * math.tau) * 1.5
    for side in (-1, 1):
        rig.poly([(hc[0] + side * (rx - 1), hc[1] - 6),
                  (hc[0] + side * (rx + 3.4), hc[1] - 2),
                  (hc[0] + side * (rx + 2.8) + sway * side * 0.3, hc[1] + 16),
                  (hc[0] + side * (rx - 2.5), hc[1] + 14)], h)
    for i in range(4):
        bx = hc[0] - rx + 2.5 + i * (2 * rx - 5) / 3
        rig.poly([(bx - 2.2, hc[1] - ry * 0.36), (bx + 2.2, hc[1] - ry * 0.36),
                  (bx + 0.2, hc[1] + ry * 0.26)], h)


def hair_pigtails(rig, p, pal, t=0.0):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    h = pal['hair']
    hi = pal.get('hair_hi', shade(h, 1.5))
    hair_dome(rig, p, 1.6, -5.0, h)
    rig.arc(hc[0], hc[1] - 1, rx + 1.0, 195, 345, hi, 2.2)
    sway = math.sin(t * math.tau) * 2.5
    for side in (-1, 1):
        top = (hc[0] + side * (rx + 1), hc[1] - 6)
        tip = (hc[0] + side * (rx + 13) + side * sway * 0.5, hc[1] + 2 + sway * 0.4)
        rig.capsule(top, tip, 6.0, h)
        rig.ell(tip[0], tip[1], 3.4, 3.6, h)
        rig.ell(top[0] + side * 1, top[1] + 1, 2.0, 2.0, hi)


def fox_ears(rig, p, pal):
    hc, rx = p['headc'], p['head_rx']
    for side in (-1, 1):
        bx = hc[0] + side * (rx - 3.5)
        by = hc[1] - p['head_ry'] * 0.58
        tip = (bx + side * 5.5, by - 12)
        rig.poly([(bx - 4.2, by + 2), (bx + 4.2, by + 2), tip], pal['hair'])
        rig.poly([(bx - 1.6, by + 1), (bx + 2.2, by + 1),
                  (bx + side * 3.0, by - 6)], pal.get('accent', hexc('e89090')))


def oni_horns(rig, p, pal):
    hc, rx = p['headc'], p['head_rx']
    horn = pal.get('horn', hexc('f2e6c8'))
    for side in (-1, 1):
        bx = hc[0] + side * (rx - 5)
        by = hc[1] - p['head_ry'] * 0.5
        tip = (bx + side * 10, by - 14)
        rig.poly([(bx - 3.0, by + 2), (bx + 3.4, by + 2),
                  (tip[0] + 1.8, tip[1] + 1), (tip[0], tip[1] - 1)], horn)
        rig.poly([(bx + side * 1.2, by + 1), (bx + 3.4, by + 2),
                  (tip[0] + 1.8, tip[1] + 1)], shade(horn, 0.72))


# ---------------------------------------------------------------- 脸库

def face_anime(rig, p, pal, angry=False, pupil=None, smile=False):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    pupil = pupil or pal.get('pupil', hexc('2b2b3d'))
    ey = hc[1] + 1.5
    for side in (-1, 1):
        ex = hc[0] + side * (rx * 0.44)
        # 上睫毛线(深色, 保证任何肤色下眼睛可读)
        rig.rrect(ex - 4.4, ey - 5.0, ex + 4.4, ey - 3.2, 1.0,
                  pal.get('brow', pal.get('hair', hexc('1c1826'))))
        rig.ell(ex, ey, 4.2, 4.6, hexc('f8f6f0'))
        rig.ell(ex + side * 0.3, ey + 0.4, 2.9, 3.5, pupil)
        rig.ell(ex - 1.2, ey - 1.4, 1.1, 1.3, hexc('ffffff'))
        by = ey - 6.0 if not angry else ey - 5.0
        brow = pal.get('brow', pal.get('hair', hexc('2b2b3d')))
        bx0, bx1 = ex - 3.4, ex + 3.4
        if angry:  # 怒眉: 内端下压(内=靠鼻侧)
            in_x = bx1 if side < 0 else bx0
            out_x = bx0 if side < 0 else bx1
            rig.poly([(out_x, by), (in_x, by + 1.0), (in_x, by + 2.8),
                      (out_x, by + 2.2)], brow)
        else:
            rig.poly([(bx0, by), (bx1, by), (bx1, by + 2.0), (bx0, by + 2.0)], brow)
    if smile:
        rig.arc(hc[0], hc[1] + ry * 0.30, 3.4, 20, 160, pal.get('mouth', hexc('b86868')), 1.8)
    else:
        rig.capsule((hc[0] - 1.6, hc[1] + ry * 0.52), (hc[0] + 1.8, hc[1] + ry * 0.52),
                    1.6, pal.get('mouth', hexc('b86868')))


def face_ppg(rig, p, pal):
    """飞天小女警: 超大圆眼"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    for side in (-1, 1):
        ex = hc[0] + side * rx * 0.42
        ey = hc[1] + 2
        rig.ell(ex, ey, 4.6, 5.2, hexc('ffffff'))
        rig.ell(ex, ey + 0.6, 3.4, 4.2, pal.get('pupil', hexc('58a8e0')))
        rig.ell(ex - 1.2, ey - 1.6, 1.3, 1.5, hexc('ffffff'))
    rig.arc(hc[0], hc[1] + ry * 0.24, 3.6, 20, 160, hexc('d86078'), 2.0)
    for side in (-1, 1):  # 腮红
        rig.ell(hc[0] + side * (rx * 0.72), hc[1] + ry * 0.40, 2.0, 1.4,
                pal.get('blush', hexc('f8b0c0')))


def face_mask_white(rig, p, pal):
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    y0 = hc[1] - 4.0
    mask = hexc('f4f2ec')
    # 面具底形(横贯双眼的尖角形)
    rig.poly([(hc[0] - rx - 1.5, y0 + 3.6), (hc[0] - rx * 0.55, y0 - 2.0),
              (hc[0] + rx * 0.55, y0 - 2.0), (hc[0] + rx + 1.5, y0 + 3.6),
              (hc[0] + rx * 0.60, y0 + 6.4), (hc[0] - rx * 0.60, y0 + 6.4)],
             mask)
    # 面具深色勾边(小尺寸下的轮廓保证)
    edge = hexc('15121c')
    rig.poly([(hc[0] - rx - 1.5, y0 + 3.6), (hc[0] - rx * 0.55, y0 - 2.0),
              (hc[0] - rx * 0.42, y0 - 2.0), (hc[0] - rx - 0.3, y0 + 3.4)], edge)
    rig.poly([(hc[0] + rx + 1.5, y0 + 3.6), (hc[0] + rx * 0.55, y0 - 2.0),
              (hc[0] + rx * 0.42, y0 - 2.0), (hc[0] + rx + 0.3, y0 + 3.4)], edge)
    for side in (-1, 1):  # 大瞳缝(红瞳, 小尺寸可读)
        ex = hc[0] + side * rx * 0.44
        rig.poly([(ex - 3.0, y0 + 1.8), (ex + 3.0, y0 + 0.6),
                  (ex + 3.0, y0 + 4.2), (ex - 3.0, y0 + 5.0)], edge)
        rig.poly([(ex - 2.2, y0 + 2.2), (ex + 2.2, y0 + 1.3),
                  (ex + 2.2, y0 + 3.6), (ex - 2.2, y0 + 4.4)], hexc('c92a44'))
    rig.capsule((hc[0] - 1.6, hc[1] + ry * 0.48), (hc[0] + 1.8, hc[1] + ry * 0.48),
                1.6, hexc('9a2a3c'))


def face_helmet(rig, p, pal, eye_col, crest=None, chin=None):
    """全头盔五官: 复眼 + 口栅 + 可选 V 天线/脊冠/下巴甲"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    if crest == 'vfin':
        gold = pal.get('accent', hexc('f2c838'))
        rig.rrect(hc[0] - 1.6, hc[1] - ry - 9.0, hc[0] + 1.6, hc[1] - ry + 2.5,
                  1.2, gold)
        for side in (-1, 1):
            for i in range(5):
                x0 = hc[0] + side * (2.0 + i * 2.2)
                y0 = hc[1] - ry + 1.0 - i * 2.0
                rig.capsule((x0, y0), (x0 + side * 2.0, y0 - 2.0), 2.0, gold)
    elif crest == 'ridge':
        rig.capsule((hc[0], hc[1] - ry - 4.5), (hc[0], hc[1] - ry + 3.5), 3.0,
                    shade(pal['helmet'], 1.5))
        rig.ell(hc[0], hc[1] - ry - 5.5, 2.2, 2.2, pal.get('crest_gem',
                pal.get('accent', hexc('ff4040'))))
    for side in (-1, 1):
        ex = hc[0] + side * rx * 0.46
        ey = hc[1] + 0.5
        rig.poly([(ex - 4.4, ey - 2.8), (ex + 4.4, ey - 3.6),
                  (ex + 4.8, ey + 1.6), (ex - 3.8, ey + 3.0)], eye_col)
        rig.poly([(ex - 2.4, ey - 1.7), (ex - 0.4, ey - 2.0),
                  (ex - 0.6, ey + 0.8), (ex - 2.1, ey + 0.8)], shade(eye_col, 1.5))
    gy = hc[1] + ry * 0.42
    rig.rrect(hc[0] - 4.6, gy - 2.2, hc[0] + 4.6, gy + 2.4, 1.5,
              pal.get('grille', hexc('b8c0c8')))
    for i in range(3):
        yy = gy - 1.2 + i * 1.6
        rig.capsule((hc[0] - 4.0, yy), (hc[0] + 4.0, yy), 0.7,
                    shade(pal.get('grille', hexc('b8c0c8')), 0.5))
    if chin:
        cy = hc[1] + ry * 0.74
        rig.rrect(hc[0] - 3.6, cy - 1.4, hc[0] + 3.6, cy + 1.6, 1.2, chin)


def face_forehead_band(rig, p, pal):
    """护额: 蓝带 + 钢牌"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    band = pal.get('band', hexc('2858a8'))
    y = hc[1] - ry * 0.30
    rig.rrect(hc[0] - rx - 1.2, y - 2.6, hc[0] + rx + 1.2, y + 2.2, 1.5, band)
    plate = hexc('9aa6b4')
    rig.rrect(hc[0] - 6.4, y - 2.8, hc[0] + 6.4, y + 2.4, 1.2, plate)
    rig.ell(hc[0] - 2.2, y - 0.2, 1.2, 1.2, shade(plate, 0.55))
    rig.capsule((hc[0] + 1.2, y), (hc[0] + 4.4, y), 1.0, shade(plate, 0.55))


def face_whiskers(rig, p, pal):
    hc, rx = p['headc'], p['head_rx']
    for side in (-1, 1):
        for i in range(3):
            yy = hc[1] + 3.5 + i * 2.0
            x0 = hc[0] + side * (rx * 0.55)
            rig.capsule((x0, yy), (x0 + side * 3.4, yy - 0.6), 0.8,
                        shade(pal['skin'], 0.55))
