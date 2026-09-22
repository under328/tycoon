# -*- coding: utf-8 -*-
"""技能/攻击/受击/变身 特效层(画在超采样画布的角色之上)。"""
import math
from px import hexc, shade


def _ray(rig, c, a, r0, r1, col, w):
    rig.capsule((c[0] + math.cos(a) * r0, c[1] + math.sin(a) * r0),
                (c[0] + math.cos(a) * r1, c[1] + math.sin(a) * r1), w, col)


def fx_slash(rig, at, col, t=0.0):
    """挥砍弧光: 双弧 + 速度线"""
    a0 = -80 + t * 40
    a1 = 60 + t * 40
    rig.arc(at[0], at[1], 16, a0, a1, col, 5)
    rig.arc(at[0], at[1], 11, a0 + 8, a1 - 4, shade(col, 1.5), 2.5)
    for i in range(3):
        a = math.radians(a0 - 18 - i * 16)
        _ray(rig, at, a, 20, 28 + i * 2, shade(col, 1.2), 1.6)


def fx_fire(rig, at, t=0.0, scale=1.0):
    """烈焰: 火舌螺旋上升"""
    core = hexc('ffd166')
    mid = hexc('ff7f3c')
    outer = hexc('e04020')
    for i in range(5):
        a = t * math.tau + i * math.tau / 5
        bx = at[0] + math.cos(a) * 6 * scale
        by = at[1] + math.sin(a) * 3 * scale
        tip = (bx + math.sin(a * 2) * 4, by - 16 * scale)
        rig.poly([(bx - 4 * scale, by), (bx + 4 * scale, by), tip], outer)
        rig.poly([(bx - 2 * scale, by), (bx + 2.5 * scale, by),
                  (bx + math.sin(a * 2) * 2, by - 10 * scale)], mid)
        rig.poly([(bx - 1.2, by - 1), (bx + 1.5, by - 1),
                  (bx + math.sin(a * 2), by - 6 * scale)], core)
    rig.glow(at, 9 * scale, mid, rings=3)


def fx_frost(rig, at, t=0.0, scale=1.0):
    """冰霜: 六枝晶簇 + 雪点"""
    ice = hexc('7ec8ff')
    ice_hi = hexc('d8f2ff')
    for i in range(6):
        a = t * 0.8 + i * math.tau / 6
        _ray(rig, at, a, 3, 14 * scale, ice, 3.4 * scale)
        _ray(rig, at, a + 0.45, 6, 11 * scale, ice, 1.8)
        _ray(rig, at, a - 0.45, 6, 11 * scale, ice, 1.8)
    for i in range(5):
        a = -t * math.tau * 1.5 + i * math.tau / 2.5
        r = 12 + (i % 3) * 4
        rig.star4((at[0] + math.cos(a) * r, at[1] + math.sin(a) * r * 0.7),
                  2.2, ice_hi, 0.4)
    rig.glow(at, 8 * scale, ice, rings=3)


def fx_light(rig, at, t=0.0, scale=1.0):
    """圣光: 光羽环 + 金辉放射"""
    gold = hexc('ffe9a0')
    gold_hi = hexc('fff8d8')
    for i in range(8):
        a = t * 1.2 + i * math.tau / 8
        r = 13 * scale
        fx, fy = at[0] + math.cos(a) * r, at[1] + math.sin(a) * r * 0.8
        # 光羽(小菱形)
        rig.poly([(fx, fy - 4), (fx + 2, fy), (fx, fy + 4), (fx - 2, fy)], gold)
        rig.poly([(fx, fy - 2), (fx + 1, fy), (fx, fy + 2), (fx - 1, fy)], gold_hi)
    for i in range(6):
        a = -t * 0.6 + i * math.tau / 6 + 0.3
        _ray(rig, at, a, 15, 22 + (i % 2) * 4, gold, 1.8)
    rig.glow(at, 9 * scale, gold, rings=3)


def fx_projectile_fire(rig, at, t=0.0):
    """火球弹(飞行)"""
    fx_fire(rig, at, t, scale=0.8)
    rig.ell(at[0], at[1], 4.5, 4.5, hexc('fff0a0'))


def fx_projectile_frost(rig, at, t=0.0):
    fx_frost(rig, at, t, scale=0.7)
    rig.ell(at[0], at[1], 4, 4, hexc('ffffff'))


def fx_projectile_light(rig, at, t=0.0):
    fx_light(rig, at, t, scale=0.7)
    rig.ell(at[0], at[1], 4, 4, hexc('fffdf0'))


def fx_shield(rig, at, col, t=0.0):
    """护盾弧(角色前方)"""
    r = 17 + t * 3
    rig.arc(at[0], at[1], r, -70, 70, col, 4)
    rig.arc(at[0], at[1], r - 4, -55, 55, shade(col, 1.4), 2)
    for i in range(3):
        a = math.radians(-40 + i * 40)
        rig.star4((at[0] + math.cos(a) * (r - 6), at[1] + math.sin(a) * (r - 6)),
                  2.5, shade(col, 1.5), 0.4)


def fx_ult(rig, p, t=0.0):
    """奥义: 能量爆发(放射光柱 + 冲击环)"""
    c = (R0 := p['hip'])
    gold = hexc('ffd166')
    white = hexc('ffffff')
    ring_r = 10 + t * 22
    rig.arc(c[0], c[1] + 8, ring_r, 0, 180, gold, 4)
    rig.arc(c[0], c[1] + 8, ring_r + 6, 0, 170, shade(gold, 1.4), 2)
    for i in range(10):
        a = math.radians(i * 36 + t * 60)
        _ray(rig, c, a, 16, 30 + (i % 3) * 6, gold if i % 2 else white, 2.4)
    rig.star4((c[0], c[1] - 10), 14 + t * 6, white, 0.30)


def fx_aura(rig, p, col, t=0.0, height=1.0):
    """斗气焰(角色脚下向上包裹)"""
    c = p['hip']
    n = 7
    for i in range(n):
        a = t * math.tau * 1.4 + i * math.tau / n
        bx = c[0] + math.cos(a) * 10
        by = c[1] + 12
        tip = (bx + math.sin(a * 3) * 5, by - 34 * height - abs(math.cos(a)) * 8)
        rig.poly([(bx - 4, by), (bx + 4, by), tip], col)
    rig.glow((c[0], c[1]), 14, col, rings=3)


def fx_transform_glow(rig, p, t, col):
    """变身: 上升光粒 + 收束环"""
    c = (p['hip'][0], p['hip'][1] + 8)
    for i in range(8):
        ph = (t + i / 8.0) % 1.0
        yy = c[1] + 14 - ph * 44
        xx = c[0] + math.sin(i * 2.2 + t * 6) * 9
        rig.star4((xx, yy), 2.0 + (1 - ph) * 1.5, col, 0.4)
    r = 30 - t * 20
    rig.arc(c[0], c[1], r, 0, 360, col, 2.5)


def fx_impact(rig, at, col, t=0.0):
    """受击星芒"""
    rig.star4(at, 9 + t * 6, col, 0.32)
    for i in range(4):
        a = math.radians(45 * i + t * 90)
        _ray(rig, at, a, 6, 12, shade(col, 1.3), 1.6)
