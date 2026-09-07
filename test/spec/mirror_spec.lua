local mirror = require("lib.mirror")

--- The shipped default: mirror east/west only, lines four chunks from the origin.
local OFFSET = 4 * 32

describe("is_slave", function()
    it("calls a chunk past the line a slave", function()
        assert.is_true(mirror.is_slave({ x = -160, y = 0 }, true, false, OFFSET))
    end)

    it("calls a chunk on the line a master", function()
        -- the line itself belongs to the master half
        assert.is_false(mirror.is_slave({ x = -OFFSET, y = 0 }, true, false, OFFSET))
    end)

    it("ignores an axis that is not being mirrored", function()
        assert.is_false(mirror.is_slave({ x = -160, y = 0 }, false, true, OFFSET))
        assert.is_true(mirror.is_slave({ x = 0, y = -160 }, false, true, OFFSET))
    end)

    it("calls a chunk past either line a slave when both axes mirror", function()
        assert.is_true(mirror.is_slave({ x = -160, y = 0 }, true, true, OFFSET))
        assert.is_true(mirror.is_slave({ x = 0, y = -160 }, true, true, OFFSET))
        assert.is_true(mirror.is_slave({ x = -160, y = -160 }, true, true, OFFSET))
    end)

    it("calls nothing a slave when neither axis mirrors", function()
        assert.is_false(mirror.is_slave({ x = -1600, y = -1600 }, false, false, OFFSET))
    end)
end)

describe("locate_master", function()
    it("reflects a slave back across the line", function()
        assert.same({ x = 0, y = 0 }, mirror.locate_master({ x = -288, y = 0 }, true, false, OFFSET))
    end)

    it("leaves the axis that is not mirrored alone", function()
        assert.same({ x = 0, y = 96 }, mirror.locate_master({ x = -288, y = 96 }, true, false, OFFSET))
    end)

    it("reflects both axes at once", function()
        assert.same({ x = 0, y = 0 },
            mirror.locate_master({ x = -288, y = -288 }, true, true, OFFSET))
    end)

    it("leaves a chunk that is already a master where it is", function()
        assert.same({ x = 64, y = 0 }, mirror.locate_master({ x = 64, y = 0 }, true, false, OFFSET))
    end)
end)

describe("locate_slaves", function()
    it("gives one reflection when one axis mirrors", function()
        assert.same({ { x = -288, y = 0 } },
            mirror.locate_slaves({ x = 0, y = 0 }, true, false, OFFSET))
    end)

    it("gives three when both do: one per axis and one diagonal", function()
        assert.same({ { x = -288, y = 0 }, { x = 0, y = -288 }, { x = -288, y = -288 } },
            mirror.locate_slaves({ x = 0, y = 0 }, true, true, OFFSET))
    end)

    it("gives none for a chunk that is itself a slave", function()
        assert.same({}, mirror.locate_slaves({ x = -288, y = 0 }, true, false, OFFSET))
    end)

    it("reflects the chunk sitting on the line, which is the last master", function()
        -- the master half is inclusive of its line, so the chunk whose left edge is the
        -- line still has a reflection, immediately the other side of it
        assert.same({ { x = -160, y = 0 } },
            mirror.locate_slaves({ x = -OFFSET, y = 0 }, true, false, OFFSET))
        assert.same({ { x = 0, y = -160 } },
            mirror.locate_slaves({ x = 0, y = -OFFSET }, false, true, OFFSET))
    end)

    it("reflects the chunk on both lines to all three partners", function()
        assert.same({ { x = -160, y = -OFFSET }, { x = -OFFSET, y = -160 }, { x = -160, y = -160 } },
            mirror.locate_slaves({ x = -OFFSET, y = -OFFSET }, true, true, OFFSET))
    end)

    it("gives only the axis whose line the chunk is past", function()
        -- a chunk south of the y line but east of the x line reflects on x alone
        local slaves = mirror.locate_slaves({ x = 0, y = -288 }, true, true, OFFSET)
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
                    if not mirror.is_slave(master, mirror_x, mirror_y, OFFSET) then
                        for _, slave in ipairs(
                            mirror.locate_slaves(master, mirror_x, mirror_y, OFFSET)) do
                            assert.is_true(mirror.is_slave(slave, mirror_x, mirror_y, OFFSET),
                                ("slave %d,%d is not past a line"):format(slave.x, slave.y))
                            assert.same(master,
                                mirror.locate_master(slave, mirror_x, mirror_y, OFFSET),
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
            for _, offset in ipairs({ 0, 32, 128, 320 }) do
                for _, slave in ipairs(
                    mirror.locate_slaves({ x = chunk_x * 32, y = 0 }, true, false, offset)) do
                    assert.equals(0, slave.x % 32,
                        ("offset %d put a slave at x=%d, off the chunk grid"):format(offset, slave.x))
                end
            end
        end
    end)

    it("puts the reflection an equal distance the other side of the line", function()
        -- a master whose near edge is d tiles past the line reflects to a chunk whose
        -- near edge is d tiles before it
        local offset = OFFSET
        local master = { x = 0, y = 0 }
        local slave = mirror.locate_slaves(master, true, false, offset)[1]
        assert.equals(master.x + offset, -offset - (slave.x + 32))
    end)
end)
