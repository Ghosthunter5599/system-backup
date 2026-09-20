-- Personal input & gestures configuration
-- Fixes standard Caps Lock key behavior and enables 3-finger workspace swipe gestures

hl.config({
  input = {
    -- Restore standard Caps Lock behavior (overriding Omarchy's compose:caps default)
    kb_options = "",

    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})

-- 3-finger touchpad gesture for changing workspaces
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
