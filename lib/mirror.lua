--- Where a chunk's reflection lives, with no game attached. Everything that touches a
--- surface stays in control.lua, so these can be tested without one.
---
--- The mirror lines sit `offset` chunks from the origin, at x = -offset*32 and
--- y = -offset*32. Everything at or above a line is a master and is copied; everything
--- below is a slave and is overwritten. A chunk's left-top corner reflects to
--- `-2*offset - corner - 32`: the extra 32 is the chunk's own width, since reflecting a
--- span swaps which end its corner is.
local mirror = {}

---The left-top corner of the chunk a slave chunk copies from.
---@param slave {x:number, y:number} left-top corner of the slave chunk
---@param mirror_x boolean
---@param mirror_y boolean
---@param coord_offset number distance from the origin to the mirror lines, in tiles
---@return {x:number, y:number}
function mirror.locate_master(slave, mirror_x, mirror_y, coord_offset)
  local master = { x = slave.x, y = slave.y }
  if mirror_x and slave.x < -coord_offset then
    master.x = -2 * coord_offset - slave.x - 32
  end
  if mirror_y and slave.y < -coord_offset then
    master.y = -2 * coord_offset - slave.y - 32
  end
  return master
end

---The left-top corners of every chunk a master chunk copies to. One for each axis being
---mirrored, and a third diagonally opposite when both are.
---@param master {x:number, y:number} left-top corner of the master chunk
---@param mirror_x boolean
---@param mirror_y boolean
---@param coord_offset number
---@return {x:number, y:number}[]
function mirror.locate_slaves(master, mirror_x, mirror_y, coord_offset)
  local slaves = {}
  local reflected_x = -2 * coord_offset - master.x - 32
  local reflected_y = -2 * coord_offset - master.y - 32
  local past_x = master.x >= -coord_offset
  local past_y = master.y >= -coord_offset
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
---@param coord_offset number
---@return boolean
function mirror.is_slave(corner, mirror_x, mirror_y, coord_offset)
  return (mirror_x and corner.x < -coord_offset)
      or (mirror_y and corner.y < -coord_offset)
end

return mirror
