--- Where a chunk's reflection lives, with no game attached. Everything that touches a
--- surface stays in control.lua, so these can be tested without one.
---
--- A mirror line is a tile coordinate: `lines.x` is the vertical line, `lines.y` the
--- horizontal one, and both fall on chunk boundaries. Everything at or beyond a line is a
--- master and is copied; everything before it is a slave and is overwritten.
---
--- A chunk's left-top corner reflects to `2*line - corner - 32`. The extra 32 is the
--- chunk's own width, since reflecting a span swaps which end its corner is. Tile by tile
--- that works out as `x -> 2*line - 1 - x`, so the line sits exactly on the boundary
--- between the tiles either side of it rather than through the middle of one.
local mirror = {}

---The left-top corner of the chunk a slave chunk copies from.
---@param slave {x:number, y:number} left-top corner of the slave chunk
---@param mirror_x boolean
---@param mirror_y boolean
---@param lines {x:number, y:number} where the mirror lines sit, in tiles
---@return {x:number, y:number}
function mirror.locate_master(slave, mirror_x, mirror_y, lines)
  local master = { x = slave.x, y = slave.y }
  if mirror_x and slave.x < lines.x then
    master.x = 2 * lines.x - slave.x - 32
  end
  if mirror_y and slave.y < lines.y then
    master.y = 2 * lines.y - slave.y - 32
  end
  return master
end

---The left-top corners of every chunk a master chunk copies to. One for each axis being
---mirrored, and a third diagonally opposite when both are.
---@param master {x:number, y:number} left-top corner of the master chunk
---@param mirror_x boolean
---@param mirror_y boolean
---@param lines {x:number, y:number}
---@return {x:number, y:number}[]
function mirror.locate_slaves(master, mirror_x, mirror_y, lines)
  local slaves = {}
  local reflected_x = 2 * lines.x - master.x - 32
  local reflected_y = 2 * lines.y - master.y - 32
  local past_x = master.x >= lines.x
  local past_y = master.y >= lines.y
  if mirror_x and past_x then
    slaves[#slaves + 1] = { x = reflected_x, y = master.y }
  end
  if mirror_y and past_y then
    slaves[#slaves + 1] = { x = master.x, y = reflected_y }
  end
  if mirror_x and mirror_y and past_x and past_y then
    slaves[#slaves + 1] = { x = reflected_x, y = reflected_y }
  end
  return slaves
end

---Is this chunk one that gets overwritten rather than copied?
---@param corner {x:number, y:number}
---@param mirror_x boolean
---@param mirror_y boolean
---@param lines {x:number, y:number}
---@return boolean
function mirror.is_slave(corner, mirror_x, mirror_y, lines)
  return (mirror_x and corner.x < lines.x)
      or (mirror_y and corner.y < lines.y)
end

return mirror
