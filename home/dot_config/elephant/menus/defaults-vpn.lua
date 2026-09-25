Name = "defaults-vpn"
NamePretty = "VPN"
Icon = "network-vpn"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("vpn")
end
