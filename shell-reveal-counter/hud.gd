extends CanvasLayer

# Compact two-row chamber overlay with auto-localization and F1-F4 toggles.
const CONFIG := {
	"language": "auto",		# "auto" follows the game locale, or force a key from LOCALES (e.g. "en", "vi", "ja")
	"start_visible": true,
	"start_counts": true,
	"start_shot": true,
	"start_tube": true,
	"show_labels": true,
	"allow_in_endless": true,
	"key_master": KEY_F1,
	"key_counts": KEY_F2,
	"key_shot": KEY_F3,
	"key_tube": KEY_F4,
	"anchor": Vector2(8, 6),
	"scale": 1.0,
	"max_opacity": 0.90,
	"fade_rate": 8.0,
}

const LOCALES := {
	"en": {"live": "LIVE", "blank": "BLANK", "shot": "SHOT", "tube": "TUBE"},
	"vi": {"live": "ĐẠN THẬT", "blank": "ĐẠN RỖNG", "shot": "PHÁT", "tube": "NÒNG"},
	"fr": {"live": "RÉELLE", "blank": "À BLANC", "shot": "TIR", "tube": "TUBE"},
	"de": {"live": "SCHARF", "blank": "BLIND", "shot": "SCHUSS", "tube": "LAUF"},
	"es": {"live": "REAL", "blank": "FOGUEO", "shot": "TIRO", "tube": "TUBO"},
	"it": {"live": "VERA", "blank": "A SALVE", "shot": "COLPO", "tube": "TUBO"},
	"pt": {"live": "REAL", "blank": "FESTIM", "shot": "TIRO", "tube": "TUBO"},
	"pl": {"live": "OSTRA", "blank": "ŚLEPA", "shot": "STRZAŁ", "tube": "MAG."},
	"ru": {"live": "БОЕВОЙ", "blank": "ХОЛОСТОЙ", "shot": "ВЫСТР.", "tube": "МАГАЗ."},
	"uk": {"live": "БОЙОВИЙ", "blank": "ХОЛОСТИЙ", "shot": "ПОСТР.", "tube": "МАГАЗ."},
	"tr": {"live": "DOLU", "blank": "BOŞ", "shot": "ATIŞ", "tube": "NAMLU"},
	"et": {"live": "LAHING", "blank": "PAUK", "shot": "LASK", "tube": "SALV"},
	"ja": {"live": "実弾", "blank": "空包", "shot": "射撃", "tube": "弾倉"},
	"ko": {"live": "실탄", "blank": "공포탄", "shot": "발사", "tube": "탄창"},
	"zh_cn": {"live": "实弹", "blank": "空弹", "shot": "射击", "tube": "弹仓"},
	"zh_tw": {"live": "實彈", "blank": "空包彈", "shot": "射擊", "tube": "彈倉"},
}

const THEME := {
	"shell_w": 6.0,
	"shell_hull_h": 9.0,
	"shell_brass_h": 3.0,
	"card_bg": Color(0.05, 0.05, 0.07, 0.80),
	"card_border": Color(1.0, 1.0, 1.0, 0.16),
	"divider": Color(1.0, 1.0, 1.0, 0.14),
	"muted": Color(0.68, 0.68, 0.72, 1.0),
	"bright": Color(0.96, 0.96, 0.98, 1.0),
	"brass": Color(0.86, 0.71, 0.32, 1.0),
	"chamber_bg": Color(0.02, 0.02, 0.04, 0.95),
	"chamber_border": Color(0.95, 0.95, 0.98, 0.92),
	"queue_bg": Color(1.0, 1.0, 1.0, 0.02),
	"queue_border": Color(1.0, 1.0, 1.0, 0.10),
	"queue_alpha": 0.72,
}

var _spawner: Node = null
var _globals: Node = null

var _font: Font = null
var _fallback_sys_font: SystemFont = null
var _font_main_size: int = 10
var _font_tag_size: int = 9
var _active_locale: String = ""

var _card: PanelContainer = null
var _counts_row: HBoxContainer = null
var _row_divider: ColorRect = null
var _detail_row: HBoxContainer = null
var _shot_group: HBoxContainer = null
var _detail_divider: ColorRect = null
var _tube_group: HBoxContainer = null
var _tube_strip: HBoxContainer = null

var _live_hull: ColorRect = null
var _live_tag: Label = null
var _live_count_lbl: Label = null
var _blank_hull: ColorRect = null
var _blank_tag: Label = null
var _blank_count_lbl: Label = null
var _shot_tag: Label = null
var _shot_lbl: Label = null
var _tube_tag: Label = null

var _slot_pool: Array[Dictionary] = []

var _enabled: bool = CONFIG["start_visible"]
var _show_counts: bool = CONFIG["start_counts"]
var _show_shot: bool = CONFIG["start_shot"]
var _show_tube: bool = CONFIG["start_tube"]

var _alpha: float = 0.0
var _last_seq_size: int = 0
var _round_capacity: int = 0
var _last_rendered_count: int = -1
var _ready_done: bool = false

func bind_sources(spawner_node: Node, globals_node: Node) -> void:
	_spawner = spawner_node
	_globals = globals_node

func _ready() -> void:
	layer = 2
	visible = false
	if not is_instance_valid(_spawner) or not is_instance_valid(_globals):
		queue_free()
		return
	_resolve_base_typography()
	_construct_layout()
	_apply_locale(_resolve_locale_key())
	_apply_visibility_state()
	_ready_done = true

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	var code: int = key_event.keycode
	if code == CONFIG["key_master"]:
		var any_section_on: bool = _show_counts or _show_shot or _show_tube
		if not _enabled or not any_section_on:
			_enabled = true
			if not any_section_on:
				_show_counts = true
				_show_shot = true
				_show_tube = true
				_apply_visibility_state()
		else:
			_enabled = false
		return

	if not _enabled:
		return

	if code == CONFIG["key_counts"]:
		_show_counts = not _show_counts
		_apply_visibility_state()
	elif code == CONFIG["key_shot"]:
		_show_shot = not _show_shot
		_apply_visibility_state()
	elif code == CONFIG["key_tube"]:
		_show_tube = not _show_tube
		_apply_visibility_state()

func _process(delta: float) -> void:
	if not _ready_done or not is_instance_valid(_spawner) or not is_instance_valid(_globals):
		visible = false
		return

	var wanted_locale: String = _resolve_locale_key()
	if wanted_locale != _active_locale:
		_apply_locale(wanted_locale)

	var raw_seq = _spawner.get("sequenceArray")
	if not (raw_seq is Array):
		visible = false
		return

	var sequence: Array = raw_seq
	_sync_round_capacity(sequence)
	_step_fade(delta, sequence.size())
	if not visible:
		return

	_render_state(sequence)

func _resolve_locale_key() -> String:
	var forced: String = str(CONFIG["language"]).strip_edges().to_lower().replace("-", "_")
	if not forced.is_empty() and forced != "auto":
		return _match_locale(forced)
	var game_locale: String = TranslationServer.get_locale().strip_edges().to_lower().replace("-", "_")
	return _match_locale(game_locale)

func _match_locale(raw: String) -> String:
	if LOCALES.has(raw):
		return raw
	if raw.begins_with("zh"):
		if raw.contains("tw") or raw.contains("hk") or raw.contains("mo") or raw.contains("hant"):
			return "zh_tw"
		return "zh_cn"
	var sep: int = raw.find("_")
	if sep > 0:
		var prefix: String = raw.substr(0, sep)
		if LOCALES.has(prefix):
			return prefix
	return "en"

func _apply_locale(locale_key: String) -> void:
	_active_locale = locale_key
	var strings: Dictionary = LOCALES.get(locale_key, LOCALES["en"])
	var show_labels: bool = CONFIG["show_labels"]

	_live_tag.text = strings["live"]
	_blank_tag.text = strings["blank"]
	_tube_tag.text = strings["tube"]
	if show_labels:
		_shot_tag.text = strings["shot"]
	else:
		_shot_tag.text = "#"

	var chosen_font: Font = _select_font_for_strings(strings)
	if chosen_font != _font:
		_font = chosen_font
		_refresh_label_fonts()

	if _card != null:
		_card.reset_size()
		_card.call_deferred("reset_size")

func _resolve_base_typography() -> void:
	var base_size: int = 16
	var game_font: Font = _get_game_font()
	var dlg = _spawner.get("dialogue")
	if dlg != null:
		var ui = dlg.get("dialogueUI")
		if ui is Control:
			base_size = ui.get_theme_font_size("font_size")

	if game_font != null:
		_font = game_font
	else:
		_font = ThemeDB.fallback_font
	if base_size <= 0:
		base_size = 16

	_font_main_size = maxi(9, int(round(base_size * 0.65)))
	_font_tag_size = maxi(8, int(round(_font_main_size * 0.85)))

func _get_game_font() -> Font:
	var dlg = _spawner.get("dialogue")
	if dlg != null:
		var ui = dlg.get("dialogueUI")
		if ui is Control:
			return ui.get_theme_font("font")
	return null

func _select_font_for_strings(strings: Dictionary) -> Font:
	var game_font: Font = _get_game_font()
	if game_font != null and _font_covers_strings(game_font, strings):
		return game_font
	if _fallback_sys_font == null:
		_fallback_sys_font = SystemFont.new()
		_fallback_sys_font.font_names = PackedStringArray([
			"Segoe UI",
			"Noto Sans",
			"DejaVu Sans",
			"Arial",
		])
	return _fallback_sys_font

func _font_covers_strings(font: Font, strings: Dictionary) -> bool:
	for key in strings:
		var text_val: String = str(strings[key])
		for i in range(text_val.length()):
			var cp: int = text_val.unicode_at(i)
			if cp > 32 and not font.has_char(cp):
				return false
	return true

func _refresh_label_fonts() -> void:
	var all_labels: Array[Label] = [
		_live_tag,
		_live_count_lbl,
		_blank_tag,
		_blank_count_lbl,
		_shot_tag,
		_shot_lbl,
		_tube_tag,
	]
	for lbl in all_labels:
		if lbl != null:
			lbl.add_theme_font_override("font", _font)

func _construct_layout() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = THEME["card_bg"]
	card_style.border_color = THEME["card_border"]
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(3)
	card_style.content_margin_left = 7
	card_style.content_margin_right = 7
	card_style.content_margin_top = 4
	card_style.content_margin_bottom = 4
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	card_style.shadow_size = 2
	card_style.shadow_offset = Vector2(0, 1)

	var ui_scale: float = CONFIG["scale"]
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", card_style)
	_card.position = CONFIG["anchor"]
	_card.scale = Vector2(ui_scale, ui_scale)
	add_child(_card)

	var stack := _make_vbox(4)
	_card.add_child(stack)

	# Row 1: Remaining Live & Blank shell counts (F2)
	_counts_row = _make_hbox(9)
	stack.add_child(_counts_row)

	var show_labels: bool = CONFIG["show_labels"]
	var live_box := _make_hbox(5)
	_counts_row.add_child(live_box)
	var live_icon := _build_shell_glyph()
	_live_hull = live_icon["hull"]
	live_box.add_child(live_icon["node"])
	_live_tag = _build_label("", _font_tag_size, THEME["bright"])
	_live_tag.visible = show_labels
	live_box.add_child(_live_tag)
	_live_count_lbl = _build_label("0", _font_main_size, THEME["bright"])
	live_box.add_child(_live_count_lbl)

	var blank_box := _make_hbox(5)
	_counts_row.add_child(blank_box)
	var blank_icon := _build_shell_glyph()
	_blank_hull = blank_icon["hull"]
	blank_box.add_child(blank_icon["node"])
	_blank_tag = _build_label("", _font_tag_size, THEME["bright"])
	_blank_tag.visible = show_labels
	blank_box.add_child(_blank_tag)
	_blank_count_lbl = _build_label("0", _font_main_size, THEME["bright"])
	blank_box.add_child(_blank_count_lbl)

	# Row separator
	_row_divider = _build_divider(false)
	stack.add_child(_row_divider)

	# Row 2: Shot progress (F3) + Magazine tube order (F4)
	_detail_row = _make_hbox(7)
	stack.add_child(_detail_row)

	var shot_sep: int = 2
	if show_labels:
		shot_sep = 4

	_shot_group = _make_hbox(shot_sep)
	_detail_row.add_child(_shot_group)
	_shot_tag = _build_label("#", _font_tag_size, THEME["muted"])
	_shot_group.add_child(_shot_tag)
	_shot_lbl = _build_label("1/1", _font_main_size, THEME["bright"])
	_shot_group.add_child(_shot_lbl)

	_detail_divider = _build_divider(true)
	_detail_row.add_child(_detail_divider)

	_tube_group = _make_hbox(5)
	_detail_row.add_child(_tube_group)
	_tube_tag = _build_label("", _font_tag_size, THEME["muted"])
	_tube_tag.visible = show_labels
	_tube_group.add_child(_tube_tag)

	_tube_strip = _make_hbox(3)
	_tube_group.add_child(_tube_strip)

func _apply_visibility_state() -> void:
	if _card == null:
		return
	var detail_active: bool = _show_shot or _show_tube
	_counts_row.visible = _show_counts
	_shot_group.visible = _show_shot
	_tube_group.visible = _show_tube
	_detail_divider.visible = _show_shot and _show_tube
	_detail_row.visible = detail_active
	_row_divider.visible = _show_counts and detail_active

	_card.reset_size()
	_card.call_deferred("reset_size")

func _sync_round_capacity(sequence: Array) -> void:
	var count: int = sequence.size()
	if count == 0:
		_round_capacity = 0
	elif count > _last_seq_size or count > _round_capacity:
		_round_capacity = count
	_last_seq_size = count

func _step_fade(delta: float, remaining: int) -> void:
	var has_content: bool = _show_counts or _show_shot or _show_tube
	var active: bool = _enabled and has_content and remaining > 0

	if active and not CONFIG["allow_in_endless"]:
		var rm = _spawner.get("roundManager")
		if rm != null and rm.get("endless") == true:
			active = false

	var target_alpha: float = 0.0
	if active:
		target_alpha = CONFIG["max_opacity"]

	var fade_rate: float = CONFIG["fade_rate"]
	_alpha = move_toward(_alpha, target_alpha, delta * fade_rate)
	visible = _alpha > 0.001
	if visible:
		_card.modulate.a = _alpha

func _render_state(sequence: Array) -> void:
	var live_col: Color = _globals.get("default_color_live")
	var blank_col: Color = _globals.get("default_color_blank")
	if _globals.get("colorblind") == true:
		live_col = _globals.get("colorblind_color_live")
		blank_col = _globals.get("colorblind_color_blank")

	var live_n: int = 0
	var blank_n: int = 0
	for item in sequence:
		if str(item) == "live":
			live_n += 1
		else:
			blank_n += 1

	_live_hull.color = live_col
	_live_tag.modulate = live_col
	_live_count_lbl.text = str(live_n)

	_blank_hull.color = blank_col
	_blank_tag.modulate = blank_col
	_blank_count_lbl.text = str(blank_n)

	var total: int = maxi(1, _round_capacity)
	var shot_idx: int = clampi(_round_capacity - sequence.size() + 1, 1, total)
	_shot_lbl.text = "%d/%d" % [shot_idx, total]

	var count: int = sequence.size()
	if count > 0:
		_render_tube(sequence, live_col, blank_col)
		if _last_rendered_count != count:
			_last_rendered_count = count
			_card.call_deferred("reset_size")

func _render_tube(sequence: Array, live_col: Color, blank_col: Color) -> void:
	var count: int = sequence.size()
	while _slot_pool.size() < count:
		_slot_pool.append(_create_tube_slot(_slot_pool.size() == 0))

	for i in range(_slot_pool.size()):
		var slot_data: Dictionary = _slot_pool[i]
		var panel: PanelContainer = slot_data["panel"]
		if i < count:
			var hull: ColorRect = slot_data["hull"]
			if str(sequence[i]) == "live":
				hull.color = live_col
			else:
				hull.color = blank_col
			panel.visible = true
		else:
			panel.visible = false

func _create_tube_slot(is_chambered: bool) -> Dictionary:
	var box_style := StyleBoxFlat.new()
	box_style.set_border_width_all(1)
	box_style.set_corner_radius_all(2)
	box_style.content_margin_top = 2
	box_style.content_margin_bottom = 2

	if is_chambered:
		box_style.bg_color = THEME["chamber_bg"]
		box_style.border_color = THEME["chamber_border"]
		box_style.content_margin_left = 3
		box_style.content_margin_right = 3
	else:
		box_style.bg_color = THEME["queue_bg"]
		box_style.border_color = THEME["queue_border"]
		box_style.content_margin_left = 2
		box_style.content_margin_right = 2

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", box_style)
	if not is_chambered:
		panel.modulate.a = THEME["queue_alpha"]

	var glyph := _build_shell_glyph()
	panel.add_child(glyph["node"])
	_tube_strip.add_child(panel)

	return {"panel": panel, "hull": glyph["hull"]}

func _build_shell_glyph() -> Dictionary:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var col := _make_vbox(0)
	holder.add_child(col)

	var w: float = THEME["shell_w"]
	var hull := ColorRect.new()
	hull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hull.custom_minimum_size = Vector2(w, THEME["shell_hull_h"])
	hull.color = Color.WHITE
	col.add_child(hull)

	var brass := ColorRect.new()
	brass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brass.custom_minimum_size = Vector2(w, THEME["shell_brass_h"])
	brass.color = THEME["brass"]
	col.add_child(brass)

	return {"node": holder, "hull": hull}

func _build_label(text_val: String, px_size: int, tint: Color) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", px_size)
	lbl.text = text_val
	lbl.modulate = tint
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl

func _build_divider(vertical: bool) -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = THEME["divider"]
	if vertical:
		line.custom_minimum_size = Vector2(1, 14)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line

func _make_hbox(sep: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", sep)
	return box

func _make_vbox(sep: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", sep)
	return box