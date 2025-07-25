local constants = require("__AbandonedRuins_updated_fork__/lua/constants")
local utils = require("__AbandonedRuins_updated_fork__/lua/utilities")
local spawning = require("__AbandonedRuins_updated_fork__/lua/spawning")

-- Enable debug log by default
settings.global["ruins-enable-debug-log"].value = true
debug_log = true

---@param center MapPosition
---@param half_size number
---@param surface LuaSurface
local function draw_dimensions(center, half_size, surface)
  rendering.draw_line(
  {
    from = {center.x + 0.5, center.y},
    to = {center.x - 0.5, center.y},
    width = 2,
    color = {b = 0.5, a = 0.5},
    surface = surface
  })
  rendering.draw_line(
  {
    from = {center.x, center.y + 0.5},
    to = {center.x, center.y - 0.5},
    width = 2,
    color = {b = 0.5, a = 0.5},
    surface = surface
  })
  rendering.draw_rectangle(
  {
    left_top = {center.x - half_size, center.y - half_size},
    right_bottom  = {center.x + half_size, center.y + half_size},
    filled = false,
    width = 2,
    color = {g = 0.3, a = 0.3},
    surface = surface
  })
end

script.on_init(function()
  -- Disable normal spawning
  remote.call("AbandonedRuins", "set_spawn_ruins", false)
end)


script.on_event(defines.events.on_player_created, function(event)
  -- This stuff is all here instead of on_init because this relies on other mods' on_init,
  --  which run after the scenario on_init, but before scenario on_player_created

  -- Set up the debug surface
  local ruin_set = remote.call("AbandonedRuins", "get_current_ruin_set")
  local total_ruins_amount = #ruin_set.small + #ruin_set.medium + #ruin_set.large
  local chunk_radius = math.ceil(math.sqrt(total_ruins_amount) / 2)
  log(string.format("[on_player_created]: total_ruins_amount=%d,chunk_radius=%.2f", total_ruins_amount, chunk_radius))

  local mgs = {
    width  = chunk_radius * 2 * 32,
    height = chunk_radius * 2 * 32,
    default_enable_all_autoplace_controls = false,
    property_expression_names = {
      elevation = 10
    }
  }

  local surface = game.create_surface(constants.DEBUG_SURFACE_NAME, mgs)

  -- skip invalid surfaces
  if not surface.valid then
    log(string.format("WARNING: surface.name='%s' is not valid - EXIT!", surface.name))
    return
  end

  surface.request_to_generate_chunks({0, 0}, chunk_radius)
  surface.force_generate_chunk_requests()

  -- Spawn all ruins at once, small to big, top left to bottom right
  local x = -chunk_radius
  local y = -chunk_radius

  for size, ruin_list in pairs(ruin_set) do
    for _, ruin in pairs(ruin_list) do
      local center = utils.get_center_of_chunk({x = x, y = y})

      spawning.spawn_ruin(ruin, utils.ruin_half_sizes[size], center, surface)
      draw_dimensions(center, utils.ruin_half_sizes[size], surface)

      x = x + 1
      if (x >= chunk_radius) then
        x = -chunk_radius
        y = y + 1
      end
    end
  end

  -- Enable map editor for the player
  local player = game.get_player(event.player_index)
  player.toggle_map_editor()
  game.tick_paused = false
  player.teleport({0, 0}, constants.DEBUG_SURFACE_NAME)
  player.force = "neutral"
  player.game_view_settings.show_entity_info = true
end)
