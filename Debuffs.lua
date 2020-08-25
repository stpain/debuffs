--[[

    TODO:
        get spell id table
        set up send addon messages
        consider the timings/lag/delay - is it latency or is it just a set time interval between the cast time and the debuff applying time ?
        make a function to check for resists/blocks - cast 1 fires no issues, cast 2 is resisted, now cooldown shows cast 2 start time incorrectly

    THEORY:
        if addon users send their spell cast data then the start time can be used
        with the duration from the spell table to determine the debuff cooldown.
        UnitBuff() returns a spell id and a source which can be checked against a 
        table to find the correct start time.

]]

local _, Debuffs = ...

local home, server = GetTime(), GetServerTime()
Debuffs.TimeDiff = (server-home)

Debuffs.CooldownFrames = {}

Debuffs.Combat = {}
Debuffs.UNIT_SPELLCAST_SUCCEEDED_EVENT = {}

Debuffs.Spells = {
    -- priest
    [589] = { Duration = 18, Name = '' }, -- shadow word: pain rank 1
    -- warlock
    [348] = { Duration = 15, Name = '' }, -- immolate rank 1
    [172] = { Duration = 12, Name = '' }, -- corruption rank 1
    [980] = { Duration = 24, Name = '' }, -- agony rank 1
    [5782] = { Duration = 10, Name = '' }, -- fear rank 1
    -- hunter
    [5116] = { Duration = 4, Name = '' }, -- concussive shot
    [1978] = { Duration = 15, Name = '' }, -- serpent string rank 1
    [13549] = { Duration = 15, Name = '' }, -- serpent string rank 2
    [13550] = { Duration = 15, Name = '' }, -- serpent string rank 3
}

function Debuffs:ADDON_LOADED(...)
    if ... == 'Debuffs' then
        self.f:UnregisterEvent('ADDON_LOADED')
        local prefixRegistered = C_ChatInfo.RegisterAddonMessagePrefix('debuffs-cast')
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

--- events
function Debuffs:PLAYER_REGEN_ENABLED(...)
    wipe(self.Combat)
    wipe(self.UNIT_SPELLCAST_SUCCEEDED_EVENT)
end

function Debuffs:CHAT_MSG_ADDON(...)
    local prefix = select(1, ...)
    if prefix == 'debuffs-cast' then
        local msg = select(2, ...)
        local d = {}
        for k in msg:gmatch("([^$]+)") do
            table.insert(d, k)
        end
        local targetGUID, sourceGUID, spellID, start = d[1], d[2], tonumber(d[3]), tonumber(d[4] - self.TimeDiff) + 1.0 -- convert server time back to local time with allowance for message delay
        -- print('ADDON MSG')
        -- local spellName = select(1, GetSpellInfo(spellID))
        -- print('spell', spellID, spellName)
        -- print('start (server time)', d[4])
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

function Debuffs:UNIT_SPELLCAST_SUCCEEDED(...)
    local spellID = select(3, ...)
    local spellName = select(1, GetSpellInfo(spellID))
    local target = select(1, ...)
    if spellID and target then
        self.UNIT_SPELLCAST_SUCCEEDED_EVENT = {
            SpellID = tonumber(spellID),
            ServerTime = GetServerTime(),
            TargetGUID = UnitGUID(target),
            SourceGUID = UnitGUID('player'),
        }
    else
        wipe(self.UNIT_SPELLCAST_SUCCEEDED_EVENT)
    end
    -- print('SPELLCAST')
    -- print('spell', spellID, spellName)
    -- print('local time', GetTime())
    -- print('server time', GetServerTime())
    -- print('--------------------')
end


function Debuffs:COMBAT_LOG_EVENT_UNFILTERED(...)
    local cleu = {CombatLogGetCurrentEventInfo()}
    if cleu[2] == 'SPELL_CAST_SUCCESS' then
        local sourceGUID = cleu[4]
        local targetGUID = cleu[8]
        local timestamp = cleu[1]
        local timestamp_trimmed = tonumber(tostring(timestamp):sub(1, -5))
        local t = GetTime()
        -- print('CLEU')
        -- print('timestamp', timestamp)
        if self.UNIT_SPELLCAST_SUCCEEDED_EVENT and next(self.UNIT_SPELLCAST_SUCCEEDED_EVENT) then
            if (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime >= (timestamp_trimmed - 1)) and (self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SourceGUID == sourceGUID) then
                --print('cleu event matches unit_spellcast event')
                local inInstance, instanceType = IsInInstance()
                if inInstance and (instanceType:lower() == 'party' or instanceType:lower() == 'raid') then
                    C_ChatInfo.SendAddonMessage('debuffs-cast', tostring(targetGUID..'$'..sourceGUID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime), instanceType:upper())
                else
                    -- normal option is to just add directly 
                    --self.Combat[targetGUID][sourceGUID][self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID] = t -- use local time for our own data, send server time and convert back when getting message
                end
                -- use this to test
                C_ChatInfo.SendAddonMessage('debuffs-cast', tostring(targetGUID..'$'..sourceGUID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.SpellID..'$'..self.UNIT_SPELLCAST_SUCCEEDED_EVENT.ServerTime), 'SAY')
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