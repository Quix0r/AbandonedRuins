
return function(center) --section of rails
    local ce = game.surfaces[1].create_entity --save typing
    local fN = game.forces.neutral
    local direct = defines.direction
    ce{name = "straight-rail", position = {center.x+(-2.0),center.y+(0.0)}, direction = direct.east, force = fN}
    ce{name = "straight-rail", position = {center.x+(0.0),center.y+(0.0)}, direction = direct.east, force = fN}
    ce{name = "straight-rail", position = {center.x+(2.0),center.y+(0.0)}, direction = direct.east, force = fN}
end
