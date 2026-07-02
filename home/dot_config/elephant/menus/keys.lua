Name = "keys"
NamePretty = "Atajos de teclado"
Icon = "input-keyboard"
Cache = true
FixedOrder = true
RefreshOnChange = {
  os.getenv("HOME") .. "/.config/niri/config.kdl",
  "/etc/keyd/default.conf",
}

function GetEntries()
  local entries = {}
  local bin = os.getenv("HOME") .. "/.local/bin/archfrican-keys"
  local handle = io.popen(bin .. " __tsv")
  if not handle then return entries end
  local in_keyd = false
  for line in handle:lines() do
    if line == "" then
      in_keyd = true
    elseif in_keyd then
      local key, ctrl = line:match("^([^\t]*)\t([^\t]*)$")
      if key then
        table.insert(entries, { Text = key, Subtext = "macOS ⌘ (keyd) · " .. ctrl, Value = key })
      end
    else
      local key, cat, desc = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if key then
        table.insert(entries, { Text = key, Subtext = cat .. " · " .. desc, Value = key })
      end
    end
  end
  handle:close()
  return entries
end
