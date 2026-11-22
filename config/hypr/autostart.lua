-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Trim Zen's saved session to one window before anything can launch it
-- (Zen otherwise reopens every window from the last session).
o.launch_on_start(os.getenv("HOME") .. "/.config/hypr/scripts/zen-trim-session")
