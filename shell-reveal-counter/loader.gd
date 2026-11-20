extends Node

# Shell Reveal & Counter: manages the single-player HUD lifecycle without mutating game nodes.
const TARGET_SCENE_PATH := "res://scenes/main.tscn"
const SPAWNER_SCRIPT_PATH := "res://scripts/ShellSpawner.gd"
const SUPPORTED_SPAWNER_SHA256 := "3831575fdfcbd30cea2158d2ca40ad88293f4771eec297f8356b2b491bf78f3c"
const GLOBAL_VARS_PATH := "/root/GlobalVariables"
const OVERLAY_FILENAME := "hud.gd"
const FALLBACK_OVERLAY_PATH := "res://shell-reveal-counter/hud.gd"
const OVERLAY_NODE_NAME := "ShellRevealCounterHUD"

var _compatible: bool = false
var _overlay_script: Script = null
var _active_scene: Node = null
var _active_spawner: Node = null
var _overlay: CanvasLayer = null

func _ready() -> void:
	set_process(false)
	if not _verify_spawner_hash():
		push_warning("Shell Reveal & Counter: unsupported or modified game script; HUD disabled. Use a clean supported game version.")
		return

	_overlay_script = _load_overlay_script()
	if _overlay_script == null:
		push_warning("Shell Reveal & Counter: could not load %s." % OVERLAY_FILENAME)
		return

	_compatible = true
	get_tree().node_added.connect(_on_node_added)
	set_process(true)

func _exit_tree() -> void:
	_detach_overlay()

func _process(_delta: float) -> void:
	if not _compatible:
		return

	if _active_scene != null and not is_instance_valid(_active_scene):
		_detach_overlay()
		_active_scene = null

	var current_scene: Node = get_tree().current_scene
	if current_scene != _active_scene:
		_detach_overlay()
		_active_scene = current_scene
		if is_instance_valid(current_scene) and _is_single_player_root(current_scene):
			_try_mount_overlay.call_deferred()
		return

	if _overlay != null and not is_instance_valid(_active_spawner):
		_detach_overlay()

func _on_node_added(node: Node) -> void:
	if not _compatible or _overlay != null or not is_instance_valid(_active_scene):
		return
	if not _is_single_player_root(_active_scene):
		return
	if _is_spawner_node(node):
		_try_mount_overlay.call_deferred()

func _try_mount_overlay() -> void:
	if not _compatible or _overlay != null or not is_instance_valid(_active_scene):
		return
	if not _is_single_player_root(_active_scene):
		return

	var globals: Node = get_node_or_null(GLOBAL_VARS_PATH)
	if globals == null:
		return

	var spawner: Node = _locate_spawner(_active_scene)
	if spawner == null or not _verify_runtime_contract(spawner, globals):
		return

	if _overlay_script == null or not _overlay_script.can_instantiate():
		return

	var instance = _overlay_script.new()
	if not (instance is CanvasLayer):
		return

	_overlay = instance
	_overlay.name = OVERLAY_NODE_NAME
	_active_spawner = spawner
	_overlay.bind_sources(spawner, globals)
	add_child(_overlay)

func _detach_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_active_spawner = null

func _verify_spawner_hash() -> bool:
	var original_source: String = FileAccess.get_file_as_string(SPAWNER_SCRIPT_PATH)
	return original_source.sha256_text() == SUPPORTED_SPAWNER_SHA256

func _load_overlay_script() -> Script:
	var own_script = get_script()
	if own_script is Script and not own_script.resource_path.is_empty():
		var sibling_path: String = own_script.resource_path.get_base_dir().path_join(OVERLAY_FILENAME)
		var loaded = load(sibling_path)
		if loaded is Script:
			return loaded
	var fallback = load(FALLBACK_OVERLAY_PATH)
	if fallback is Script:
		return fallback
	return null

func _is_single_player_root(scene: Node) -> bool:
	return (
		scene == get_tree().current_scene
		and scene.get_parent() == get_tree().root
		and scene.scene_file_path == TARGET_SCENE_PATH
	)

func _is_spawner_node(node: Node) -> bool:
	var script = node.get_script()
	return script is Script and script.resource_path == SPAWNER_SCRIPT_PATH

func _locate_spawner(root: Node) -> Node:
	if _is_spawner_node(root):
		return root
	for child in root.get_children():
		var match_node: Node = _locate_spawner(child)
		if match_node != null:
			return match_node
	return null

func _verify_runtime_contract(spawner: Node, globals: Node) -> bool:
	return (
		spawner.get("sequenceArray") is Array
		and globals.get("default_color_live") is Color
		and globals.get("default_color_blank") is Color
	)