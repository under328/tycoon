## 服务器战绩持久化（user://stats.json）。按客户端 ID 记录场数/胜场/累计积分。
class_name StatsLib
extends RefCounted

const SAVE_PATH := "user://stats.json"

var data: Dictionary = {}   # client_id -> {name, matches, wins, total_points}
var save_path := SAVE_PATH  # 测试可指向独立文件


func _init() -> void:
	load_from_disk()


func load_from_disk() -> void:
	data = {}
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data = parsed


func save_to_disk() -> void:
	# 原子写入(tmp→rename): 崩溃/断电不会损坏战绩存档(损坏会导致全员战绩清零)
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(save_path))


func get_entry(cid: String) -> Dictionary:
	if cid == "" or not data.has(cid):
		return {}
	return data[cid]


## entries: [{client_id, name, total, win}]
func record(entries: Array) -> void:
	var changed := false
	for e in entries:
		var cid := str(e.get("client_id", ""))
		if cid == "":
			continue
		var entry: Dictionary = data.get(cid, {
			"name": "", "matches": 0, "wins": 0, "total_points": 0,
		})
		entry["name"] = str(e.get("name", entry.get("name", "")))
		entry["matches"] = int(entry.get("matches", 0)) + 1
		entry["total_points"] = int(entry.get("total_points", 0)) + int(e.get("total", 0))
		if bool(e.get("win", false)):
			entry["wins"] = int(entry.get("wins", 0)) + 1
		data[cid] = entry
		changed = true
	if changed:
		save_to_disk()
