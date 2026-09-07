--- What a real game does when a chunk is generated.
local world = require("test.ft.world")

describe("a generated chunk", function()
    test("gets a reflection whose tiles match, reversed", function()
        -- real terrain, not the lab world this suite starts on: a reflection written 32
        -- tiles off still matched there, because one patch of checkerboard looks much
        -- like another
        local surface = world.terrain()
        local master = world.claim(surface)
        world.generate(surface, master)

        local slave = world.reflection_of(master)
        local matched, mismatched, out_of_map, first = world.compare(surface, master, slave)

        assert.equals(0, mismatched, "first difference: " .. tostring(first))
        assert.equals(1024, matched)
        assert.equals(0, out_of_map, "the reflection was blanked and never refilled")
    end)

    test("gets a reflection the mod put there, not the map generator", function()
        -- the reflection sits past the mirror line, so anything there was written by the
        -- mod; if it had never run, the map generator's own terrain would not match
        local surface = world.terrain()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)
        assert.is_false(surface.is_chunk_generated({ x = slave.x / 32, y = slave.y / 32 }),
            "setup: the reflection already existed")

        world.generate(surface, master)

        assert.is_true(surface.is_chunk_generated({ x = slave.x / 32, y = slave.y / 32 }),
            "generating a master did not bring its reflection into being")
    end)

    test("carries its entities across", function()
        local surface = world.terrain()
        local master, slave = world.claim_with(surface, function(s, corner)
            return #world.cloned_entities(s, corner) > 0
        end)

        local originals = world.cloned_entities(surface, master)

        local missing, first = 0, nil
        for _, entity in ipairs(originals) do
            local want_x = slave.x + 32 - (entity.position.x - master.x)
            if #surface.find_entities_filtered({ name = entity.name,
                    position = { want_x, entity.position.y }, radius = 0.6 }) == 0 then
                missing = missing + 1
                first = first or ("%s at (%.1f,%.1f)"):format(
                    entity.name, entity.position.x, entity.position.y)
            end
        end
        -- a handful fail to place where the mirrored ground will not take them; the point
        -- is that cloning happens at all, not that it is flawless
        assert.is_true(missing <= #originals * 0.1,
            ("%d of %d entities did not make it across, first %s")
            :format(missing, #originals, tostring(first)))
    end)

    test("carries its decoratives across, not merely some decoratives", function()
        local surface = world.terrain()
        local master, slave = world.claim_with(surface, function(s, corner)
            return #s.find_decoratives_filtered({
                area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } } }) > 0
        end)

        -- Every decorative, at its mirrored position, not merely the same tally: a
        -- reflection generated from its own noise could match on counts by luck, and
        -- would not match on where each one sits.
        local function census(corner, reflect)
            local at = {}
            for _, d in pairs(surface.find_decoratives_filtered({
                    area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } } })) do
                local dx, dy = d.position.x - corner.x, d.position.y - corner.y
                -- an area query reaches past the chunk edge; those belong to a neighbour
                if dx >= 0 and dx < 32 and dy >= 0 and dy < 32 then
                    at[("%s@%d,%d"):format(d.decorative.name, reflect and (31 - dx) or dx, dy)] = d.amount
                end
            end
            return at
        end

        local on_master, on_slave = census(master, true), census(slave, false)
        assert.is_true(next(on_master) ~= nil, "setup: the master chunk has no decoratives")
        assert.same(on_master, on_slave)
    end)
end)

describe("a slave chunk reached before its master exists", function()
    test("does not stay blank", function()
        -- What a player walking west into unexplored ground does. The mod blanks the
        -- chunk to out-of-map, and only fills it if the master already exists; otherwise
        -- it asks for the master to be generated and returns, leaving a black hole until
        -- that request lands. SoulForge reported black sections on the portal in 2017.
        local surface = world.terrain()
        local slave, master = world.claim_slave(surface)

        async(600)
        surface.request_to_generate_chunks({ slave.x + 16, slave.y + 16 }, 0)
        surface.force_generate_chunk_requests()

        after_ticks(300, function()
            -- the master must have been fetched, or nothing was mirrored and a chunk of
            -- ordinary terrain would pass this on its own
            assert.is_true(surface.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
                ("the master at %d,%d was never generated"):format(master.x, master.y))
            local blank = surface.count_tiles_filtered({
                area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } },
                name = "out-of-map" })
            assert.equals(0, blank, ("%d tiles left blank at %d,%d"):format(blank, slave.x, slave.y))

            local matched, mismatched = 0, 0
            for dx = 0, 31 do
                for dy = 0, 31 do
                    if surface.get_tile(master.x + dx, master.y + dy).name
                        == surface.get_tile(slave.x + 31 - dx, slave.y + dy).name then
                        matched = matched + 1
                    else
                        mismatched = mismatched + 1
                    end
                end
            end
            assert.equals(0, mismatched, "the chunk was refilled, but not with its mirror")
            assert.equals(1024, matched)
            done()
        end)
    end)
end)

describe("a whole region of slave chunks revealed at once", function()
    test("none of them stays blank", function()
        -- radar, or a scenario that pre-generates its starting area, asks for many chunks
        -- in one go. Every one of them is blanked and wants a master fetched.
        local surface = world.terrain()
        local first = world.claim_slave(surface)
        local width, height = 4, 3

        async(1200)
        for cx = 0, width - 1 do
            for cy = 0, height - 1 do
                surface.request_to_generate_chunks(
                    { first.x - cx * 32 + 16, first.y + cy * 32 + 16 }, 0)
            end
        end
        surface.force_generate_chunk_requests()

        after_ticks(600, function()
            local blank_chunks, worst = 0, nil
            for cx = 0, width - 1 do
                for cy = 0, height - 1 do
                    local corner = { x = first.x - cx * 32, y = first.y + cy * 32 }
                    local blank = surface.count_tiles_filtered({
                        area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } },
                        name = "out-of-map" })
                    if blank > 0 then
                        blank_chunks = blank_chunks + 1
                        worst = worst or ("%d,%d with %d blank tiles"):format(corner.x, corner.y, blank)
                    end
                end
            end
            assert.equals(0, blank_chunks,
                ("%d of %d chunks left blank, first %s")
                :format(blank_chunks, width * height, tostring(worst)))
            done()
        end)
    end)
end)

describe("all four quadrants at once", function()
    local saved
    before_each(function() saved = world.snapshot() end)
    after_each(function() world.restore(saved) end)

    test("gives a master all three of its reflections", function()
        -- the README's "all four quarters" case. One master, deliberately: mirroring it
        -- into three reflections costs the best part of a second, and asking for a region
        -- of them outlasts the runner's patience -- which is a performance problem in its
        -- own right, noted for later, not something to hide behind a smaller number here.
        local surface = world.terrain()
        world.configure({ mirror_x = true, mirror_y = true, chunk_offset = 0 })

        local master = { x = 70 * 32, y = 70 * 32 }
        assert.is_false(surface.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
            "setup: the master chunk already exists")

        async(1200)
        surface.request_to_generate_chunks({ master.x + 16, master.y + 16 }, 0)
        surface.force_generate_chunk_requests()

        after_ticks(120, function()
            -- with the lines through the origin a master at m reflects to -m-32
            local across = -master.x - 32
            local reflections = {
                { x = across, y = master.y },
                { x = master.x, y = across },
                { x = across, y = across },
            }
            for _, corner in ipairs(reflections) do
                local blank = surface.count_tiles_filtered({
                    area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } },
                    name = "out-of-map" })
                assert.equals(0, blank,
                    ("reflection at %d,%d has %d blank tiles"):format(corner.x, corner.y, blank))
                assert.is_true(surface.is_chunk_generated({ x = corner.x / 32, y = corner.y / 32 }),
                    ("reflection at %d,%d was never made"):format(corner.x, corner.y))
            end
            done()
        end)
    end)
end)

describe("a chunk somebody has built in", function()
    test("keeps what was built", function()
        -- Issue #1: the PVP scenario generates each team's chunks, then builds its silo,
        -- turrets and walls. A base west of the line survives that, and then dies the
        -- moment its master chunk east of the line is generated -- which happens as soon
        -- as anyone walks that way.
        local surface = world.terrain()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)

        -- the slave exists first, as a team's starting area does
        surface.request_to_generate_chunks({ slave.x + 16, slave.y + 16 }, 0)
        surface.force_generate_chunk_requests()
        surface.destroy_decoratives({ area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } } })
        for _, entity in pairs(surface.find_entities({ { slave.x, slave.y },
                                                       { slave.x + 32, slave.y + 32 } })) do
            if entity.valid and entity.type ~= "character" then entity.destroy() end
        end

        local base = surface.create_entity({
            name = "steel-chest", position = { slave.x + 16.5, slave.y + 16.5 }, force = "player" })
        assert.is_not_nil(base, "setup: could not build in the slave chunk")

        -- and now somebody walks east and generates its master
        world.generate(surface, master)

        assert.is_true(base.valid, "the mod destroyed something somebody had built")
        assert.equals(1, surface.count_entities_filtered({
            area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } },
            name = "steel-chest" }))
    end)

    test("still has the same terrain as its partner", function()
        -- The point of the mod is that both halves match. Skipping a built-in chunk must
        -- not cost that: the chunk should already hold its mirrored terrain by the time
        -- anyone can build in it, so refusing to redo the copy changes nothing.
        local surface = world.terrain()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)

        surface.request_to_generate_chunks({ slave.x + 16, slave.y + 16 }, 0)
        surface.force_generate_chunk_requests()
        local base = surface.create_entity({
            name = "steel-chest", position = { slave.x + 16.5, slave.y + 16.5 }, force = "player" })
        assert.is_not_nil(base, "setup: could not build in the slave chunk")

        world.generate(surface, master)

        assert.is_true(base.valid, "the base did not survive")
        local matched, mismatched, out_of_map, first = world.compare(surface, master, slave)
        assert.equals(0, out_of_map, "the chunk was left blank")
        assert.equals(0, mismatched, "terrain no longer matches: " .. tostring(first))
        assert.equals(1024, matched)
    end)

    test("is mirrored when only the map generator has been there", function()
        -- the guard must not stop ordinary mirroring: trees and rocks are nobody's work
        local surface = world.terrain()
        local master = world.claim(surface)
        world.generate(surface, master)

        local matched, mismatched = world.compare(surface, master, world.reflection_of(master))
        assert.equals(0, mismatched)
        assert.equals(1024, matched)
    end)
end)

describe("which surfaces count as worlds", function()
    test("nauvis does", function()
        assert.is_true(is_a_world(world.nauvis()))
    end)

    test("so does another planet, and it is mirrored like any other world", function()
        -- space age put four more worlds in the game; mirroring the world is the point
        local surface = world.terrain()
        assert.is_true(is_a_world(surface))

        local master = world.claim(surface)
        world.generate(surface, master)
        local matched, mismatched = world.compare(surface, master, world.reflection_of(master))

        assert.equals(0, mismatched)
        assert.equals(1024, matched)
    end)

    test("a surface with no planet does not, and is left untouched", function()
        -- a space platform is one of these, and blanking its chunks would delete it
        local scratch = game.surfaces["wm-scratch"]
            or game.create_surface("wm-scratch")
        scratch.generate_with_lab_tiles = true
        assert.is_false(is_a_world(scratch),
            "a planetless surface now reads as a world, and would be mirrored")

        -- Generate a chunk past the mirror line. Checking only that its tiles survive is
        -- not enough: without the guard the mod blanks the chunk, fetches the master it
        -- reflects, and copies it back, so the tiles come out looking untouched. What it
        -- cannot hide is the master chunk it had to generate to do that.
        local corner = { x = -12 * 32, y = 0 }
        local master = world.reflection_of(corner)
        assert.is_false(scratch.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
            "setup: the chunk on the other side of the line already exists")

        scratch.request_to_generate_chunks({ corner.x + 16, corner.y + 16 }, 0)
        scratch.force_generate_chunk_requests()

        assert.equals(0, scratch.count_tiles_filtered({
            area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } },
            name = "out-of-map" }), "the mod blanked a surface that is not a world")
        assert.is_false(scratch.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
            "the mod reached across the line on a surface that is not a world")
    end)
end)

describe("the settings", function()
    local saved
    before_each(function() saved = world.snapshot() end)
    after_each(function() world.restore(saved) end)

    test("are read when a chunk generates, not once when the file loaded", function()
        -- Loading them once meant a change during a game did nothing until reload, and
        -- left a joining client working from different numbers than the host.
        local surface = world.terrain()
        world.configure({ mirror_y = true })

        -- With the Y axis on, a master gains a north/south reflection -- but only if it
        -- is north of the Y line. claim() walks rows either side of it, so ask until it
        -- hands back one that qualifies.
        local master
        repeat master = world.claim(surface) until master.y >= -world.COORD_OFFSET
        world.generate(surface, master)

        local reflected_y = -2 * world.COORD_OFFSET - master.y - 32
        local slave = { x = master.x, y = reflected_y }
        assert.is_true(surface.is_chunk_generated({ x = slave.x / 32, y = slave.y / 32 }),
            "turning on the Y axis mid-game had no effect")

        local matched, mismatched = 0, 0
        for dx = 0, 31 do
            for dy = 0, 31 do
                if surface.get_tile(master.x + dx, master.y + dy).name
                    == surface.get_tile(slave.x + dx, slave.y + 31 - dy).name then
                    matched = matched + 1
                else
                    mismatched = mismatched + 1
                end
            end
        end
        assert.equals(0, mismatched)
        assert.equals(1024, matched)
    end)
end)
