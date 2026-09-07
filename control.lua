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
---The settings count mirror lines in chunks, because that is the unit a player thinks in
---and the lines can only fall on chunk boundaries anyway. Everything below this point
---works in tiles, so the conversion happens here and nowhere else.
---@return boolean mirror_x, boolean mirror_y, {x:number, y:number} lines, in tiles
---Where the PVP scenario wants the mirror lines, or nil if it is not running one this
---mod can help with.
---
---PVP arranges its teams on a circle around a centre it picks at random, and does not
---expose that centre -- but the spawns are readable from the team forces, and their
---average is it.
---
---Mirroring on both axes does not merely turn the map half way round: it copies one
---quadrant into the other three, so all four carry the same ground. What each team gets
---out of that depends on where it stands in its own quadrant.
---
---Two teams sit diametrically opposite whatever rotation the scenario chose, so they land
---the same distance from both lines and their surroundings match exactly.
---
---Four teams land one to a quadrant, a quarter turn apart. Opposite pairs -- one and
---three, two and four -- are again the same distance from the lines and match exactly.
---The adjacent pairs get the same ground with their position transposed within it: at a
---rotation of 17 degrees, teams one and three stand 256 east and 896 south of the lines
---while two and four stand 896 and 256. Not perfect fairness, but every team draws from
---the same quadrant of terrain rather than from four unrelated ones.
---
---Any other count gets the same treatment. Three, five or six teams do not divide neatly
---into four quadrants, so some share one and no pairing is exact -- but every team still
---draws from the same quarter of terrain rather than from unrelated pieces of map, which
---beats leaving it to chance. One team is left alone: there is nobody to be fair to.
---
---The reflection lands one tile off: it maps tile x to 2*line-1-x, so a spawn on a chunk
---boundary reflects to an odd tile and never onto the other spawn exactly. The terrain
---matches; each base sits one tile differently within it.
---@param surface LuaSurface
---@return {x:number, y:number}?
local function pvp_lines(surface)
  if not remote.interfaces["pvp"] then return nil end
  local ok, teams = pcall(remote.call, "pvp", "get_teams")
  if not ok or type(teams) ~= "table" then return nil end

  local spawns = {}
  for _, team in pairs(teams) do
    local force = game.forces[team.name]
    if not force then return nil end
    spawns[#spawns + 1] = force.get_spawn_position(surface)
  end
  if #spawns < 2 then return nil end

  local centre = mirror.centre_of(spawns)
  if not centre then return nil end
  return mirror.on_chunk_boundary(centre)
end

---As above, but worked out once a round rather than once a chunk. PVP clears the surface
---to start a round, which is the moment the answer changes.
---@param surface LuaSurface
---@return {x:number, y:number}?
local function remembered_pvp_lines(surface)
  storage.pvp = storage.pvp or {}
  local remembered = storage.pvp[surface.index]
  if remembered == nil then
    remembered = pvp_lines(surface) or false
    storage.pvp[surface.index] = remembered
  end
  return remembered or nil
end

script.on_event(defines.events.on_surface_cleared, function(event)
  if storage.pvp then storage.pvp[event.surface_index] = nil end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function()
  storage.pvp = nil
end)

local function current_settings()
  return settings.global['world-mirror-x'].value --[[@as boolean]],
         settings.global['world-mirror-y'].value --[[@as boolean]],
         {
           x = settings.global['world-mirror-x-line'].value --[[@as number]] * 32,
           y = settings.global['world-mirror-y-line'].value --[[@as number]] * 32,
         }
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

---Every tile a demolisher is standing on, as a set keyed "x,y".
---
---Demolishers are left entirely alone: never destroyed, never copied, nothing done about
---the territory they patrol. The ground beneath them cannot be touched either -- blanking
---a tile out from under one kills it -- so those tiles keep their old terrain for now and
---are written down for later.
local function wipe_chunk(surface, pos, covered)
  -- No blanking. The mirrored tiles are laid straight over what is here, in one pass by
  -- mirror_chunk, so the ground is never briefly out-of-map -- which is what used to kill
  -- anything standing on it.

  -- destroy entities
  local entities = surface.find_entities({pos, {pos.x+32, pos.y+32}})
  for _, entity in ipairs(entities) do
    -- Destroying one entity can take others in this list with it. A demolisher on vulcanus
    -- is a chain of segments, and removing any segment removes the whole creature, leaving
    -- the rest of them here as invalid handles.
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity.valid and entity.position.x >= pos.x and entity.position.x < pos.x+32 and entity.position.y >= pos.y and entity.position.y < pos.y+32 then 
      if entity.type == "character" or entity.type == "player" then
        -- need to move player to a legal place to stand or else they die
        local dest = surface.find_non_colliding_position(entity.type, pos, 0, 1)
        entity.teleport(dest)
      elseif is_someones_work(entity) then
        -- leave it standing: see is_someones_work
      elseif entity.type == "segmented-unit" or entity.type == "segment" then
        -- a demolisher: never destroyed, never copied, and nothing done about the
        -- territory it patrols. It keeps standing where it is while the ground beneath
        -- it is replaced under its feet.
      else
        entity.destroy()
        --TODO handle destroy failures
      end
    end
  end

  -- remove decoratives
  surface.destroy_decoratives({pos, {pos.x+32, pos.y+32}})
end

---Can a player put this down? Map generation makes things no item places -- fulgora's
---ruin attractors among them -- and those are the ones worth copying. Anything a player
---could have built is theirs, not the map's.
---@param entity LuaEntity
---@return boolean
local function is_placeable(entity)
  local items = entity.prototype.items_to_place_this
  return items ~= nil and #items > 0
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
    -- valid, for the same reason as in wipe_chunk: creating cliffs reshapes their
    -- neighbours, which can remove one that is still sitting in this list
    -- attempt to avoid affecting entities not actually "on" this chunk
    if entity.valid and entity.position.x >= master_pos.x and entity.position.x < master_pos.x+32 and entity.position.y >= master_pos.y and entity.position.y < master_pos.y+32 then 
      if entity.type == "fish" or
         entity.type == "tree" or
         entity.type == "unit" or
         entity.type == "cliff" or
         entity.type == "resource" or
         entity.type == "unit-spawner" or
         entity.type == "simple-entity" or
         -- Fulgora grows ruin attractors among its scrap. Only the ones nothing can
         -- place: lightning rods and collectors are the same type and players build
         -- those, and copying a team's rod into the other team's half would hand them a
         -- structure -- still on the builder's force -- that they never built.
         ( entity.type == "lightning-attractor" and not is_placeable(entity) ) or
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

---Copy one edge of a chunk again, now that the neighbour beside it has settled the tiles
---there.
---
---A chunk's outermost tiles are not final when it is generated: the boundary between it
---and a neighbour is resolved when that neighbour arrives, which may be much later. The
---copy taken at generation therefore holds provisional values along any side whose
---neighbour did not exist yet -- most visibly land where the settled answer is water. Only
---the one row or column facing the new neighbour needs redoing, 32 tiles rather than 1024.
---@param surface LuaSurface
---@param master_pos {x:number, y:number} the settled chunk's corner
---@param towards {x:number, y:number} unit vector pointing at the neighbour that settled it
---@param mirror_x boolean
---@param mirror_y boolean
---@param lines {x:number, y:number}
---@param tiles table[] appended to, so every edge settled at once goes in one write
local function recopy_edge(surface, master_pos, towards, mirror_x, mirror_y, lines, tiles)
  for _, slave_pos in ipairs(mirror.locate_slaves(master_pos, mirror_x, mirror_y, lines)) do
    if surface.is_chunk_generated({x=math.floor(slave_pos.x/32), y=math.floor(slave_pos.y/32)}) then
      local flip_x = slave_pos.x ~= master_pos.x
      local flip_y = slave_pos.y ~= master_pos.y
      for step = 0, 31 do
        -- the row or column facing the neighbour, depending on which way it lies
        local ix = towards.x == 0 and step or (towards.x > 0 and 31 or 0)
        local iy = towards.y == 0 and step or (towards.y > 0 and 31 or 0)
        tiles[#tiles+1] = {
          name = surface.get_tile(master_pos.x + ix, master_pos.y + iy).name,
          position = {
            x = slave_pos.x + (flip_x and 31 - ix or ix),
            y = slave_pos.y + (flip_y and 31 - iy or iy),
          },
        }
      end
    end
  end
end

local function on_chunk_generated(event)
  local world_mirror_x, world_mirror_y, lines = current_settings()
  if not world_mirror_x and not world_mirror_y then
    return
  end

  if not is_a_world(event.surface) then
    return
  end

  local surface = event.surface

  if settings.global['world-mirror-follow-pvp'].value then
    local from_pvp = remembered_pvp_lines(surface)
    if from_pvp then
      -- a half turn about the teams' centre, which is what makes their ground match
      lines = from_pvp
      world_mirror_x, world_mirror_y = true, true
    end
  end
  local p1 = event.area.left_top

  if mirror.is_slave(p1, world_mirror_x, world_mirror_y, lines) then
    -- slave
    local master_pos = mirror.locate_master(p1, world_mirror_x, world_mirror_y, lines)
    wipe_chunk(surface, p1)
    if surface.is_chunk_generated({x=math.floor(master_pos.x/32), y=math.floor(master_pos.y/32)}) then
      mirror_chunk(surface, master_pos, p1)
    else
      surface.request_to_generate_chunks(master_pos)
    end
  else
    -- master
    local slaves = mirror.locate_slaves(p1, world_mirror_x, world_mirror_y, lines)
    for _,slave_pos in ipairs(slaves) do
      local slave_chunk_pos = {x=math.floor(slave_pos.x/32), y=math.floor(slave_pos.y/32)}
      if surface.is_chunk_generated(slave_chunk_pos) then
        wipe_chunk(surface, slave_pos)
      end
      mirror_chunk(surface, p1, slave_pos)
      surface.set_chunk_generated_status(slave_chunk_pos, defines.chunk_generated_status.entities)
    end

    -- This chunk has just settled the boundary with every neighbour that already existed,
    -- so their copies are now out of date along that one edge.
    local settled = {}
    for _, towards in ipairs({{x=-1,y=0},{x=1,y=0},{x=0,y=-1},{x=0,y=1}}) do
      local neighbour = {x = p1.x + towards.x*32, y = p1.y + towards.y*32}
      if not mirror.is_slave(neighbour, world_mirror_x, world_mirror_y, lines)
        and surface.is_chunk_generated({x=math.floor(neighbour.x/32), y=math.floor(neighbour.y/32)})
      then
        recopy_edge(surface, neighbour, {x = -towards.x, y = -towards.y},
          world_mirror_x, world_mirror_y, lines, settled)
      end
    end
    if #settled > 0 then
      surface.set_tiles(settled, true, false, false)
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
