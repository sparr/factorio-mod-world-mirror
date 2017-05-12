local function debug(...)
  if game and game.players[1] then
    game.players[1].print("DEBUG: " .. serpent.line(...,{comment=false}))
  end
end

local function pos2s(pos)
  return "(" .. pos.x .. "," .. pos.y .. ")"
end

local world_mirror_x = settings.global['world-mirror-x'].value
local world_mirror_y = settings.global['world-mirror-y'].value

local function locate_master(slave_pos)
  local master = {x=slave_pos.x, y=slave_pos.y}
  if world_mirror_x and slave_pos.x < 0 then
    master.x = -slave_pos.x - 32
  end
  if world_mirror_y and slave_pos.y < 0 then
    master.y = -slave_pos.y - 32
  end
  return master
end

local function locate_slaves(master_pos)
  local slaves = {}
  if world_mirror_x and master_pos.x >= 0 then
    slaves[#slaves+1] = {x=-master_pos.x-32, y=master_pos.y}
  end
  if world_mirror_y and master_pos.y >= 0 then
    slaves[#slaves+1] = {x=master_pos.x, y=-master_pos.y-32}
  end
  if world_mirror_x and world_mirror_y and master_pos.x >= 0 and master_pos.y >= 0 then
    slaves[#slaves+1] = {x=-master_pos.x-32, y=-master_pos.y-32}
  end
  return slaves
end

local function wipe_chunk(surface, pos)
  -- destroy entities
  local entities = surface.find_entities({pos, {pos.x+32, pos.y+32}})
  for _, entity in ipairs(entities) do
    if entity.type == "character" or entity.type == "player" then
      -- need to move player to a legal place to stand or else they die
      local dest = surface.find_non_colliding_position(entity.type, pos, 0, 1)
      entity.teleport({x=1,y=1})
    else
      entity.destroy()
      --TODO handle destroy failures
    end
  end

  -- blank tiles
  local tiles = {}
  for dx = 0,31 do
    for dy = 0,31 do
      tiles[#tiles+1] = {name= "out-of-map", position= {x= pos.x+dx, y= pos.y+dy}}
    end
  end
  surface.set_tiles(tiles)

  -- remove decoratives
  surface.destroy_decoratives({pos, {pos.x+32, pos.y+32}})
end

local function mirror_chunk(surface, master_pos, slave_pos)
  -- calculate slave origin and direction
  local slave_dx = 1
  local slave_dy = 1
  if slave_pos.x < master_pos.x then
    slave_dx = -1
    slave_pos.x = slave_pos.x + 31
  end
  if slave_pos.y < master_pos.y then
    slave_dy = -1
    slave_pos.y = slave_pos.y + 31
  end

  -- clone tiles
  local tiles = {}
  for dx = 0,31 do
    for dy = 0,31 do
      local tilename = surface.get_tile(master_pos.x + dx, master_pos.y + dy).name
      tiles[#tiles+1] = {name= tilename, position= {x= slave_pos.x + dx*slave_dx, y= slave_pos.y + dy*slave_dy}}
    end
  end
  surface.set_tiles(tiles)

  -- clone entities
  local master_entities = surface.find_entities({master_pos, {master_pos.x+32, master_pos.y+32}})
  for _, entity in ipairs(master_entities) do
    if entity.position.x ~= master_pos.x+32 and entity.position.y ~= master_pos.y+32 then
      if entity.type ~= "character" and entity.type ~= "player" then
        local amount = entity.type == "resource" and entity.amount or nil
        surface.create_entity{
          name= entity.name,
          position= {
            x= (entity.position.x - master_pos.x) * slave_dx + slave_pos.x + (master_pos.x > slave_pos.x and 1 or 0),
            y= (entity.position.y - master_pos.y) * slave_dy + slave_pos.y + (master_pos.y > slave_pos.y and 1 or 0)
          },
          direction= entity.direction,
          force= entity.force,
          -- TODO: more thorough cloning
          -- type-specific parameters
          amount= amount,
        }
      end
    end
  end

  --TODO clone decoratives
end

local function on_chunk_generated(event)
  if not world_mirror_x and not world_mirror_y then
    return
  end

  local surface = event.surface
  local p1 = event.area.left_top

  if (world_mirror_x and p1.x < 0) or (world_mirror_y and p1.y < 0) then
    -- slave
    if p1.y==0 then debug("slave chunk at " .. pos2s(p1)) end
    local master_pos = locate_master(p1)
    wipe_chunk(surface, p1)
    if surface.is_chunk_generated({x=math.floor(master_pos.x/32), y=math.floor(master_pos.y/32)}) then
      mirror_chunk(surface, master_pos, p1)
    else
      surface.request_to_generate_chunks(master_pos)
    end
  else
    -- master
    if p1.y==0 then debug("master chunk at " .. pos2s(p1)) end
    local slaves = locate_slaves(p1)
    for _,slave_pos in ipairs(slaves) do
      if p1.y==0 then debug("copying to slave at " .. pos2s(slave_pos)) end
      if surface.is_chunk_generated({x=math.floor(slave_pos.x/32), y=math.floor(slave_pos.y/32)}) then
        wipe_chunk(surface, slave_pos)
      end
      mirror_chunk(surface, p1, slave_pos)
      surface.set_chunk_generated_status(slave_pos, defines.chunk_generated_status.entities)
    end
  end
end


script.on_event(defines.events.on_chunk_generated, on_chunk_generated)