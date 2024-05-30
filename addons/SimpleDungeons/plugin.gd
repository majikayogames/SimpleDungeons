@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type("DungeonGenerator3D", "Node3D", preload("DungeonGenerator3D.gd"), preload("res://addons/SimpleDungeons/res/dungeongenerator3dicon.svg"))
	add_custom_type("DungeonRoom3D", "Node3D", preload("DungeonRoom3D.gd"), preload("res://addons/SimpleDungeons/res/dungeonroom3dicon.svg"))

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_custom_type("DungeonGenerator3D")
	remove_custom_type("DungeonRoom3D")
