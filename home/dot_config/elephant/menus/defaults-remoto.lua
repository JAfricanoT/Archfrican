Name = "defaults-remoto"
NamePretty = "Acceso remoto"
Icon = "applications-system"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("remoto")
end
