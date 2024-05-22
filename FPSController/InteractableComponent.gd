class_name InteractableComponent
extends Node

var characters_hovering = {}

signal interacted()
signal interacted_by_character(character : CharacterBody3D)

func interact_with(character : CharacterBody3D):
	interacted.emit()
	interacted_by_character.emit(character)

func hover_cursor(character : CharacterBody3D):
	characters_hovering[character] = Engine.get_process_frames()

func get_character_hovered_by_cur_camera() -> CharacterBody3D:
	for character in characters_hovering.keys():
		var cur_cam = get_viewport().get_camera_3d() if get_viewport() else null
		if cur_cam != null and character.is_ancestor_of(cur_cam):
			return character
	return null

func _process(_delta):
	for character in characters_hovering.keys():
		if Engine.get_process_frames() - characters_hovering[character] > 1:
			characters_hovering.erase(character)
