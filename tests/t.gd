## 极简断言助手（零依赖测试框架的一部分）。
extends RefCounted

var checks := 0
var failures: Array = []


func expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


func expect_eq(a, b, msg: String) -> void:
	checks += 1
	if a != b:
		failures.append("%s  (got=%s want=%s)" % [msg, str(a), str(b)])
