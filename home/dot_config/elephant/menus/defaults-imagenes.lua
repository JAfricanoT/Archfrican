Name = "defaults-imagenes"
NamePretty = "Visor de imágenes"
Icon = "image-viewer"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("imagenes")
end
