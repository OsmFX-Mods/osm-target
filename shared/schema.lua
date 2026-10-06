local Schema = {}

Schema.DIALECTS = { ox = 'ox', qb = 'qb', qtarget = 'qtarget' }

-- Reserved schema keys: protect internal option properties from caller override
Schema.RESERVED = {
  label = true, description = true, name = true,
  icon = true, iconColor = true, badges = true,
  distance = true,

  groups = true, gangs = true, items = true, anyItem = true, citizenid = true,
  excludeGroups = true, excludeGangs = true,
  jobTypes = true, excludeJobTypes = true,

  bones = true, offset = true, offsetSize = true, absoluteOffset = true,

  canInteract = true, hideWhenIneligible = true, showWithoutTarget = true,

  onSelect = true, export = true, event = true, serverEvent = true,
  command = true, qbCommand = true, openMenu = true, menuName = true,

  order = true, index = true, resource = true,
  dialect = true, qb = true, qtarget = true,
}

---Determine table structure type: distinguish array, hash, empty, and nil.
---@return 'array' | 'hash' | 'empty' | 'nil'
function Schema.tableType(t)
  if type(t) ~= 'table' then return 'nil' end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return 'empty' end
  return #t == n and 'array' or 'hash'
end

function Schema.isArray(t)
  return Schema.tableType(t) == 'array'
end

---Normalize gate entries: convert string, array, or map into structured entry list.
---@return { name: string, value: number? }[]
function Schema.gateEntries(gate)
  local out = {}
  local t = type(gate)

  if t == 'string' then
    out[1] = { name = gate }
  elseif t == 'table' then
    if Schema.isArray(gate) then
      for i = 1, #gate do
        local v = gate[i]
        if type(v) == 'string' then out[#out + 1] = { name = v } end
      end
    else
      for k, v in pairs(gate) do
        if type(k) == 'string' then
          out[#out + 1] = { name = k, value = type(v) == 'number' and v or nil }
        elseif type(v) == 'string' then
          out[#out + 1] = { name = v }
        end
      end
      -- Sort gate entries: ensure deterministic reason string output
      table.sort(out, function(a, b) return a.name < b.name end)
    end
  end

  return out
end

---Check gate membership: determine if gate declarations match the specified identifier.
---@return boolean
function Schema.gateNames(gate, value)
  if value == nil then return false end
  local entries = Schema.gateEntries(gate)
  for i = 1, #entries do
    if entries[i].name == value then return true end
  end
  return false
end

---Prettify identifier: format snake_case or camelCase names into title case.
function Schema.prettify(name)
  if type(name) ~= 'string' or name == '' then return tostring(name) end
  local words = {}
  for word in name:gmatch('[^%s_%-]+') do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
  end
  return #words > 0 and table.concat(words, ' ') or name
end

---Format name list: join names with commas and append overflow count when exceeding limit.
function Schema.joinNames(names, limit)
  limit = limit or 3
  local n = #names
  if n == 0 then return '' end
  if n <= limit then return table.concat(names, ', ') end
  local head = {}
  for i = 1, limit do head[i] = names[i] end
  return table.concat(head, ', ') .. ' +' .. tostring(n - limit)
end

function Schema.deepCopy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = Schema.deepCopy(v) end
  return out
end

OsmTargetSchema = Schema
return Schema
