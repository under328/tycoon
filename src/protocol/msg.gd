## 消息名与协议版本常量（契约见 docs/协议.md）。M2 联机时启用。
class_name Msg
extends RefCounted

const PROTOCOL_VERSION := 3  # v3: 修复 c_room_settings RPC 缺失(模式/规则此前未下发) + hello 携带昵称(重装找回)
