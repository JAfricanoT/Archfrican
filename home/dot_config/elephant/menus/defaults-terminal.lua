Name = "defaults-terminal"
NamePretty = "Terminal"
Icon = "utilities-terminal"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("terminal")
end
