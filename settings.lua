data:extend(
  {
    {
      type = "bool-setting",
      name = "world-mirror-x",
      setting_type = "runtime-global",
      per_user = "false",
      admin = "true",
      default_value = true
    },
    {
      type = "bool-setting",
      name = "world-mirror-y",
      setting_type = "runtime-global",
      per_user = "false",
      admin = "true",
      default_value = false
    },
    {
      type = "int-setting",
      name = "world-mirror-chunk-offset",
      setting_type = "runtime-global",
      per_user = "false",
      admin = "true",
      default_value = 4,
      min_value = 0
    },
  }
)
