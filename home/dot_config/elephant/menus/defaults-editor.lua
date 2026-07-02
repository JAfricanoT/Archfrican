Name = "defaults-editor"
NamePretty = "Editor / IDE"
Icon = "accessories-text-editor"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("editor")
end
