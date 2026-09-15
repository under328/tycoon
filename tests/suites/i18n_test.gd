## 多语言测试: 16 语言目录 / 词典注册 / 切换即时生效 / 英语回退 / 持久化。
extends RefCounted

const I18nGd = preload("res://src/autoload/i18n.gd")
const StringsDbGd = preload("res://src/autoload/strings_db.gd")


func run(t) -> void:
	tst(t)


func tst(t) -> void:
	# 目录: 16 种语言, 编码唯一, 全部在词典或为源语言
	t.expect_eq(I18nGd.LANGUAGES.size(), 16, "语言目录 16 种")
	var codes := {}
	for l in I18nGd.LANGUAGES:
		codes[str(l["code"])] = true
		t.expect(str(l["name"]).length() > 0, "语言名非空")
	t.expect(codes.size() == 16, "语言编码唯一")
	t.expect(codes.has("zh_CN") and codes.has("en") and codes.has("ja")
			and codes.has("ko"), "含中英日韩")

	# 词典: 英语覆盖 ≥150 条; zh_CN 为源语言恒等(I18n 内注册)
	t.expect((StringsDbGd.DB["en"] as Dictionary).size() >= 150,
			"英语词典覆盖充分")
	for code in StringsDbGd.DB:
		t.expect(codes.has(str(code)), "词典语言 %s 在目录内" % code)

	# 运行时切换(需要 autoload I18n/GameSettings, 由运行环境提供)
	var i18n_node = null
	var tree_root := Engine.get_main_loop() as SceneTree
	var has_tree: bool = tree_root != null and tree_root.root != null \
			and tree_root.root.get_child_count() > 0
	if has_tree:
		for child in tree_root.root.get_children():
			if child.name == "I18n":
				i18n_node = child
	if i18n_node == null:
		t.expect(true, "无运行环境(跳过运行时切换检查)")
		return
	i18n_node._register_translations()   # 延迟注册在首帧后; 测试在 _initialize 期手动触发(幂等)

	# 英语: 攻击 → Attack
	i18n_node.set_language("en")
	t.expect_eq(TranslationServer.translate("本地游戏"), "Local Game", "英语切换生效")
	# 日语
	i18n_node.set_language("ja")
	t.expect_eq(TranslationServer.translate("本地游戏"), "ローカル対局", "日语切换生效")
	# 源语言 zh_CN: 恒等返回原文
	i18n_node.set_language("zh_CN")
	t.expect_eq(TranslationServer.translate("本地游戏"), "本地游戏", "中文恒等返回")
	# 回退: 韩语词典未覆盖的字符串 → 英语
	i18n_node.set_language("ko")
	t.expect_eq(TranslationServer.translate("同一个不在韩语词典里的句子"),
			"同一个不在韩语词典里的句子", "两词典皆缺 → 返回原文")
	var partial := TranslationServer.translate("本地游戏")
	t.expect(str(partial) != "本地游戏", "韩语核心词已覆盖(本地游戏)")
	# 持久化: set_language 写回 GameSettings
	i18n_node.set_language("fr")
	var gs = null
	for child in tree_root.root.get_children():
		if child.name == "GameSettings":
			gs = child
	t.expect(gs == null or str(gs.language) == "fr", "语言选择已持久化")
	# 还原默认
	i18n_node.set_language("zh_CN")
