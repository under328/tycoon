## 消息名与协议版本常量（契约见 docs/协议.md）。M2 联机时启用。
class_name Msg
extends RefCounted

const PROTOCOL_VERSION := 2  # v2: exchange_return 动作 + s_game_played.eight_cut

# C → S
const HELLO := "hello"
const ROOM_QUICK := "room_quick"
const ROOM_CREATE := "room_create"
const ROOM_JOIN := "room_join"
const ROOM_LEAVE := "room_leave"
const ROOM_KICK := "room_kick"
const ROOM_START := "room_start"
const BOT_FILL := "bot_fill"
const GAME_PLAY := "game_play"
const GAME_PASS := "game_pass"

# S → C
const WELCOME := "welcome"
const ROOM_STATE := "room_state"
const GAME_VIEW := "game_view"
const GAME_TURN := "game_turn"
const GAME_PLAYED := "game_played"
const GAME_CLEARED := "game_cleared"
const REVOLUTION := "revolution"
const ROUND_END := "round_end"
const EXCHANGE := "exchange"
const GAME_END := "game_end"
const KICKED := "kicked"
const ERROR := "error"
