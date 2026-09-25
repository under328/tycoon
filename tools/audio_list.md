# 音频素材清单(v3 — 音乐 3.0 / 音效 3.0)

> BGM: `tools/pixart/gen_music.py`(音色引擎) + `tools/pixart/gen_songs.py`(谱面)
> → `assets/music/*.ogg`(44.1k 立体声, 施罗德混响母带)。
> SFX: `src/client/audio/synth.gd` 运行时程序化合成(`audio.gd _build_library`)。
> 改曲后: `python tools/pixart/gen_music.py` 重生成 + 引擎 `--import` 重导入,
> 再跑 `tools/bgm_render_check.gd` 体检。

## BGM(OGG 循环; 循环点 0.3s 淡出, 编曲上以属和弦悬回主和弦衔接)

| 轨道 | 风格 | 结构 |
|---|---|---|
| lobby 首页 73.8s | C 大调 104BPM 温暖邀约 | intro(垫弦+EP) → A 主旋律 → A' 琶音重奏 → B 扬起 → outro 属和弦回环 |
| table 对局 64.0s | G 大调 120BPM 摇摆律动 | 鼓点 intro → A riff 钩子 → B 抒情 → A' riff+琶音对位 → 军鼓渐强桥 → 收束 |
| table_rev 革命 51.2s | A 小调 150BPM 急进 | 八分低音 + 小调五声 riff + 铜管反拍刺击 ×3 段 + 紧张收束 |
| rogue 肉鸽 60.0s | D 多利亚 96BPM 神秘推进 | 拨弦点描 + 手鼓 + 笛句 ×3 段递强 |
| boss BOSS 48.6s | E 弗里几亚 158BPM 狂暴 | 双底鼓 + 力度刺击 + 高音嘶吼 riff ×3 段 |
| fight 格斗 54.9s | A 小调 140BPM 热血摇滚 | 力度和弦 + 呼应短句 + 军鼓推进 ×3 段 |

## SFX 键名一览(`Audio.play(key)`)

| 键名 | 触发点 |
|---|---|
| click / select | 按钮 / 点选手牌(更轻触感) |
| deal / shuffle | 发牌 / 新一局洗牌 |
| play_card / pass / clear | 出牌(四条自动换 bomb) / 不要 / 清桌 |
| bomb | 四条(炸弹)落桌: 低频爆+碎裂 |
| revolution / eight_cut / exchange / fall | 革命 / 8切 / 换牌 / 一落千丈 |
| turn / tick | 轮到你 / 倒计时跳秒 |
| win / lose / result | 终局胜/负/结算号角 |
| coin / gem / sign / ach / buy | 任务奖励 / 钻石兑换 / 签到 / 成就解锁 / 商城购买 |
| error | 非法操作(低哑短音) |
| hit / crit / hurt / guard / dodge | 格斗: 命中/暴击/受击/格挡/闪避 |
| skill / heal / ult / transform | 格斗: 施法/治疗/奥义/变身 |
| ko / floor | 格斗: 回合终结(KO)/进入下一层 |
| pop | 表情气泡等通用轻响 |

> 语音播报(出牌/战斗解说)走 `assets/voice/*.mp3`, 见 voice_manifest.py。
