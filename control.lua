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

---Find the canonical unmirrored position for a given potentially mirrored position
---@param target_pos MapPosition
---@return MapPosition
local function locate_source(target_pos)
  local unmirrored_pos = util.copy(target_pos)
  if world_mirror_x and target_pos.x < -coord_offset then
    unmirrored_pos.x = -2*coord_offset - target_pos.x - 32
  end
  if world_mirror_y and target_pos.y < -coord_offset then
    unmirrored_pos.y = -2*coord_offset - target_pos.y - 32
  end
  return unmirrored_pos
end

---Find mirrored positions for a given unmirrored position
---@param this_pos MapPosition
---@return MapPosition[]
local function locate_targets(this_pos)
  ---@type MapPosition[]
  local mirrored_poss = {}
  local this_pos_x, this_pos_y = this_pos.x, this_pos.y
  if world_mirror_x and this_pos_x >= -coord_offset then
    mirrored_poss[#mirrored_poss+1] = {x=-2*coord_offset-this_pos_x-32, y=this_pos_y}
  end
  if world_mirror_y and this_pos_y >= -coord_offset then
    mirrored_poss[#mirrored_poss+1] = {x=this_pos_x, y=-2*coord_offset-this_pos_y-32}
  end
  if world_mirror_x and world_mirror_y and this_pos_x >= -coord_offset and this_pos_y >= -coord_offset then
    mirrored_poss[#mirrored_poss+1] = {x=-2*coord_offset-this_pos_x-32, y=-2*coord_offset-this_pos_y-32}
  end
  return mirrored_poss
end

---@type Tile[] Blank tiles to be placed
local blank_tiles = {}
for count = 0, 32*32-1 do
  -- position will be updated before placement
  blank_tiles[count] = {name= "out-of-map", position= {0, 0}}
end

---@type Tile[] New tiles to be placed
local new_tiles = {}
for count = 0, 32*32-1 do
  -- position will be updated before placement
  new_tiles[count] = {name= "", position= {0, 0}}
end

---Delete tiles, entities, decoratives in a chunk
---@param surface LuaSurface
---@param pos MapPosition
local function wipe_chunk(surface, pos)
  local tiles = {}
  local pos_x, pos_y = pos.x, pos.y
  local index = 0
  for dy = 0,31 do
    for dx = 0,31 do
      local blank_tile_position = blank_tiles[index].position
      blank_tile_position.x, blank_tile_position.y = pos_x + dx, pos_y + dy
      index = index + 1
    end
  end
  local tile_correction = false -- causes problems with deep water
  surface.set_tiles(tiles, tile_correction)

  -- destroy entities
  local entities = surface.find_entities({pos, {pos_x+32, pos_y+32}})
  for _, entity in ipairs(entities) do
    local entity_position_x, entity_position_y = entity.position.x, entity.position.y
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity_position_x >= pos_x and entity_position_x < pos_x+32 and entity_position_y >= pos_y and entity_position_y < pos_y+32 then 
      local entity_type = entity.type
      if entity_type == "character" or entity_type == "player" then
        -- need to move player to a legal place to stand or else they die
        local dest = surface.find_non_colliding_position(entity_type, pos, 0, 1)
        assert(dest) -- 0/infinite search radius should prevent this
        entity.teleport(dest)
      else
        entity.destroy()
        --TODO handle destroy failures
      end
    end
  end

  -- remove decoratives
  surface.destroy_decoratives({pos, {pos_x+32, pos_y+32}})
end

local autoplaced_prototypes = game.get_filtered_entity_prototypes{{filter="autoplace"}}
---Which names of which types can be autoplaced
---@type { [string]: { [string]: true }}
local autoplaced_types_and_names = {}
for _, prototype in pairs(autoplaced_prototypes) do
  local prototype_type = prototype.type
  autoplaced_types_and_names[prototype_type] = autoplaced_types_and_names[prototype_type] or {}
  autoplaced_types_and_names[prototype_type][prototype.name] = true
end

---Copy tiles and entities, and regenerate decoratives, to a mirror location
---@param surface LuaSurface
---@param source_pos MapPosition
---@param target_pos MapPosition
local function mirror_chunk(surface, source_pos, target_pos)
  local target_pos_x, target_pos_y = target_pos.x, target_pos.y
  local source_pos_x, source_pos_y = source_pos.x, source_pos.y
  -- which direction(s) are we mirroring?
  local mirror_x = target_pos_x ~= source_pos_x
  local mirror_y = target_pos_y ~= source_pos_y

  -- calculate target origin and direction
  local target_dx = 1
  local target_dy = 1
  if mirror_x then
    target_dx = -1
    target_pos_x = target_pos_x + 31
  end
  if mirror_y then
    target_dy = -1
    target_pos_y = target_pos_y + 31
  end

  local index = 0
  for dx = 0,31 do
    for dy = 0,31 do
      local new_tile = new_tiles[index]
      index = index + 1
      new_tile.name = surface.get_tile(source_pos_x + dx, source_pos_y + dy).name
      local new_tile_position = new_tile.position
      new_tile_position.x = target_pos_x + dx * target_dx
      new_tile_position.y = target_pos_y + dy * target_dy
    end
  end
  local tile_correction = true -- causes problems with deep water
  surface.set_tiles(new_tiles, tile_correction)

  -- clone entities
  local source_entities = surface.find_entities({source_pos, {source_pos_x+32, source_pos_y+32}})
  for _, entity in ipairs(source_entities) do
    local entity_position_x, entity_position_y = entity.position.x, entity.position.y
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity_position_x >= source_pos_x and entity_position_x < source_pos_x+32 and entity_position_y >= source_pos_y and entity_position_y < source_pos_y+32 then
      local entity_type, entity_name = entity.type, entity.name
      -- list of entity types generated on the map, not built by a player
      if autoplaced_types_and_names[entity_type] and autoplaced_types_and_names[entity_type][entity_name] then
        ---@type CliffOrientation
        local cliff_orientation
        if entity_type == "cliff" then
          cliff_orientation = entity.cliff_orientation
          if mirror_x then
            cliff_orientation = cliff_orientation:gsub("[we][ea]st",{east="west",west="east"})--[[@as CliffOrientation]]
          end
          if mirror_y then
            cliff_orientation = cliff_orientation:gsub("[ns]o[ru]th",{north="south",south="north"})--[[@as CliffOrientation]]
          end
          -- -- SO CLOSE!!
          if (mirror_x or mirror_y) and not (mirror_x and mirror_y) then
            cliff_orientation = cliff_orientation:gsub("^(%w%w%w%w%w?)%-to%-(%w%w%w%w%w?)$","%2-to-%1")--[[@as CliffOrientation]]
          end
        end
        local new_x = (entity_position_x - source_pos_x) * target_dx + target_pos_x + (mirror_x and 1 or 0)
        local new_y = (entity_position_y - source_pos_y) * target_dy + target_pos_y + (mirror_y and 1 or 0)
        -- new_entities[#new_entities+1] = surface.create_entity{
        surface.create_entity{
          name= entity_name,
          position= {
            x= new_x,
            y= new_y
          },
          direction= entity.direction,
          force= entity.force,
          -- TODO: more thorough cloning
          -- entity-type-specific parameters
          ---@diagnostic disable-next-line: assign-type-mismatch
          amount= entity_type == "resource" and entity.amount or nil,
          cliff_orientation= cliff_orientation
        }
        -- if entity_type == "cliff" then
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
  ---@type string[]
  local decorative_names = {}
  for k,v in pairs(game.decorative_prototypes) do
    if v.autoplace_specification then
      decorative_names[#decorative_names+1] = k
    end
  end
  -- apply them all to this chunk
  surface.regenerate_decorative(decorative_names, {{x=math.floor(target_pos_x/32),y=math.floor(target_pos_y/32)}})
end

---@param event EventData.on_chunk_generated
local function on_chunk_generated(event)
  if not world_mirror_x and not world_mirror_y then
    return
  end

  local surface = event.surface
  local p1 = event.area.left_top

  if (world_mirror_x and p1.x < -coord_offset) or (world_mirror_y and p1.y < -coord_offset) then
    -- target
    -- if p1.y==-coord_offset then debug("target chunk at " .. pos2s(p1)) end
    local source_pos = locate_source(p1)
    wipe_chunk(surface, p1)
    if surface.is_chunk_generated({x=math.floor(source_pos.x/32), y=math.floor(source_pos.y/32)}) then
      mirror_chunk(surface, source_pos, p1)
    else
      surface.request_to_generate_chunks(source_pos)
    end
  else
    -- source
    -- if p1.y==-coord_offset then debug("source chunk at " .. pos2s(p1)) end
    local targets = locate_targets(p1)
    for _,target_pos in ipairs(targets) do
      local target_chunk_pos = {x=math.floor(target_pos.x/32), y=math.floor(target_pos.y/32)}
      -- if p1.y==-coord_offset then debug("copying to target at " .. pos2s(target_pos)) end
      if surface.is_chunk_generated(target_chunk_pos) then
        wipe_chunk(surface, target_pos)
      end
      mirror_chunk(surface, p1, target_pos)
      surface.set_chunk_generated_status(target_chunk_pos, defines.chunk_generated_status.entities)
    end
  end
end

script.on_event(defines.events.on_chunk_generated, on_chunk_generated)