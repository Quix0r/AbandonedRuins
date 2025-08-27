--- "Class/library" for surface handling
local surfaces = {}

-- Always-excluded surfaces (intended for "internal" surfaces, don't add your planet here)
---@type table<string, boolean>
surfaces.excluded = {
  ["beltlayer"]     = true,
  ["pipelayer"]     = true,
  ["Factory floor"] = true, -- factorissimo
  ["ControlRoom"]   = true, -- mobile factory
  ["NiceFill"]      = true, -- NiceFill's hidden surface
  ["aai-signals"]   = true  -- AAI Signals' hidden surface
}

-- Returns all excluded surfaces
---@return table<string, boolean>
function surfaces.get_all_excluded()
  return surfaces.excluded
end

-- Any surface whose name contains this string will not have ruins generated on it.
---@param name string
function surfaces.exclude(name)
  if debug_log then log(string.format("[exclude]: name[]='%s',ruin_sets[]='%s' - CALLED!", type(name), type(ruin_sets))) end
  if type(name) ~= "string" then
    error(string.format("name[]='%s' is not expected type 'string'", type(name)))
  elseif surfaces.excluded[name] ~= nil then
    error(string.format("name='%s' is already added to surfaces.excluded table", name))
  end

  if debug_log then log(string.format("[exclude]: Excluding surface name='%s' ...", name)) end
  surfaces.excluded[name] = true

  if debug_log then log("[exclude]: EXIT!") end
end

-- You excluded a surface at some earlier point but you don't want it excluded anymore.
---@param name string
function surfaces.reinclude(name)
  if debug_log then log(string.format("[reinclude]: name[]='%s' - CALLED!", type(name))) end
  if type(name) ~= "string" then
    error(string.format("name[]='%s' is not expected type 'string'", type(name)))
  elseif surfaces.excluded[name] == nil then
    error(string.format("name='%s' is already removed from surfaces.excluded table", name))
  end

  if debug_log then log(string.format("[reinclude]: Reincluding surface name='%s' ...", name)) end
  surfaces.excluded[name] = nil

  if debug_log then log("[reinclude]: EXIT!") end
end

-- Checks whether given surface name is i exclusion table
---@param name string
---@return boolean Whether surface is in exclusion list
function surfaces.is_excluded(name)
  if debug_log then log(string.format("[is_excluded]: name[]='%s' - CALLED!", type(name))) end
  if type(name) ~= "string" then
    error(string.format("name[]='%s' is not expected type 'string'", type(name)))
  end

  local is_excluded = (surfaces.excluded[name] ~= nil and surfaces.excluded[name])

  if debug_log then log(string.format("[is_excluded]: is_excluded='%s' - EXIT!", is_excluded)) end
end

return surfaces
