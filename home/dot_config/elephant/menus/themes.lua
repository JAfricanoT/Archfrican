Name = "themes"
NamePretty = "Temas"
Icon = "preferences-desktop-theme"
Cache = false

function GetEntries()
  local entries = {}
  local dir = os.getenv("HOME") .. "/.archfrican/themes"
  local handle = io.popen("for d in '" .. dir .. "'/*/; do [ -d \"$d\" ] && basename \"$d\"; done 2>/dev/null")
  if not handle then return entries end
  for name in handle:lines() do
    if name ~= "" then
      table.insert(entries, { Text = name, Value = name, Actions = { apply = "theme-switch '%VALUE%'" } })
    end
  end
  handle:close()
  return entries
end
