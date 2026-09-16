# -*- coding: utf-8 -*-
"""语音播报批量合成: tools/voice_manifest.py → assets/voice/<key>.mp3。
欢乐斗地主式中文语音: edge-tts 活泼女声(小晓), 略快略高音。
用法:
  python tools/voice_gen.py            # 增量: 只生成缺失的
  python tools/voice_gen.py --force    # 全量重生成
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice_manifest import MANIFEST  # noqa: E402

VOICE = "zh-CN-XiaoxiaoNeural"
RATE = "+12%"
PITCH = "+20Hz"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "assets", "voice")


async def gen_one(key: str, text: str) -> bool:
    import edge_tts
    out = os.path.join(OUT_DIR, key + ".mp3")
    for attempt in range(3):
        try:
            tts = edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH)
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
    print("[voice] total=%d todo=%d" % (len(MANIFEST), len(todo)))
    ok = 0
    for k, t in todo:
        if await gen_one(k, t):
            ok += 1
        else:
            print("[voice] FAILED: %s (%s)" % (k, t))
    print("[voice] done %d/%d" % (ok, len(todo)))


if __name__ == "__main__":
    asyncio.run(main("--force" in sys.argv))
