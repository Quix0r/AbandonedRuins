local constants = require("lua/constants")
local utils = require("lua/utilities")
local spawning = require("lua/spawning")
local surfaces = require("lua/surfaces")
local queue = require("lua/queue")

-- Load events, initialize debug_log variable
require("lua/events")

-- Init ruin sets (empty for now)
---@type table<string, RuinSet>
local _ruin_sets = {}

---@param size string
---@param min_distance number
---@param center MapPosition
---@param surface LuaSurface
local function try_ruin_spawn(size, min_distance, center, surface)
  if debug_log then log(string.format("[try_ruin_spawn]: size='%s',min_distance=%d,center[]='%s',surface[]='%s' - CALLED!", size, min_distance, type(center), type(surface))) end
  if type(size) ~= "string" then
    error(string.format("size[]='%s' is not expected type 'string'", type(size)))
  elseif not utils.list_contains(spawning.ruin_sizes, size) then
    error(string.format("size='%s' is not a valid ruin size", size))
  elseif utils.ruin_min_distance_multiplier[size] == nil then
    error(string.format("size='%s' is not found in multiplier table", size))
  elseif type(min_distance) ~= "number" then
    error(string.format("min_distance[]='%s' is not expected type 'string'", type(min_distance)))
  elseif surface.name == constants.DEBUG_SURFACE_NAME then
    error(string.format("Debug surface '%s' has no random ruin spawning.", surface.name))
  elseif utils.str_contains_any_from_table(surface.name, surfaces.get_all_excluded()) then
    error(string.format("surface.name='%s' is excluded, cannot spawn ruins on", surface.name))
  elseif settings.global[constants.CURRENT_RUIN_SET_KEY].value == constants.NONE then
    error("No ruin-set selected by player but this function was invoked. This should not happen.")
  end

  if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d - BEFORE!", min_distance)) end
  min_distance = min_distance * utils.ruin_min_distance_multiplier[size]
  if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d - AFTER!", min_distance)) end

  if math.abs(center.x) < min_distance and math.abs(center.y) < min_distance then
    if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d is to close to spawn area - EXIT!", min_distance)) end
    return
  end

  -- random variance so they aren't always chunk aligned
  local variance = -(utils.ruin_half_sizes[size] * 0.75) + 12 -- 4 -> 9, 8 -> 6, 16 -> 0. Was previously 4 -> 10, 8 -> 5, 16 -> 0
  if debug_log then log(string.format("[try_ruin_spawn]: variance=%.2f,center.x=%d,center.y=%d - BEFORE!", variance, center.x, center.y)) end
  if variance > 0 then
    if debug_log then log(string.format("[try_ruin_spawn]: Applying random variance=%.2f ...", variance)) end
    center.x = center.x + math.random(-variance, variance)
    center.y = center.y + math.random(-variance, variance)
  end
  if debug_log then log(string.format("[try_ruin_spawn]: variance=%.2f,center.x=%d,center.y=%d - AFTER!", variance, center.x, center.y)) end

  queue.add_ruin({
    size    = size,
    center  = center,
    surface = surface
  })

  if debug_log then log("[try_ruin_spawn]: EXIT!") end
end

remote.add_interface("AbandonedRuins",
{
  -- The event contains:
  ---@class on_entity_force_changed_event_data:EventData
  ---@field entity LuaEntity The entity that had its force changed.
  ---@field force LuaForce The entity that had its force changed.
  -- The current force can be gotten from event.entity.
  -- This is raised after the force is changed.
  -- Mod event subscription explanation can be found lower in this file.
  get_on_entity_force_changed_event = function() return on_entity_force_changed_event end,

  -- Set whether ruins should be spawned at all
  ---@param spawn_ruins boolean
  set_spawn_ruins = function(spawn_ruins)
    if debug_log then log(string.format("[set_spawn_ruins]: spawn_ruins[]=%s - CALLED!", type(spawn_ruins))) end
    if type(spawn_ruins) ~= "boolean" then
      error(string.format("spawn_ruins[]='%s' is not expected type 'boolean'", type(spawn_ruins)))
    end

    if debug_log then log(string.format("[set_spawn_ruins]: Setting spawn_ruins=%s", spawn_ruins)) end
    storage.spawn_ruins = spawn_ruins

    if debug_log then log("[set_spawn_ruins]: EXIT!") end
  end,

  -- Get whether ruins should be spawned at all
  ---@return boolean
  get_spawn_ruins = function() return storage.spawn_ruins end,

  -- Add ruin size and its halfed size
  ---@param size string
  ---@param half_size number
  add_ruin_size = function(size, half_size)
    if debug_log then log(string.format("[add_ruin_size]: size[]='%s',half_size[]='%s' - CALLED!", type(size), type(half_size))) end
    if type(size) ~= "string" then
      error(string.format("size[]='%s' is not expected type 'string'", type(size)))
    elseif utils.list_contains(spawning.ruin_sizes, size) then
      error(string.format("size='%s' is already added as ruin size", size))
    elseif type(half_size) ~= "number" then
      error(string.format("half_size[]='%s' is not expected type 'number'", type(half_size)))
    end

    if debug_log then log(string.format("[add_ruin_size]: Adding ruin size='%s',half_size=%d ...", size, half_size)) end
    table.insert(spawning.ruin_sizes, size)
    table.insert(utils.ruin_half_sizes, half_size)

    if debug_log then log("[add_ruin_size]: EXIT!") end
  end,

  -- Get all ruin sizes
  ---@return table
  get_ruin_sizes = function() return spawning.ruin_sizes end,

  -- Get all ruin-sets
  ---@return table<string, RuinSet>
  get_ruin_sets = function() return _ruin_sets end,

  -- Any surface whose name contains this string will not have any ruins from any ruin-set mod spawned on it.
  -- Please note, that this feature is intended for "internal" or "hidden" surfaces, such as `NiceFill` uses
  -- and not for having an entire planet not having any ruins spawned.
  ---@param name string
  exclude_surface = function(name)
    if debug_log then log(string.format("[exclude_surface]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    elseif game.surfaces[name] ~= nil and game.surfaces[name].planet ~= nil then
      error(string.format("Surface name='%s' is a planet surface. This function is for internal or underground surfaces only. If you want your ruins not spawning on a certain planet, use `no_spawning` for individual ruins or invoke the remote-call function `no_spawning_on` to exclude your ruin-set from a planet entirely.", name))
    end

    if not surfaces.is_excluded(name) then
      if debug_log then log(string.format("[exclude_surface]: Excluding surface name='%s' ...", name)) end
      surfaces.exclude(name)
    end

    if debug_log then log("[exclude_surface]: EXIT!") end
  end,

  -- You excluded a surface at some earlier point but you don't want it excluded anymore.
  ---@param name string
  reinclude_surface = function(name)
    if debug_log then log(string.format("[reinclude_surface]: name[]='%s' - CALLED!", type(name))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    elseif game.surfaces[name].planet ~= nil then
      error(string.format("Surface name='%s' is a planet surface. This function is for internal or underground surfaces only. If you want your ruins not spawning on a certain planet, use `no_spawning` for individual ruins or invoke the remote-call function `no_spawning_on` to exclude your ruin-set from a planet entirely.", name))
    end

    if surfaces.is_excluded(name) then
      if debug_log then log(string.format("[reinclude_surface]: Reincluding surface name='%s' ...", name)) end
      surfaces.reinclude(name)
    end

    if debug_log then log("[reinclude_surface]: EXIT!") end
  end,

  -- !! ALWAYS call this in on_load and on_init. !!
  -- !! The ruins sets are not saved or loaded. !!
  -- The ruins should have the sizes given in utils.ruin_half_sizes, e.g. ruins in the small_ruins array should be 8x8 tiles.
  -- See also: docs/ruin_sets.md
  ---@param name string
  ---@param ruin_sets table<string, Ruins[]>
  add_ruin_sets = function(name, ruin_sets)
    if debug_log then log(string.format("[add_ruin_sets]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    elseif type(ruin_sets) ~= "table" then
      error(string.format("ruin_sets[]='%s' is not expected type 'table'", type(ruin_sets)))
    end

    if debug_log then log(string.format("[add_ruin_sets]: Setting name='%s' ruin sets ...", name)) end
    _ruin_sets[name] = ruin_sets

    if debug_log then log("[add_ruin_sets]: EXIT!") end
  end,

  -- !! The ruins sets are not saved or loaded. !!
  -- returns {small = {<array of ruins>}, medium = {<array of ruins>}, large = {<array of ruins>}}
  ---@param name string
  ---@return RuinSet
  get_ruin_set = function(name)
    if debug_log then log(string.format("[get_ruin_set]: name[]='%s' - CALLED!", type(name))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    end

    if debug_log then log(string.format("[get_ruin_set]: _ruin_sets[%s][]='%s' - EXIT!", name, type(_ruin_sets[name]))) end
    return _ruin_sets[name]
  end,

  -- Returns a table with: {<size> = {<array of ruins>}, <size-n> = {<array of ruins>}}}
  ---@return RuinSet
  get_current_ruin_set = function()
    if debug_log then log(string.format("[get_current_ruin_set]: current-ruin-set='%s'", settings.global[constants.CURRENT_RUIN_SET_KEY].value)) end
    return _ruin_sets[settings.global[constants.CURRENT_RUIN_SET_KEY].value]
  end,

  -- Registers ruin-set name as exclusive to a surface
  ---@param surface_name string Surface's name to the ruin-set should be exclusive to
  ---@param ruinset_name string Name of the ruin-set that is exclusive to given surface (aka. planet/moon)
  spawn_exclusively_on = function(surface_name, ruinset_name)
    if debug_log then log(string.format("[spawn_exclusively_on]: surface_name[]='%s',ruinset_name[]='%s' - CALLED!", type(surface_name), type(ruinset_name))) end
    if type(surface_name) ~= "string" then
      error(string.format("surface_name[]='%s' is not expected type 'string'", type(surface_name)))
    elseif type(ruinset_name) ~= "string" then
      error(string.format("ruinset_name[]='%s' is not expected type 'string'", type(ruinset_name)))
    elseif spawning.no_spawning[surface_name] ~= nil and ruinset_name == spawning.no_spawning[surface_name] then
      error(string.format("ruinset_name='%s' is marked for 'no-spawning' at surface_name='%s' which is the opposite of exclusive", ruinset_name, surface_name))
    end

    if debug_log then log(string.format("[spawn_exclusively_on]: Registering surface_name='%s',ruinset_name='%s' as exclusive ...", surface_name, ruinset_name)) end
    spawning.exclusive_ruinset[surface_name] = ruinset_name

    if debug_log then log("[spawn_exclusively_on]: EXIT!") end
  end,

  -- Registers ruin-set name as "no-spawning" to a surface. This means that ruins from given set will not spawn on given surface.
  ---@param surface_name string Surface's name to the ruin-set should be exclusive to
  ---@param ruinset_name string Name of the ruin-set that is exclusive to given surface (aka. planet/moon)
  no_spawning_on = function(surface_name, ruinset_name)
    if debug_log then log(string.format("[no_spawning_on]: surface_name[]='%s',ruinset_name[]='%s' - CALLED!", type(surface_name), type(ruinset_name))) end
    if type(surface_name) ~= "string" then
      error(string.format("surface_name[]='%s' is not expected type 'string'", type(surface_name)))
    elseif type(ruinset_name) ~= "string" then
      error(string.format("ruinset_name[]='%s' is not expected type 'string'", type(ruinset_name)))
    elseif spawning.exclusive_ruinset[surface_name] ~= nil and ruinset_name == spawning.exclusive_ruinset[surface_name] then
      error(string.format("ruinset_name='%s' is marked for exclusive spawning at surface_name='%s' which is the opposite of 'no-spawning'", ruinset_name, surface_name))
    end

    if debug_log then log(string.format("[no_spawning_on]: Registering surface_name='%s',ruinset_name='%s' as 'no-spawning' ...", surface_name, ruinset_name)) end
    spawning.no_spawning[surface_name] = ruinset_name

    if debug_log then log("[no_spawning_on]: EXIT!") end
  end,
})

--[[ How to: Subscribe to mod events
  Basics: Get the event id from a remote interface. Subscribe to the event in on_init and on_load.

  Example:

  local init = function ()
    if script.active_mods["AbandonedRuins_updated_fork"] then
      script.on_event(remote.call("AbandonedRuins", "get_on_entity_force_changed_event"),
      ---@param event on_entity_force_changed_event_data
      function(event)
        -- An entity changed force, let's handle that
        local entity = event.entity
        local old_force = event.force
        local new_force = entity.force
        -- handle the force change
        utils.output_message("old: " .. old_force.name .. " new: " .. new_force.name)
      end)
    end
  end

  script.on_load(init)
  script.on_init(init)

--]]
