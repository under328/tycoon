# -*- coding: utf-8 -*-
"""语音播报批量合成: tools/voice_manifest.py → assets/voice/<key>.mp3。

v2 配音升级: 双声优分工 —
  · 播报女声(小晓, 明快): 出牌/回合/道具等常规播报
  · 燃系男声(云健, 沉稳有力): 战斗/必杀/胜负等关键时刻
生成策略: 男声键列表覆盖同 key 文件(效果=关键时刻换人喊)。
用法:
  python tools/voice_gen.py            # 增量: 只生成缺失的
  python tools/voice_gen.py --force    # 全量重生成
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice_manifest import MANIFEST  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "assets", "voice")

FEMALE = "zh-CN-XiaoxiaoNeural"
MALE = "zh-CN-YunjianNeural"
FEMALE_RATE, FEMALE_PITCH = "+10%", "+14Hz"
MALE_RATE, MALE_PITCH = "+6%", "-2Hz"

## 燃系男声接管的关键时刻(战斗演出/胜负宣判)
MALE_KEYS = {
    "battle_start", "f_boss", "f_ult", "f_vs", "f_parry", "f_crit", "f_kill",
    "f_boss_skill", "f_transform", "f_fury", "f_clear", "f_round_lose",
    "revolution", "eight_cut", "victory", "defeat", "daily_start", "f_skill",
    "v_dafuhao", "v_r4", "v_last_one",
}


def voice_of(key: str):
    if key in MALE_KEYS:
        return MALE, MALE_RATE, MALE_PITCH
    return FEMALE, FEMALE_RATE, FEMALE_PITCH


async def gen_one(key: str, text: str) -> bool:
    import edge_tts
    out = os.path.join(OUT_DIR, key + ".mp3")
    voice, rate, pitch = voice_of(key)
    for attempt in range(3):
        try:
            tts = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
            await tts.save(out)
            if os.path.getsize(out) > 500:
                return True
        except Exception as e:  # noqa: BLE001
            print("[voice] %s attempt %d failed: %s" % (key, attempt + 1, e))
            await asyncio.sleep(1.5 * (attempt + 1))
    return False


async def main(force: bool) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    todo = [(k, t) for k, t in MANIFEST.items()
            if force or not os.path.exists(os.path.join(OUT_DIR, k + ".mp3"))]
    print("[voice] total=%d todo=%d (male=%d)" % (
        len(MANIFEST), len(todo), sum(1 for k, _ in todo if k in MALE_KEYS)))
    ok = 0
    for k, t in todo:
        if await gen_one(k, t):
            ok += 1
        else:
            print("[voice] FAILED: %s (%s)" % (k, t))
    print("[voice] done %d/%d" % (ok, len(todo)))


if __name__ == "__main__":
    asyncio.run(main("--force" in sys.argv))
