-- Our whole table for constants
local constants = {
  -- Configuration key for current ruin set
  ---@type string
  CURRENT_RUIN_SET_KEY = "current-ruin-set",

  -- Configuration key for enabling debug log
  ---@type string
  ENABLE_DEBUG_LOG_KEY = "ruins-enable-debug-log",

  -- Key for distance between two spawn ticks
  ---@type uint
  SPAWN_TICK_DISTANCE_KEY = "ruins-spawn-tick-distance",

  -- Debug surface name
  ---@type string
  DEBUG_SURFACE_NAME = "debug-ruins",

  -- None (no ruin-set selected)
  ---@type string
  NONE = "__none__"
}

return constants
