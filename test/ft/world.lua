--- The shared ground: making chunks exist and comparing a chunk with its reflection.
---
--- Every fixture works far from spawn and from every other fixture, because a mirrored
--- chunk is written by generating its master and there is no undoing that.
local world = {}

--- The settings the mod is running with. It reads them once at load, so these are the
--- shipped defaults and a fixture cannot change them -- which is itself a 2.1.2 matter.
world.MIRROR_X = true
world.MIRROR_Y = false
world.COORD_OFFSET = 4 * 32

local next_chunk = 9
local next_row = 0

---A master chunk east of the mirror line that nothing has generated yet -- neither the
---save this suite starts from nor an earlier fixture. Generating a master writes its
---reflection, so a chunk can only be used once.
---@return {x:number, y:number}
---@param surface LuaSurface? defaults to the lab world
function world.claim(surface)
    surface = surface or world.nauvis()
    for _ = 1, 400 do
        next_row = next_row + 1
        if next_row > 6 then
            next_row = -6
            next_chunk = next_chunk + 2
        end
        -- a whole grid rather than one line east: the strip along y=0 turned out to hold
        -- no trees at all for a dozen chunks, and a fixture about cloning needs some
        local corner = { x = next_chunk * 32, y = next_row * 32 }
        local reflection = world.reflection_of(corner)
        if not surface.is_chunk_generated({ x = corner.x / 32, y = corner.y / 32 })
            and not surface.is_chunk_generated({ x = reflection.x / 32, y = reflection.y / 32 })
        then
            return corner
        end
    end
    error("no unused master chunk left to claim")
end

---Claim and generate chunks until one of them holds something the mod clones, and hand
---back that chunk with its reflection. Terrain is terrain: not every chunk has a tree in
---it, and a fixture about cloning needs one that does.
---@param surface LuaSurface
---@param wanted fun(surface: LuaSurface, corner: table): boolean
---@return {x:number, y:number} master, {x:number, y:number} slave
function world.claim_with(surface, wanted)
    for _ = 1, 40 do
        local master = world.claim(surface)
        world.generate(surface, master)
        if wanted(surface, master) then
            return master, world.reflection_of(master)
        end
    end
    error("no chunk in reach held what this fixture needs")
end

---@return LuaSurface
function world.nauvis() return game.surfaces["nauvis"] end

--- A surface with terrain on it. The save this suite runs from is a lab-tile world --
--- lab-dark-1 and lab-dark-2, no entities, no decoratives -- which is fine for asking
--- whether tiles reflect but useless for asking whether a tree does. Vulcanus is a real
--- planet, so the mod treats it as a world, and the map generator puts rocks and
--- decoratives on it.
---@return LuaSurface
function world.terrain()
    local existing = game.surfaces["vulcanus"]
    if existing then return existing end
    return game.planets["vulcanus"].create_surface()
end

---Make a chunk exist and let the mod see it. Chunks generated during on_init raise no
---events, but a fixture runs on a tick, where they do.
---@param surface LuaSurface
---@param corner {x:number, y:number}
function world.generate(surface, corner)
    surface.request_to_generate_chunks({ corner.x + 16, corner.y + 16 }, 0)
    surface.force_generate_chunk_requests()
end

---Where a master chunk's reflection lives.
---
---Written out here rather than called from lib.mirror on purpose. Asking the code under
---test where it put something and then checking it is there agrees with any answer it
---cares to give -- dropping the chunk width from the reflection passed the tile fixture
---until this stopped borrowing it.
---@param corner {x:number, y:number}
---@return {x:number, y:number}
function world.reflection_of(corner)
    return { x = -2 * world.COORD_OFFSET - corner.x - 32, y = corner.y }
end

---Compare a chunk with its reflection, tile by tile, east-west reversed.
---@return integer matched, integer mismatched, integer out_of_map, string? first
function world.compare(surface, master, slave)
    local matched, mismatched, out_of_map, first = 0, 0, 0, nil
    for dx = 0, 31 do
        for dy = 0, 31 do
            local a = surface.get_tile(master.x + dx, master.y + dy).name
            local b = surface.get_tile(slave.x + 31 - dx, slave.y + dy).name
            if b == "out-of-map" then out_of_map = out_of_map + 1 end
            if a == b then matched = matched + 1
            else
                mismatched = mismatched + 1
                first = first or ("(%d,%d)=%s vs (%d,%d)=%s")
                    :format(master.x + dx, master.y + dy, a, slave.x + 31 - dx, slave.y + dy, b)
            end
        end
    end
    return matched, mismatched, out_of_map, first
end

---Entities of the kinds the mod clones, inside one chunk.
---@return LuaEntity[]
function world.cloned_entities(surface, corner)
    local kinds = { fish = true, tree = true, unit = true, cliff = true, resource = true,
                    ["unit-spawner"] = true, ["simple-entity"] = true }
    local found = {}
    for _, entity in pairs(surface.find_entities({ { corner.x, corner.y },
                                                   { corner.x + 32, corner.y + 32 } })) do
        if kinds[entity.type]
            and entity.position.x >= corner.x and entity.position.x < corner.x + 32
            and entity.position.y >= corner.y and entity.position.y < corner.y + 32 then
            found[#found + 1] = entity
        end
    end
    return found
end

return world
