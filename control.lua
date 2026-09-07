local mirror = require("lib.mirror")

-- local function debug(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG: " .. serpent.line(...,{comment=false}))
--   end
-- end

-- local function pos2s(pos)
--   return "(" .. pos.x .. "," .. pos.y .. ")"
-- end

---The mod's settings, read where they are used rather than once when the file loads.
---Loading them once meant changing an axis or the offset during a game did nothing until
---the save was reloaded -- and worse, left a client who joined after the change working
---from different numbers than everyone already playing.
---@return boolean mirror_x, boolean mirror_y, number coord_offset in tiles
local function current_settings()
  return settings.global['world-mirror-x'].value --[[@as boolean]],
         settings.global['world-mirror-y'].value --[[@as boolean]],
         settings.global['world-mirror-chunk-offset'].value --[[@as number]] * 32
end

---Did somebody build this, rather than the map generator growing it?
---
---A chunk west of the line is blanked to out-of-map while it waits for its partner to be
---generated, and anything built during that wait -- a PVP team's starting base, most of
---all -- is standing there when the copy finally arrives. The terrain still has to be
---mirrored, or the two halves stop matching, so what survives the wipe is the built
---things rather than the chunk.
---@param entity LuaEntity
---@return boolean
local function is_someones_work(entity)
  local force = entity.force.name
  return force ~= "neutral" and force ~= "enemy"
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
  -- do not let blanking the tiles take the built things with it; the mirrored tiles below
  -- are laid with collision handling on, so anything the new ground cannot hold still goes
  surface.set_tiles(tiles, tile_correction, false, false)

  -- destroy entities
  local entities = surface.find_entities({pos, {pos.x+32, pos.y+32}})
  for _, entity in ipairs(entities) do
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity.position.x >= pos.x and entity.position.x < pos.x+32 and entity.position.y >= pos.y and entity.position.y < pos.y+32 then 
      if entity.type == "character" or entity.type == "player" then
        -- need to move player to a legal place to stand or else they die
        local dest = surface.find_non_colliding_position(entity.type, pos, 0, 1)
        entity.teleport(dest)
      elseif is_someones_work(entity) then
        -- leave it standing: see is_someones_work
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

  -- clone decoratives. Their positions are tile positions, so they reflect the way the
  -- tiles above did and not the way the entities did -- no extra tile on the mirrored
  -- axis. find_decoratives_filtered hands back the prototype rather than its name.
  local mirrored_decoratives = {}
  for _, decorative in pairs(surface.find_decoratives_filtered{
      area = {master_pos, {master_pos.x+32, master_pos.y+32}}}) do
    -- the same care the entity loop takes: an area query reaches past the chunk, and a
    -- decorative on the far side of the edge belongs to its own chunk, not this one
    if decorative.position.x >= master_pos.x and decorative.position.x < master_pos.x+32 and
       decorative.position.y >= master_pos.y and decorative.position.y < master_pos.y+32 then
      mirrored_decoratives[#mirrored_decoratives+1] = {
        name = decorative.decorative.name,
        position = {
          x = (decorative.position.x - master_pos.x) * slave_dx + slave_pos.x,
          y = (decorative.position.y - master_pos.y) * slave_dy + slave_pos.y,
        },
        amount = decorative.amount,
      }
    end
  end
  surface.create_decoratives{check_collision=false, decoratives=mirrored_decoratives}
end

---Only worlds the map generator made. Space age brought surfaces that are not worlds: a
---space platform is a surface like any other, and wiping one of its chunks would delete
---the platform out from under whoever is standing on it. A scripted surface is nobody's
---world to mirror either. Planets other than nauvis are fair game -- they are generated
---worlds, and mirroring the world is what this mod is for.
---Global, as set_times is in axial-tilt, so the test tier can drive the real predicate
---rather than reimplementing it.
---@param surface LuaSurface
---@return boolean
function is_a_world(surface)
  return surface.planet ~= nil and surface.platform == nil
end

local function on_chunk_generated(event)
  local world_mirror_x, world_mirror_y, coord_offset = current_settings()
  if not world_mirror_x and not world_mirror_y then
    return
  end

  if not is_a_world(event.surface) then
    return
  end

  local surface = event.surface
  local p1 = event.area.left_top

  if mirror.is_slave(p1, world_mirror_x, world_mirror_y, coord_offset) then
    -- slave
    -- if p1.y==-coord_offset then debug("slave chunk at " .. pos2s(p1)) end
    local master_pos = mirror.locate_master(p1, world_mirror_x, world_mirror_y, coord_offset)
    wipe_chunk(surface, p1)
    if surface.is_chunk_generated({x=math.floor(master_pos.x/32), y=math.floor(master_pos.y/32)}) then
      mirror_chunk(surface, master_pos, p1)
    else
      surface.request_to_generate_chunks(master_pos)
    end
  else
    -- master
    -- if p1.y==-coord_offset then debug("master chunk at " .. pos2s(p1)) end
    local slaves = mirror.locate_slaves(p1, world_mirror_x, world_mirror_y, coord_offset)
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
--- The integration tier, which runs inside a live game rather than against nothing.
--- wm-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["wm-tests"] then
    require("__factorio-test__/init")({
        "test.ft.mirroring",
    }, {
        load_luassert = true,
        game_speed = 100,
    })
end
