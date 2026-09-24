# -*- coding: utf-8 -*-
"""生成商城头像(64×64 像素半身像) + 联络表(视觉迭代用)。

头像构图: 胸像特写 — 头部占画面 ~46%, 取 128 基准骨架放大后裁上半身。
"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import Canvas, hexc, shade, finish
import rig as R
import specs
import fx as FX
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'assets', 'avatars')

_HERE = os.path.dirname(os.path.abspath(__file__))


def _inline_colors():
    """收集 rig/specs/fx 源码里所有 hexc('xxxxxx') 内联色(量化必须覆盖)"""
    cols = []
    for fn in ('rig.py', 'specs.py', 'fx.py'):
        with open(os.path.join(_HERE, fn), encoding='utf-8') as f:
            for m in re.finditer(r"hexc\('([0-9a-fA-F]{6})'\)", f.read()):
                cols.append(hexc(m.group(1)))
    return cols


def palette_of(skin_id, extra=()):
    """角色调色板 + 自动明暗梯度 + 全部内联色(量化吸附用)"""
    pal = []
    seen = set()

    def add(c):
        key = (c[0], c[1], c[2])
        if key not in seen:
            seen.add(key)
            pal.append(key)

    for v in specs.SPECS[skin_id]['pal'].values():
        if not isinstance(v, tuple):   # 非颜色字段(eye_scale 等)跳过
            continue
        add(v)
        for f in (0.62, 0.8, 1.3, 1.55, 1.8):
            add(shade(v, f))
    for c in extra:
        add(c)
        for f in (0.62, 1.35, 1.7):
            add(shade(c, f))
    for c in _inline_colors():
        add(c)
        for f in (0.62, 1.35, 1.7):
            add(shade(c, f))
    return pal


def _center_x(img):
    """水平自动居中: 朝右构图的人物本体常偏右 3~5px(鼻/发/前肢), 商城/头像
    预览里表现为"整体偏右" — 按内容 bbox 中心平移回画布中线。"""
    bb = img.getbbox()
    if not bb:
        return img
    off = (bb[0] + bb[2]) // 2 - img.width // 2
    if abs(off) < 1:
        return img
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (-off, 0))
    return out


def gen_avatar(skin_id, size=64):
    """64×64 胸像: 128 骨架 ×0.82 缩放, 头中心落在 (32, 26), 水平自动居中"""
    pose = R.pose_idle(0.15)
    cv = Canvas(size)
    scale = 0.82
    ox = 32.0 - 60.0 * scale
    oy = 26.0 - 41.0 * scale
    spec = specs.SPECS[skin_id]
    saved_front = spec.get('front')
    specs.SPECS[skin_id]['front'] = None   # 半身像不画武器(小尺寸下成噪点)
    try:
        specs.draw_character(cv, skin_id, pose, t=0.15, scale=scale,
                             origin=(ox, oy))
    finally:
        specs.SPECS[skin_id]['front'] = saved_front
    img = finish(cv, palette_of(skin_id), spec['pal'].get(
        'outline', hexc('14101e')))
    return _center_x(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    ids = list(specs.SPECS.keys())
    # 联络表(4×3)
    sheet = Image.new('RGBA', (64 * 4 + 20 * 5, 64 * 3 + 20 * 4),
                      (24, 20, 38, 255))
    for i, sid in enumerate(ids):
        img = gen_avatar(sid)
        img.save(os.path.join(OUT, sid + '_64.png'))
        x = 20 + (i % 4) * (64 + 20)
        y = 20 + (i // 4) * (64 + 20)
        sheet.paste(img, (x, y))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
        os.path.join(OUT, '_contact.png'))
    print('avatars:', len(ids), '→', OUT)


if __name__ == '__main__':
    main()
