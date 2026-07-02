Name = "defaults-archivos"
NamePretty = "Gestor de archivos"
Icon = "system-file-manager"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("archivos")
end
