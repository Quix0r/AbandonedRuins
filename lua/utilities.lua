local constants = require("constants")
local core_utils = require("__core__/lualib/util")

local util = {}

util.ruin_half_sizes =
{
  small  = 8  / 2,
  medium = 16 / 2,
  large  = 32 / 2
}

util.ruin_min_distance_multiplier =
{
  small  = 1,
  medium = 2.5,
  large  = 5
}

util.debugprint = __DebugAdapter and __DebugAdapter.print or function() end

---@param chunk_position ChunkPosition
---@return MapPosition
util.get_center_of_chunk = function(chunk_position)
  return {x = chunk_position.x * 32 + 16, y = chunk_position.y * 32 + 16}
end

---@param half_size number
---@param center MapPosition
---@return BoundingBox
util.area_from_center_and_half_size = function(half_size, center)
  return {{center.x - half_size, center.y - half_size}, {center.x + half_size, center.y + half_size}}
end

---@param haystack string
---@param needles table<string, boolean> The boolean should always be true, it is ignored.
---@return boolean @True if the haystack contains at least one of the needles from the table
util.str_contains_any_from_table = function(haystack, needles)
  if debug_log then log(string.format("[str_contains_any_from_table]: haystack='%s',needles[]='%s' - CALLED!", haystack, type(needles))) end
  for needle in pairs(needles) do
    if debug_log then log(string.format("[str_contains_any_from_table]: haystack='%s',needle='%s'", haystack, needle)) end
    if haystack:find(needle, 1, true) then -- plain find, no pattern
      if debug_log then log(string.format("[str_contains_any_from_table]: Found needle='%s' - EXIT!", needle)) end
      return true
    end
  end

  if debug_log then log(string.format("[str_contains_any_from_table]: haystack='%s' does not contain any needles - EXIT!", haystack)) end
  return false
end

-- TODO Bilka: this doesn't show in intellisense
---@param entity LuaEntity
---@param item_dict table<string, uint> Dictionary of item names to counts
util.safe_insert = core_utils.insert_safe

---@param entity LuaEntity
---@param fluid_dict table<string, number> Dictionary of fluid names to amounts
util.safe_insert_fluid = function(entity, fluid_dict)
  if debug_log then log(string.format("[safe_insert_fluid]: entity[]='%s',fluid_dict[]='%s' - CALLED!", type(entity), type(fluid_dict))) end
  if not (entity and entity.valid and fluid_dict) then
    log(string.format("[safe_insert_fluid]: entitiy[]='%s' or fluid_dict[]='%s' is not valid!", type(entity), type(fluid_dict)))
    return
  end

  local fluids = prototypes.fluid
  local insert = entity.insert_fluid

  for name, amount in pairs (fluid_dict) do
    if fluids[name] or not fluids[name].valid then
      insert{name = name, amount = amount}
    else
      log(string.format("[safe_insert_fluid]: name='%s' is not a valid fluid to insert", name))
    end
  end

  if debug_log then log("[safe_insert_fluid]: EXIT!") end
end

---@param entity LuaEntity
---@param damage_info Damage
---@param damage_amount number
util.safe_damage = function(entity, damage_info, damage_amount)
  if not (entity and entity.valid) then
    log(string.format("[safe_damage]: entity[]='%s' is not valid!", type(entity)))
    return
  elseif type(damage_amount) ~= "number" then
    error(string.format("[safe_damage]: damage_amount[]='%s' is not expected type 'number'", type(damage_amount)))
  end

  entity.damage(damage_amount, damage_info.force or "neutral", damage_info.type or "physical")
end

---@param entity LuaEntity
---@param chance number
util.safe_die = function(entity, chance)
  if not (entity and entity.valid) then
    log(string.format("[safe_damage]: entity[]='%s' is not valid!", type(entity)))
    return
  elseif type(chance) ~= "number" then
    error(string.format("[safe_damage]: chance[]='%s' is not expected type 'number'", type(chance)))
  end

  if math.random() <= chance then
    entity.die()
  end
end

-- Set cease_fire status for all forces.
---@param enemy_force LuaForce
---@param cease_fire boolean
util.set_enemy_force_cease_fire = function(enemy_force, cease_fire)
  for _, force in pairs(game.forces) do
    if force ~= enemy_force then
      force.set_cease_fire(enemy_force, cease_fire)
      enemy_force.set_cease_fire(force, cease_fire)
    end
  end
end

-- Set cease_fire status for all forces and friend = true for all biter forces.
---@param enemy_force LuaForce
---@param cease_fire boolean
util.set_enemy_force_diplomacy = function(enemy_force, cease_fire)
  for _, force in pairs(game.forces) do
    if force.ai_controllable then
      force.set_friend(enemy_force, true)
      enemy_force.set_friend(force, true)
    end
  end

  util.set_enemy_force_cease_fire(enemy_force, cease_fire)
end

-- Setups configured enemy force and returns it
---@return LuaForce
local function setup_enemy_force()
  ---@type LuaForce
  local enemy_force = game.forces["AbandonedRuins:enemy"] or game.create_force("AbandonedRuins:enemy")

  util.set_enemy_force_diplomacy(enemy_force, false)
  storage.enemy_force = enemy_force

  return enemy_force
end

-- Safely returns "cached" enemy force or sets it up if not present
---@return LuaForce
util.get_enemy_force = function()
  if (storage.enemy_force and storage.enemy_force.valid) then
    return storage.enemy_force
  end

  return setup_enemy_force()
end

-- "Registers" this ruin set's name to the selection box
---@param name string
---@param is_default boolean
util.register_ruin_set = function(name, is_default)
  if type(name) ~= "string" then
    error(string.format("name[]='%s' is not expected type 'string'", type(name)))
  elseif type(is_default) ~= "boolean" then
    error(string.format("is_default[]='%s' is not expected type 'boolean'", type(is_default)))
  end

  -- First get settings
  local set = data.raw["string-setting"][constants.CURRENT_RUIN_SET_KEY]

  -- Add this ruin set's name to it
  table.insert(set.allowed_values, name)

  -- Set it as default
  if is_default then
    set.default_value = name
  end
end

-- Returns "unknown" if optional (but recommended) table key `name` isn't found or otherwise it returns that key's value
---@param ruin Ruin
---@return string
util.get_ruin_name = function(ruin)
  local name = "unknown"

  if type(ruin.name) == "string" then
    name = ruin.name
  end

  return ruin
end

return util
