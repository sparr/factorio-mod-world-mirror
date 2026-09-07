-- Before 2.1.5 both mirror lines were a single distance west and north of the origin,
-- named world-mirror-chunk-offset. They are now a position each, either side of zero.
--
-- A world that had the offset at its default carries over untouched, since the new
-- defaults describe the same map. A world where it was changed would otherwise start
-- mirroring about a different line than the one its existing chunks were built around,
-- so the old value is read here and written into the new settings.
local offset = settings.global["world-mirror-chunk-offset"]
if not offset then return end

-- Both are counted in chunks. The old one was a distance west and north, so 10 meant a
-- line ten chunks before the origin; the new one is the position itself, so that same
-- line is -10. The sign is the whole of the conversion.
local line_in_chunks = -offset.value
if settings.global["world-mirror-x-line"].value == -4
  and settings.global["world-mirror-y-line"].value == -4
  and line_in_chunks ~= -4
then
  settings.global["world-mirror-x-line"] = { value = line_in_chunks }
  settings.global["world-mirror-y-line"] = { value = line_in_chunks }
  log("World Mirror: carried the old chunk offset of " .. offset.value ..
      " over to mirror lines at chunk " .. line_in_chunks .. ".")
end
