# SimpleDungeons for Godot 4

SimpleDungeons is a Godot 4 addon which allows for the creation of procedurally generated 3D dungeons/levels using user defined prefab rooms.

I did a YouTube video explaining how the algorithm works here:
https://www.youtube.com/watch?v=TPvxWIKHE6Q

You can download this repo and open its folder in Godot to run the sample project.

## Installation

1. Clone this repo or download as a zip by clicking the `Code` button above.
2. Copy the contents of the `addons` folder to your project's `addons` directory.

## Usage

- Add a DungeonGenerator instance to your scene (`addons/SimpleDungeons/DungeonGenerator.tscn`) and set the size and shape of the dungeon you want to create.
- Set the dungeon kit variable (which houses all the prefab rooms) on the DungeonGenerator. Use one of the sample DungeonKits or create your own.
- Refer to the sample DungeonKit examples to see how you should structure the DungeonKit.
    - Each room needs doors defined by creating Node3Ds with the prefix "DOOR" for required doors or "DOOR?" for optional doors.
    - Define the AABB of each room with an invisible CSGBox3D named "AABB" as a direct child of the DungeonRoom. Must be standardized to the "room_size" export variable set on the DungeonKit scene.
    - Each room must inherit from the DungeonRoom class. When creating custom room scripts, make sure to add the @tool directive if you want to see in editor debug info for the room's doors.
    - You can connect to the `placed_room` signal which is emitted on the DungeonRoom once the generation is finished.
    - Other useful functions are `DungeonRoom.get_doors() -> Array[Door]` on DungeonRoom and `Door.get_room_leads_to() -> DungeonRoom instance or null if none`. Also `DungeonRoom.get_door_by_node(door_node : Node3D) -> Door`. Useful for removing unused optional doors after generation is finished.

## License

This addon is available under the CC0 license.
