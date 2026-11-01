# dmgbuild settings for islo.'s disk image (used by scripts/create-dmg.sh).
# Positions match the artwork in background.tiff (see background.swift).
app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"

window_rect = ((200, 140), (640, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
hide_extensions = ["islo.app"]
icon_locations = {
    "islo.app": (160, 238),
    "Applications": (480, 238),
}
