# Archfrican Design Language — DARK. The default identity: signature teal (#2dd4bf) on warm graphite.
# Hybrid: keeps the WhiteSur GTK structure for comfort; the teal accent is injected on top of GTK/Qt
# in the cohesion layer (see templates/gtk.css, Commit 3). Non-colour identity (Inter + 7/11/15 radii)
# comes from themes/tokens.defaults.sh.
export GTK_SCHEME="prefer-dark"; export GTK_THEME="WhiteSur-Dark"; export ICON_THEME="WhiteSur-dark"
export BG="#17181b"  BG_ALT="#1f2024"  BG_DIM="#2d2f34"
export FG="#f2f1ee"  FG_DIM="#9a9892"
export ACCENT="#2dd4bf"  ACCENT_FG="#0f1011"
export RED="#ff6b5e" GREEN="#57d9a3" YELLOW="#f5c451" BLUE="#5aa9ff" MAGENTA="#c792ea" CYAN="#45d4c4"
export BORDER_ACTIVE="$ACCENT" BORDER_INACTIVE="#2d2f34"
