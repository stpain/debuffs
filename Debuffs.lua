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

Debuffs.CooldownFrames = {}

Debuffs.Combat = {}

-- this is a shot in the dark but it seems about right, not sure if cooldown template frames adjust this with math.ceil ?
local bandwidthIn, bandwidthOut, latencyHome, latencyWorld = GetNetStats() -- hmm ?
local LAG = latencyWorld / 100
Debuffs.Spells = {
    -- priest
    [589] = { Duration = 18 + LAG, Name = '' }, -- shadow word: pain rank 1
    -- warlock
    [348] = { Duration = 15 + LAG, Name = '' }, -- immolate rank 1
    [172] = { Duration = 12 + LAG, Name = '' }, -- corruption rank 1
    [980] = { Duration = 24 + LAG, Name = '' }, -- agony rank 1
    [5782] = { Duration = 10 + LAG, Name = '' }, -- fear rank 1
    -- hunter
    [5116] = { Duration = 4 + LAG, Name = '' }, -- concussive shot
    [1978] = { Duration = 15 + LAG, Name = '' }, -- serpent string rank 1
    [13549] = { Duration = 15 + LAG, Name = '' }, -- serpent string rank 2
    [13550] = { Duration = 15 + LAG, Name = '' }, -- serpent string rank 3
}

function Debuffs:SetCooldowns()
    local targetGUID = UnitGUID('target')
    for i = 1, 40 do
        if _G['TargetFrameDebuff'..i] then
            if not Debuffs.CooldownFrames['TargetFrameDebuff'..i] then
                Debuffs.CooldownFrames['TargetFrameDebuff'..i] = CreateFrame("Cooldown", tostring('TargetFrameDebuff'..i.."Cooldown"), _G['TargetFrameDebuff'..i], "CooldownFrameTemplate")
                Debuffs.CooldownFrames['TargetFrameDebuff'..i]:SetHideCountdownNumbers(true)
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
end

function Debuffs:UNIT_SPELLCAST_SUCCEEDED(...)
    local t = GetTime()
    local s = GetServerTime()
    local targetGUID = UnitGUID('target')
    local playerGUID = UnitGUID('player')
    local spellID = select(3, ...)
    if targetGUID then
        if not self.Combat[targetGUID] then
            self.Combat[targetGUID] = {
                [playerGUID] = {}
            }
        end
        -- TODO: check if cast was resisted/blocked first
        self.Combat[targetGUID][playerGUID][spellID] = t -- consider if spell can stack?
    end
end

-- needed?
function Debuffs:PLAYER_TARGET_CHANGED(...)
    local targetGUID = UnitGUID('target')
    local playerGUID = UnitGUID('player')
    if targetGUID then
        if not self.Combat[targetGUID] then
            self.Combat[targetGUID] = {
                [playerGUID] = {}
            }
        end
    end
end

-- needed?
function Debuffs:UNIT_AURA(...)
    local unitGUID = UnitGUID(...)
    if unitGUID then
        if not self.Combat[unitGUID] then
            self.Combat[unitGUID] = {
                [playerGUID] = {}
            }
        end
    end
end

-- needed?
function Debuffs:COMBAT_LOG_EVENT_UNFILTERED(...)
    -- local cleu = {CombatLogGetCurrentEventInfo()}
    -- for k, v in pairs(cleu) do
    --     print(k, v)
    -- end
end

Debuffs.f = CreateFrame('FRAME', 'DebuffEventFrame', UIParent)
Debuffs.f:RegisterEvent('PLAYER_TARGET_CHANGED')
Debuffs.f:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
Debuffs.f:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED')
Debuffs.f:RegisterEvent('PLAYER_REGEN_ENABLED')
Debuffs.f:RegisterEvent('UNIT_AURA')

Debuffs.f:SetScript('OnEvent', function(self, event, ...)
    Debuffs[event](Debuffs, ...)
end)
Debuffs.f:SetScript('OnUpdate', function()
     Debuffs:SetCooldowns()
end)