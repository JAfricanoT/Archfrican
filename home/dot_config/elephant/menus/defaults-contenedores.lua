Name = "defaults-contenedores"
NamePretty = "Gestor de contenedores"
Icon = "applications-system"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("contenedores")
end
