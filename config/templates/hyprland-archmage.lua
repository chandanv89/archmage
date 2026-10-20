-- Archmage overlay for Hyprland 0.56+ (Lua config). Loaded via require("archmage").

hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- VMware SVGA: use the connected virtual output explicitly.
hl.monitor({
    output   = "Virtual-1",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

hl.config({
    input = {
        kb_layout = "us",
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar &")
end)
