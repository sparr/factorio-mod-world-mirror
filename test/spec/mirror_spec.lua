local mirror = require("lib.mirror")

--- The shipped default: mirror east/west only, both lines four chunks west and north of
--- the origin.
local LINES = { x = -4 * 32, y = -4 * 32 }

describe("is_slave", function()
    it("calls a chunk past the line a slave", function()
        assert.is_true(mirror.is_slave({ x = -160, y = 0 }, true, false, LINES))
    end)

    it("calls a chunk on the line a master", function()
        -- the line itself belongs to the master half
        assert.is_false(mirror.is_slave({ x = LINES.x, y = 0 }, true, false, LINES))
    end)

    it("ignores an axis that is not being mirrored", function()
        assert.is_false(mirror.is_slave({ x = -160, y = 0 }, false, true, LINES))
        assert.is_true(mirror.is_slave({ x = 0, y = -160 }, false, true, LINES))
    end)

    it("calls a chunk past either line a slave when both axes mirror", function()
        assert.is_true(mirror.is_slave({ x = -160, y = 0 }, true, true, LINES))
        assert.is_true(mirror.is_slave({ x = 0, y = -160 }, true, true, LINES))
        assert.is_true(mirror.is_slave({ x = -160, y = -160 }, true, true, LINES))
    end)

    it("calls nothing a slave when neither axis mirrors", function()
        assert.is_false(mirror.is_slave({ x = -1600, y = -1600 }, false, false, LINES))
    end)
end)

describe("locate_master", function()
    it("reflects a slave back across the line", function()
        assert.same({ x = 0, y = 0 }, mirror.locate_master({ x = -288, y = 0 }, true, false, LINES))
    end)

    it("leaves the axis that is not mirrored alone", function()
        assert.same({ x = 0, y = 96 }, mirror.locate_master({ x = -288, y = 96 }, true, false, LINES))
    end)

    it("reflects both axes at once", function()
        assert.same({ x = 0, y = 0 },
            mirror.locate_master({ x = -288, y = -288 }, true, true, LINES))
    end)

    it("leaves a chunk that is already a master where it is", function()
        assert.same({ x = 64, y = 0 }, mirror.locate_master({ x = 64, y = 0 }, true, false, LINES))
    end)
end)

describe("locate_slaves", function()
    it("gives one reflection when one axis mirrors", function()
        assert.same({ { x = -288, y = 0 } },
            mirror.locate_slaves({ x = 0, y = 0 }, true, false, LINES))
    end)

    it("gives three when both do: one per axis and one diagonal", function()
        assert.same({ { x = -288, y = 0 }, { x = 0, y = -288 }, { x = -288, y = -288 } },
            mirror.locate_slaves({ x = 0, y = 0 }, true, true, LINES))
    end)

    it("gives none for a chunk that is itself a slave", function()
        assert.same({}, mirror.locate_slaves({ x = -288, y = 0 }, true, false, LINES))
    end)

    it("reflects the chunk sitting on the line, which is the last master", function()
        -- the master half is inclusive of its line, so the chunk whose left edge is the
        -- line still has a reflection, immediately the other side of it
        assert.same({ { x = -160, y = 0 } },
            mirror.locate_slaves({ x = LINES.x, y = 0 }, true, false, LINES))
        assert.same({ { x = 0, y = -160 } },
            mirror.locate_slaves({ x = 0, y = LINES.x }, false, true, LINES))
    end)

    it("reflects the chunk on both lines to all three partners", function()
        assert.same({ { x = -160, y = LINES.x }, { x = LINES.x, y = -160 }, { x = -160, y = -160 } },
            mirror.locate_slaves({ x = LINES.x, y = LINES.x }, true, true, LINES))
    end)

    it("gives only the axis whose line the chunk is past", function()
        -- a chunk south of the y line but east of the x line reflects on x alone
        local slaves = mirror.locate_slaves({ x = 0, y = -288 }, true, true, LINES)
        assert.same({ { x = -288, y = -288 } }, slaves)
    end)
end)

describe("the two directions together", function()
    it("round trip: every slave points back at the master that made it", function()
        for _, axes in ipairs({ { true, false }, { false, true }, { true, true } }) do
            local mirror_x, mirror_y = axes[1], axes[2]
            for chunk_x = -4, 8 do
                for chunk_y = -4, 8 do
                    local master = { x = chunk_x * 32, y = chunk_y * 32 }
                    if not mirror.is_slave(master, mirror_x, mirror_y, LINES) then
                        for _, slave in ipairs(
                            mirror.locate_slaves(master, mirror_x, mirror_y, LINES)) do
                            assert.is_true(mirror.is_slave(slave, mirror_x, mirror_y, LINES),
                                ("slave %d,%d is not past a line"):format(slave.x, slave.y))
                            assert.same(master,
                                mirror.locate_master(slave, mirror_x, mirror_y, LINES),
                                ("%d,%d -> %d,%d did not come back")
                                :format(master.x, master.y, slave.x, slave.y))
                        end
                    end
                end
            end
        end
    end)

    it("keeps every reflection chunk-aligned", function()
        for chunk_x = 0, 8 do
            for _, line in ipairs({ 0, -32, -128, -320, 96, 320 }) do
                for _, slave in ipairs(mirror.locate_slaves(
                    { x = chunk_x * 32, y = 0 }, true, false, { x = line, y = line })) do
                    assert.equals(0, slave.x % 32,
                        ("line at %d put a slave at x=%d, off the chunk grid"):format(line, slave.x))
                end
            end
        end
    end)

    it("puts the reflection an equal distance the other side of the line", function()
        -- a master whose near edge is d tiles past the line reflects to a chunk whose far
        -- edge is d tiles before it
        local master = { x = 0, y = 0 }
        local slave = mirror.locate_slaves(master, true, false, LINES)[1]
        assert.equals(master.x - LINES.x, LINES.x - (slave.x + 32))
    end)
end)

describe("a line anywhere, on either axis", function()
    it("mirrors about a line east of the origin as readily as one west of it", function()
        local lines = { x = 5 * 32, y = 0 }
        -- a master at 5 chunks east reflects to the chunk immediately west of the line
        assert.same({ { x = 4 * 32, y = 0 } },
            mirror.locate_slaves({ x = 5 * 32, y = 0 }, true, false, lines))
        assert.same({ x = 5 * 32, y = 0 },
            mirror.locate_master({ x = 4 * 32, y = 0 }, true, false, lines))
    end)

    it("takes a different line on each axis", function()
        local lines = { x = 2 * 32, y = -7 * 32 }
        local slaves = mirror.locate_slaves({ x = 2 * 32, y = -7 * 32 }, true, true, lines)
        assert.same({
            { x = 1 * 32, y = -7 * 32 },
            { x = 2 * 32, y = -8 * 32 },
            { x = 1 * 32, y = -8 * 32 },
        }, slaves)
    end)

    it("round trips whichever way the lines are placed", function()
        for _, lines in ipairs({ { x = 0, y = 0 }, { x = 3 * 32, y = -11 * 32 },
                                 { x = -6 * 32, y = 9 * 32 } }) do
            for chunk_x = -6, 8 do
                for chunk_y = -6, 8 do
                    local master = { x = chunk_x * 32, y = chunk_y * 32 }
                    if not mirror.is_slave(master, true, true, lines) then
                        for _, slave in ipairs(mirror.locate_slaves(master, true, true, lines)) do
                            assert.is_true(mirror.is_slave(slave, true, true, lines),
                                ("slave %d,%d is not past a line"):format(slave.x, slave.y))
                            assert.same(master, mirror.locate_master(slave, true, true, lines))
                        end
                    end
                end
            end
        end
    end)
end)

describe("centre_of", function()
    it("finds the midpoint of two spawns", function()
        assert.same({ x = 0, y = 0 },
            mirror.centre_of({ { x = -960, y = 0 }, { x = 960, y = 0 } }))
    end)

    it("finds it wherever the pair sits", function()
        -- PVP puts its circle around a randomly chosen centre, nowhere near the origin
        assert.same({ x = 320, y = -640 },
            mirror.centre_of({ { x = 320 - 896, y = -640 - 256 },
                               { x = 320 + 896, y = -640 + 256 } }))
    end)

    it("finds the centre of four spawns on a circle", function()
        assert.same({ x = 0, y = 0 }, mirror.centre_of({
            { x = -256, y = 896 }, { x = -896, y = -256 },
            { x = 256, y = -896 }, { x = 896, y = 256 } }))
    end)

    it("has nothing to say about no spawns", function()
        assert.is_nil(mirror.centre_of({}))
    end)

    it("comes out within half a chunk for every rotation PVP might pick", function()
        -- Exact almost always, because the snapping is symmetric -- but not in floating
        -- point: sin(30 degrees) is 0.49999999999999994, which snaps down a whole chunk
        -- while its opposite snaps up. Half a chunk is the worst of it.
        local function snap(v) return v > 0 and 32 * math.floor(v / 32) or 32 * math.ceil(v / 32) end
        local centre = { x = 7 * 32, y = -11 * 32 }
        local worst = 0
        for degrees = 0, 359 do
            for _, count in ipairs({ 2, 4 }) do
                local spawns = {}
                for k = 1, count do
                    local angle = math.rad(degrees) + (k * 2 * math.pi / count)
                    spawns[k] = {
                        x = centre.x + snap(math.cos(angle) * 960),
                        y = centre.y + snap(math.sin(angle) * 960),
                    }
                end
                local found = mirror.centre_of(spawns)
                worst = math.max(worst, math.abs(found.x - centre.x), math.abs(found.y - centre.y))
            end
        end
        assert.is_true(worst <= 16, "worst error was " .. worst .. " tiles")
    end)
end)

describe("on_chunk_boundary", function()
    it("leaves a point already on one alone", function()
        assert.same({ x = 320, y = -640 }, mirror.on_chunk_boundary({ x = 320, y = -640 }))
    end)

    it("moves one that is not back to the boundary before it", function()
        assert.same({ x = 320, y = -672 }, mirror.on_chunk_boundary({ x = 340, y = -641 }))
    end)
end)
