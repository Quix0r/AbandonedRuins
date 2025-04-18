local util = require("__AbandonedRuins20__/lua/utilities")
local spawning = require("__AbandonedRuins20__/lua/spawning")

debug_log = settings.global["AbandonedRuins-enable-debug-log"].value
debug_on_tick = settings.global["AbandonedRuins-enable-debug-on-tick"].value

---@type table<string, RuinSet>
local ruin_sets = {
  base = require("__AbandonedRuins20__/lua/ruins/base_ruin_set")
}

local on_entity_force_changed_event = script.generate_event_name()

local function spawn_chances()
  local smallChance  = settings.global["ruins-small-ruin-chance"].value
  local mediumChance = settings.global["ruins-medium-ruin-chance"].value
  local largeChance  = settings.global["ruins-large-ruin-chance"].value

  local sumChance = smallChance + mediumChance + largeChance
  local totalChance = math.min(sumChance, 1)

  -- now compute cumulative distribution of conditional probabilities for
  -- spawn_type given a spawn occurs.
  local smallThreshold  = smallChance  / sumChance * totalChance
  local mediumThreshold = mediumChance / sumChance * totalChance + smallThreshold
  local largeThreshold  = largeChance  / sumChance * totalChance + mediumThreshold

  storage.spawn_table = {
    small  = smallThreshold,
    medium = mediumThreshold,
    large  = largeThreshold
  }
end

local function init()
  util.set_enemy_force_cease_fire(util.get_enemy_force(), not settings.global["AbandonedRuins-enemy-not-cease-fire"].value)

  spawn_chances()
  if storage.spawn_ruins == nil then
    storage.spawn_ruins = true
  end
  storage.ruin_queue = storage.ruin_queue or {}
  if not storage.excluded_surfaces then
    storage.excluded_surfaces = {
      ["beltlayer"]     = true,
      ["pipelayer"]     = true,
      ["Factory floor"] = true, -- factorissimo
      ["ControlRoom"]   = true -- mobile factory
    }
    if script.active_mods["space-age"] then
      -- @todo Fulgora has heavy oil seas, Vulcanus lava "seas", currently not detected as "water"
      --storage.excluded_surfaces["fulgora"]  = true
      --storage.excluded_surfaces["vulcanus"] = true
    end
  end
end

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_runtime_mod_setting_changed, init)

script.on_event(defines.events.on_force_created,
  function()
    -- Sets up the diplomacy for all forces, not just the newly created one.
    util.set_enemy_force_diplomacy(util.get_enemy_force(), not settings.global["AbandonedRuins-enemy-not-cease-fire"].value)
  end
)

script.on_event(defines.events.on_tick,
  function(event)
    if debug_on_tick then log(string.format("[on_tick]: event.tick=%d - CALLED!", event.tick)) end

    ---@type RuinQueueItem[]
    local ruins = storage.ruin_queue[event.tick]

    if not ruins then
      if debug_on_tick then log(string.format("[on_tick]: No ruin queued for event.tick=%d  EXIT!", event.tick)) end
      return
    end

    if debug_on_tick then log(string.format("[on_tick]: Spawning %d random ruin sets ...", #ruins)) end
    for _, ruin in pairs(ruins) do
      if debug_on_tick then log(string.format("[on_tick]: Spawning ruin.size=%d,ruin.center='%s',ruin.surface='%s' ...", ruin.size, tostring(ruin.center), tostring(ruin.surface))) end
      spawning.spawn_random_ruin(ruin_sets[settings.global["AbandonedRuins-set"].value][ruin.size], util.ruin_half_sizes[ruin.size], ruin.center, ruin.surface)
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
  local processing_tick = tick + 1

  if not storage.ruin_queue[processing_tick] then
    storage.ruin_queue[processing_tick] = {}
  end

  table.insert(storage.ruin_queue[processing_tick], ruin)

  if debug_log then log("[queue_ruin]: EXIT!") end
end

---@param size number
---@param min_distance number
---@param center MapPosition
---@param surface LuaSurface
---@param tick uint
local function try_ruin_spawn(size, min_distance, center, surface, tick)
  if debug_log then log(string.format("[try_ruin_spawn]: size=%d,min_distance=%d,center[]='%s',surface[]='%s',tick=%d - CALLED!", size, min_distance, type(center), type(surface), tick)) end

  min_distance = min_distance * util.ruin_min_distance_multiplier[size]
  if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d", min_distance)) end

  if math.abs(center.x) < min_distance and math.abs(center.y) < min_distance then
    if debug_log then log(string.format("[try_ruin_spawn]: min_distance=%d is to close to spawn area - EXIT!", min_distance)) end
    return
  end

  -- random variance so they aren't always chunk aligned
  local variance = -(util.ruin_half_sizes[size] * 0.75) + 12 -- 4 -> 9, 8 -> 6, 16 -> 0. Was previously 4 -> 10, 8 -> 5, 16 -> 0
  if debug_log then log(string.format("[try_ruin_spawn]: variance={:04.2f},center.x=%d,center.y=%d - BEFORE!", variance, center.x, center.y)) end
  if variance > 0 then
    center.x = center.x + math.random(-variance, variance)
    center.y = center.y + math.random(-variance, variance)
  end
  if debug_log then log(string.format("[try_ruin_spawn]: variance={:04.2f},center.x=%d,center.y=%d - AFTER!", variance, center.x, center.y)) end

  queue_ruin(tick, {size = size, center = center, surface = surface})

  if debug_log then log("[on_chunk_generated]: EXIT!") end
end

script.on_event(defines.events.on_chunk_generated,
  function (event)
    if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' - CALLED!", event.surface.name)) end
    if storage.spawn_ruins == false then
      if debug_log then log("[on_chunk_generated]: Spawning ruins is disabled by configuration - EXIT!") end
      return
    elseif util.str_contains_any_from_table(event.surface.name, storage.excluded_surfaces) then
      if debug_log then log(string.format("[on_chunk_generated]: event.surface.name='%s' is excluded - EXIT!", event.surface.name)) end
      return
    end

    local center       = util.get_center_of_chunk(event.position)
    local min_distance = settings.global["ruins-min-distance-from-spawn"].value
    local spawn_chance = math.random()

    if spawn_chance <= storage.spawn_table["small"] then
      try_ruin_spawn("small", min_distance, center, event.surface, event.tick)
    elseif spawn_chance <= storage.spawn_table["medium"] then
      try_ruin_spawn("medium", min_distance, center, event.surface, event.tick)
    elseif spawn_chance <= storage.spawn_table["large"] then
      try_ruin_spawn("large", min_distance, center, event.surface, event.tick)
    end

    if debug_log then log("[on_chunk_generated]: EXIT!") end
  end
)

script.on_event({defines.events.on_player_selected_area, defines.events.on_player_alt_selected_area}, function(event)
  if debug_log then log("[on_player_selected_area]: event.item='" .. event.item .. "',event.entities()=" .. #event.entities .. " - CALLED!") end
  if (event.item ~= "AbandonedRuins-claim") then
    if debug_log then log("[on_player_selected_area]: event.item='" .. event.item .. "' is not ruin claim - EXIT!") end
    return
  elseif (#event.entities == 0) then
    if debug_log then log("[on_player_selected_area]: No entities selected - EXIT!") end
    return
  end

  local neutral_force = game.forces.neutral
  local claimants_force = game.get_player(event.player_index).force
  if debug_log then log("[on_player_selected_area]: neutral_force='" .. tostring(neutral_force) .. "',claimants_force='" .. tostring(claimants_force) .. "'") end

  for _, entity in pairs(event.entities) do
    if debug_log then log("[on_player_selected_area]:entity.valid='" .. tostring(entity.valid) .. "',entity.force='" .. tostring(entity.force) .. "'") end
    if entity.valid and entity.force == neutral_force then
      if debug_log then log("[on_player_selected_area]:Setting entity.force='" .. tostring(claimants_force) .. "' ...") end
      entity.force = claimants_force

      if debug_log then log("[on_player_selected_area]:entity.valid='" .. tostring(entity.valid) .. "'") end
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

  if debug_log then log("[on_player_selected_area]:EXIT!") end
end)

remote.add_interface("AbandonedRuins",
{
  get_on_entity_force_changed_event = function() return on_entity_force_changed_event end,
  -- The event contains:
  ---@class on_entity_force_changed_event_data:EventData
  ---@field entity LuaEntity The entity that had its force changed.
  ---@field force LuaForce The entity that had its force changed.
  -- The current force can be gotten from event.entity.
  -- This is raised after the force is changed.
  -- Mod event subscription explanation can be found lower in this file.

  -- Set whether ruins should be spawned at all
  ---@param spawn_ruins boolean
  set_spawn_ruins = function(spawn_ruins)
    assert(type(spawn_ruins) == "boolean",
      "Remote call parameter to set_spawn_ruins for AbandonedRuins must be a boolean value."
    )
    storage.spawn_ruins = spawn_ruins
  end,

  -- Get whether ruins should be spawned at all
  ---@return boolean
  get_spawn_ruins = function() return storage.spawn_ruins end,

  -- Any surface whose name contains this string will not have ruins generated on it.
  ---@param name string
  exclude_surface = function(name)
    assert(type(name) == "string",
      "Remote call parameter to exclude_surface for AbandonedRuins must be a string value."
    )
    storage.excluded_surfaces[name] = true
  end,

  -- You excluded a surface at some earlier point but you don't want it excluded anymore.
  ---@param name string
  reinclude_surface = function(name)
    assert(type(name) == "string",
      "Remote call parameter to reinclude_surface for AbandonedRuins must be a string value."
    )
    storage.excluded_surfaces[name] = nil
  end,

  -- !! ALWAYS call this in on_load and on_init. !!
  -- !! The ruins sets are not saved or loaded. !!
  -- The ruins should have the sizes given in util.ruin_half_sizes, e.g. ruins in the small_ruins array should be 8x8 tiles.
  -- See also: docs/ruin_sets.md
  ---@param name string
  ---@param small_ruins Ruin[]
  ---@param medium_ruins Ruin[]
  ---@param large_ruins Ruin[]
  add_ruin_set = function(name, small_ruins, medium_ruins, large_ruins)
    assert(type(name) == "string",
      "Remote call parameter to add_ruin_set for AbandonedRuins must be a string value."
    )
    assert(small_ruins and next(small_ruins))
    assert(medium_ruins and next(medium_ruins))
    assert(large_ruins and next(large_ruins))

    ruin_sets[name] = {
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
    assert(type(name) == "string",
      "Remote call parameter to get_ruin_set for AbandonedRuins must be a string value."
    )
    return ruin_sets[name]
  end,

  -- !! The ruins sets are not saved or loaded. !!
  -- returns {small = {<array of ruins>}, medium = {<array of ruins>}, large = {<array of ruins>}}
  ---@return RuinSet
  get_current_ruin_set = function()
    return ruin_sets[settings.global["AbandonedRuins-set"].value]
  end
})

--[[ How to: Subscribe to mod events
  Basics: Get the event id from a remote interface. Subscribe to the event in on_init and on_load.

  Example:

  script.on_load(function()
    if remote.interfaces["AbandonedRuins"] then
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
  end)

  script.on_init(function()
    if remote.interfaces["AbandonedRuins"] then
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
  end)

--]]
