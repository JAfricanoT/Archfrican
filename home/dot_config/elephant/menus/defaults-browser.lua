Name = "defaults-browser"
NamePretty = "Navegador web"
Icon = "web-browser"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("browser")
end
