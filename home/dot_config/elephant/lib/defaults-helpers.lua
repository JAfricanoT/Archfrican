function BuildCategoryEntries(slug)
  local entries = {}
  local bin = os.getenv("HOME") .. "/.local/bin/archfrican-defaults"
  local handle = io.popen(bin .. " __list " .. slug)
  if not handle then return entries end
  for line in handle:lines() do
    local disp, installed = line:match("^([^\t]*)\t([01])$")
    if disp then
      local text = disp
      if installed == "0" then text = "⤓ Instalar " .. disp .. "…" end
      table.insert(entries, {
        Text = text,
        Value = disp,
        Actions = { apply = bin .. " __apply " .. slug .. " '%VALUE%'" },
      })
    end
  end
  handle:close()
  return entries
end
