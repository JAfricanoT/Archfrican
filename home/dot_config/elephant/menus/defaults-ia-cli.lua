Name = "defaults-ia-cli"
NamePretty = "IA / agentes (CLI)"
Icon = "utilities-terminal"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("ia-cli")
end
