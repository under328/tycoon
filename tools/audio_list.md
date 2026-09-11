# 音频素材清单与替换指南

> 当前所有音频为**程序化合成占位**（`src/client/audio/synth.gd` 运行时生成）。
> 正式 AI 生成素材到位后，按下表逐项替换，代码钩子不变。

## BGM（OGG，循环，建议 90–104 BPM）

| 轨道 | 键名 | 挂载点 | 风格要求 |
|---|---|---|---|
| 大厅 | `lobby` | 主菜单/大厅 `_ready` | D 羽调式轻快 Lo-fi，无缝循环 |
| 对局 | `table` | 牌桌 `_ready` | A 羽调式舒缓，节奏略紧不抢注意力 |
| 革命变奏 | （预留） | 革命转场 | 对局主题的倒转强化版，8–16s |
| 终局结算 | （预留） | 终局演出 | 凯旋短句 8 小节 |

替换方式：`src/autoload/audio.gd` 的 `_bgm_tracks` 处改为
`load("res://assets/audio/bgm/<name>.ogg")`，导入设置开 loop。

## SFX（WAV，16-bit，≤0.4s 为主）

| 键名 | 触发点 | 内容 |
|---|---|---|
| click | 所有按钮 | 短促嗒 |
| deal | 发牌动画 | 纸牌滑动 |
| play_card | 任何人出牌 | 拍牌声 |
| pass | 玩家不要 | 低闷短音 |
| clear | 清桌 | 下滑扫除 |
| revolution | 革命触发 | 双音警报 |
| exchange | 局间换牌展示 | 双音上行 |
| win / lose | 终局演出 | 上行/下行 jingle |
| pop | 表情 | 气泡弹出 |
| tick | 倒计时最后 5s | 每秒滴答 |
| turn | 轮到你（联机） | 轻铃 |

替换方式：`src/autoload/audio.gd` 的 `_build_library()` 中把
`Synth.wav(...)` 换成 `load("res://assets/audio/sfx/<name>.wav")`，键名不变。

## 音量

- 总线：Master → BGM / SFX（`audio.gd._setup_buses`）。
- 用户音量存 `user://settings.cfg`，主菜单"设置"面板调节。
