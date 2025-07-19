local core_utils = require("__core__/lualib/util")

if storage.spawn_table ~= nil then
  -- Fully copy table over (not reference)
  storage.spawn_chances = core_utils.copy(storage.spawn_table)

  -- Delete old table
  storage.spawn_table = nil
end
