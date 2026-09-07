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
        world.configure({ mirror_x = true, mirror_y = true, x_line = 0, y_line = 0 })

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

    test("tells built from grown by force, which is what the game does", function()
        -- The rule is "not neutral and not enemy". It holds because the map generator
        -- puts nothing on a player force: trees, rocks, fish, cliffs and ore are neutral,
        -- units and nests are enemy. If that ever stops being true this goes red, rather
        -- than the mod quietly sparing scenery or destroying somebody's factory.
        local surface = world.terrain()
        local master = world.claim(surface)
        world.generate(surface, master)

        local wrong = {}
        for _, entity in pairs(surface.find_entities({ { master.x, master.y },
                                                       { master.x + 32, master.y + 32 } })) do
            local force = entity.force.name
            if force ~= "neutral" and force ~= "enemy" then
                wrong[#wrong + 1] = entity.type .. " on force " .. force
            end
        end
        assert.same({}, wrong)
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

describe("demolishers", function()
    -- Left entirely alone: not destroyed, not copied, nothing done about their territory.
    -- Blanking a chunk would kill one -- it cannot live on out-of-map, and dies within a
    -- tick or two -- and it cannot be moved out of the way either, since teleport refuses
    -- on a segmented unit at any distance. So the tiles it is standing on are left as
    -- they are and written down, and laid as soon as it moves off them.
    --
    -- Verified by hand rather than here: reaching it wants the map generator to put a
    -- demolisher in a chunk that is about to be mirrored, which a fixture cannot arrange
    -- on demand. Over a slab of vulcanus, 5 demolishers and 231 segments survive, 371
    -- tiles are held back out of 156672, and clearing the ground drains the queue to nil.
    test("are not copied to the other side", function()
        local surface = world.terrain()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)
        world.generate(surface, master)

        local demolisher = surface.create_entity({
            name = "small-demolisher", position = { master.x + 16, master.y + 16 },
            force = "enemy" })
        assert.is_not_nil(demolisher, "setup: could not place a demolisher")

        async(600)
        after_ticks(60, function()
            assert.equals(0, surface.count_entities_filtered({
                area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } },
                type = { "segmented-unit", "segment" } }),
                "a demolisher was copied across the mirror line")
            done()
        end)
    end)
end)

describe("what makes a chunk fair to both sides", function()
    test("worms are still recognised the way the mod recognises them", function()
        -- The clone list takes a turret only when its subgroup reads "enemies", which is a
        -- string written in 1.1. It is still true, and a worm that stopped matching would
        -- silently leave one half of the map without its defences -- so say so here rather
        -- than find out from a player.
        for _, name in ipairs({ "small-worm-turret", "medium-worm-turret", "big-worm-turret" }) do
            local worm = prototypes.entity[name]
            assert.is_not_nil(worm, name .. " is gone")
            assert.equals("turret", worm.type, name .. " is no longer a turret")
            assert.equals("enemies", worm.subgroup.name,
                name .. " left the enemies subgroup, so the mod stopped cloning it")
        end
    end)

    test("nests and biters are types the mod clones", function()
        -- the other half of the same assumption, for the entities that come with them
        assert.equals("unit-spawner", prototypes.entity["biter-spawner"].type)
        assert.equals("unit", prototypes.entity["small-biter"].type)
    end)
end)

describe("fulgora's lightning attractors", function()
    test("are copied to the reflection, in the mirrored places", function()
        -- The map generator grows these, and they arrive on the player force, which is
        -- the only vanilla case of that. They were not in the clone list, so one half of
        -- the map had them and the other did not.
        local surface = world.fulgora()
        local master, slave = world.claim_with(surface, function(s, corner)
            return s.count_entities_filtered({
                area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } },
                type = "lightning-attractor" }) > 0
        end)

        local function census(corner, reflect)
            local at = {}
            for _, e in pairs(surface.find_entities_filtered({
                    area = { { corner.x, corner.y }, { corner.x + 32, corner.y + 32 } },
                    type = "lightning-attractor" })) do
                local dx = e.position.x - corner.x
                if reflect then dx = 32 - dx end
                at[("%.1f,%.1f"):format(dx, e.position.y - corner.y)] = e.name
            end
            return at
        end

        local on_master, on_slave = census(master, true), census(slave, false)
        assert.is_true(next(on_master) ~= nil, "setup: no attractors in the master chunk")
        assert.same(on_master, on_slave)
    end)
end)

describe("attractors a player could have built", function()
    test("are a different prototype from the ones fulgora grows", function()
        -- The rule is "copy the ones nothing can place". It rests on the ruins having no
        -- item that builds them, while rods and collectors do.
        local ruin = prototypes.entity["fulgoran-ruin-attractor"]
        assert.is_not_nil(ruin, "fulgoran-ruin-attractor is gone")
        assert.equals("lightning-attractor", ruin.type)
        local items = ruin.items_to_place_this
        assert.is_true(items == nil or #items == 0,
            "the ruin attractor became placeable, so the mod now copies players' work")

        for _, name in ipairs({ "lightning-rod", "lightning-collector" }) do
            local built = prototypes.entity[name]
            assert.is_not_nil(built, name .. " is gone")
            assert.equals("lightning-attractor", built.type)
            assert.is_true(built.items_to_place_this ~= nil and #built.items_to_place_this > 0,
                name .. " stopped being placeable, so the mod would start copying it")
        end
    end)

    -- The behaviour itself is not covered here. Reaching it needs a master chunk that
    -- has been built in since it was generated, which means deleting the reflection and
    -- letting it be made again -- and delete_chunk is deferred, so it does not happen
    -- within one test. Fulgora's attractor chunks are sparse enough that hunting for a
    -- suitable one is flaky too. Checked by hand instead: a rod built on a team force in
    -- a master chunk stays out of the reflection with this rule, and is copied across
    -- without it, still on the builder's force.
end)

describe("a reflection reached before its partner", function()
    test("keeps its own ground while it waits, rather than going black", function()
        -- Nothing is ever blanked: the partner's tiles are laid straight over whatever is
        -- here. So a chunk reached first looks like ordinary ground until its partner
        -- turns up, instead of being a hole in the map for however long that takes.
        local surface = world.fulgora()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)

        surface.request_to_generate_chunks({ slave.x + 16, slave.y + 16 }, 0)
        surface.force_generate_chunk_requests()

        assert.equals(0, surface.count_tiles_filtered({
            area = { { slave.x, slave.y }, { slave.x + 32, slave.y + 32 } },
            name = "out-of-map" }), "the waiting chunk was blanked")
    end)

    test("still ends up matching its partner once that arrives", function()
        local surface = world.terrain()
        local master = world.claim(surface)
        local slave = world.reflection_of(master)

        surface.request_to_generate_chunks({ slave.x + 16, slave.y + 16 }, 0)
        surface.force_generate_chunk_requests()
        world.generate(surface, master)

        local matched, mismatched = world.compare(surface, master, slave)
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
        repeat master = world.claim(surface) until master.y >= world.LINES.y
        world.generate(surface, master)

        local reflected_y = 2 * world.LINES.y - master.y - 32
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

describe("mirror lines placed anywhere", function()
    local saved
    before_each(function() saved = world.snapshot() end)
    after_each(function() world.restore(saved) end)

    test("work east of the origin, not only west of it", function()
        -- what PVP needs: its teams sit around a centre that is nowhere near the origin,
        -- so the lines have to go where the teams are
        local surface = world.terrain()
        local line = 40 * 32
        world.configure({ mirror_x = true, mirror_y = false, x_line = 40 })

        local master = { x = line, y = 0 }
        assert.is_false(surface.is_chunk_generated({ x = master.x / 32, y = 0 }),
            "setup: the master chunk already exists")
        surface.request_to_generate_chunks({ master.x + 16, 16 }, 0)
        surface.force_generate_chunk_requests()

        local slave = { x = 2 * line - master.x - 32, y = 0 }
        local matched, mismatched = 0, 0
        for dx = 0, 31 do
            for dy = 0, 31 do
                if surface.get_tile(master.x + dx, dy).name
                    == surface.get_tile(slave.x + 31 - dx, dy).name then
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

describe("following the PVP scenario", function()
    local saved
    before_each(function() saved = world.snapshot() end)
    after_each(function()
        world.restore(saved)
        if remote.interfaces["pvp"] then remote.remove_interface("pvp") end
    end)

    --- Stand in for the scenario: two teams on a circle around a centre of our choosing,
    --- reached the way the real one is reached -- a remote interface listing the teams,
    --- and each team force carrying its spawn.
    local function pretend_pvp(surface, centre, radius, count)
        local teams = {}
        for index = 1, count do
            local name = "pvp-team-" .. index
            local force = game.forces[name] or game.create_force(name)
            local angle = index * 2 * math.pi / count
            force.set_spawn_position({
                centre.x + 32 * math.floor(math.cos(angle) * radius / 32),
                centre.y + 32 * math.floor(math.sin(angle) * radius / 32),
            }, surface)
            teams[index] = { name = name }
        end
        remote.add_interface("pvp", { get_teams = function() return teams end })
    end

    test("puts the mirror lines on the teams, not where the settings say", function()
        local surface = world.terrain()
        local centre = { x = 100 * 32, y = 4 * 32 }
        pretend_pvp(surface, centre, 30 * 32, 2)
        -- deliberately nothing like the centre, so following is the only way to match
        world.configure({ mirror_x = true, mirror_y = false, x_line = -4, y_line = -4 })

        local master = { x = centre.x + 10 * 32, y = centre.y + 3 * 32 }
        assert.is_false(surface.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
            "setup: the master chunk already exists")
        surface.request_to_generate_chunks({ master.x + 16, master.y + 16 }, 0)
        surface.force_generate_chunk_requests()

        -- a half turn about the centre: reflected on both axes at once
        local slave = { x = 2 * centre.x - master.x - 32, y = 2 * centre.y - master.y - 32 }
        assert.is_true(surface.is_chunk_generated({ x = slave.x / 32, y = slave.y / 32 }),
            "the far side of the centre was never written")

        local matched, mismatched = 0, 0
        for dx = 0, 31 do
            for dy = 0, 31 do
                if surface.get_tile(master.x + dx, master.y + dy).name
                    == surface.get_tile(slave.x + 31 - dx, slave.y + 31 - dy).name then
                    matched = matched + 1
                else
                    mismatched = mismatched + 1
                end
            end
        end
        assert.equals(0, mismatched)
        assert.equals(1024, matched)
    end)

    test("gives all four quadrants of a four team round the same ground", function()
        -- Mirroring both axes copies one quadrant into the other three, so every team
        -- draws from the same terrain. Opposite teams stand the same distance from the
        -- lines and match exactly; adjacent ones get that terrain with their position
        -- transposed within it.
        local surface = world.terrain()
        local centre = { x = 200 * 32, y = 8 * 32 }
        pretend_pvp(surface, centre, 30 * 32, 4)
        world.configure({ mirror_x = true, mirror_y = false, x_line = -4, y_line = -4 })

        local master = { x = centre.x + 6 * 32, y = centre.y + 5 * 32 }
        assert.is_false(surface.is_chunk_generated({ x = master.x / 32, y = master.y / 32 }),
            "setup: the master chunk already exists")
        surface.request_to_generate_chunks({ master.x + 16, master.y + 16 }, 0)
        surface.force_generate_chunk_requests()

        local across_x = 2 * centre.x - master.x - 32
        local across_y = 2 * centre.y - master.y - 32
        local quadrants = {
            { corner = { x = across_x, y = master.y }, flip_x = true,  flip_y = false },
            { corner = { x = master.x, y = across_y }, flip_x = false, flip_y = true },
            { corner = { x = across_x, y = across_y }, flip_x = true,  flip_y = true },
        }
        for index, q in ipairs(quadrants) do
            assert.is_true(surface.is_chunk_generated({ x = q.corner.x / 32, y = q.corner.y / 32 }),
                ("quadrant %d was never written"):format(index))
            local mismatched = 0
            for dx = 0, 31 do
                for dy = 0, 31 do
                    local sx = q.corner.x + (q.flip_x and 31 - dx or dx)
                    local sy = q.corner.y + (q.flip_y and 31 - dy or dy)
                    if surface.get_tile(master.x + dx, master.y + dy).name
                        ~= surface.get_tile(sx, sy).name then
                        mismatched = mismatched + 1
                    end
                end
            end
            assert.equals(0, mismatched, ("quadrant %d does not match the master"):format(index))
        end
    end)

    test("is ignored when the scenario is not running", function()
        local surface = world.terrain()
        world.configure({ mirror_x = true, mirror_y = false, x_line = -4, y_line = -4 })
        assert.is_nil(remote.interfaces["pvp"], "setup: something is pretending to be pvp")

        local master = world.claim(surface)
        world.generate(surface, master)

        local matched, mismatched = world.compare(surface, master, world.reflection_of(master))
        assert.equals(0, mismatched, "the settings' own lines stopped being used")
        assert.equals(1024, matched)
    end)
end)
