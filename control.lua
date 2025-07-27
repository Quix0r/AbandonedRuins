local constants = require("lua/constants")
local utils = require("lua/utilities")
local spawning = require("lua/spawning")

debug_log = settings.global["ruins-enable-debug-log"].value
debug_on_tick = settings.global["ruins-enable-debug-on-tick"].value

-- Init ruin sets (empty for now)
---@type table<string, RuinSet>
local _ruin_sets = {}

-- Initial ruin sizes: small, medium, large
---@type table<string>
local ruin_sizes = {"small", "medium", "large"}

local on_entity_force_changed_event = script.generate_event_name()

local function init_spawn_chances()
  if debug_log then log("[init_spawn_chances]: CALLED!") end

  -- Init spawn_chances table if not found
  if storage.spawn_chances == nil then
    storage.spawn_chances = {}
    for _, size in pairs(ruin_sizes) do
      storage.spawn_chances[size] = 0.0
    end
  end

  -- Table of exclusive ruinsets
  storage.exclusive_ruinset = storage.exclusive_ruinset or {}

  -- Init local tables, variables
  local chances = {}
  local thresholds = {}
  local sumChance = 0.0

  for _, size in pairs(ruin_sizes) do
    chances[size] = settings.global["ruins-" .. size .. "-ruin-chance"].value
    sumChance = sumChance + chances[size]
    if debug_log then log(string.format("[init_spawn_chances]: chances[%s]=%.2f", size, chances[size])) end
  end

  local totalChance = math.min(sumChance, 1)
  if debug_log then log(string.format("[init_spawn_chances]: sumChance=%.2f,totalChance=%.2f", sumChance, totalChance)) end

  -- now compute cumulative distribution of conditional probabilities for
  -- spawn_type given a spawn occurs.
  for i, size in pairs(ruin_sizes) do
    if debug_log then log(string.format("[init_spawn_chances]: i=%d,size='%s'", i, size)) end
    thresholds[size] = chances[size]  / sumChance * totalChance
    if i > 1 then
      -- Add threshold of previous ruin size
      thresholds[size] = thresholds[size] + thresholds[ruin_sizes[i - 1]]
    end
    if debug_log then log(string.format("[init_spawn_chances]: thresholds[%s]=%.2f", size, thresholds[size])) end
  end

  if debug_log then log(string.format("[init_spawn_chances]: Adding %d thresholds ...", table_size(thresholds))) end
  for size, threshold in pairs(thresholds) do
    if debug_log then log(string.format("[init_spawn_chances]: Adding/updating size='%s',threshold=%.2f ...", size, threshold)) end
    storage.spawn_chances[size] = threshold
  end

  if debug_log then log("[init_spawn_chances]: EXIT!") end
end

local function update_debug_log()
  debug_log = settings.global["ruins-enable-debug-log"].value
  debug_on_tick = settings.global["ruins-enable-debug-on-tick"].value
  game.print(string.format("debug log is now: %s/%s", debug_log, debug_on_tick))
end

local function init()
  if debug_log then log("[init]: CALLED!") end
  utils.set_enemy_force_cease_fire(utils.get_enemy_force(), not settings.global["ruins-enemy-not-cease-fire"].value)

  -- Initialize spawn changes array (isn't stored in save-game)
  init_spawn_chances()

  ---@type boolean
  storage.spawn_ruins = storage.spawn_ruins or true

  ---@type RuinQueueItem[]
  storage.ruin_queue = storage.ruin_queue or {}

  if not storage.excluded_surfaces then
    if debug_log then log("[init]: Initializing excluded_surfaces table ...") end
    storage.excluded_surfaces = {
      ["beltlayer"]     = true,
      ["pipelayer"]     = true,
      ["Factory floor"] = true, -- factorissimo
      ["ControlRoom"]   = true, -- mobile factory
      ["NiceFill"]      = true  -- mod's own surface
    }
  end
  if debug_log then log("[init]: EXIT!") end
end

script.on_init(init)
script.on_configuration_changed(update_debug_log)
script.on_configuration_changed(init)
script.on_event(defines.events.on_player_created, update_debug_log)
script.on_event(defines.events.on_runtime_mod_setting_changed, init)

script.on_event(defines.events.on_force_created,
  function()
    -- Sets up the diplomacy for all forces, not just the newly created one.
    utils.set_enemy_force_diplomacy(utils.get_enemy_force(), not settings.global["ruins-enemy-not-cease-fire"].value)
  end
)

script.on_event(defines.events.on_tick,
  function(event)
    if debug_on_tick then log(string.format("[on_tick]: event.tick=%d - CALLED!", event.tick)) end

    ---@type RuinQueueItem[]
    local ruins = storage.ruin_queue[event.tick]
    ---@type string
    local ruinset_name = settings.global[constants.CURRENT_RUIN_SET_KEY].value

    if debug_on_tick then log(string.format("[on_tick]: runins[]='%s',ruinset_name='%s'", type(ruins), ruinset_name)) end
    if not ruins then
      if debug_on_tick then log(string.format("[on_tick]: No ruin queued for event.tick=%d  EXIT!", event.tick)) end
      return
    elseif table_size(ruins) == 0 then
      log(string.format("[on_tick]: event.tick=%d has empty list set, deleting list ... - EXIT!", event.tick))
      storage.ruin_queue[event.tick] = nil
      return
    end

    if debug_on_tick then log(string.format("[on_tick]: Spawning %d random ruin sets ...", #ruins)) end
    for _, ruin in pairs(ruins) do
      if debug_on_tick then log(string.format("[on_tick]: Spawning ruin.size='%s',ruin.center='%s',ruin.surface='%s' ...", ruin.size, tostring(ruin.center), tostring(ruin.surface))) end
      if storage.exclusive_ruinset[ruin.surface.name] == nil or ruinset_name == storage.exclusive_ruinset[ruin.surface.name] then
        -- The ruin-set is either marked as non-exclusive or it surface and ruin-set name are matching
        if debug_on_tick then log(string.format("[on_tick]: Invoking spawning.spawn_random_ruin() with ruinset_name='%s',ruin.size='%s' ...", ruinset_name, ruin.size)) end
        spawning.spawn_random_ruin(_ruin_sets[ruinset_name][ruin.size], utils.ruin_half_sizes[ruin.size], ruin.center, ruin.surface)
      end
    end

    if debug_on_tick then log(string.format("[on_tick]: Deleting ruin(s) on event.tick=%d ...", event.tick)) end
    storage.ruin_queue[event.tick] = nil

    if debug_on_tick then log("[on_tick]: EXIT!") end
  end
)

-- This delays ruin spawning to the next tick. This is done because on_chunk_generated may be called before other mods have a chance to do the remote call for the ruin set:
-- ThisMod_onInit -> SomeOtherMod_generatesChunks -> ThisMod_onChunkGenerated (ruin is queued) -> RuinPack_onInit (ruin set remote call) -> ThisMod_OnTick (ruin set is used)
---@param tick uint
---@param ruin RuinQueueItem
local function queue_ruin(tick, ruin)
  if debug_log then log(string.format("[queue_ruin]: tick=%d,ruin[]='%s' - CALLED!", tick, type(ruin))) end
  if ruin.surface.name == constants.DEBUG_SURFACE_NAME then
    error(string.format("[queue_ruin]: Debug surface '%s' has no random ruin spawning.", ruin.surface.name))
  end

  local processing_tick = tick + 1

  if not storage.ruin_queue[processing_tick] then
    if debug_log then log(string.format("[queue_ruin]: Initializing ruins list on processing_tick=%d", processing_tick)) end
    storage.ruin_queue[processing_tick] = {}
  end

  if debug_log then log(string.format("[queue_ruin]: Queueing ruin[]='%s' ...", type(ruin))) end
  table.insert(storage.ruin_queue[processing_tick], ruin)

  if debug_log then log("[queue_ruin]: EXIT!") end
end

---@param size string
---@param min_distance number
---@param center MapPosition
---@param surface LuaSurface
---@param tick uint
local function try_ruin_spawn(size, min_distance, center, surface, tick)
  if debug_log then log(string.format("[try_ruin_spawn]: size='%s',min_distance=%d,center[]='%s',surface[]='%s',tick=%d - CALLED!", size, min_distance, type(center), type(surface), tick)) end
  if type(size) ~= "string" then
    error(string.format("[try_ruin_spawn]: size[]='%s' is not expected type 'string'", type(size)))
  elseif type(min_distance) ~= "number" then
    error(string.format("[try_ruin_spawn]: min_distance[]='%s' is not expected type 'string'", type(min_distance)))
  elseif utils.ruin_min_distance_multiplier[size] == nil then
    error(string.format("[try_ruin_spawn]: size='%s' is not found in multiplier table", size))
  elseif surface.name == constants.DEBUG_SURFACE_NAME then
    error(string.format("[try_ruin_spawn]: Debug surface '%s' has no random ruin spawning.", surface.name))
  end

  min_distance = min_distance * utils.ruin_min_distance_multiplier[size]
  if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d", min_distance)) end

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

  queue_ruin(tick, {
    size    = size,
    center  = center,
    surface = surface
  })

  if debug_log then log("[try_ruin_spawn]: EXIT!") end
end

script.on_event(defines.events.on_chunk_generated,
  function (event)
    if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' - CALLED!", event.surface.name)) end
    if storage.spawn_ruins == false then
      if debug_log then log("[on_chunk_generated]: Spawning ruins is disabled by configuration - EXIT!") end
      return
    elseif event.surface.name == constants.DEBUG_SURFACE_NAME then
      if debug_log then log(string.format("[on_chunk_generated]: Debug surface '%s' must spawn ruins on their own, not through randomness.", event.surface.name)) end
      return
    elseif utils.str_contains_any_from_table(event.surface.name, storage.excluded_surfaces) then
      if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' is excluded - EXIT!", event.surface.name)) end
      return
    end

    local center       = utils.get_center_of_chunk(event.position)
    local min_distance = settings.global["ruins-min-distance-from-spawn"].value
    local spawn_chance = math.random()
    if debug_log then log(string.format("[on_chunk_generated]: center.x=%d,center.y=%d,min_distance=%d,spawn_chance=%2.f", center.x, center.y, min_distance, spawn_chance)) end

    for _, size in pairs(ruin_sizes) do
      if debug_log then log(string.format("[on_chunk_generated]: spawn_chances[%s]=%.2f,spawn_chance=%.2f", size, storage.spawn_chances[size], spawn_chance)) end
      if spawn_chance <= storage.spawn_chances[size] then
        if debug_log then log(string.format("[on_chunk_generated]: Trying to spawn ruin of size='%s' at event.surface='%s' ...", size, event.surface)) end
        try_ruin_spawn(size, min_distance, center, event.surface, event.tick)

        if debug_log then log("[on_chunk_generated]: BREAK!") end
        break
      end
    end

    if debug_log then log("[on_chunk_generated]: EXIT!") end
  end
)

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
      error(string.format("[set_spawn_ruins]: spawn_ruins[]='%s' is not expected type 'boolean'", type(spawn_ruins)))
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
      error(string.format("[add_ruin_size]: size[]='%s' is not expected type 'string'", type(size)))
    elseif type(half_size) ~= "number" then
      error(string.format("[add_ruin_size]: half_size[]='%s' is not expected type 'number'", type(half_size)))
    elseif ruin_sizes[size] ~= nil then
      error(string.format("[add_ruin_size]: size='%s' is already added as ruin size", size))
    end

    if debug_log then log(string.format("[add_ruin_size]: Adding ruin size='%s',half_size=%d ...", size, half_size)) end
    table.insert(ruin_sizes, size)
    table.insert(utils.ruin_half_sizes, half_size)

    if debug_log then log("[add_ruin_size]: EXIT!") end
  end,

  -- Get all ruin sizes
  ---@return table
  get_ruin_sizes = function() return ruin_sizes end,

  -- Any surface whose name contains this string will not have ruins generated on it.
  ---@param name string
  exclude_surface = function(name)
    if debug_log then log(string.format("[exclude_surface]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
    if type(name) ~= "string" then
      error(string.format("[exclude_surface]: name[]='%s' is not expected type 'string'", type(name)))
    end

    if debug_log then log(string.format("[exclude_surface]: Excluding surface name='%s' ...", name)) end
    storage.excluded_surfaces[name] = true

    if debug_log then log("[exclude_surface]: EXIT!") end
  end,

  -- You excluded a surface at some earlier point but you don't want it excluded anymore.
  ---@param name string
  reinclude_surface = function(name)
    if debug_log then log(string.format("[reinclude_surface]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
    if type(name) ~= "string" then
      error(string.format("[reinclude_surface]: name[]='%s' is not expected type 'string'", type(name)))
    end

    if debug_log then log(string.format("[reinclude_surface]: Reincluding surface name='%s' ...", name)) end
    storage.excluded_surfaces[name] = nil

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
      error(string.format("[add_ruin_sets]: name[]='%s' is not expected type 'string'", type(name)))
    elseif type(ruin_sets) ~= "table" then
      error(string.format("[add_ruin_sets]: ruin_sets[]='%s' is not expected type 'table'", type(ruin_sets)))
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
    if type(name) ~= "string" then
      error(string.format("[add_ruin_set]: name[]='%s' is not expected type 'string'", type(name)))
    elseif not (small_ruins and next(small_ruins)) then
      error("[add_ruin_set]: Argument 'small_ruins' is an empty ruin set")
    elseif not (medium_ruins and next(medium_ruins)) then
      error("[add_ruin_set]: Argument 'medium_ruins' is an empty ruin set")
    elseif not (large_ruins and next(large_ruins)) then
      error("[add_ruin_set]: Argument 'large_ruins' is an empty ruin set")
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
      error(string.format("[get_ruin_set]: name[]='%s' is not expected type 'string'", type(name)))
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

  -- Registers ruin-set name as exclusive to only one surface
  spawn_exclusively_on = function(surface_name, ruinset_name)
    if debug_log then log(string.format("[spawn_exclusively_on]: surface_name[]='%s',ruinset_name[]='%s' - CALLED!", type(surface_name), type(ruinset_name))) end
    if type(surface_name) ~= "string" then
      error(string.format("surface_name[]='%s' is not expected type 'string'", type(surface_name)))
    elseif type(ruinset_name) ~= "string" then
      error(string.format("ruinset_name[]='%s' is not expected type 'string'", type(ruinset_name)))
    end

    if debug_log then log(string.format("[spawn_exclusively_on]: Registering surface_name='%s',ruinset_name='%s' as exclusive ...", surface_name, ruinset_name)) end
    storage.exclusive_ruinset[surface_name] = ruinset_name

    if debug_log then log("[spawn_exclusively_on]: EXIT!") end
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
        game.print("old: " .. old_force.name .. " new: " .. new_force.name)
      end)
    end
  end

  script.on_load(init)
  script.on_init(init)

--]]
