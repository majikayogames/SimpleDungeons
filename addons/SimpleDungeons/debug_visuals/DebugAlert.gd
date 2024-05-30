@tool
extends Node3D

@export var text = "" :
	set(v):
		text = v
		if is_inside_tree(): update_visual()
		
func update_visual():
	self.visible = len(text) > 0
	self.global_transform.basis = self.global_transform.basis.orthonormalized() * self.global_transform.basis.y.length()
	$Label3D.text = text
	$Sprite3D.texture = preload("res://addons/SimpleDungeons/res/error-sign.svg") if text.begins_with("Error") else preload("res://addons/SimpleDungeons/res/warning-sign.svg")

func _ready():
	update_visual()
	set_process_input(false)
