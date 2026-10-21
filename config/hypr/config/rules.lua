-- Swash must float so its image editor can be sized independently.
hl.window_rule({ match = { class = "^(dev\\.lemmy\\.swash|swash)$" }, float = true, center = true })
-- Suppress application maximize requests; keep tiling under compositor control.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
