local constants = require("constants")
local utils = require("utilities")
local surfaces = require("surfaces")

--- "Class/library" for ruin queue
local queue = {}

-- Ruin queue
---@type RuinQueueItem[]
queue.ruins = {}

-- This delays ruin spawning to the next n-th tick. This is done because on_chunk_generated may be called before other mods have a chance to do the remote call for the ruin set:
-- ThisMod_onInit -> SomeOtherMod_generatesChunks -> ThisMod_onChunkGenerated (ruin is queued) -> RuinPack_onInit (ruin set remote call) -> ThisMod_OnTick (ruin set is used)
---@param tick uint
---@param ruin RuinQueueItem
function queue.add_ruin(tick, ruin)
  if debug_log then log(string.format("[add_ruin]: tick[]='%s',ruin[]='%s' - CALLED!", type(tick), type(ruin))) end
  if ruin.surface.name == constants.DEBUG_SURFACE_NAME then
    error(string.format("Debug surface '%s' has no random ruin spawning.", ruin.surface.name))
  elseif utils.str_contains_any_from_table(ruin.surface.name, surfaces.get_all()) then
    error(string.format("ruin.surface.name='%s' is excluded - EXIT!", ruin.surface.name))
  end

  if debug_log then log(string.format("[add_ruin]: Queueing ruin[]='%s' ...", type(ruin))) end
  queue.ruins[#queue.ruins] = ruin

  if debug_log then log("[add_ruin]: EXIT!") end
end

--- Get all ruins
---@return RuinQueueItem[]
function queue.get_ruins()
  return queue.ruins
end

--- Resets queue for ruins
function queue.reset_ruins()
  queue.ruins = {}
end

return queue
