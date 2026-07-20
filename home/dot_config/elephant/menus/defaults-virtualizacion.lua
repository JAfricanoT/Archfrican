Name = "defaults-virtualizacion"
NamePretty = "Máquinas virtuales"
Icon = "applications-system"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("virtualizacion")
end
