--- Livery Slots.
--- Decides which of a model's materials is its paint: the submaterial that a livery,
--- an autoskin or a material path in `EMV.Skin` replaces.
---
--- Photon's own rule takes the first material whose name ends `/skin`, `/skin0` or
--- `/carpaint`. A model that names its paint anything else can still take liveries:
--- an addon registers a rule in the `PhotonLiverySlots` list, or a vehicle file names
--- its slot with `EMV.LiverySubMaterial`. See docs/livery-slots.md.
---
--- Rules live in a `list` rather than behind a function so that an addon can register
--- one before Photon has loaded. Autorun files run in name order, and many sort ahead
--- of `emv_init.lua`.
--- @copyright Photon Team
--- @release development
--- @author Photon Team
--- @namespace Photon.LiverySlots
--- @state shared

--- A rule for finding a model's paint submaterial. A rule matches a material when any
--- of the matchers it sets does; it needs at least one.
--- @class Photon.LiverySlotRule
--- @field Suffixes string[]? The material name ends with one of these, compared exactly as `GetMaterials` returns it.
--- @field Pattern string? A Lua pattern, tested against the material name with `string.find`.
--- @field Match (fun(name: string, index: integer, ent: Entity): boolean)? Decides one material; `index` is 0-based.
--- @field Priority number? Rules with a higher priority are tried first. Defaults to 0.

--- @class Photon.LiverySlots
local SLOTS = Photon.LiverySlots or {}
Photon.LiverySlots = SLOTS

--- The `list` that rules are registered in.
SLOTS.ListName = "PhotonLiverySlots"

--- Photon's own suffixes, tried after every registered rule.
SLOTS.BuiltIn = {"/skin", "/skin0", "/carpaint"}

-- Problems already reported, so a broken rule or override is named once rather than on every spawn.
SLOTS.Reported = SLOTS.Reported or {}

local EndsWith = string.EndsWith
local find = string.find

--- Report a problem once per key.
--- @param key string What the problem is about, so it is reported only once.
--- @param ... any Message parts.
function SLOTS.ReportOnce(key, ...)
	if SLOTS.Reported[key] then return end
	SLOTS.Reported[key] = true
	Photon.Logging.Warning(...)
end

--- Check a rule before it is used.
--- @param rule any The value registered in the list.
--- @return boolean ok Whether the rule can be used.
--- @return string? reason Why not, when it cannot.
function SLOTS.ValidateRule(rule)
	if not istable(rule) then return false, "must be a table" end

	local matchers = 0
	if rule.Suffixes ~= nil then
		if not istable(rule.Suffixes) then return false, "Suffixes must be a list of strings" end
		for _, suffix in ipairs(rule.Suffixes) do
			if not isstring(suffix) or suffix == "" then return false, "Suffixes must be a list of non-empty strings" end
			matchers = matchers + 1
		end
	end
	if rule.Pattern ~= nil then
		if not isstring(rule.Pattern) or rule.Pattern == "" then return false, "Pattern must be a non-empty string" end
		if not pcall(find, "", rule.Pattern) then return false, "Pattern is not a valid Lua pattern" end
		matchers = matchers + 1
	end
	if rule.Match ~= nil then
		if not isfunction(rule.Match) then return false, "Match must be a function" end
		matchers = matchers + 1
	end
	if matchers == 0 then return false, "needs Suffixes, Pattern or Match" end
	if rule.Priority ~= nil and not isnumber(rule.Priority) then return false, "Priority must be a number" end

	return true
end

--- The registered rules that pass validation, highest priority first and then by key.
--- A rule that fails is skipped with a warning naming it.
--- @return {key: string, rule: Photon.LiverySlotRule}[] rules
function SLOTS.GetRules()
	local rules = {}
	for key, rule in pairs(list.GetForEdit(SLOTS.ListName)) do
		local ok, reason = SLOTS.ValidateRule(rule)
		if ok then
			rules[#rules + 1] = {key = tostring(key), rule = rule}
		else
			SLOTS.ReportOnce("rule:" .. tostring(key), "Livery slot rule '", tostring(key), "' in ", SLOTS.ListName, " is ignored: ", reason, ".")
		end
	end

	table.sort(rules, function(a, b)
		local pa, pb = a.rule.Priority or 0, b.rule.Priority or 0
		if pa ~= pb then return pa > pb end
		return a.key < b.key
	end)

	return rules
end

--- Turn a vehicle's `EMV.LiverySubMaterial` into what the resolver reads: a 0-based
--- index, or a list of suffixes. Anything else is reported and dropped.
--- @param vehicleName string The vehicle the value came from, for the warning.
--- @param value any The `EMV.LiverySubMaterial` value.
--- @return integer|string[]|nil override
function SLOTS.NormalizeOverride(vehicleName, value)
	if value == nil then return nil end

	if isnumber(value) then
		if value >= 0 and math.floor(value) == value then return value end
	elseif isstring(value) then
		if value ~= "" then return {value} end
	elseif istable(value) then
		local suffixes = {}
		for _, suffix in ipairs(value) do
			if not isstring(suffix) or suffix == "" then
				suffixes = nil
				break
			end
			suffixes[#suffixes + 1] = suffix
		end
		if suffixes and #suffixes > 0 then return suffixes end
	end

	SLOTS.ReportOnce("override:" .. tostring(vehicleName), "EMV.LiverySubMaterial on '", tostring(vehicleName),
		"' is ignored: use a 0-based submaterial index, a material name suffix, or a list of suffixes.")
	return nil
end

--- The first material, in model order, ending with one of `suffixes`.
--- @param materials string[]
--- @param suffixes string[]
--- @return integer|false index
local function FirstWithSuffix(materials, suffixes)
	for i = 1, #materials do
		local name = materials[i]
		for s = 1, #suffixes do
			if EndsWith(name, suffixes[s]) then return i - 1 end
		end
	end
	return false
end

--- The first material, in model order, that `rule` matches. A `Match` that errors is
--- reported and ends the search for this rule only.
--- @param key string
--- @param rule Photon.LiverySlotRule
--- @param materials string[]
--- @param ent Entity
--- @return integer|false index
local function FirstMatching(key, rule, materials, ent)
	local suffixes, pattern, match = rule.Suffixes, rule.Pattern, rule.Match
	for i = 1, #materials do
		local name = materials[i]
		if suffixes then
			for s = 1, #suffixes do
				if EndsWith(name, suffixes[s]) then return i - 1 end
			end
		end
		if pattern and find(name, pattern) then return i - 1 end
		if match then
			local ok, result = pcall(match, name, i - 1, ent)
			if not ok then
				SLOTS.ReportOnce("match:" .. key, "Livery slot rule '", key, "' errored and was skipped: ", tostring(result))
				return false
			end
			if result then return i - 1 end
		end
	end
	return false
end

--- Find the paint submaterial on `ent`: the slot that a livery, an autoskin or a
--- material path in `EMV.Skin` replaces.
---
--- Tries, in order: the vehicle's own `EMV.LiverySubMaterial`; the rules registered in
--- `PhotonLiverySlots`, highest priority first, each over the whole material list; and
--- Photon's built-in `/skin`, `/skin0` and `/carpaint`.
--- @param ent Entity The chassis, or one of its sub-props.
--- @param vehicleName string? The Photon vehicle whose `EMV.LiverySubMaterial` applies. Leave it out for a sub-prop, which has its own materials.
--- @return integer|false index The 0-based index `SetSubMaterial` takes, or false when no material matches.
function Photon.GetLiverySubMaterial(ent, vehicleName)
	if not IsValid(ent) then return false end
	local materials = ent:GetMaterials()

	local override = isstring(vehicleName) and EMVU and EMVU.LiverySlots and EMVU.LiverySlots[vehicleName]
	if isnumber(override) then return override end
	if istable(override) then
		local index = FirstWithSuffix(materials, override)
		if index then return index end
		SLOTS.ReportOnce("unmatched:" .. vehicleName .. ":" .. tostring(ent:GetModel()), "EMV.LiverySubMaterial on '", vehicleName,
			"' matches no material on ", tostring(ent:GetModel()), "; falling back to the livery slot rules.")
	end

	local rules = SLOTS.GetRules()
	for r = 1, #rules do
		local index = FirstMatching(rules[r].key, rules[r].rule, materials, ent)
		if index then return index end
	end

	return FirstWithSuffix(materials, SLOTS.BuiltIn)
end
