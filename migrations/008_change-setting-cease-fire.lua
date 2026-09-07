local constants = require("__AbandonedRuins_updated_fork__/lua/constants")

if settings.global["ruins-enemy-not-cease-fire"] ~= nil then
  local current = settings.global["ruins-enemy-not-cease-fire"].value
  settings.global[constants.ENABLE_ENEMY_CEASE_FIRE_KEY].value = not current
  settings.global["ruins-enemy-not-cease-fire"] = nil
end
