Name = "defaults-mensajeria"
NamePretty = "Mensajería"
Icon = "internet-chat"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("mensajeria")
end
