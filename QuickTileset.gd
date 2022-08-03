tool
extends TileMap

### ---------------------------------------------------------------------------
### # QuickTileset (for Godot)
###
### A quick and dirty script for creating complete Godot TileSets without hours
### of endless clicking.
###
### Version: 0.1.0
### Author: <paradrogue@gmail.com>
### URL: https://github.com/paradrogue/Godot-QuickTileset
###
### See LICENSE.md for licensing.
### ---------------------------------------------------------------------------

# A notional maximum number of tiles to create.
# More than this will generate a warning.
const MAX_TILES_LIMIT := 1024

# Common tile sizes for trying to guess cell size.
const COMMON_TILE_SIZES := [8, 12, 16, 18, 24, 32, 48, 64, 72, 96, 128, 192, 256]

export (Texture) var _texture:Texture setget _set_texture
export (Vector2) var _offset := Vector2.ZERO setget _set_offset
export (Vector2) var _padding := Vector2.ZERO setget _set_padding
export (bool) var _ignore_tile_limits := false setget _set_ignore_tile_limits
export (int) var _custom_tile_limit := MAX_TILES_LIMIT
export (bool) var _fix_tilemap_on_texture_change := false
export (bool) var _guess_tile_size := true

onready var _previous_cell_size := cell_size
var _clear_existing_tileset := false

# Executed when the script is added to the TileMap node.
func _init() -> void:
	# Only perform this method when running in the Godot editor.
	if not Engine.is_editor_hint():
		return

	# Connect signals
	_connect_setting_signal()

	if tile_set:
		push_warning(tr("QuickTileset: A TileSet already exists in this TileMap. This will be overridden if any changes are made."))

# Refreshes the TileSet.
func _refresh_tileset() -> void:
	# Only perform this method when running in the Godot editor.
	if not Engine.is_editor_hint():
		return

	# Make sure a tileset texture has been supplied.
	if not _texture:
		push_warning(tr("QuickTileset: No tiled texture is supplied"))
		return

	print(tr("QuickTileset: Refreshing TileSet"))

	# If no tileset exists, create one.
	if tile_set == null:
		tile_set = TileSet.new()
		property_list_changed_notify()

	# Try and work out how many cells there are vertically
	# and horizontally according to the cell size.
	var cells_h_guess := _texture.get_width() / (cell_size.x + _offset.x + _padding.x)
	var cells_v_guess := _texture.get_height() / (cell_size.y + _offset.y + _padding.y)

	# Round this down.
	var cells_h := int(cells_h_guess)
	var cells_v := int(cells_v_guess)

	# If they don't match exactly, warn the user.
	if cells_h != cells_h_guess or cells_v != cells_v_guess:
		push_warning(tr("QuickTileset: Tile texture is not an exact multiple of %s pixels (%s offset, %s padding)-it may not work as expected." % [cell_size, _offset, _padding]))

	var total_tiles := cells_h * cells_v
	if total_tiles > _custom_tile_limit:
		push_warning(tr("QuickTileset: A large number (%d) of tiles will be created.  This may cause performance issues." % total_tiles))
		if _ignore_tile_limits:
			push_warning(tr("QuickTileset: The tile limit (%d) is being ignored." % _custom_tile_limit))
		else:
			push_warning(tr("QuickTileset: The tile limit (%d) has prevented the TileSet from being generated. Aborting." % _custom_tile_limit))
			return

	# Clear the entire tileset if there is a need to.
	if _clear_existing_tileset:
		# Clear the tileset.
		tile_set.clear()
		# Remove any other tiles.  The above doesn't always work
		# as expected...
		for id in tile_set.get_tiles_ids():
			tile_set.remove_tile(id)

	# Create the tiles.
	for y in cells_v:
		for x in cells_h:
			# Work of the index of the tile.
			var index = (y * cells_h) + x
			# Create a new tile.
			tile_set.create_tile(index)
			# Set the texture.
			tile_set.tile_set_texture(index, _texture)
			# Calculate the Rect2 representing the region
			# of the texture.
			var rect := Rect2(_offset + Vector2(x * (cell_size.x + _padding.x), y * (cell_size.y + _padding.y)), cell_size)
			# Set the tile's region.
			tile_set.tile_set_region(index, rect)

	property_list_changed_notify()

# Setget handler for _texture
func _set_texture(value:Texture) -> void:
	_texture = value
	_clear_existing_tileset = true
	_refresh_tileset()

	# Fix invalid tiles, if allowed.
	if _fix_tilemap_on_texture_change:
		fix_invalid_tiles()

	# Guess tile size, if allowed.
	if _guess_tile_size:
		_guess_tile_size_from_texture()


# Setget handler for _offset
func _set_offset(value:Vector2) -> void:
	_offset = value
	_clear_existing_tileset = true
	_refresh_tileset()

# Setget handler for _padding
func _set_padding(value:Vector2) -> void:
	_padding = value
	_clear_existing_tileset = true
	_refresh_tileset()

# Setget handler for _ignore_tile_limits
func _set_ignore_tile_limits(value:bool) -> void:
	_ignore_tile_limits = value
	_clear_existing_tileset = true
	_refresh_tileset()

# Listener for when the TileMap's settings have changed.
# It compares the current cell size with the previous cell size.
# If it has changed, refresh the tileset.
func _on_settings_changed() -> void:
	if _previous_cell_size != cell_size:
		_previous_cell_size = cell_size
		_refresh_tileset()

# Connect the settings_changed signal. This updates
# the TileSet only if the cell size is changed.
func _connect_setting_signal() -> void:
	if not is_connected("settings_changed", self, "_on_settings_changed"):
		var _discard := connect("settings_changed", self, "_on_settings_changed")

# Attempt to discern the cell size from the source texture's file name.
func _guess_tile_size_from_texture() -> void:
	# Get the list of sizes
	var sizes := COMMON_TILE_SIZES
	# Invert it so we deal with the longest strings first
	# (less likely to be discovered accidentally).
	sizes.invert()

	# Get the texture's file name (well, path, but it will do).
	var texture_file_name := _texture.resource_path

	# Check each of the size combinations and see if we can find one.
	for w in sizes:
		for h in sizes:
			# If we find one, assign it to cell_size and update
			# the editor.
			if texture_file_name.count("%dx%d" % [w, h]):
				self.set_cell_size(Vector2(w,h))
				push_warning(tr("QuickTileset: Texture assumed to contain tiles of size %s.  Update cell_size manually if incorrect." % str(Vector2(w,h))))
				property_list_changed_notify()
				return

	push_warning(tr("QuickTileset: Could not determine cell size.  Update cell_size manually."))

func _get_configuration_warning() -> String:
	if !_texture:
		return tr("No tiled texture is supplied")
	return ""
