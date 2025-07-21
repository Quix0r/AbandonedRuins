local utils = require("__AbandonedRuins_updated_fork__/lua/utilities")
local expressions = require("__AbandonedRuins_updated_fork__/lua/expression_parsing")

local spawning = {}

---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
local function no_corpse_fade(half_size, center, surface)
  if debug_log then log(string.format("[no_corpse_fade]: half_size=%d,center[]='%s',surface[]='%s' - CALLED!", half_size, type(center), type(surface))) end

  if half_size <= 0 then
    error(string.format("[no_corpse_fade]: Unexpected value half_size=%d, must be positive", half_size))
  elseif not surface.valid then
    error(string.format("[no_corpse_fade]: surface.name='%s' is not valid", surface.name))
  end

  local area = utils.area_from_center_and_half_size(half_size, center)
  if debug_log then log(string.format("[no_corpse_fade]: area[]='%s',surface.name='%s'", type(area), surface.name)) end

  for _, entity in pairs(surface.find_entities_filtered({area = area, type={"corpse", "rail-remnants"}})) do
    if debug_log then log(string.format("[no_corpse_fade]: entity.type='%s',entity.name='%s',entity.valid='%s' - Setting corpse_expires=false ...", entity.type, entity.name, entity.valid)) end
    entity.corpse_expires = false
  end

  if debug_log then log("[no_corpse_fade]: EXIT!") end
end

---@param entity EntityExpression|string
---@param relative_position MapPosition
---@param center MapPosition
---@param surface LuaSurface
---@param extra_options EntityOptions
---@param vars VariableValues
local function spawn_entity(entity, relative_position, center, surface, extra_options, vars)
  if debug_log then
    log(string.format(
      "[spawn_entity]: entity[]='%s',relative_position[]='%s',center[]='%s',surface[]='%s',extra_options[]='%s',vars[]='%s' - CALLED!",
      type(entity),
      type(relative_position),
      type(center),
      type(surface),
      type(extra_options),
      type(vars)
    ))
  end
  if not surface.valid then
    error(string.format("[spawn_entity]: surface.name='%s' is not valid", surface.name))
  end

  local entity_name = expressions.entity(entity, vars)
  if debug_log then log(string.format("[spawn_entity]: entity_name='%s',entity.name='%s'", entity_name, entity.name)) end

  if _G["prototypes"].entity[entity_name] == nil then
    log(string.format("[spawn_entity]: entity_name='%s' does not exist!", entity_name))
    return
  end

  local force = extra_options.force or "neutral"
  if debug_log then log(string.format("[spawn_entity]: force='%s' - BEFORE!", force)) end
  if force == "enemy" then
    force = utils.get_enemy_force()
  end
  if debug_log then log(string.format("[spawn_entity]: force='%s' - AFTER!", force)) end

  local recipe
  if debug_log then log(string.format("[spawn_entity]: extra_options.recipe='%s'", extra_options.recipe)) end
  if type(extra_options.recipe) == "string" then
    if not _G["prototypes"].recipe[extra_options.recipe] then
      log(string.format("[spawn_entity]: extra_options.recipe='%s'' does not exist!", extra_options.recipe))
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
  if debug_log then log(string.format("[spawn_entity]: Entity created: e.valid='%s'", e.valid)) end

  if debug_log then log(string.format("[spawn_entity]: extra_options.dmg[]='%s'", type(extra_options.dmg))) end
  if extra_options.dmg then
    utils.safe_damage(e, extra_options.dmg, expressions.number(extra_options.dmg.dmg, vars))
  end

  if debug_log then log(string.format("[spawn_entity]: extra_options.dead[]='%s'", type(extra_options.dead))) end
  if extra_options.dead then
    utils.safe_die(e, extra_options.dead)
  end

  if debug_log then log(string.format("[spawn_entity]: extra_options.fluids[]='%s'", type(extra_options.fluids))) end
  if extra_options.fluids then
    local fluids = {}
    if debug_log then log(string.format("[spawn_entity]: Parsing %d fluids ...", #extra_options.fluids)) end
    for name, amount_expression in pairs(extra_options.fluids) do
      if debug_log then log(string.format("[spawn_entity]: name='%s',amount_expression='%s',vars[]='%s'", name, amount_expression, type(vars))) end
      local amount = expressions.number(amount_expression, vars)

      if debug_log then log(string.format("[spawn_entity]: amount=%d", amount)) end
      if amount > 0 then
        if debug_log then log(string.format("[spawn_entity]: Adding fluid name='%s',amount=%d ...", name, amount)) end
        fluids[name] = amount
      end
    end

    if debug_log then log(string.format("[spawn_entity]: fluids()=%d", table_size(fluids))) end
    if table_size(fluids) > 0 then
      if debug_log then log(string.format("[spawn_entity]: Safely inserting %d fluids ...", table_size(fluids))) end
      utils.safe_insert_fluid(e, fluids)
    end
  end

  if debug_log then log(string.format("[spawn_entity]: extra_optios.items[]='%s'", type(extra_options.items))) end
  if extra_options.items then
    local items = {}

    for name, count_expression in pairs(extra_options.items) do
      if debug_log then log(string.format("[spawn_entity]: name='%s',count_expression='%s'", name, count_expression)) end
      if not _G["prototypes"].item[name] then
        log(string.format("[spawn_entity]: item '%s' does not exist!", name))
      else
        local count = expressions.number(count_expression, vars)
        if debug_log then log(string.format("[spawn_entity]: count=%d", count)) end
        if count > 0 then
          if debug_log then log(string.format("[spawn_entity]: Adding item name='%s',count=%d ...", name, count)) end
          items[name] = count
        end
      end
    end

    if debug_log then log(string.format("[spawn_entity]: Found %d items.", #items)) end
    if table_size(items) > 0 then
      if debug_log then log(string.format("[spawn_entity]: Safely inserting %d items ...", table_size(items))) end
      utils.safe_insert(e, items)
    end
  end

  if debug_log then log("[spawn_entity]: EXIT!") end
end

---@param entities RuinEntity[]
---@param center MapPosition
---@param surface LuaSurface
---@param vars VariableValues
local function spawn_entities(entities, center, surface, vars)
  if debug_log then log(string.format("[spawn_entities]: entities[]='%s',center[]='%s',surface[]='%s',vars[]='%s' - CALLED!", type(entities), type(center), type(surface), type(vars))) end
  if table_size(entities) == 0 then
    error(string.format("[spawn_entities]: No entities to spawn on surface.name='%s' - EXIT!", surface.name))
  elseif not surface.valid then
    error(string.format("[spawn_entities]: surface.name='%s' is not valid", surface.name))
  end

  if debug_log then log(string.format("[spawn_entities]: Spawning %d entities on surface.name='%s' ...", #entities, surface.name)) end
  for _, entity_info in pairs(entities) do
    spawn_entity(entity_info[1], entity_info[2], center, surface, entity_info[3] or {}, vars)
  end

  if debug_log then log("[spawn_entities]: EXIT!") end
end

---@param ruin_tiles RuinTile[]
---@param center MapPosition
---@param surface LuaSurface
local function spawn_tiles(ruin_tiles, center, surface)
  if debug_log then log(string.format("[spawn_tiles]: ruin_tiles[]='%s',center[]='%s',surface[]='%s' - CALLED!", type(ruin_tiles), type(center), type(surface))) end
  if table_size(ruin_tiles) == 0 then
    error("[spawn_tiles]: Cannot spawn empty run_tiles!")
  elseif not surface.valid then
    error(string.format("[spawn_tiles]: surface.name='%s' is not valid", surface.name))
  end

  local tiles = {}
  local count = 0

  if debug_log then log(string.format("[spawn_tiles]: Spawning %d tiles on surface.name='%s' ...", #ruin_tiles, surface.name)) end
  for _, tile_spec in pairs(ruin_tiles) do
    if prototypes.tile[tile_spec[1]] then
      if debug_log then log(string.format("[spawn_tiles]: tile_spec[1]='%s',center.x=%d,center.y=%d,tile_spec[2].x=%d,tile_spec[2].y=%d", tile_spec[1], center.x, center.y, tile_spec[2].x, tile_spec[2].y)) end
      count = count + 1
      tiles[count] = {
        name     = tile_spec[1],
        position = {center.x + tile_spec[2].x, center.y + tile_spec[2].y}
      }
    else
      log(string.format("[spawn_tiles]: Tile '%s' does not exist!", tile_spec[1]))
    end
  end

  if debug_log then log(string.format("[spawn_tiles]: Setting %d tiles for surface.name='%s' ...", #tiles, surface.name)) end
  surface.set_tiles(
    tiles,
    true, -- correct_tiles,                Default: true
    true, -- remove_colliding_entities,    Default: true
    true, -- remove_colliding_decoratives, Default: true
    true) -- raise_event,                  Default: false

  if debug_log then log("[spawn_tiles]: EXIT!") end
end

-- Evaluates the values of the variables.
---@param variables Variable[]
---@return VariableValues
local function parse_variables(variables)
  if debug_log then log(string.format("[parse_variables]: variables[]='%s' - CALLED!", type(variables))) end
  if table_size(variables) == 0 then
    error("[parse_variables]: Not parsing an empty variables list!")
  end

  local parsed = {}

  if debug_log then log(string.format("[parse_variables]: Parsing %d variables ...", #variables)) end
  for _, var in pairs(variables) do
    if debug_log then log(string.format("[parse_variables]: var.type='%s',var.name='%s',var.value[]='%s'", var.type, var.name, type(var.value))) end
    if var.type == "entity-expression" then
      if debug_log then log(string.format("[parse_variables]: Parsing entity expression for var.name='%s',var.value[]='%s' ...", var.name, type(var.value))) end
      parsed[var.name] = expressions.entity(var.value)
    elseif var.type == "number-expression" then
      if debug_log then log(string.format("[parse_variables]: Parsing number expression for var.name='%s',var.value[]='%s' ...", var.name, type(var.value))) end
      parsed[var.name] = expressions.number(var.value)
    else
      error(string.format("[parse_variables]: Unrecognized variable type: '%s'", var.type))
    end
  end

  if debug_log then log(string.format("[parse_variables]: parsed()=%d - EXIT!", table_size(parsed))) end
  return parsed
end

---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
---@return boolean @Whether the area is clear and ruins can be spawned
local function clear_area(half_size, center, surface)
  if debug_log then log(string.format("[clear_area]: half_size[]='%s',center[]='%s',surface[]='%s' - CALLED!", type(half_size), type(center), type(surface))) end
  if half_size <= 0 then
    error(string.format("[clear_area]: Unexpected value half_size=%d, must be positive", half_size))
  elseif not surface.valid then
    error(string.format("[clear_area]: surface.name='%s' is not valid", surface.name))
  end

  local area = utils.area_from_center_and_half_size(half_size, center)

  -- exclude tiles that we shouldn't spawn on
  if surface.count_tiles_filtered{ area = area, limit = 1, collision_mask = { item = true, object = true, water_tile = true } } == 1 then
    if debug_log then log(string.format("[clear_area]: surface.name='%s' has excluded tile - EXIT!", surface.name)) end
    return false
  end

  for _, entity in pairs(surface.find_entities_filtered({area = area, type = {"resource"}, invert = true})) do
    if debug_log then log(string.format("[clear_area]: entity.type='%s',entity.name='%s',entity.valid='%s'", entity.type, entity.name, entity.valid)) end
    if (entity.valid and entity.type ~= "tree") or math.random() < (half_size / 14) then
      if debug_log then log(string.format("[clear_area]: Destroying entity.name='%s' ...", entity.name)) end
      entity.destroy({do_cliff_correction = true, raise_destroy = true})
    end
  end

  if debug_log then log("[clear_area]: Area is clear for ruin! - EXIT!") end
  return true
end

---@param ruin Ruin
---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
spawning.spawn_ruin = function(ruin, half_size, center, surface)
  if debug_log then log(string.format("[spawn_ruin]: ruin[]='%s',half_size[]='%s',center[]='%s',surface[]='%s' - CALLED!", type(ruin), type(half_size), type(center), type(surface))) end
  if half_size <= 0 then
    error(string.format("[spawn_ruin]: Unexpected value half_size=%d, must be positive", half_size))
  elseif not surface.valid then
    error(string.format("[spawn_ruin]: surface.name='%s' is not valid", surface.name))
  end

  if clear_area(half_size, center, surface) then
    local variables = {}
    if debug_log then log(string.format("[spawn_ruin]: ruin.variables[]='%s'", type(ruin.variables))) end
    if ruin.variables ~= nil then
      variables = parse_variables(ruin.variables)
    end
    if debug_log then log(string.format("[spawn_ruin]: variables[%s]()=%d,ruin.entities[]='%s'", type(variables), #variables, type(ruin.entities))) end

    if ruin.entities == nil then
      game.print(string.format("Won't spawn a ruin at '%s' as no entities are included. Please report this to your ruin-set developer!", surface.name))
      return
    end
    spawn_entities(ruin.entities, center, surface, variables)

    if debug_log then log(string.format("[spawn_ruin]: ruin.tiles[]='%s'", type(ruin.tiles))) end
    if ruin.tiles ~= nil then
      spawn_tiles(ruin.tiles, center, surface)
    end
    no_corpse_fade(half_size, center, surface)
  end

  if debug_log then log("[spawn_ruin]: EXIT!") end
end

---@param ruins Ruin[]
---@param half_size number
---@param center MapPosition
---@param surface LuaSurface
spawning.spawn_random_ruin = function(ruins, half_size, center, surface)
  if debug_log then log(string.format("[spawn_random_ruin]: ruins[]='%s',half_size[]='%s',center[]='%s',surface[]='%s' - CALLED!", type(ruins), type(half_size), type(center), type(surface))) end
  if table_size(ruins) == 0 then
    error("[spawn_random_ruin]: Array 'ruins' is empty")
  elseif not surface.valid then
    error(string.format("[spawn_random_ruin]: surface.name='%s' is not valid", surface.name))
  end

  --spawn a random ruin from the list
  spawning.spawn_ruin(ruins[math.random(table_size(ruins))], half_size, center, surface)

  if debug_log then log("[spawn_random_ruin]: EXIT!") end
end

return spawning
