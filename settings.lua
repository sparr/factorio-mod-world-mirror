data:extend(
  {
    {
      type = "bool-setting",
      name = "world-mirror-x",
      setting_type = "runtime-global",
      default_value = true
    },
    {
      type = "bool-setting",
      name = "world-mirror-y",
      setting_type = "runtime-global",
      default_value = false
    },
    {
      -- Kept only so a world saved before 2.1.5 can be read and carried over: see
      -- migrations/world-mirror_2.1.5.lua. Hidden, because nothing should set it now.
      type = "int-setting",
      name = "world-mirror-chunk-offset",
      setting_type = "runtime-global",
      default_value = 4,
      minimum_value = 0,
      hidden = true,
      order = "z"
    },
    {
      type = "int-setting",
      name = "world-mirror-x-line",
      setting_type = "runtime-global",
      default_value = -4,
      order = "c"
    },
    {
      type = "int-setting",
      name = "world-mirror-y-line",
      setting_type = "runtime-global",
      default_value = -4,
      order = "d"
    },
  }
)
