local util = require("__AbandonedRuins20__/lua/utilities")
local expressions = require("__AbandonedRuins20__/lua/expression_parsing")

local spawning = {}

---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
local function no_corpse_fade(half_size, center, surface)
  if debug_log then log(string.format("[no_corpse_fade]: half_size=%d,center[]='%s',surface[]='%s' - CALLED!", half_size, type(center), type(surface))) end
  if half_size <= 0 or not center or not surface then return end
  assert(surface.valid, string.format("[spawn_entities]: surface.name='%s' is not valid", surface.name))

  local area = util.area_from_center_and_half_size(half_size, center)
  if debug_log then log(string.format("[no_corpse_fade]: area[]='%s',surface.name='%s'", type(area), surface.name)) end

  for _, entity in pairs(surface.find_entities_filtered({area = area, type={"corpse", "rail-remnants"}})) do
    if debug_log then log(string.format("[no_corpse_fade]: entity.type='%s',entity.name='%s' - Setting corpse_expires=false ...", entity.type, entity.name)) end
    entity.corpse_expires = false
  end

  if debug_log then log("[spawn_entities]: EXIT!") end
end

---@param entity EntityExpression|string
---@param relative_position MapPosition
---@param center MapPosition
---@param surface LuaSurface
---@param extra_options EntityOptions
---@param vars VariableValues
---@param prototypes LuaCustomTable<string,LuaEntityPrototype>
local function spawn_entity(entity, relative_position, center, surface, extra_options, vars, prototypes)
  if debug_log then
    log(string.format(
      "[spawn_entity]: entity[]='%s',relative_position[]='%s',center[]='%s',surface[]='%s',extra_options[]='%s',vars[]='%s',prototypes[]='%s' - CALLED!",
      type(entity),
      type(relative_position),
      type(center),
      type(surface),
      type(extra_options),
      type(vars),
      type(prototypes)
    ))
  end
  local entity_name = expressions.entity(entity, vars)
  if debug_log then log(string.format("[spawn_entity]: entity_name='%s',entity.name='%s'", entity_name, entity.name)) end

  if not prototypes[entity_name] then
    util.debugprint(string.format("[spawn_entity]: entity '%s' does not exist!", entity_name))
    return
  end

  local force = extra_options.force or "neutral"
  if debug_log then log(string.format("[spawn_entity]: force='%s' - BEFORE!", force)) end
  if force == "enemy" then
    force = util.get_enemy_force()
  end
  if debug_log then log(string.format("[spawn_entity]: force='%s' - AFTER!", force)) end

  local recipe
  if debug_log then log(string.format("[spawn_entity]: extra_options.recipe[]='%s'", type(extra_options.recipe))) end
  if extra_options.recipe then
    if not _G["prototypes"].recipe[extra_options.recipe] then
      util.debugprint(string.format("[spawn_entity]: recipe '%s'' does not exist", extra_options.recipe))
    else
      recipe = extra_options.recipe
    end
  end
  if debug_log then log(string.format("[spawn_entity]: recipe[]='%s'", type(recipe))) end

  local e = surface.create_entity
  {
    name = entity_name,
    position = {center.x + relative_position.x, center.y + relative_position.y},
    direction = defines.direction[extra_options.dir] or defines.direction.north,
    force = force,
    raise_built = true,
    create_build_effect_smoke = false,
    recipe = recipe
  }

  if debug_log then log(string.format("[spawn_entity]: extra_options.dmg[]='%s'", type(extra_options.dmg))) end
  if extra_options.dmg then
    util.safe_damage(e, extra_options.dmg, expressions.number(extra_options.dmg.dmg, vars))
  end

  if debug_log then log(string.format("[spawn_entity]: extra_options.dead[]='%s'", type(extra_options.dead))) end
  if extra_options.dead then
    util.safe_die(e, extra_options.dead)
  end

  if debug_log then log(string.format("[spawn_entity]: extra_options.fluids[]='%s'", type(extra_options.fluids))) end
  if extra_options.fluids then
    local fluids = {}
    if debug_log then log(string.format("[spawn_entity]: Parsing %d fluids ...", #extra_options.fluids)) end
    for name, amount_expression in pairs(extra_options.fluids) do
      if debug_log then log(string.format("[spawn_entity]: name='%s',amount_expression='%s'", name, amount_expression)) end
      local amount = expressions.number(amount_expression, vars)
      if amount > 0 then
        if debug_log then log(string.format("[spawn_entity]: Adding fluid name='%s',amount=%d ...", name, amount)) end
        fluids[name] = amount
      end
    end

    if debug_log then log(string.format("[spawn_entity]: Safely inserting %d fluids ...", #fluids)) end
    util.safe_insert_fluid(e, fluids)
  end

  if debug_log then log(string.format("[spawn_entity]: extra_optios.items[]='%s'", type(extra_options.items))) end
  if extra_options.items then
    local items = {}

    for name, count_expression in pairs(extra_options.items) do
      if debug_log then log(string.format("[spawn_entity]: name='%s',count_expression='%s'", name, count_expression)) end
      if not _G["prototypes"].item[name] then
        util.debugprint(string.format("[spawn_entity]: item '%s' does not exist", name))
      else
        local count = expressions.number(count_expression, vars)
        if count > 0 then
          if debug_log then log(string.format("[spawn_entity]: Adding item name='%s',count=%d ...", name, count)) end
          items[name] = count
        end
      end
    end

    if debug_log then log(string.format("[spawn_entity]: Found %d items.", #items)) end
    if not (next(items) == nil) then
      if debug_log then log(string.format("[spawn_entity]: Safely inserting %d items ...", #items)) end
      util.safe_insert(e, items)
    end
  end

  if debug_log then log("[spawn_entities]: EXIT!") end
end

---@param entities RuinEntity[]
---@param center MapPosition
---@param surface LuaSurface
---@param vars VariableValues
local function spawn_entities(entities, center, surface, vars)
  if debug_log then log(string.format("[spawn_entities]: entities[]=%s,center[]='%s',surface[]='%s',vars[]='%s' - CALLED!", type(entities), type(center), type(surface), type(vars))) end
  if not entities or not surface then return end
  if #entities == 0 then error(string.format("[spawn_entities]: No entities to spawn on surface.name='%s' - EXIT!", surface.name)) return end
  assert(surface.valid, string.format("[spawn_entities]: surface.name='%s' is not valid", surface.name))

  local prototypes = prototypes.entity

  if debug_log then log(string.format("[spawn_entities]: Spawning %d entities on surface.name='%s' ...", #entities, surface.name)) end
  for _, entity_info in pairs(entities) do
    spawn_entity(entity_info[1], entity_info[2], center, surface, entity_info[3] or {}, vars, prototypes)
  end

  if debug_log then log("[spawn_entities]: EXIT!") end
end

---@param tiles RuinTile[]
---@param center MapPosition
---@param surface LuaSurface
local function spawn_tiles(tiles, center, surface)
  if debug_log then log(string.format("[spawn_tiles]: tiles[]=%s,center[]='%s',surface[]='%s' - CALLED!", type(tiles), type(center), type(surface))) end
  if not tiles or not surface then return end
  if #tiles == 0 then return end
  assert(surface.valid, string.format("[spawn_entities]: surface.name='%s' is not valid", surface.name))

  local valid = {}

  if debug_log then log(string.format("[spawn_tiles]: Spawning %d tiles on surface.name='%s' ...", #tiles, surface.name)) end
  for _, tile_info in pairs(tiles) do
    local name = tile_info[1]
    local pos = tile_info[2]

    if prototypes.tile[name] then
      if debug_log then log(string.format("[spawn_tiles]: name='%s',center.x=%d,center.y=%d,pos.x=%d,pos.y=%d", name, center.x, center.y, pos.x, pos.y)) end
      valid[#valid + 1] = {name = name, position = {center.x + pos.x, center.y + pos.y}}
    else
      util.debugprint(string.format("[spawn_tiles]: Tile '%s' does not exist!", name))
    end
  end

  if debug_log then log(string.format("[spawn_tiles]: Setting %d valid tiles for surface.name='%s' ...", #valid, surface.name)) end
  surface.set_tiles(
    valid,
    true, -- correct_tiles,                Default: true
    true, -- remove_colliding_entities,    Default: true
    true, -- remove_colliding_decoratives, Default: true
    true) -- raise_event,                  Default: false

  if debug_log then log("[spawn_entities]: EXIT!") end
end

-- Evaluates the values of the variables.
---@param vars Variable[]
---@return VariableValues
local function parse_variables(vars)
  if debug_log then log(string.format("[parse_variables]: vars[]='%s' - CALLED!", type(vars))) end
  if not vars then return end
  if #vars == 0 then return end

  local parsed = {}

  if debug_log then log(string.format("[parse_variables]: Parsing %d variables ...", #vars)) end
  for _, var in pairs(vars) do
    if debug_log then log(string.format("[parse_variables]: var.type='%s',var.name='%s',var.value[]='%s'", var.type, var.name, type(var.value))) end
    if var.type == "entity-expression" then
      parsed[var.name] = expressions.entity(var.value)
    elseif var.type == "number-expression" then
      parsed[var.name] = expressions.number(var.value)
    else
      error(string.format("[parse_variables]: Unrecognized variable type: '%s'", var.type))
    end
  end

  if debug_log then log(string.format("[parse_variables]: parsed()=%d - EXIT!", #parsed)) end
  return parsed
end

---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
---@return boolean @Whether the area is clear and ruins can be spawned
local function clear_area(half_size, center, surface)
  if debug_log then log(string.format("[clear_area]: half_size[]='%s',center[]='%s',surface='%s' - CALLED!", type(half_size), type(center), type(surface))) end
  local area = util.area_from_center_and_half_size(half_size, center)

  -- exclude tiles that we shouldn't spawn on
  if surface.count_tiles_filtered{ area = area, limit = 1, collision_mask = { item = true, object = true, water_tile = true } } == 1 then
    if debug_log then log(string.format("[clear_area]: surface.name='%s' has excluded tile - EXIT!", surface.name)) end
    return false
  end

  for _, entity in pairs(surface.find_entities_filtered({area = area, type = {"resource"}, invert = true})) do
    if debug_log then log(string.format("[clear_area]: entity.type='%s',entity.name='%s'", entity.type, entity.name)) end
    if (entity.valid and entity.type ~= "tree") or math.random() < (half_size / 14) then
      entity.destroy({do_cliff_correction = true, raise_destroy = true})
    end
  end

  log("[clear_area]: Area is clear for ruin! - EXIT!")
  return true
end

---@param ruin Ruin
---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
spawning.spawn_ruin = function(ruin, half_size, center, surface)
  if debug_log then log(string.format("[spawn_ruin]: ruin[]='%s',half_size[]='%s',center[]='%s',surface='%s' - CALLED!", type(ruin), type(half_size), type(center), type(surface))) end
  if not ruin then
    error("Parameter 'ruin' is not set")
    return
  elseif not surface then
    error("Parameter 'surface' is not set")
    return
  end

  assert(surface.valid, string.format("surface.name='%s' is not valid", surface.name))

  if clear_area(half_size, center, surface) then
    local vars = parse_variables(ruin.variables)
    if debug_log then log(string.format("[spawn_ruin]: vars[]='%s'", type(vars))) end

    spawn_entities(ruin.entities, center, surface, vars)
    spawn_tiles(ruin.tiles, center, surface)
    no_corpse_fade(half_size, center, surface)
  end

  if debug_log then log("[spawn_ruin]: EXIT!") end
end

---@param ruins Ruin[]
---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
spawning.spawn_random_ruin = function(ruins, half_size, center, surface)
  if debug_log then log(string.format("[spawn_random_ruin]: ruins[]='%s',half_size[]='%s',center[]='%s',surface='%s' - CALLED!", type(ruins), type(half_size), type(center), type(surface))) end
  if not ruins then
    error("Parameter 'ruins' is not set")
    return
  elseif not surface then
    error("Parameter 'surface' is not set")
    return
  elseif #ruins == 0 then
    error("Array 'ruins' is empty")
  end

  assert(surface.valid, string.format("surface.name='%s' is not valid", surface.name))

  --spawn a random ruin from the list
  spawning.spawn_ruin(ruins[math.random(#ruins)], half_size, center, surface)

  if debug_log then log("[spawn_random_ruin]: EXIT!") end
end

return spawning
