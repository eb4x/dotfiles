-- hyprctl monitors -j | jq '.[] | {name, width, height, scale}'
hl.monitor({ output = "DP-5", mode = "preferred", position = "auto", scale = 1.5 })
hl.monitor({ output = "DP-7", mode = "preferred", position = "auto", scale = 1.5 })
