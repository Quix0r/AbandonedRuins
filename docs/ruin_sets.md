# Ruin sets

Other mods can add their own ruin sets to *Abandoned Ruins - Updated*.

## Step 1: Ruin set setting

The settings should be modified in settings.lua. Make sure to set "AbandonedRuins >= 1.3.2" (this mod) as a dependency.

Add a ruin set name to the setting:
```lua
-- Add this to your init() function in control.lua:
remote.call("AbandonedRuins", "register_ruin_set", "my-ruin-set", false)
```
Optional: replace `false` with `true` to mark as default.

## Step 2: Ruin set remote interface

Adding a ruin set is a simple as providing the ruins to *Abandoned Ruins - Updated* via the add_ruin_set remote call in on_init and on_load in control.lua. For the format of ruins, see [ruin data format](https://github.com/Quix0r/AbandonedRuins-base/blob/master/docs/format.md).

Some extra care needs to be taken with ruin sets, as they are not save/loaded. That means they should not be changed during the game.<br>
For that reason, it is recommended to only add ruin sets in on_init and on_load. Furthermore, it is recommended to not conditionally change ruin sets.

```lua
local ruin_sets = {
  small = require("ruins/small") -- an array of ruins
  medium = require("ruins/medium") -- an array of ruins
  large = require("ruins/large") -- an array of ruins
}

local function init()
  remote.call("AbandonedRuins", "add_ruin_sets", "my-ruin-set", ruin_sets)
end

-- The ruin set is always created when the game is loaded, since the ruin sets are not save/loaded by AbandonedRuins.
-- Since this is using on_load, we must be sure that it always produces the same result for everyone.
script.on_init(init)
script.on_load(init)
```
With `ruin_sets` seperated from function call, you can e.g. modify the entities depending if other mods are installed. For an example clone `AbandonedRuins-base`, too, and study each file carefully.
