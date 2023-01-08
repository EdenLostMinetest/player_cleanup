# player_cleanup

Removes unused player accounts

## Caveat

This mod is a work-in-progress, and highly customized to EdenLost. A stock
minetest server will lack many of the mods that populate player metadata that
this mod requires to determine if a player account should be kept or not.
Furthermore, there is no minetest API that lets the server load the metadata for
an offline player. Such a thing was asked for many times (see the forums), but
never implemented. So this mod is split into two pieces:

- `player_analyzer.py` - A python script which runs "offline" and performs raw
  reads on `auth.sqlite` and `players.sqlite`. The output is a list of players
  to be removed.

- The in-game mod, which exposes a chat command `/pcleaner`, which performs the
  actual player removal.

## Usage

1. Make a backup of your server. Seriously. You've been warned.

1. Install the mod, restart the server.

1. Carefully read `player_analyzer.py` function `keep_player()`.

1. CD into the `world` folder (has the `players.sqlite` file in it).

1. Run `./worldmods/player_cleanup/player_analyzer.py`. Carefully examine the
   output (it writes to STDOUT).

1. Re-run the above command, grep out any players that you want to keep, write
   only the first column of text to a text file. Ex:

   ```
   $ cd ${WORLDIR}
   $ ./worldmods/player_cleanup/player_analyzer.py | \
     grep -v "^#" | awk '{ print $1 }' | sort > list.txt
   ```

1. Carefully examine `list.txt`. These are the players that will be removed from
   the server. You can hand-edit this file if you want to.

1. Log into the game world as a user with `staff` privs.

1. Chat command: `/pcleaner dryrun list.txt` and note the returned chat message.

1. When satisfied, run `/pcleaner delete list.txt` and the mod will remove all
   data for that player (player inventory, auth data, mailbox, etc...). To avoid
   halting the server while processing a huge list, the server will actually
   perform the removal in small batches, and run cycles every second until all
   targetted player accounts are removed.

## Player Removal

The following things are removed:

1. Player's inventory, via `minetest.remove_player()`

1. Player's auth data, via `minetest.remove_player_auth()`

1. Players mail box and contact list from the `mail` mod (if present).

   - `${WORLD}/mails/${NAME}.json`
   - `${WORLD}/mails/contacts/${NAME}.json`

1. Player's `dreambuilder_hotbar` setting

   - `${WORLD}/hotbar_settings` (serialized lua table)

1. Player's ATM account and account history (`atm` mod)

   - `${WORLD}/atm_accounts` (flat text file)
   - `${WORLD}/atm_wt_transactions` (serialized lau table)

1. Protected areas (non-recursively) via the `areas` mod

   - `${WORLD}/areas.dat` (serialized lua table)

1. `beds` mod respawn position.

   - `${WORLD}/beds_spawn` (flat text file)

1. `highscore.txt` entry (from `xp_redo` mod).

Other things that we could possibly remove player data from are:

- `jailData.txt` (requires change to the `jail` mod first).
- `mod_storage/awards`
- `mod_storage/draconis` (aux_key_setting, bonded_dragons)
- `mod_storage/moremesecons_wireless`
- `mod_storage/playerfactions`
- `mod_storage/rhotator`
- `mod_storage/skinsdb`
  - Needs update to mod, or add a command to clear all entries for non-existant
    players.

These things are indexed by custom data files and could be removed, but also
require the mod to edit the actual map data as well.

- travelnets (indexed by player in `mod_travelnet.data`, json format) need to
  load the mapblock, nuke the node).
- elevators.
- Smartshop data (also need to remove the smart-shop nodes).

These cannot be removed, as they require a full scan of the map database:

- `protector:protection` ("prot blocks")
- `bones:bones`
