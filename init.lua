-- Minetest Player Cleaner (for EdenLost).
-- license: Apache 2.0
-- Custom designed for EdenLost.  Assumes the presense of EdenLost's custom
-- `citizenship` mod, which adds a priv (`citizenship`).  Players without this
-- priv are likely to be deleted by this mod.
--
pcleaner = {}

-- How long to sleep (in seconds) between removal of players in queue.
local delay = 1.0

-- Queue of players to remove.
local queue = {}

local function log(txt)
    minetest.log('action', '[pcleaner] ' .. (txt or ''))
end

local function remove_file(fname)
    local f = io.open(fname, 'r')
    if f then
        local size = f:seek('end')
        f:close()
        log('Removing file ' .. fname .. ' bytes ' .. size)
        os.remove(fname)
    end
end

local function remove_from_serialized_by_pname(fname, pname)
    local fqpn = minetest.get_worldpath() .. DIR_DELIM .. fname
    local f = io.open(fqpn, 'r')
    if f then
        local data = minetest.deserialize(f:read('*all'))
        f:close()
        if data[pname] ~= nil then
            log('Removing ' .. pname .. ' from ' .. fname)
            data[pname] = nil
            minetest.safe_file_write(fqpn, minetest.serialize(data))
        end
    end
end

local function remove_areas(pname)
    if minetest.get_modpath('areas') == nil then return end
    local list = {}
    for id, area in pairs(areas.areas) do
        if areas:isAreaOwner(id, pname) then table.insert(list, id) end
    end
    if #list < 1 then return end
    log('Removing ' .. #list .. ' owned areas from player ' .. pname)
    for _, id in ipairs(list) do areas:remove(id, false) end
    areas:save()
end

local function remove_atm_stuff(pname)
    if minetest.get_modpath('atm') == nil then return end

    atm.readaccounts()
    if type(atm.balance[pname]) == 'number' then
        log('Removing atm.balance for ' .. pname .. '' .. atm.balance[pname])
        atm.balance[pname] = nil
        atm.saveaccounts()
    end

    atm.read_transactions()
    if atm.completed_transactions[pname] then
        log('Removing atm.completed_transactions for ' .. pname)
        atm.completed_transactions[pname] = nil
        atm.write_transactions()
    end
    -- TOOD: Whould we remove transaction from other players that involved
    -- the nuked player?
end

local function remove_bed_spawn(pname)
    if minetest.get_modpath('beds') == nil then return end
    if beds.spawn[pname] == nil then return end
    log('Removing bed spawn for ' .. pname .. ' ' ..
            minetest.pos_to_string(beds.spawn[pname], 0))
    beds.spawn[pname] = nil
    beds.save_spawns()
end

local function remove_jail(pname)
    if minetest.get_modpath('jail') == nil then return end
    -- TODO: need to add API hook to jail mod.
    -- It is not safe for other mods to rewrite the `jail-data.txt` file, since
    -- the jail mod caches it entirely in RAM anyway.
end

local function remove_hotbar(pname)
    if minetest.get_modpath('dreambuilder_hotbar') then
        remove_from_serialized_by_pname('hotbar_settings', pname)
    end
end

local function remove_mailbox(pname)
    -- https://github.com/minetest-mail/mail_mod.git
    if minetest.get_modpath('mail') then
        remove_file(mail.getMailFile(pname))
        remove_file(mail.getContactsFile(pname))
    end
end

local function remove_xp_redo(pname)
    if minetest.get_modpath('xp_redo') == nil then return end
    local id = nil
    for idx, entry in ipairs(xp_redo.highscore) do
        if entry['name'] == pname then id = idx end
    end
    if id then
        log('Removing xp_redo.highscore for ' .. pname .. ' for ' ..
                xp_redo.highscore[id].xp)
        table.remove(xp_redo.highscore, id)
    end
    -- xp_redo does not expose an API to force its file to flush, but the
    -- mod rewrites `highscore.txt` every 60s from the xr_redo data anyway.
end

-- Removes the indicated player from the system.
pcleaner.remove_player = function(pname)
    -- Please keep these alphabetized.
    remove_areas(pname)
    remove_atm_stuff(pname)
    remove_bed_spawn(pname)
    remove_hotbar(pname)
    remove_jail(pname)
    remove_mailbox(pname)
    remove_xp_redo(pname)

    local auth_handler = minetest.get_auth_handler()
    if auth_handler.get_auth(pname) then
        log('Removing player ' .. pname)
        minetest.remove_player(pname)
        auth_handler.delete_auth(pname)
    end
end

-- Returns list of players, read one per line from a text file in the
-- game's 'WORLD' directory.
local function load_player_list(fname)
    local names = {}
    local fqpn = minetest.get_worldpath() .. DIR_DELIM .. fname
    local handler = minetest.get_auth_handler()
    for line in io.lines(fqpn) do
        -- TODO 'trim' the string.  reject comments.
        if handler.get_auth(line) then table.insert(names, line) end
    end
    return names
end

local function process_queue()
    local pname = next(queue)
    if pname == nil then return end
    pcleaner.remove_player(pname)
    queue[pname] = nil
    minetest.after(delay, process_queue)
end

local function chat_cmd_handler(pname, param)
    local parts = param:split(' ')
    if (parts[1] == 'load') and (type(parts[2]) == 'string') then
        local fname = parts[2]
        local players = load_player_list(fname)
        minetest.chat_send_player(pname, 'Loaded ' .. #players ..
                                      ' player names from ' .. fname)
        for _, pname in ipairs(players) do queue[pname] = true end
    elseif parts[1] == 'run' then
        minetest.after(0, process_queue)
    elseif parts[1] == 'cancel' then
        queue = {}
    elseif (parts[1] == 'delay') and (type(parts[2]) ~= 'nil') then
        delay = tonumber(parts[2]) or 1.0
        minetest.chat_send_player(pname, 'Setting delay to ' .. delay)
    else
        minetest.chat_send_player(pname, 'Unrecognized /pcleaner command.')
        for i, k in ipairs(parts) do
           log('/pcleaner ' .. i .. ' ' .. type(parts[i]) .. ' ' .. parts[i])
        end
    end
end

minetest.register_chatcommand('pcleaner', {
    privs = {staff = true},
    description = 'Issue commands to the player_cleaner mod.  See README for details.',
    params = '<command> <args>',
    func = chat_cmd_handler
})
