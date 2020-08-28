--[[

    track player casted spell debuffs on targets, tested with warlock, hunter and priest so far

    TODO:
        get spell id table
        test addon with party/raid groups
        consider how to include non casted spells (effects from talents), does this exist in classic or more of a retail thing?
        consider how to add non spells, melee hits, weapons with effects ? - this will show in cleu/unit_aura, how to get spell/weapon/effect id? classic cleu is basic only

    THEORY:
        UnitBuff() returns no time data but does return spell id and source
        UNIT_SPELLCAST_SUCCEEDED returns a spell id
        COMBAT_LOG_EVENT_UNFILTERED returns a source and target

        by adding a time stamp to the events, the addon can track time, spell id,
        source and target. this info can be sent other other players with the addon
        where it then updates cooldowns which are added the default target debuff frames

]]

local _, Debuffs = ...


-- cooldown widget table
Debuffs.CooldownFrames = {}

-- combat table, { targetGUID = { sourceGUID = { spellID = start }}}, use this to grab the correct cooldown data for current target/source
Debuffs.Combat = {}

-- table to hold last spell cast data
Debuffs.UNIT_SPELLCAST_SUCCEEDED_EVENT = {}

-- table of spells to check when updatign cooldown widgets
Debuffs.Spells = {
    -- priest
    [589] = { Duration = 18, Mod = 0 }, -- shadow word: pain rank 1
    -- warlock
    [348] = { Duration = 15, Mod = 0 }, -- immolate rank 1
    [172] = { Duration = 12, Mod = 0 }, -- corruption rank 1
    [6222] = { Duration = 12, Mod = 0 }, -- corruption rank 2
    [6223] = { Duration = 12, Mod = 0 }, -- corruption rank 3
    [7648] = { Duration = 12, Mod = 0 }, -- corruption rank 4
    [11671] = { Duration = 12, Mod = 0 }, -- corruption rank 5
    [980] = { Duration = 24, Mod = 0 }, -- agony rank 1
    [5782] = { Duration = 10, Mod = 0 }, -- fear rank 1
    [689] = { Duration = 5, Mod = 0 }, -- drain life rank 1
    [1120] = { Duration = 15, Mod = 0 }, -- drain soul rank 1
    -- hunter
    [5116] = { Duration = 4, Mod = 0 }, -- concussive shot
    [1978] = { Duration = 15, Mod = 0 }, -- serpent string rank 1
    [13549] = { Duration = 15, Mod = 0 }, -- serpent string rank 2
    [13550] = { Duration = 15, Mod = 0 }, -- serpent string rank 3
}


function Debuffs:ADDON_LOADED(...)
    if ... == 'Debuffs' then
        self.f:UnregisterEvent('ADDON_LOADED')
        local prefixRegistered = C_ChatInfo.RegisterAddonMessagePrefix('debuffs-cast')

        -- TODO: make addon_loaded var if prefix fails
    end
end


function Debuffs:SetCooldowns()
    local targetGUID = UnitGUID('target')
    for i = 1, 40 do
        if _G['TargetFrameDebuff'..i] then
            if not Debuffs.CooldownFrames['TargetFrameDebuff'..i] then
                Debuffs.CooldownFrames['TargetFrameDebuff'..i] = CreateFrame("Cooldown", tostring('TargetFrameDebuff'..i.."Cooldown"), _G['TargetFrameDebuff'..i], "CooldownFrameTemplate")
                Debuffs.CooldownFrames['TargetFrameDebuff'..i]:SetHideCountdownNumbers(false)
            end
            local name, icon, count, debuffType, duration, expirationTime, source, b, c, spellID, e = UnitDebuff("target", i)
            if source then
                local sourceGUID = UnitGUID(source)
                if sourceGUID and targetGUID and self.Combat[targetGUID] and self.Combat[targetGUID][sourceGUID] then
                    for spell, start in pairs(self.Combat[targetGUID][sourceGUID]) do
                        if Debuffs.Spells[spellID] and (spell == spellID) then
                            Debuffs.CooldownFrames['TargetFrameDebuff'..i]:SetCooldown(start, self.Spells[spell].Duration)
                        end
                    end
                end
            end
        end
    end
end

--- clear tables after combat
function Debuffs:PLAYER_REGEN_ENABLED(...)
    wipe(self.Combat)
    wipe(self.UNIT_SPELLCAST_SUCCEEDED_EVENT) -- maybe a dodgy name?
end

-- get data from message and update combat table, local vars required ??? maybe pass in directly from table
function Debuffs:CHAT_MSG_ADDON(...)
    local prefix = select(1, ...)
    local sender = select(4, ...)
    local player, realm = UnitFullName('player')
    -- use this to test without filtering player
    --if prefix == 'debuffs-cast' then
    if prefix == 'debuffs-cast' and (sender ~= tostring(player..'-'..realm)) then
        local msg = select(2, ...)
        local tbl = {}
        for k in msg:gmatch("([^$]+)") do
            table.insert(tbl, k)
        end
        if #tbl == 4 then
            local targetGUID, sourceGUID, spellID = tbl[1], tbl[2], tonumber(tbl[3])
            local start = GetTime() - 0.2
            -- print('ADDON MSG')
            -- local spellName = select(1, GetSpellInfo(spellID))
            -- print('spell', spellID, spellName)
            -- print('start (server time)', tbl[4])
            -- print('server time', GetServerTime())
            -- print('calc local start', start)
            -- print('---------------------')
            if not self.Combat[targetGUID] then
                self.Combat[targetGUID] = {
                    [sourceGUID] = {}
                }
            end
            self.Combat[targetGUID][sourceGUID][spellID] = start
        end
    end
end

-- this event fires before CLEU, catch spell data and store as reference to check
function Debuffs:UNIT_SPELLCAST_SUCCEEDED(...)
    local spellID = select(3, ...)
    local target = select(1, ...)
    if spellID and target then
        self.UNIT_SPELLCAST_SUCCEEDED_EVENT = {
            SpellID = tonumber(spellID),
            ServerTime = GetServerTime(),
            SourceGUID = UnitGUID('player'),
        }
    else
        wipe(self.UNIT_SPELLCAST_SUCCEEDED_EVENT)
    end
    -- local spellName = select(1, GetSpellInfo(spellID))
    -- print('SPELLCAST')
    -- print('spell', spellID, spellName)
    -- print('local time', GetTime())
    -- print('server time', GetServerTime())
    -- print('--------------------')
end

-- using this we know the spell landed without being blocked/resisted etc, this keeps start times accurate for cooldown widgets
function Debuffs:COMBAT_LOG_EVENT_UNFILTERED(...)
    local cleu = {CombatLogGetCurrentEventInfo()}
    local t = GetTime()
    local s = GetServerTime()
    local sourceGUID = cleu[4]
    local targetGUID = cleu[8]

    if cleu[2] == 'RANGE_AURA_APPLIED' or 'SPELL_AURA_APPLIED' then
        print('AURA APPLIED CLEU - RANGE or SPELL')
        print('local time:', t)
        print('aura type:', cleu[15])
        print('amount:', cleu[16])
        print('--------------------'
    end

    if cleu[2] == 'RANGE_AURA_REFRESH' or 'SPELL_AURA_REFRESH' then
        print('AURA REFRESHED CLEU - RANGE or SPELL')
        print('local time:', t)
        print('aura type:', cleu[15])
        print('amount:', cleu[16])
        print('--------------------'
    end

    if cleu[2] == 'SWING_AURA_APPLIED' then
        print('AURA APPLIED CLEU - SWING')
        print('local time:', t)
        print('aura type:', cleu[12])
        print('amount:', cleu[13])
        print('--------------------'
    end

    if cleu[2] == 'SWING_AURA_REFRESH' then
        print('AURA REFRESHED CLEU - SWING')
        print('local time:', t)
        print('aura type:', cleu[12])
        print('amount:', cleu[13])
        print('--------------------'
    end

    if cleu[2] == 'SPELL_CAST_SUCCESS' then
        -- local timestamp = cleu[1]
        -- --local timestamp_trimmed = tonumber(tostring(timestamp):sub(1, -5))
        -- print('CLEU')
        -- print('server time', s)
        -- print('timestamp', timestamp)
        if self.UNIT_SPELLCAST_SUCCEEDED_EVENT and next(self.UNIT_SPELLCAST_SUCCEEDED_EVENT) then
            --local eventDelay = 1.0
            --if (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime >= (tonumber(tostring(cleu[1]):sub(1, -5)) - eventDelay)) and (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SourceGUID == sourceGUID) then
            if (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime == s) and (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SourceGUID == sourceGUID) then
                if not self.Combat[targetGUID] then
                    self.Combat[targetGUID] = {
                        [sourceGUID] = {}
                    }
                end
                self.Combat[targetGUID][sourceGUID][self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID] = (t - 0.2)
                -- --print('cleu event matches unit_spellcast event')
                -- local inInstance, instanceType = IsInInstance()
                -- if inInstance and (instanceType:lower() == 'party' or instanceType:lower() == 'raid') then
                --     C_ChatInfo.SendAddonMessage('debuffs-cast', tostring(targetGUID..'$'..sourceGUID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime), instanceType:upper())
                -- else
                --     -- normal option is to just add directly
                --     if not self.Combat[targetGUID] then
                --         self.Combat[targetGUID] = {
                --             [sourceGUID] = {}
                --         }
                --     end
                --     self.Combat[targetGUID][sourceGUID][self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID] = t
                -- end
                -- use this to test sending data
                -- C_ChatInfo.SendAddonMessage('debuffs-cast', tostring(targetGUID..'$'..sourceGUID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime), 'SAY')
            end
        end
        --print('--------------------')
    end
end

Debuffs.f = CreateFrame('FRAME', 'DebuffEventFrame', UIParent)
Debuffs.f:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
Debuffs.f:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED')
Debuffs.f:RegisterEvent('PLAYER_REGEN_ENABLED')
Debuffs.f:RegisterEvent('ADDON_LOADED')
Debuffs.f:RegisterEvent('CHAT_MSG_ADDON')

Debuffs.f:SetScript('OnEvent', function(self, event, ...)
    Debuffs[event](Debuffs, ...)
end)
Debuffs.f:SetScript('OnUpdate', function()
     Debuffs:SetCooldowns()
end)