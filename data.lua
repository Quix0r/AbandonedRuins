local base_util = require("__core__/lualib/util")
data.raw["utility-constants"]["default"].default_other_force_color = base_util.copy(data.raw["utility-constants"]["default"].default_enemy_force_color)

data:extend({
  {
    type = "selection-tool",
    name = "AbandonedRuins-claim",
    icon = "__AbandonedRuins20__/graphics/AbandonedRuins-claim.png",
    icon_size = 64,
    small_icon = "__AbandonedRuins20__/graphics/AbandonedRuins-claim.png",
    small_icon_size = 64,
    stack_size = 1,
    select = {
      border_color = {1, 1, 1},
      mode = {"buildable-type", "not-same-force", "friend"},
      cursor_box_type = "train-visualization",
    },
    alt_select = {
      border_color = {1, 1, 1},
      mode = {"any-entity", "not-same-force", "friend"},
      cursor_box_type = "train-visualization",
    },
    always_include_tiles = true,
    flags = {"only-in-cursor", "spawnable"}
  }, {
    type = "shortcut",
    name = "AbandonedRuins-claim",
    action = "spawn-item",
    icon = "__AbandonedRuins20__/graphics/AbandonedRuins-claim-shortcut.png",
    icon_size = 32,
    small_icon = "__AbandonedRuins20__/graphics/AbandonedRuins-claim-shortcut.png",
    small_icon_size = 32,
    item_to_spawn = "AbandonedRuins-claim",
    associated_control_input = "AbandonedRuins-claim"
  }, {
    type = "custom-input",
    name = "AbandonedRuins-claim",
    key_sequence = "SHIFT + C",
    action = "spawn-item",
    item_to_spawn = "AbandonedRuins-claim"
  }
})
