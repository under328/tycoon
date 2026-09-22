# -*- coding: utf-8 -*-
"""12 个角色的皮肤规格 + 总绘制入口。

每个角色: pal(调色板) + hair/face/outfit/back/front 回调, 依据 rig 的
关节地标绘制。draw_character 按 背景层→后肢→躯干→前肢→头 的顺序合成。
"""
import math
from px import hexc, shade
import rig as R
from rig import Rig

GOLD = hexc('e0a83c')
WHITE = hexc('f4f2ec')
INK = hexc('16121c')


# ================================================================ 角色规格

def _back_cape(rig, p, pal, length=26, color=None, sway=0.0):
    """披风/大衣后摆(身后飘动)"""
    col = color or pal['suit_b']
    neck, hip = p['neck'], p['hip']
    x0 = neck[0] - 2
    rig.poly([(neck[0] - 6, neck[1] + 2), (neck[0] + 3, neck[1] + 2),
              (hip[0] + 5 + sway, hip[1] + length * 0.5),
              (hip[0] - 12 - sway, hip[1] + length * 0.55),
              (hip[0] - 9 - sway * 1.5, hip[1] + length)], col)


def _long_nose(rig, p, pal):
    """天狗长鼻(伸出脸前)"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    skin = pal['skin']
    rig.poly([(hc[0] + rx * 0.42, hc[1] - 1.5),
              (hc[0] + rx + 13, hc[1] + 3.2),
              (hc[0] + rx + 12.5, hc[1] + 5.8),
              (hc[0] + rx * 0.45, hc[1] + 4.5)], skin)
    rig.poly([(hc[0] + rx + 6, hc[1] + 4.6), (hc[0] + rx + 13, hc[1] + 3.4),
              (hc[0] + rx + 12.5, hc[1] + 5.8), (hc[0] + rx + 6, hc[1] + 5.8)],
             shade(skin, 0.72))


def tengu_face(rig, p, pal):
    """天狗脸: 浓白眉 + 小眼 + 长鼻 + 白髭"""
    hc, rx, ry = p['headc'], p['head_rx'], p['head_ry']
    white = pal['accent']
    # 浓白眉(压在鼻根上)
    for side in (-1, 1):
        rig.poly([(hc[0] + side * 3, hc[1] - 6), (hc[0] + side * 9.5, hc[1] - 7.5),
                  (hc[0] + side * 9.5, hc[1] - 4.8), (hc[0] + side * 3, hc[1] - 3.6)],
                 white)
    # 小眼(怒)
    for side in (-1, 1):
        ex = hc[0] + side * rx * 0.40
        ey = hc[1] + 0.5
        rig.poly([(ex - 2.6, ey - 1.8), (ex + 2.6, ey - 1.8), (ex + 2.6, ey + 1.4),
                  (ex - 2.6, ey + 1.4)], hexc('f8f6f0'))
        rig.poly([(ex - 1.6, ey - 1.0), (ex + 1.4, ey - 1.0), (ex + 1.4, ey + 1.0),
                  (ex - 1.6, ey + 1.0)], pal.get('pupil', hexc('241c30')))
    _long_nose(rig, p, pal)
    # 白髭(鼻侧下垂)
    for side in (-1, 1):
        rig.poly([(hc[0] + side * 6.5, hc[1] + 5), (hc[0] + side * 11, hc[1] + 5),
                  (hc[0] + side * 10, hc[1] + 12), (hc[0] + side * 7, hc[1] + 11)],
                 white)


# ---- 每角色的绘制回调 ----

def def_hair(rig, p, pal, t):
    R.hair_topknot(rig, p, pal)


def def_outfit(rig, p, pal):
    """墨客: 藏青羽织 + 白领 + 金扣"""
    neck, hip = p['neck'], p['hip']
    rig.poly([(neck[0] - 7, neck[1]), (neck[0] + 7, neck[1]),
              (neck[0] + 2, neck[1] + 14), (neck[0] - 2, neck[1] + 14)],
             pal.get('collar', WHITE))
    ty = R.lerp(hip[1], neck[1], 0.28)
    rig.ell(R.lerp(hip[0], neck[0], 0.28) + 4, ty, 2.2, 2.2, GOLD)


def oni_outfit(rig, p, pal):
    """鬼: 毛披肩 + 虎纹兜裆布裙"""
    neck, hip = p['neck'], p['hip']
    fur = pal.get('fur', hexc('8a7448'))
    for side in (-1, 1):
        rig.poly([(neck[0] + side * 5, neck[1] - 1), (neck[0] + side * 15, neck[1] + 6),
                  (neck[0] + side * 12, neck[1] + 13), (neck[0] + side * 4, neck[1] + 8)],
                 fur)
    # 虎纹腰布(黑色条纹的金布)
    tx = hip[0]
    rig.rrect(tx - 13, hip[1] - 5, tx + 13, hip[1] + 16, 3, pal.get('skirt', GOLD))
    dark = shade(pal.get('skirt', GOLD), 0.35)
    for i in range(3):
        x = tx - 9 + i * 7
        rig.poly([(x, hip[1] - 4), (x + 3, hip[1] - 4), (x + 5, hip[1] + 8),
                  (x + 2, hip[1] + 8)], dark)
    rig.rrect(tx - 13, hip[1] - 6, tx + 13, hip[1] - 2, 1.5,
              pal.get('rope', hexc('8a2a20')))


def oni_club(rig, p, pal, t):
    """金棒(铁棒+铆钉)在前手"""
    h = p['h_f']
    iron = hexc('6a6f78')
    rig.capsule((h[0] - 2, h[1] + 9), (h[0] + 16, h[1] - 16), 4.2, iron)
    for i in range(4):
        a = math.radians(40 + i * 35)
        cx = h[0] + 16 + math.cos(a) * 3.5
        cy = h[1] - 16 + math.sin(a) * 3.5
        rig.star4((cx, cy), 3.2, shade(iron, 1.5), 0.4)


def kitsu_outfit(rig, p, pal):
    """狐妖: 白巫女袍 + 红袖口/领"""
    neck, hip = p['neck'], p['hip']
    red = pal.get('accent', hexc('c93030'))
    rig.poly([(neck[0] - 6, neck[1]), (neck[0] + 6, neck[1]),
              (neck[0] + 2, neck[1] + 12), (neck[0] - 2, neck[1] + 12)], red)
    # 红色裙甲(袴)
    tx = hip[0]
    rig.rrect(tx - 13, hip[1] - 4, tx + 13, hip[1] + 15, 3, red)


def oiran_outfit(rig, p, pal):
    """花魁: 紫打挂(宽下摆) + 前红带 + 金领 + 三齿木屐"""
    neck, hip = p['neck'], p['hip']
    kim = pal['suit']
    # 宽下摆裙(打挂): 从腰向外展开拖到地
    tx, ty = hip[0], hip[1]
    rig.poly([(tx - 12, ty - 5), (tx + 12, ty - 5), (tx + 20, ty + 26),
              (tx + 8, ty + 30), (tx - 8, ty + 30), (tx - 20, ty + 26)], kim)
    # 黑地纹样(下摆缘)
    hem = shade(kim, 0.45)
    rig.poly([(tx - 19, ty + 22), (tx + 19, ty + 22), (tx + 20, ty + 26),
              (tx - 20, ty + 26)], hem)
    for i in range(4):  # 波纹
        x = tx - 12 + i * 8
        rig.arc(x, ty + 8, 3.5, 0, 180, hem, 1.6)
    # 前红带(花魁签名: 腹前结)
    obi = pal.get('obi', hexc('e0a83c'))
    rig.rrect(tx - 9, ty - 6, tx + 9, ty + 8, 2.5, pal.get('obi_red', hexc('c22840')))
    rig.rrect(tx - 9, ty - 6, tx + 9, ty - 2, 1.5, obi)
    # 内衬红领
    rig.poly([(neck[0] - 6, neck[1]), (neck[0] + 6, neck[1]),
              (neck[0] + 2, neck[1] + 13), (neck[0] - 2, neck[1] + 13)],
             pal.get('collar', hexc('c22840')))


def oiran_kanzashi(rig, p, pal, t):
    """金簪(右侧) + 垂珠"""
    hc, rx = p['headc'], p['head_rx']
    rig.capsule((hc[0] + rx - 2, hc[1] - 10), (hc[0] + rx + 8, hc[1] - 13), 1.8, GOLD)
    rig.ell(hc[0] + rx + 8.5, hc[1] - 13, 2.2, 2.2, hexc('c22840'))
    sway = math.sin(t * math.tau + 1.0) * 1.2
    for i in range(3):
        rig.capsule((hc[0] + rx + 6, hc[1] - 8 + i * 3),
                    (hc[0] + rx + 9 + sway, hc[1] - 5 + i * 3), 1.2, GOLD)


def tengu_back(rig, p, pal, t):
    """天狗黑羽翼(身后)"""
    neck = p['neck']
    wing = pal.get('wing', hexc('1c1c2a'))
    sway = math.sin(t * math.tau) * 2
    for side in (-1, 1):
        for i in range(3):
            ln = 24 - i * 5
            a = math.radians(-35 - i * 18) * (1 if side < 0 else 0.6)
            tipx = neck[0] + side * (10 + ln * 0.55)
            tipy = neck[1] - 6 - ln * 0.55 + i * 7 + sway
            rig.poly([(neck[0] + side * 6, neck[1] + 4),
                      (tipx, tipy), (tipx - side * 4, tipy + 3)], wing)


def tengu_hat(rig, p, pal):
    """皂角帽(小黑帽)"""
    hc, ry = p['headc'], p['head_ry']
    hat = pal.get('hat', hexc('101018'))
    rig.rrect(hc[0] - 7, hc[1] - ry - 7.5, hc[0] + 7, hc[1] - ry - 5.0, 1.2, hat)
    rig.rrect(hc[0] - 5, hc[1] - ry - 11.5, hc[0] + 5, hc[1] - ry - 7.0, 1.5, hat)


def dball_outfit(rig, p, pal):
    """龙珠武道服: 蓝内衬 V 领 + 蓝腰带(金扣)"""
    neck, hip = p['neck'], p['hip']
    blue = pal.get('blue', hexc('2868c8'))
    rig.poly([(neck[0] - 6, neck[1]), (neck[0] + 6, neck[1]),
              (neck[0] + 2, neck[1] + 15), (neck[0] - 2, neck[1] + 15)], blue)


def ninja_outfit(rig, p, pal):
    """木叶外套: 蓝肩 + 拉链"""
    neck, hip = p['neck'], p['hip']
    blue = pal.get('blue', hexc('2858a8'))
    for side in (-1, 1):
        rig.poly([(neck[0] + side * 5, neck[1] - 1), (neck[0] + side * 12, neck[1] + 5),
                  (neck[0] + side * 10, neck[1] + 10), (neck[0] + side * 4, neck[1] + 6)],
                 blue)
    tx = R.lerp(hip[0], neck[0], 0.4)
    ty = R.lerp(hip[1], neck[1], 0.4)
    rig.capsule((neck[0], neck[1]), (tx, ty + 4), 1.6, shade(pal['suit'], 0.5))


def rx_outfit(rig, p, pal):
    """RX骑士: 红色胸纹 + 银色腹甲 + 金腰带"""
    neck, hip = p['neck'], p['hip']
    red = pal.get('accent', hexc('d83828'))
    silver = pal.get('silver', hexc('b8c0c8'))
    # 胸 V 纹
    rig.poly([(neck[0] - 6, neck[1] + 2), (neck[0], neck[1] + 10),
              (neck[0] + 6, neck[1] + 2), (neck[0] + 4, neck[1] + 5),
              (neck[0], neck[1] + 13), (neck[0] - 4, neck[1] + 5)], red)
    # 腹甲(银横纹)
    ty = R.lerp(hip[1], neck[1], 0.32)
    rig.rrect(hip[0] - 9, ty - 3, hip[0] + 9, ty + 6, 2, silver)
    rig.capsule((hip[0] - 8, ty + 1), (hip[0] + 8, ty + 1), 1.0, shade(silver, 0.6))
    # 金带扣
    rig.ell(R.lerp(hip[0], neck[0], 0.28) + 4, ty, 2.4, 2.4, GOLD)


def p5_back(rig, p, pal, t):
    """怪盗: 黑大衣后摆(燕尾)"""
    _back_cape(rig, p, pal, length=30, color=shade(pal['suit'], 0.75),
               sway=math.sin(t * math.tau) * 3)


def p5_outfit(rig, p, pal):
    """灰马甲 + 金扣 + 红领巾"""
    neck, hip = p['neck'], p['hip']
    vest = pal.get('vest', hexc('3c3c48'))
    tx = R.lerp(hip[0], neck[0], 0.5)
    ty = R.lerp(hip[1], neck[1], 0.5)
    rig.rrect(tx - 7, neck[1] + 2, tx + 7, ty + 6, 2.5, vest)
    for i in range(2):
        rig.ell(tx - 3 + i * 6, ty, 1.2, 1.2, GOLD)
    rig.poly([(neck[0] - 5, neck[1]), (neck[0] + 5, neck[1]),
              (neck[0] + 1.5, neck[1] + 9), (neck[0] - 1.5, neck[1] + 9)],
             pal.get('accent', hexc('c92a44')))


def gundam_outfit(rig, p, pal):
    """高达: 蓝胸甲 + 红腹 + 黄散热口"""
    neck, hip = p['neck'], p['hip']
    blue = pal.get('blue', hexc('2858a8'))
    red = pal.get('red', hexc('d84040'))
    ty = R.lerp(hip[1], neck[1], 0.34)
    rig.rrect(neck[0] - 9, neck[1] + 1, neck[0] + 9, R.lerp(hip[1], neck[1], 0.30),
              2.5, blue)
    rig.rrect(hip[0] - 8, ty - 3, hip[0] + 8, ty + 5, 2, red)
    for i in range(2):
        rig.rrect(neck[0] - 6 + i * 8, neck[1] + 4, neck[0] - 3 + i * 8,
                  neck[1] + 8, 1.0, pal.get('accent', hexc('f2c838')))


def ppg_outfit(rig, p, pal):
    """小女警: 蓝裙 + 黑条纹带"""
    neck, hip = p['neck'], p['hip']
    tx, ty = hip[0], hip[1]
    rig.poly([(tx - 11, ty - 2), (tx + 11, ty - 2), (tx + 17, ty + 14),
              (tx - 17, ty + 14)], pal.get('dress_b', hexc('4890c8')))
    rig.poly([(tx - 13, ty + 2), (tx + 13, ty + 2), (tx + 17, ty + 14),
              (tx - 17, ty + 14)], pal.get('dress', hexc('7ac0e8')))
    rig.poly([(tx - 15, ty + 9), (tx + 15, ty + 9), (tx + 16, ty + 12),
              (tx - 16, ty + 12)], hexc('1a1626'))


# ---------------------------------------------------------------- 规格表

SPECS = {
    'skin_default': {
        'name': '墨客',
        'pal': {
            'skin': hexc('e8dcc8'), 'skin_b': hexc('c9b098'),
            'hair': hexc('2b2b3d'), 'suit': hexc('3a4a6a'),
            'suit_b': hexc('28324a'), 'glove': hexc('e8dcc8'),
            'boot': hexc('1c2438'), 'belt': hexc('1c2438'),
            'accent': GOLD, 'pupil': hexc('2b2b3d'), 'outline': hexc('14101e'),
        },
        'hair': lambda rig, p, pal, t: R.hair_topknot(rig, p, pal),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal),
        'outfit': def_outfit,
        'fx': hexc('e0a83c'),
    },
    'skin_aka': {
        'name': '赤鬼',
        'pal': {
            'skin': hexc('d9887c'), 'skin_b': hexc('b86055'),
            'hair': hexc('2b1a2a'), 'suit': hexc('d9887c'),
            'suit_b': hexc('b86055'), 'glove': hexc('d9887c'),
            'boot': hexc('5a3020'), 'belt': hexc('8a2a20'),
            'horn': hexc('f2e6c8'), 'accent': hexc('e0503c'),
            'pupil': hexc('3a1420'), 'skirt': GOLD, 'outline': hexc('200e14'),
        },
        'hair': lambda rig, p, pal, t: R.hair_mane(rig, p, pal),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal, angry=True),
        'outfit': oni_outfit,
        'head_extra': lambda rig, p, pal, t: R.oni_horns(rig, p, pal),
        'front': oni_club,
        'fx': hexc('ff5040'),
    },
    'skin_ao': {
        'name': '青鬼',
        'pal': {
            'skin': hexc('a8c8ec'), 'skin_b': hexc('7898c4'),
            'hair': hexc('1c1c28'), 'suit': hexc('a8c8ec'),
            'suit_b': hexc('7a96c0'), 'glove': hexc('9db8dc'),
            'boot': hexc('243048'), 'belt': hexc('243048'),
            'horn': hexc('f2e6c8'), 'accent': hexc('7ec8ff'),
            'pupil': hexc('14203a'), 'skirt': hexc('e8c878'),
            'outline': hexc('101828'),
        },
        'hair': lambda rig, p, pal, t: R.hair_mane(rig, p, pal),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal, angry=False),
        'outfit': oni_outfit,
        'head_extra': lambda rig, p, pal, t: R.oni_horns(rig, p, pal),
        'front': oni_club,
        'fx': hexc('7ec8ff'),
    },
    'skin_kitsu': {
        'name': '狐妖',
        'pal': {
            'skin': hexc('f2efe6'), 'skin_b': hexc('d8d2c0'),
            'hair': hexc('f2efe6'), 'hair_hi': hexc('ffffff'),
            'suit': hexc('e8e2d4'), 'suit_b': hexc('b8b2a0'),
            'glove': hexc('f2efe6'), 'boot': hexc('c93030'),
            'belt': hexc('c93030'), 'accent': hexc('e89090'),
            'pupil': hexc('8a5426'), 'outline': hexc('3a3040'),
        },
        'hair': lambda rig, p, pal, t: R.hair_medium(rig, p, pal, t),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal, smile=True),
        'outfit': kitsu_outfit,
        'head_extra': lambda rig, p, pal, t: R.fox_ears(rig, p, pal),
        'fx': hexc('ff9a8a'),
    },
    'skin_oiran': {
        'name': '花魁',
        'pal': {
            'skin': hexc('f2e6d8'), 'skin_b': hexc('d8c0ac'),
            'hair': hexc('2a1f30'), 'hair_hi': hexc('584a60'),
            'suit': hexc('7a2464'), 'suit_b': hexc('4e1540'),
            'fore': hexc('7a2464'), 'fore_b': hexc('4e1540'),
            'glove': hexc('f2e6d8'), 'boot': hexc('8a2f20'),
            'belt': hexc('e0a83c'), 'accent': hexc('e0a83c'),
            'obi_red': hexc('c22840'), 'collar': hexc('c22840'),
            'pupil': hexc('241a28'), 'mouth': hexc('c22840'),
            'outline': hexc('180a16'),
        },
        'hair': lambda rig, p, pal, t: R.hair_long(rig, p, pal, t, length=36),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal),
        'outfit': oiran_outfit,
        'head_extra': lambda rig, p, pal, t: oiran_kanzashi(rig, p, pal, t),
        'fx': hexc('ff6b9a'),
    },
    'skin_tengu': {
        'name': '天狗',
        'pal': {
            'skin': hexc('d95040'), 'skin_b': hexc('b83a30'),
            'hair': hexc('f2e6d8'), 'suit': hexc('3a3a4c'),
            'suit_b': hexc('23232f'), 'glove': hexc('d95040'),
            'boot': hexc('2a2028'), 'belt': hexc('8a2a20'),
            'wing': hexc('1c1c2a'), 'hat': hexc('101018'),
            'accent': hexc('f2e6d8'), 'pupil': hexc('241c30'),
            'outline': hexc('160f14'),
        },
        'back': tengu_back,
        'hair': lambda rig, p, pal, t: R.hair_mane(rig, p, pal),
        'face': tengu_face,
        'outfit': lambda rig, p, pal: None,
        'head_extra': lambda rig, p, pal, t: tengu_hat(rig, p, pal),
        'fx': hexc('8fd8ff'),
    },
    'skin_dball': {
        'name': '龙珠战士',
        'pal': {
            'skin': hexc('f2c8a0'), 'skin_b': hexc('d4a880'),
            'hair': hexc('1c1620'), 'hair_hi': hexc('3c3440'),
            'suit': hexc('f28020'), 'suit_b': hexc('c05810'),
            'glove': hexc('2868c8'), 'boot': hexc('2868c8'),
            'belt': hexc('2868c8'), 'blue': hexc('2868c8'),
            'accent': GOLD, 'pupil': hexc('241c26'),
            'outline': hexc('1a1210'),
        },
        'hair': lambda rig, p, pal, t: R.hair_spiky(rig, p, pal, spikes=7, reach=1.0),
        'face': lambda rig, p, pal: R.face_anime(rig, p, pal, angry=True),
        'outfit': dball_outfit,
        'fx': hexc('ffb028'),
    },
    'skin_ninja': {
        'name': '木叶忍者',
        'pal': {
            'skin': hexc('f2d0a8'), 'skin_b': hexc('d0a878'),
            'hair': hexc('e8c840'), 'hair_hi': hexc('f8e888'),
            'suit': hexc('f07818'), 'suit_b': hexc('c05808'),
            'glove': hexc('2858a8'), 'boot': hexc('2858a8'),
            'belt': hexc('2858a8'), 'band': hexc('2858a8'),
            'accent': hexc('9aa6b4'), 'pupil': hexc('2858a8'),
            'outline': hexc('1a160e'),
        },
        'hair': lambda rig, p, pal, t: R.hair_spiky(rig, p, pal, spikes=6, reach=0.85),
        'face': lambda rig, p, pal: (
            R.face_anime(rig, p, pal, angry=True),
            R.face_forehead_band(rig, p, pal),
            R.face_whiskers(rig, p, pal)),
        'outfit': ninja_outfit,
        'fx': hexc('ffe060'),
    },
    'skin_rx': {
        'name': 'RX骑士',
        'pal': {
            'helmet': hexc('22222e'), 'skin': hexc('22222e'),
            'skin_b': hexc('12121c'),
            'hair': hexc('22222e'), 'suit': hexc('2c2c3a'),
            'suit_b': hexc('1a1a26'), 'glove': hexc('3a3a4a'),
            'boot': hexc('26262f'), 'belt': hexc('e0a83c'),
            'grille': hexc('c8d0d8'), 'silver': hexc('c8d0d8'),
            'accent': hexc('ff4030'), 'crest_gem': hexc('ff5040'),
            'outline': hexc('000000'),
        },
        'helmet': True,
        'hair': None,
        'face': lambda rig, p, pal: R.face_helmet(rig, p, pal,
            pal['accent'], crest='ridge'),
        'outfit': rx_outfit,
        'fx': hexc('ff4040'),
    },
    'skin_p5': {
        'name': '怪盗J',
        'pal': {
            'skin': hexc('f2e2d4'), 'skin_b': hexc('d4bca8'),
            'hair': hexc('181420'), 'hair_hi': hexc('342c40'),
            'suit': hexc('1a1a24'), 'suit_b': hexc('101018'),
            'fore': hexc('1a1a24'), 'fore_b': hexc('101018'),
            'glove': hexc('c92a44'), 'boot': hexc('101018'),
            'belt': hexc('101018'), 'vest': hexc('3c3c48'),
            'accent': hexc('c92a44'), 'outline': hexc('060408'),
        },
        'back': p5_back,
        'hair': lambda rig, p, pal, t: R.hair_long(rig, p, pal, t, length=22),
        'face': lambda rig, p, pal: R.face_mask_white(rig, p, pal),
        'outfit': p5_outfit,
        'fx': hexc('ff3355'),
    },
    'skin_gundam': {
        'name': '高达',
        'pal': {
            'helmet': hexc('e8ecf4'), 'skin': hexc('e8ecf4'),
            'skin_b': hexc('c0c8d8'),
            'hair': hexc('e8ecf4'), 'suit': hexc('e8ecf4'),
            'suit_b': hexc('c0c8d8'), 'glove': hexc('e8ecf4'),
            'boot': hexc('2858a8'), 'belt': hexc('2858a8'),
            'blue': hexc('2858a8'), 'red': hexc('d84040'),
            'grille': hexc('2a60b8'), 'accent': hexc('f2c838'),
            'outline': hexc('101828'),
        },
        'helmet': True,
        'hair': None,
        'face': lambda rig, p, pal: R.face_helmet(rig, p, pal, hexc('3ddc6c'),
            crest='vfin', chin=hexc('d84040')),
        'outfit': gundam_outfit,
        'fx': hexc('7ad9ff'),
    },
    'skin_ppg': {
        'name': '飞天小女警',
        'pal': {
            'skin': hexc('f8e2d8'), 'skin_b': hexc('e8c8bc'),
            'hair': hexc('f8e078'), 'hair_hi': hexc('fdf0b8'),
            'suit': hexc('7ac0e8'), 'suit_b': hexc('4890c8'),
            'dress': hexc('7ac0e8'), 'dress_b': hexc('4890c8'),
            'pants': hexc('f8e2d8'), 'pants_b': hexc('e8c8bc'),
            'glove': hexc('f8e2d8'), 'boot': hexc('1a1626'),
            'belt': hexc('1a1626'), 'pupil': hexc('58a8e0'),
            'blush': hexc('f8b0c0'), 'outline': hexc('302838'),
        },
        'hair': lambda rig, p, pal, t: R.hair_pigtails(rig, p, pal, t),
        'face': lambda rig, p, pal: R.face_ppg(rig, p, pal),
        'outfit': ppg_outfit,
        'fx': hexc('9ad8ff'),
    },
}


# ================================================================ 总绘制

def draw_character(cv, skin_id, pose, t=0.0, scale=1.0, origin=(0.0, 0.0),
                   whiteout=0.0, tint=None):
    """把角色画到超采样画布 cv 上。whiteout∈[0,1] 变身白闪覆盖率。"""
    spec = SPECS[skin_id]
    pal = spec['pal']
    rig = Rig(cv, scale, origin)

    # 蒙版配色: 变身白闪时全部颜色向白推进
    if whiteout > 0.0:
        w = whiteout
        tgt = tint or hexc('ffffff')
        pal = {k: tuple(int(c + (tgt[i] - c) * w) for i, c in enumerate(v[:3])) + (255,)
               for k, v in pal.items()}

    p = pose
    # 1. 背景层(披风/翅膀/后发)
    if spec.get('back'):
        spec['back'](rig, p, pal, t)
    # 2. 后肢
    R.draw_arm(rig, p['s_b'], p['e_b'], p['h_b'], pal, back=True)
    R.draw_leg(rig, p['hip_b'], p['knee_b'], p['foot_b'], pal, back=True)
    # 3. 躯干 + 服装
    R.draw_torso(rig, p, pal)
    if spec.get('outfit'):
        spec['outfit'](rig, p, pal)
    # 4. 前腿
    R.draw_leg(rig, p['hip_f'], p['knee_f'], p['foot_f'], pal, back=False)
    # 5. 头(皮肤或头盔) + 五官 + 发 + 头饰
    if spec.get('helmet'):
        rig.head_ell(p, pal['helmet'], shade(pal['helmet'], 0.72))
        rig.arc(p['headc'][0], p['headc'][1], p['head_rx'] + 0.5, 200, 320,
                shade(pal['helmet'], 1.3), 1.8)
    else:
        rig.head_ell(p, pal['skin'], pal['skin_b'])
    if spec.get('hair'):
        spec['hair'](rig, p, pal, t)
    if spec.get('face'):
        spec['face'](rig, p, pal)
    if spec.get('head_extra'):
        spec['head_extra'](rig, p, pal, t)
    # 6. 前臂
    R.draw_arm(rig, p['s_f'], p['e_f'], p['h_f'], pal, back=False)
    # 7. 前景层(武器等)
    if spec.get('front'):
        spec['front'](rig, p, pal, t)
    return rig
