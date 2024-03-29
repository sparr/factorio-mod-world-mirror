-- local function debug(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG: " .. serpent.line(...,{comment=false}))
--   end
-- end

-- local function pos2s(pos)
--   return "(" .. pos.x .. "," .. pos.y .. ")"
-- end

local world_mirror_x = settings.global['world-mirror-x'].value
local world_mirror_y = settings.global['world-mirror-y'].value
local chunk_offset = settings.global['world-mirror-chunk-offset'].value
local coord_offset = chunk_offset * 32

local function locate_master(slave_pos)
  local master = {x=slave_pos.x, y=slave_pos.y}
  if world_mirror_x and slave_pos.x < -coord_offset then
    master.x = -2*coord_offset - slave_pos.x - 32
  end
  if world_mirror_y and slave_pos.y < -coord_offset then
    master.y = -2*coord_offset - slave_pos.y - 32
  end
  return master
end

local function locate_slaves(master_pos)
  local slaves = {}
  if world_mirror_x and master_pos.x >= -coord_offset then
    slaves[#slaves+1] = {x=-2*coord_offset-master_pos.x-32, y=master_pos.y}
  end
  if world_mirror_y and master_pos.y >= -coord_offset then
    slaves[#slaves+1] = {x=master_pos.x, y=-2*coord_offset-master_pos.y-32}
  end
  if world_mirror_x and world_mirror_y and master_pos.x >= -coord_offset and master_pos.y >= -coord_offset then
    slaves[#slaves+1] = {x=-2*coord_offset-master_pos.x-32, y=-2*coord_offset-master_pos.y-32}
  end
  return slaves
end

local function wipe_chunk(surface, pos)
  -- blank tiles
  local tiles = {}
  for dx = 0,31 do
    for dy = 0,31 do
      tiles[#tiles+1] = {name= "out-of-map", position= {x= pos.x+dx, y= pos.y+dy}}
    end
  end
  local tile_correction = false -- causes problems with deep water
  surface.set_tiles(tiles, tile_correction)

  -- destroy entities
  local entities = surface.find_entities({pos, {pos.x+32, pos.y+32}})
  for _, entity in ipairs(entities) do
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity.position.x >= pos.x and entity.position.x < pos.x+32 and entity.position.y >= pos.y and entity.position.y < pos.y+32 then 
      if entity.type == "character" or entity.type == "player" then
        -- need to move player to a legal place to stand or else they die
        local dest = surface.find_non_colliding_position(entity.type, pos, 0, 1)
        entity.teleport(dest)
      else
        entity.destroy()
        --TODO handle destroy failures
      end
    end
  end

  -- remove decoratives
  surface.destroy_decoratives({pos, {pos.x+32, pos.y+32}})
end

local function mirror_chunk(surface, master_pos, slave_pos)
  -- which direction(s) are we mirroring?
  local mirror_x = slave_pos.x ~= master_pos.x
  local mirror_y = slave_pos.y ~= master_pos.y

  -- calculate slave origin and direction
  local slave_dx = 1
  local slave_dy = 1
  if mirror_x then
    slave_dx = -1
    slave_pos.x = slave_pos.x + 31
  end
  if mirror_y then
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
  local tile_correction = true -- causes problems with deep water
  surface.set_tiles(tiles, tile_correction)

  -- clone entities
  local master_entities = surface.find_entities({master_pos, {master_pos.x+32, master_pos.y+32}})
  -- local new_entities = {}
  for _, entity in ipairs(master_entities) do
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity.position.x >= master_pos.x and entity.position.x < master_pos.x+32 and entity.position.y >= master_pos.y and entity.position.y < master_pos.y+32 then 
      if entity.type == "fish" or
         entity.type == "tree" or
         entity.type == "unit" or
         entity.type == "cliff" or
         entity.type == "resource" or
         entity.type == "unit-spawner" or
         entity.type == "simple-entity" or
         ( entity.type == "turret" and entity.prototype.subgroup.name == "enemies" ) or
         false then -- makes above lines more diff-friendly
        local cliff_orientation
        if entity.type == "cliff" then
          cliff_orientation = entity.cliff_orientation
          if mirror_x then
            cliff_orientation = cliff_orientation:gsub("[we][ea]st",{east="west",west="east"})
          end
          if mirror_y then
            cliff_orientation = cliff_orientation:gsub("[ns]o[ru]th",{north="south",south="north"})
          end
          -- -- SO CLOSE!!
          if (mirror_x or mirror_y) and not (mirror_x and mirror_y) then
            cliff_orientation = cliff_orientation:gsub("^(%w%w%w%w%w?)%-to%-(%w%w%w%w%w?)$","%2-to-%1")
          end
        end
        local new_x = (entity.position.x - master_pos.x) * slave_dx + slave_pos.x + (mirror_x and 1 or 0)
        local new_y = (entity.position.y - master_pos.y) * slave_dy + slave_pos.y + (mirror_y and 1 or 0)
        -- new_entities[#new_entities+1] = surface.create_entity{
        surface.create_entity{
          name= entity.name,
          position= {
            x= new_x,
            y= new_y
          },
          direction= entity.direction,
          force= entity.force,
          -- TODO: more thorough cloning
          -- entity-type-specific parameters
          amount= entity.type == "resource" and entity.amount or nil,
          cliff_orientation= cliff_orientation
        }
        -- if entity.type == "cliff" then
        --   debug("" .. new_x .. "," .. new_y .. " " .. entity.cliff_orientation .. "->" .. cliff_orientation)
        -- end
      end
    end
  end

  -- -- in progress efforts to resolve cliff problems
  -- for _, entity in ipairs(new_entities) do
  --   entity.update_connections() -- to fix cliff connections
  -- end

  --TODO clone decoratives
  -- temp solution is to just regenerate new decoratives instead
  -- get a list of all known autoplace-able decorative names
  local decorative_names = {}
  for k,v in pairs(game.decorative_prototypes) do
    if v.autoplace_specification then
      decorative_names[#decorative_names+1] = k
    end
  end
  -- apply them all to this chunk
  surface.regenerate_decorative(decorative_names, {{x=math.floor(slave_pos.x/32),y=math.floor(slave_pos.y/32)}})
end

local function on_chunk_generated(event)
  if not world_mirror_x and not world_mirror_y then
    return
  end

  local surface = event.surface
  local p1 = event.area.left_top

  if (world_mirror_x and p1.x < -coord_offset) or (world_mirror_y and p1.y < -coord_offset) then
    -- slave
    -- if p1.y==-coord_offset then debug("slave chunk at " .. pos2s(p1)) end
    local master_pos = locate_master(p1)
    wipe_chunk(surface, p1)
    if surface.is_chunk_generated({x=math.floor(master_pos.x/32), y=math.floor(master_pos.y/32)}) then
      mirror_chunk(surface, master_pos, p1)
    else
      surface.request_to_generate_chunks(master_pos)
    end
  else
    -- master
    -- if p1.y==-coord_offset then debug("master chunk at " .. pos2s(p1)) end
    local slaves = locate_slaves(p1)
    for _,slave_pos in ipairs(slaves) do
      local slave_chunk_pos = {x=math.floor(slave_pos.x/32), y=math.floor(slave_pos.y/32)}
      -- if p1.y==-coord_offset then debug("copying to slave at " .. pos2s(slave_pos)) end
      if surface.is_chunk_generated(slave_chunk_pos) then
        wipe_chunk(surface, slave_pos)
      end
      mirror_chunk(surface, p1, slave_pos)
      surface.set_chunk_generated_status(slave_chunk_pos, defines.chunk_generated_status.entities)
    end
  end
end

script.on_event(defines.events.on_chunk_generated, on_chunk_generated)