local constants = require("lua/constants")
local utils = require("lua/utilities")
local spawning = require("lua/spawning")
local surfaces = require("lua/surfaces")
local queue = require("lua/queue")

debug_log = settings.global[constants.ENABLE_DEBUG_LOG_KEY].value
debug_on_tick = settings.global["ruins-enable-debug-on-tick"].value
local spawn_tick = settings.global[constants.SPAWN_TICK_DISTANCE_KEY].value

-- Init ruin sets (empty for now)
---@type table<string, RuinSet>
local _ruin_sets = {}

local on_entity_force_changed_event = script.generate_event_name()

local function update_debug_log()
  debug_log = settings.global[constants.ENABLE_DEBUG_LOG_KEY].value
  debug_on_tick = settings.global["ruins-enable-debug-on-tick"].value
  utils.output_message(string.format("Ruins: debug log is now: debug=%s,on_tick=%s", debug_log, debug_on_tick))
end

local function init()
  if debug_log then log("[init]: CALLED!") end
  if game then
    utils.set_enemy_force_cease_fire(utils.get_enemy_force(), not settings.global["ruins-enemy-not-cease-fire"].value)
  else
    log("[init]: Cannot intitialize enemy force' cease fire, this is normal during on_load event.")
  end

  -- Initialize spawn changes array (isn't stored in save-game)
  spawning.init()

  -- Update debug flags
  update_debug_log()

  ---@type boolean
  storage.spawn_ruins = storage.spawn_ruins or true

  if debug_log then log("[init]: EXIT!") end
end

script.on_init(init)
script.on_load(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_player_created, update_debug_log)
script.on_event(defines.events.on_runtime_mod_setting_changed, init)

script.on_event(defines.events.on_force_created, function()
  -- Sets up the diplomacy for all forces, not just the newly created one.
  utils.set_enemy_force_diplomacy(utils.get_enemy_force(), not settings.global["ruins-enemy-not-cease-fire"].value)
end)

script.on_nth_tick(spawn_tick, function(event)
  if debug_on_tick then log(string.format("[on_tick]: event.tick=%d - CALLED!", event.tick)) end

  ---@type RuinQueueItem[] All currently queued ruin-queue items
  local ruins = queue.get_ruins()

  ---@type string
  local ruinset_name = settings.global[constants.CURRENT_RUIN_SET_KEY].value

  if debug_on_tick then log(string.format("[on_tick]: runins[]='%s',ruinset_name='%s'", type(ruins), ruinset_name)) end
  if table_size(ruins) == 0 then
    if debug_on_tick then log(string.format("[on_tick]: event.tick=%d has no ruins to spawn - EXIT!", event.tick)) end
    return
  elseif not _ruin_sets[ruinset_name] then
    error(string.format("ruinset_name='%s' is not registered with this mod. Have you forgotten to invoke `utils.register_ruin_set()`?", ruinset_name))
  end

  if debug_on_tick then log(string.format("[on_tick]: Spawning %d random ruin sets ...", table_size(ruins))) end

  ---@type RuinQueueItem Individual ruin-queue item
  for _, queue_item in pairs(ruins) do
    if debug_on_tick then log(string.format("[on_tick]: Spawning queue_item.size='%s',queue_item.center='%s',queue_item.surface='%s' ...", queue_item.size, tostring(queue_item.center), tostring(queue_item.surface))) end
    if not utils.ruin_half_sizes[queue_item.size] then
      error(string.format("queue_item.size='%s' is not registered in ruin_half_sizes table. Have you forgotten to invoke `utils.register_ruin_set()`?", queue_item.size))
    end
    if spawning.no_spawning[queue_item.surface.name] ~= nil and ruinset_name == spawning.no_spawning[queue_item.surface.name] then
      if debug_on_tick then log(string.format("[on_tick]: ruinset_name='%s' is not allowed to spawn on surface='%s' - SKIPPED!", ruinset_name, queue_item.surface.name)) end
    elseif spawning.exclusive_ruinset[queue_item.surface.name] == nil or ruinset_name == spawning.exclusive_ruinset[queue_item.surface.name] then
      -- The ruin-set is either marked as non-exclusive or it surface and ruin-set name are matching
      if debug_on_tick then log(string.format("[on_tick]: Invoking spawning.spawn_random_ruin() with ruinset_name='%s',queue_item.size='%s' ...", ruinset_name, queue_item.size)) end
      spawning.spawn_random_ruin(_ruin_sets[ruinset_name][queue_item.size], utils.ruin_half_sizes[queue_item.size], queue_item.center, queue_item.surface)
    end
  end

  if debug_on_tick then log("[on_tick]: Resetting queue ...") end
  queue.reset_ruins()

  if debug_on_tick then log("[on_tick]: EXIT!") end
end)

---@param size string
---@param min_distance number
---@param center MapPosition
---@param surface LuaSurface
---@param tick uint
local function try_ruin_spawn(size, min_distance, center, surface, tick)
  if debug_log then log(string.format("[try_ruin_spawn]: size='%s',min_distance=%d,center[]='%s',surface[]='%s',tick=%d - CALLED!", size, min_distance, type(center), type(surface), tick)) end
  if type(size) ~= "string" then
    error(string.format("size[]='%s' is not expected type 'string'", type(size)))
  elseif type(min_distance) ~= "number" then
    error(string.format("min_distance[]='%s' is not expected type 'string'", type(min_distance)))
  elseif utils.ruin_min_distance_multiplier[size] == nil then
    error(string.format("size='%s' is not found in multiplier table", size))
  elseif surface.name == constants.DEBUG_SURFACE_NAME then
    error(string.format("Debug surface '%s' has no random ruin spawning.", surface.name))
  elseif utils.str_contains_any_from_table(surface.name, surfaces.get_all()) then
    error(string.format("surface.name='%s' is excluded - EXIT!", surface.name))
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

  queue.add_ruin(tick, {
    size    = size,
    center  = center,
    surface = surface
  })

  if debug_log then log("[try_ruin_spawn]: EXIT!") end
end

script.on_event(defines.events.on_chunk_generated, function (event)
  if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' - CALLED!", event.surface.name)) end
  if storage.spawn_ruins == false then
    if debug_log then log("[on_chunk_generated]: Spawning ruins is disabled by configuration - EXIT!") end
    return
  elseif event.surface.name == constants.DEBUG_SURFACE_NAME then
    if debug_log then log(string.format("[on_chunk_generated]: Debug surface '%s' must spawn ruins on their own, not through randomness.", event.surface.name)) end
    return
  elseif settings.global[constants.CURRENT_RUIN_SET_KEY].value == constants.NONE then
    if debug_log then log("[on_chunk_generated]: No ruin-set selected by player - EXIT!") end
    return
  elseif utils.str_contains_any_from_table(event.surface.name, surfaces.get_all()) then
    if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' is excluded - EXIT!", event.surface.name)) end
    return
  end

  local center       = utils.get_center_of_chunk(event.position)
  local min_distance = settings.global["ruins-min-distance-from-spawn"].value
  local spawn_chance = math.random()
  if debug_log then log(string.format("[on_chunk_generated]: center.x=%d,center.y=%d,min_distance=%d,spawn_chance=%.2f", center.x, center.y, min_distance, spawn_chance)) end

  for _, size in pairs(spawning.ruin_sizes) do
    if debug_log then log(string.format("[on_chunk_generated]: spawn_chance=%.2f,size[%s]='%s'", spawn_chance, type(size), size)) end
    if spawn_chance <= spawning.get_spawn_chance(size) then
      if debug_log then log(string.format("[on_chunk_generated]: Trying to spawn ruin of size='%s' at event.surface='%s' ...", size, event.surface)) end
      try_ruin_spawn(size, min_distance, center, event.surface, event.tick)

      if debug_log then log("[on_chunk_generated]: Ruin was attempted to spawn - BREAK!") end
      break
    end
  end

  if debug_log then log("[on_chunk_generated]: EXIT!") end
end)

script.on_event({defines.events.on_player_selected_area, defines.events.on_player_alt_selected_area}, function(event)
  if debug_log then log(string.format("[on_player_selected_area]: event.item='%s',event.entities()=%d - CALLED!", event.item, table_size(event.entities))) end
  if event.item ~= "AbandonedRuins-claim" then
    if debug_log then log(string.format("[on_player_selected_area]: event.item='%s' is not ruin claim - EXIT!", event.item)) end
    return
  elseif table_size(event.entities) == 0 then
    if debug_log then log("[on_player_selected_area]: No entities selected - EXIT!") end
    return
  end

  ---@type LuaForce
  local neutral_force = game.forces.neutral
  ---@type LuaForce
  local claimants_force = game.get_player(event.player_index).force
  if debug_log then log(string.format("[on_player_selected_area]: neutral_force='%s',claimants_force='%s'", tostring(neutral_force), tostring(claimants_force))) end

  for _, entity in pairs(event.entities) do
    if debug_log then log(string.format("[on_player_selected_area]:entity.valid='%s',entity.force='%s'", entity.valid, tostring(entity.force))) end
    if entity.valid and entity.force == neutral_force then
      if debug_log then log(string.format("[on_player_selected_area]:Setting entity.force='%s' ...", tostring(claimants_force))) end
      entity.force = claimants_force

      if debug_log then log(string.format("[on_player_selected_area]:entity.valid='%s'", tostring(entity.valid))) end
      if entity.valid then
        script.raise_event(on_entity_force_changed_event, {entity = entity, force = neutral_force})
      end
    end
  end

  if event.name == defines.events.on_player_alt_selected_area then
    local remnants = event.surface.find_entities_filtered{area = event.area, type = {"corpse", "rail-remnants"}}
    for _, remnant in pairs(remnants) do
      remnant.destroy({raise_destroy = true})
    end
  end

  if debug_log then log("[on_player_selected_area]: EXIT!") end
end)

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
    elseif type(half_size) ~= "number" then
      error(string.format("half_size[]='%s' is not expected type 'number'", type(half_size)))
    elseif spawning.ruin_sizes[size] ~= nil then
      error(string.format("size='%s' is already added as ruin size", size))
    end

    if debug_log then log(string.format("[add_ruin_size]: Adding ruin size='%s',half_size=%d ...", size, half_size)) end
    table.insert(spawning.ruin_sizes, size)
    table.insert(utils.ruin_half_sizes, half_size)

    if debug_log then log("[add_ruin_size]: EXIT!") end
  end,

  -- Get all ruin sizes
  ---@return table
  get_ruin_sizes = function() return spawning.ruin_sizes end,

  -- Any surface whose name contains this string will not have any ruins from any ruin-set mod spawned on it.
  -- Please note, that this feature is intended for "internal" or "hidden" surfaces, such as `NiceFill` uses
  -- and not for having an entire planet not having any ruins spawned.
  ---@param name string
  exclude_surface = function(name)
    if debug_log then log(string.format("[exclude_surface]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    end

    if debug_log then log(string.format("[exclude_surface]: Excluding surface name='%s' ...", name)) end
    surfaces.exclude(name)

    if debug_log then log("[exclude_surface]: EXIT!") end
  end,

  -- You excluded a surface at some earlier point but you don't want it excluded anymore.
  ---@param name string
  reinclude_surface = function(name)
    if debug_log then log(string.format("[reinclude_surface]: name[]='%s' - CALLED!", type(name))) end
    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    end

    if debug_log then log(string.format("[reinclude_surface]: Reincluding surface name='%s' ...", name)) end
    surfaces.reinclude(name)

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

  -- The ruins should have the sizes given in utils.ruin_half_sizes, e.g. ruins in the small_ruins array should be 8x8 tiles.
  -- See also: docs/ruin_sets.md
  ---@param name string
  ---@param small_ruins Ruin[]
  ---@param medium_ruins Ruin[]
  ---@param large_ruins Ruin[]
  ---@deprecated
  add_ruin_set = function(name, small_ruins, medium_ruins, large_ruins)
    log(string.format("[add_ruin_set]: DEPECATED! This function only allows 'small', 'medium' and 'large'. Please use add_ruin_sets() instead! name='%s'", name))
    utils.output_message(string.format("The ruin-set '%s' has invoked a deprecated remote-call function 'add_ruin_set()'. Please inform your mod developer to switch to 'add_ruin_sets()' instead.", name))

    if type(name) ~= "string" then
      error(string.format("name[]='%s' is not expected type 'string'", type(name)))
    elseif not (small_ruins and next(small_ruins)) then
      error("Argument 'small_ruins' is an empty ruin set")
    elseif not (medium_ruins and next(medium_ruins)) then
      error("Argument 'medium_ruins' is an empty ruin set")
    elseif not (large_ruins and next(large_ruins)) then
      error("Argument 'large_ruins' is an empty ruin set")
    end

    _ruin_sets[name] = {
      small  = small_ruins,
      medium = medium_ruins,
      large  = large_ruins
    }
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
