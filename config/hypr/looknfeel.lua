-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
	general = {
		-- No gaps between windows or borders.
		gaps_in = 2,
		gaps_out = 2,
		border_size = 2,

		-- Change to niri-like side-scrolling layout.
		-- layout = "scrolling",
	},
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
	decoration = {
		-- Use round window corners.
		rounding = 4,

		-- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
		dim_inactive = true,
		dim_strength = 0.15,
	},
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
hl.config({
	decoration = {
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		fullscreen_opacity = 1.0,
	},
})
-- Force full opacity everywhere, overriding Omarchy/theme defaults.
o.window(".*", { opacity = "1.0 1.0" })

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.

-- Liquid-glass top bar (Rice Bar "Liquid" style): blur whatever sits behind
-- the Rice Bar chrome layer. Windows are forced opaque above, so turning blur
-- on only affects layers that opt in with a layer rule.
hl.config({
	decoration = {
		blur = {
			enabled = true,
			size = 3,
			passes = 2,
			new_optimizations = true,
			xray = false,
			contrast = 1.0,
			brightness = 0.6,
			noise = 0.01,
			vibrancy = 0.15,
			vibrancy_darkness = 0.3,
			popups = false,
		},
	},
})
hl.layer_rule({ match = { namespace = "^omarchy-rice-bar$" }, blur = true, ignore_alpha = 0.0 })
