# assets/ 素材目录

当前 M4 采用**程序化视听**方案（卡面运行时直绘、音频运行时合成），
本目录用于承载正式素材与生成产物：

```
assets/
├─ cards/preview/   # tools/card_gen.gd 导出的 54+1 张牌面 PNG（已入库，供下载页/对比）
├─ audio/
│  ├─ bgm/          # 正式 BGM 落位点（OGG 循环），替换指南见 tools/audio_list.md
│  └─ sfx/          # 正式音效落位点（WAV）
└─ fonts/           # 如需内置商用字体放这里（当前用 SystemFont 系统字体方案）
```

## 换皮三步

1. 卡面：改 `src/client/ui/card_view.gd`（程序化）或整副替换为图集纹理。
2. 音频：按 `tools/audio_list.md` 把合成器替换为文件加载，键名不变。
3. 颜色/样式：只改 `src/client/theme/app_theme.gd`，全场景自动生效。
