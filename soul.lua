addon.name    = 'soul'
addon.author  = 'sruon'
addon.version = '1.0.0'
addon.desc    = 'Soul Plate and Reflector viewer'

require('common')

local addonPath = string.format('%saddons/%s/', AshitaCore:GetInstallPath(), 'soul')
dofile(addonPath .. 'pankration.lua')
dofile(addonPath .. 'pankration_data.lua')

local pankration = xi.pankration
local feralSkillData = xi.data.pankration.feralSkills

local PLATE_IDS = {
    [2477] = 'Soul Plate',
    [2480] = 'Gauger Plate',
    [2560] = 'Fiend Plate',
}

local REFLECTOR_IDS = {
    [2478] = 'Soul Reflector',
    [2500] = 'Official Soul Reflector',
}

local C = {
    RESET   = '\31\1',
    PLATE   = '\31\206',
    REFLECT = '\31\207',
    LABEL   = '\31\200',
    VALUE   = '\31\001',
    NAME    = '\31\158',
    WARN    = '\31\167',
}

local function reverseLookup(tbl)
    local t = {}
    for k, v in pairs(tbl) do t[v] = k end
    return t
end

local disciplineNames     = reverseLookup(pankration.discipline)
local temperamentNames    = reverseLookup(pankration.temperament)
local aggressivenessNames = reverseLookup(pankration.aggressiveness)
local firstNameLookup     = reverseLookup(pankration.firstName)
local secondNameLookup    = reverseLookup(pankration.secondName)
local feralSkillNames     = reverseLookup(pankration.feralSkill)

local function getByte(extra, i)
    return string.byte(extra, i) or 0
end

local function getUInt16(extra, offset)
    return getByte(extra, offset) + getByte(extra, offset + 1) * 256
end

local function getUInt32(extra, offset)
    return getByte(extra, offset)
         + getByte(extra, offset + 1) * 0x100
         + getByte(extra, offset + 2) * 0x10000
         + getByte(extra, offset + 3) * 0x1000000
end

-- Unpack 7-bit encoded monster name from plate signature
local function unpackSoultrapperName(extra)
    local out = ''
    local rem, shift = 0, 1

    for i = 0, 13 do
        local cur = getByte(extra, i + 1)
        local ch = bit.bor(bit.rshift(cur, shift), rem)
        if ch >= 48 and ch <= 122 then
            out = out .. string.char(ch)
        end
        rem = bit.band(bit.lshift(cur, 7 - shift), 0x7F)
        if shift == 7 then
            if rem >= 48 and rem <= 122 then
                out = out .. string.char(rem)
            end
            rem, shift = 0, 1
        else
            shift = shift + 1
        end
    end
    return out
end

local function getSkillName(id)
    return feralSkillNames[id] or string.format('Unknown(%d)', id)
end

local function getSkillFP(id)
    local d = feralSkillData[id]
    return d and d.fp or 0
end

local function canSkillLevel(id)
    local d = feralSkillData[id]
    return d and d.canLevel or true
end

local function parsePlate(extra)
    local name = unpackSoultrapperName(extra)
    local poolId = getUInt16(extra, 19)
    local bf = getUInt32(extra, 21)

    return {
        name       = name,
        poolId     = poolId,
        level      = bit.band(bf, 0x7F),
        skill      = bit.band(bit.rshift(bf, 7), 0xFFF),
        skillName  = getSkillName(bit.band(bit.rshift(bf, 7), 0xFFF)),
        fp         = bit.band(bit.rshift(bf, 19), 0x7F),
        quality    = bit.band(bit.rshift(bf, 26), 0x3F),
    }
end

local function parseSkillStream(extra)
    local skills = {}
    local b32 = getUInt32(extra, 5)
    local stream0 = bit.band(bit.rshift(b32, 27), 0x1F)

    local bytes = { stream0 }
    for i = 9, 24 do bytes[#bytes + 1] = getByte(extra, i) end

    local pos = 0
    for _ = 1, 7 do
        local idx = math.floor(pos / 8) + 1
        local val = 0

        if idx == 1 then
            val = bytes[1]
            if bytes[2] then val = val + bytes[2] * 32 end
            if bytes[3] then val = val + bytes[3] * 32 * 256 end
            if bytes[4] then val = val + bytes[4] * 32 * 65536 end
        else
            local adjIdx = 2 + math.floor((pos - 5) / 8)
            local adjOff = (pos - 5) % 8
            for j = 0, 3 do
                if bytes[adjIdx + j] then
                    val = val + bytes[adjIdx + j] * (256 ^ j)
                end
            end
            val = bit.rshift(val, adjOff)
        end

        local skillId = bit.band(val, 0x3FF)
        local skillLv = bit.band(bit.rshift(val, 12), 0x7F)
        if skillId > 0 then
            skills[#skills + 1] = { id = skillId, name = getSkillName(skillId), lv = skillLv }
        end
        pos = pos + 19
    end
    return skills
end

local function parseReflector(extra)
    local b0 = getUInt32(extra, 1)
    local b1 = getUInt32(extra, 5)

    local nameFirst = bit.band(b0, 0x3F)
    local nameLast  = bit.band(bit.rshift(b0, 6), 0x3F)
    local poolId    = bit.band(bit.rshift(b0, 12), 0xFFFF)
    local exp       = bit.band(bit.rshift(b0, 28), 0x0F) + bit.band(b1, 0x0F) * 16
    local disc      = bit.band(bit.rshift(b1, 4), 0xFF)
    local temp      = bit.band(bit.rshift(b1, 12), 0x0F)
    local aggr      = bit.band(bit.rshift(b1, 16), 0x0F)
    local level     = bit.band(bit.rshift(b1, 20), 0x7F)

    return {
        name     = (firstNameLookup[nameFirst] or '?') .. ' ' .. (secondNameLookup[nameLast] or '?'),
        poolId   = poolId,
        level    = level,
        exp      = exp,
        disc     = disc,
        discName = disciplineNames[math.floor(disc / 16)] or '?',
        temp     = temp,
        tempName = temperamentNames[math.floor(temp / 2)] or '?',
        aggr     = aggr,
        aggrName = aggressivenessNames[math.floor(aggr / 2)] or '?',
        skills   = parseSkillStream(extra),
    }
end

local function printPlate(slot, itemId, extra)
    local d = parsePlate(extra)
    local expectedFP = getSkillFP(d.skill)
    local warn = (expectedFP > 0 and d.fp ~= expectedFP) and (C.WARN .. '*') or ''

    print(string.format('%s[%d] %s (%s%s%s)%s',
        C.PLATE, slot, PLATE_IDS[itemId], C.NAME, d.name, C.PLATE, C.RESET))
    print(string.format('       %sPoolId:%s %d  %sLv:%s %d  %sQuality:%s %d',
        C.LABEL, C.VALUE, d.poolId, C.LABEL, C.VALUE, d.level, C.LABEL, C.VALUE, d.quality))
    print(string.format('       %sSkill:%s %s  %sFP:%s %d%s',
        C.LABEL, C.NAME, d.skillName, C.LABEL, C.VALUE, d.fp, warn))
end

local function printReflector(slot, itemId, extra)
    local d = parseReflector(extra)
    local totalFP = 0
    for _, s in ipairs(d.skills) do totalFP = totalFP + getSkillFP(s.id) end

    print(string.format('%s[%d] %s (%s%s%s)%s',
        C.REFLECT, slot, REFLECTOR_IDS[itemId], C.NAME, d.name, C.REFLECT, C.RESET))
    print(string.format('       %sPoolId:%s %d  %sLv:%s %d  %sExp:%s %d  %sFP:%s %d',
        C.LABEL, C.VALUE, d.poolId, C.LABEL, C.VALUE, d.level,
        C.LABEL, C.VALUE, d.exp, C.LABEL, C.VALUE, totalFP))
    print(string.format('       %sDisc:%s %s (%d)  %sTemp:%s %s (%d)  %sAggr:%s %s (%d)',
        C.LABEL, C.VALUE, d.discName, d.disc,
        C.LABEL, C.VALUE, d.tempName, d.temp,
        C.LABEL, C.VALUE, d.aggrName, d.aggr))

    if #d.skills > 0 then
        local parts = {}
        for _, s in ipairs(d.skills) do
            local fp = getSkillFP(s.id)
            local warn = (s.lv > 1 and not canSkillLevel(s.id)) and (C.WARN .. '*') or ''
            parts[#parts + 1] = string.format('%s%s%s Lv%d (%dFP)%s', C.NAME, s.name, C.VALUE, s.lv, fp, warn)
        end
        print(string.format('       %sSkills:%s %s', C.LABEL, C.VALUE, table.concat(parts, ', ')))
    end
end

local function scan()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local plates, reflectors = {}, {}

    local max = inv:GetContainerCountMax(0)
    for slot = 1, max do
        local item = inv:GetContainerItem(0, slot)
        if item and item.Id ~= 0 and item.Id ~= 65535 then
            if PLATE_IDS[item.Id] then
                plates[#plates + 1] = { slot = slot, id = item.Id, extra = item.Extra }
            elseif REFLECTOR_IDS[item.Id] then
                reflectors[#reflectors + 1] = { slot = slot, id = item.Id, extra = item.Extra }
            end
        end
    end

    for _, p in ipairs(plates) do printPlate(p.slot, p.id, p.extra) end
    for _, r in ipairs(reflectors) do printReflector(r.slot, r.id, r.extra) end

    print(string.format('%sFound %s%d%s plates, %s%d%s reflectors.%s',
        C.LABEL, C.PLATE, #plates, C.LABEL, C.REFLECT, #reflectors, C.LABEL, C.RESET))
end

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or args[1] ~= '/soul' then return end
    e.blocked = true
    scan()
end)
