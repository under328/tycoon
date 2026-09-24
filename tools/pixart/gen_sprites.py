# -*- coding: utf-8 -*-
"""生成格斗精灵图(256×256/帧, 纵向拼图): 每角色每个动作一张 PNG。

动作: idle(4) attack(4) skill_fire/skill_frost/skill_light(4×3)
defend(2) ult(4) transform(6) hit(2)
技能三系不同弹体/施法特效; 变身帧中性配色(运行时按主花色 modulate)。
128 基准骨架 ×2 缩放绘制 — 高分辨率下矢量图元自然带出更多细节。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import Canvas, hexc, shade, finish, save_sheet, SS
import rig as R
import specs
import fx as FX
from gen_avatars import palette_of
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'assets', 'fight')

FRAMES = {
    'idle': 4,
    'attack': 4,
    'skill_fire': 4,
    'skill_frost': 4,
    'skill_light': 4,
    'defend': 2,
    'ult': 4,
    'transform': 6,
    'hit': 2,
}


def _pose_of(action, i, n):
    t = i / float(n)
    if action == 'idle':
        return R.pose_idle(i / float(n))
    if action == 'attack':
        return R.pose_attack(i)
    if action.startswith('skill_'):
        return R.pose_skill(i)
    if action == 'defend':
        return R.pose_defend(i)
    if action == 'ult':
        return R.pose_ult(i)
    if action == 'transform':
        return R.pose_transform(i)
    if action == 'hit':
        return R.pose_hit(i)
    return R.pose_idle(0)


def _fx_of(rig, action, i, n, p, spec):
    """在该帧角色之上叠加动作特效"""
    t = i / float(n)
    acc = spec['fx']
    h_f = p['h_f']
    hip = p['hip']
    if action == 'attack':
        if i == 1:
            FX.fx_slash(rig, (h_f[0] + 8, h_f[1] - 4), acc, t * 0.3)
        elif i == 2:
            FX.fx_slash(rig, (h_f[0] + 12, h_f[1] - 2), acc, t * 0.6)
            FX.fx_impact(rig, (h_f[0] + 22, h_f[1]), shade(acc, 1.4), 0.3)
        elif i == 3:
            FX.fx_impact(rig, (h_f[0] + 20, h_f[1]), acc, 0.6)
    elif action == 'skill_fire':
        FX.fx_aura(rig, p, hexc('ff7f3c'), t, 0.55)
        if i == 0:
            FX.fx_fire(rig, (h_f[0], h_f[1]), t, 0.6)
        elif i == 1:
            FX.fx_fire(rig, (h_f[0] + 4, h_f[1]), t, 0.9)
        elif i == 2:
            FX.fx_projectile_fire(rig, (h_f[0] + 18, h_f[1] - 6), t)
        else:
            FX.fx_projectile_fire(rig, (h_f[0] + 30, h_f[1] - 10), t)
    elif action == 'skill_frost':
        FX.fx_aura(rig, p, hexc('7ec8ff'), t, 0.5)
        if i == 0:
            FX.fx_frost(rig, (h_f[0], h_f[1]), t, 0.6)
        elif i == 1:
            FX.fx_frost(rig, (h_f[0] + 4, h_f[1]), t, 0.9)
        elif i == 2:
            FX.fx_projectile_frost(rig, (h_f[0] + 18, h_f[1] - 6), t)
        else:
            FX.fx_projectile_frost(rig, (h_f[0] + 30, h_f[1] - 10), t)
    elif action == 'skill_light':
        FX.fx_aura(rig, p, hexc('ffe9a0'), t, 0.5)
        if i == 0:
            FX.fx_light(rig, (h_f[0], h_f[1]), t, 0.6)
        elif i == 1:
            FX.fx_light(rig, (h_f[0] + 4, h_f[1]), t, 0.9)
        elif i == 2:
            FX.fx_projectile_light(rig, (h_f[0] + 18, h_f[1] - 6), t)
        else:
            FX.fx_projectile_light(rig, (h_f[0] + 30, h_f[1] - 10), t)
    elif action == 'defend':
        FX.fx_shield(rig, (hip[0] + 6, hip[1] - 16), hexc('7ec8ff'), t)
    elif action == 'ult':
        if i == 0:
            FX.fx_aura(rig, p, acc, t, 0.9)
        elif i == 1:
            FX.fx_aura(rig, p, acc, t, 1.2)
            FX.fx_ult(rig, p, t * 0.5)
        elif i == 2:
            FX.fx_ult(rig, p, t)
            FX.fx_impact(rig, (h_f[0] + 16, h_f[1]), acc, 0.8)
        else:
            FX.fx_aura(rig, p, acc, t, 0.7)
    elif action == 'transform':
        core = hexc('ffe9a0')
        if i == 0:
            FX.fx_transform_glow(rig, p, 0.2, core)
        elif i == 1:
            FX.fx_transform_glow(rig, p, 0.5, core)
            FX.fx_aura(rig, p, core, t, 0.6)
        elif i == 2:
            FX.fx_aura(rig, p, core, t, 1.1)
        elif i == 3:
            FX.fx_aura(rig, p, core, t, 1.3)
            FX.fx_ult(rig, p, 0.4)
        elif i == 4:
            FX.fx_aura(rig, p, core, t, 1.2)
        else:
            FX.fx_aura(rig, p, core, t, 0.8)
    elif action == 'hit':
        FX.fx_impact(rig, (p['headc'][0] + 4, p['headc'][1] - 2),
                     hexc('ffffff'), t)


def _whiteout_of(action, i, n):
    if action == 'transform':
        # f2 白闪: 全身亮白; f3 略亮(能量状态)
        if i == 2:
            return 0.85
        if i == 3:
            return 0.30
    return 0.0


FRAME = 256   # 帧边长(128 骨架 ×2)


def gen_action(skin_id, action):
    spec = specs.SPECS[skin_id]
    n = FRAMES[action]
    frames = []
    for i in range(n):
        pose = _pose_of(action, i, n)
        cv = Canvas(FRAME)
        rig = specs.draw_character(cv, skin_id, pose, t=i / float(n),
                                   scale=FRAME / 128.0,
                                   whiteout=_whiteout_of(action, i, n))
        _fx_of(rig, action, i, n, pose, spec)
        frames.append(finish(cv, palette_of(skin_id),
                             spec['pal'].get('outline', hexc('14101e'))))
    return frames


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    base = os.path.join(OUT)
    for skin_id in specs.SPECS:
        if only and only != skin_id:
            continue
        d = os.path.join(base, skin_id)
        os.makedirs(d, exist_ok=True)
        for action, n in FRAMES.items():
            frames = gen_action(skin_id, action)
            save_sheet(frames, os.path.join(d, action + '.png'))
        print('sprites done:', skin_id)
    # 联络表: 抽查角色(所有动作, 每行一个动作)
    actions = list(FRAMES.keys())
    row_h = 96
    check_ids = ['skin_dball', 'skin_oiran', 'skin_rx']
    sheet = Image.new('RGBA', (row_h * 6 + 12 * 7, (row_h + 10) * len(actions) * 2
                               + 20), (24, 20, 38, 255))
    yy = 10
    for sid in check_ids:
        for action in actions:
            src = Image.open(os.path.join(base, sid, action + '.png'))
            for i in range(FRAMES[action]):
                fr = src.crop((0, i * FRAME, FRAME,
                               (i + 1) * FRAME)).resize(
                    (row_h, row_h), Image.NEAREST)
                sheet.paste(fr, (12 + i * (row_h + 12), yy))
            yy += row_h + 10
    sheet = sheet.resize((sheet.width, sheet.height), Image.NEAREST)
    sheet.save(os.path.join(OUT, '_sprites_contact.png'))
    print('all sprite sheets →', base)


if __name__ == '__main__':
    main()
