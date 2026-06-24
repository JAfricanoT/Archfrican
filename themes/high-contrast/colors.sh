# High-contrast (accessibility). Maximal contrast for low vision — the shell (waybar, swaync, niri
# borders, ghostty, fuzzel) goes pure black / white / amber. GTK apps follow via the GNOME a11y
# high-contrast gsetting that archfrican-a11y also flips (libadwaita/GTK4 respect it).
export GTK_SCHEME="prefer-dark"; export GTK_THEME="WhiteSur-Dark"; export ICON_THEME="WhiteSur-dark"
export BG="#000000"  BG_ALT="#0a0a0a"  BG_DIM="#2a2a2a"
export FG="#ffffff"  FG_DIM="#e6e6e6"
export ACCENT="#ffe000"  ACCENT_FG="#000000"
export RED="#ff5555" GREEN="#55ff55" YELLOW="#ffe000" BLUE="#55aaff" MAGENTA="#ff77ff" CYAN="#55ffff"
export BORDER_ACTIVE="$ACCENT" BORDER_INACTIVE="#ffffff"
