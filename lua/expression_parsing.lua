local parsing = {}

-- extend table 1 with table 2
-- no safety checks, very naive
---@param table1 table table to extend
---@param table2 table
local function extend(table1, table2)
  for key, value in pairs(table2) do
    log(string.format("key='%s',value[]='%s'", key, type(value)))
    table1[key] = value
  end
end

local common_expressions =
{
  ---@param t NumberExpression|EntityExpression
  ---@param vars VariableValues
  ---@return number|string
  ["variable"] = function(t, vars) return vars[t.name] end,
  ---@param t NumberExpression|EntityExpression
  ---@param vars VariableValues
  ---@return number|string
  ["random-variable"] = function(t, vars) return vars[t.variables[math.random(#t.variables)]] end,
  ---@param t NumberExpression|EntityExpression
  ---@return number|string
  ["random-from-list"] = function(t)
    assert(type(t.list) == "table", "Expression random-from-list: list expected a table, got " .. type(t.list))
    return t.list[math.random(#t.list)]
  end
}

local number_expressions =
{
  ---@param t NumberExpression
  ---@return number
  ["random"] = function(t) return math.random(t.min, t.max) end
}
extend(number_expressions, common_expressions)


local entity_expressions =
{
  ---@param t EntityExpression
  ---@return string
  ["random-of-entity-type"] = function(t)
    assert(type(t.entity_type) == "string", "Expression random-of-entity-type: entity_type expected a string, got " .. type(t.entity_type))
    ---@type string[]
    local entities = {}

    for entity in pairs(prototypes.get_entity_filtered({{filter = "type", type = t.entity_type}})) do
      entities[#entities + 1] = entity
    end
    return entities[math.random(#entities)]
  end
}
extend(entity_expressions, common_expressions)


---@param t NumberExpression|number
---@param vars VariableValues
---@return number
parsing.number = function(t, vars)
  if debug_log then log(string.format("[number]: t[]='%s',vars[]='%s' - CALLED!", type(t), type(vars))) end
  if type(t) == "table" then
    if debug_log then log(string.format("[number]: Parsing t.type='%s',t.name='%s' ...", t.type, t.name)) end
    if number_expressions[t.type] == "nil" then
      error("Unrecognized number-expression type: " .. t.type)
    end

    local ret = number_expressions[t.type](t, vars)

    if debug_log then log(string.format("[number]: ret[]='%s'", type(ret))) end
    assert(type(ret) == "number", "String expression did not return a number. Expression was " .. serpent.line(t))

    if debug_log then log(string.format("[number]: ret=%.2f - EXIT!", ret)) end
    return ret
  elseif type(t) == "number" then
    if debug_log then log(string.format("[number]: t=%.2f - EXIT!", t)) end
    return t
  end
  error("Received something that is not a number or table as number-expression")
end

---@param t EntityExpression|string
---@param vars VariableValues
---@return string
parsing.entity = function(t, vars)
  if debug_log then log(string.format("[entity]: t[]='%s',vars[]='%s' - CALLED!", type(t), type(vars))) end
  if type(t) == "table" then
    if debug_log then log(string.format("[entity]: Parsing t.type='%s',t.name='%s' ...", t.type, t.name)) end
    if entity_expressions[t.type] == "nil" then
      error("Unrecognized entity-expression type: " .. t.type)
    end

    local ret = entity_expressions[t.type](t, vars)

    if debug_log then log(string.format("[entity]: ret[]='%s'", type(ret))) end
    assert(type(ret) == "string", "Entity expression did not return a string. Expression was " .. serpent.line(t))

    if debug_log then log(string.format("[entity]: ret='%s' - EXIT!", ret)) end
    return ret
  elseif type(t) == "string" then
    if debug_log then log(string.format("[entity]: t='%s' - EXIT!", t)) end
    return t
  end
  error("Received something that is not an entity or table as entity-expression")
end

return parsing
