Name = "defaults-correo"
NamePretty = "Correo"
Icon = "mail-unread"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("correo")
end
