local active_border_color = "rgb(306772)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
    },
  },

  decoration = {
    blur = {
      enabled = true,
      size = 3,
      passes = 2,
    },
  },
})

-- Override the stock default-opacity rule (0.985 0.96) with something
-- more transparent. Apps that removed the tag keep their own opacity.
o.window({ tag = "default-opacity" }, { opacity = "0.95 0.92" })
