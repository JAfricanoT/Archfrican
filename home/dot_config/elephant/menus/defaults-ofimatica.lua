Name = "defaults-ofimatica"
NamePretty = "Ofimática (Word/Excel/PowerPoint)"
Icon = "applications-office"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("ofimatica")
end
