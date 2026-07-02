Name = "defaults-pdf"
NamePretty = "Visor de PDF"
Icon = "application-pdf"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("pdf")
end
