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

    -- KNOWN FAILING, for 2.1.2. The reflected chunk comes back with no decoratives at
    -- all, though the master it was copied from has plenty and the mod asks for them by
    -- name. Fixing the crash in prototypes.decorative got the call running again; it did
    -- not make the call do anything. Left red on purpose: the bug is real and outstanding,
    -- and a test that goes green when it is fixed is worth more than a deleted one.
    test("gets decoratives on the reflected side", function()
        -- regenerating these is what game.decorative_prototypes used to crash on, so a
        -- reflected chunk with none at all means the call quietly does nothing
        local surface = world.terrain()
        local master, slave = world.claim_with(surface, function(s, corner)
            return #s.find_decoratives_filtered({
                area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } } }) > 0
        end)

        local decoratives = surface.find_decoratives_filtered({
            area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } } })
        assert.is_true(#decoratives > 0,
            "the master chunk has decoratives and its reflection has none")
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

        -- with the Y axis on, a master chunk gains a north/south reflection it would not
        -- otherwise have; pick one north of the Y line so it has one
        local master = world.claim(surface)
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
