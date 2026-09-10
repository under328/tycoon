## 零依赖测试入口：
##   godot --headless --path . --script tests/run_tests.gd
## 扫描 tests/suites/ 下全部 *_test.gd，汇总报告，失败退出码 1。
extends SceneTree

const T := preload("res://tests/t.gd")
const SUITE_DIR := "res://tests/suites"


func _initialize() -> void:
	var t := T.new()
	var suite_paths := _collect_suites()
	for path in suite_paths:
		var before_checks: int = t.checks
		var before_fails: int = t.failures.size()
		var script = load(path)
		if script == null or not script.can_instantiate():
			t.failures.append("套件加载失败(解析错误?): " + path)
			print("%-46s LOAD FAILED" % path.get_file())
			continue
		var suite = script.new()
		suite.run(t)
		print("%-46s %3d checks, %d failed" % [
			path.get_file(), t.checks - before_checks, t.failures.size() - before_fails,
		])
	print("-----------------------------------------------")
	if t.failures.is_empty():
		print("ALL PASS  (%d checks, %d suites)" % [t.checks, suite_paths.size()])
		quit(0)
	else:
		for f in t.failures:
			printerr("FAIL: " + str(f))
		printerr("%d/%d checks FAILED" % [t.failures.size(), t.checks])
		quit(1)


func _collect_suites() -> Array:
	var paths := []
	var dir := DirAccess.open(SUITE_DIR)
	if dir == null:
		printerr("无法打开测试目录: " + SUITE_DIR)
		quit(1)
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_test.gd"):
			paths.append(SUITE_DIR + "/" + fname)
		fname = dir.get_next()
	paths.sort()
	return paths
