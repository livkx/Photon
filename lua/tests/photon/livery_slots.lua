-- Livery slots: which submaterial a livery or EMV.Skin material path replaces.
-- Cases drive Photon.GetLiverySubMaterial with stand-ins, since it only reads a material list.

local VEHICLE = "photon_test_livery_slots"
local RULE_PREFIX = "photon_test_rule_"

--- A stand-in entity whose model has `materials`, in model order.
local function model(materials)
	return {
		IsValid = function() return true end,
		GetMaterials = function() return materials end,
		GetModel = function() return "models/photon_test.mdl" end,
	}
end

--- Register a rule under a test key; afterEach removes every test key.
local function rule(name, data)
	list.Set(Photon.LiverySlots.ListName, RULE_PREFIX .. name, data)
end

return {
	groupName = "Photon livery slots",

	cases = {
		{
			name = "Without rules, the built-in suffixes pick the first match in model order",
			func = function()
				local ent = model({"pack/glass", "pack/carpaint", "pack/skin"})
				expect(Photon.GetLiverySubMaterial(ent)).to.equal(1)
				expect(Photon.GetLiverySubMaterial(model({"pack/glass", "pack/paint"}))).to.beFalse()
			end
		},
		{
			name = "A suffix rule matches the exact suffix only",
			func = function()
				rule("l2", {Suffixes = {"/skin_l2"}})
				local ent = model({"pack/skin1_l2", "pack/windowskin_l2", "pack/skin_l2"})
				expect(Photon.GetLiverySubMaterial(ent)).to.equal(2)
			end
		},
		{
			name = "A registered rule wins over the built-in suffixes",
			func = function()
				rule("l2", {Suffixes = {"/skin_l2"}})
				expect(Photon.GetLiverySubMaterial(model({"pack/skin", "pack/skin_l2"}))).to.equal(1)
			end
		},
		{
			name = "Higher priority runs first, whatever the material order",
			func = function()
				rule("a_low", {Suffixes = {"/body"}})
				rule("b_high", {Suffixes = {"/paint"}, Priority = 5})
				expect(Photon.GetLiverySubMaterial(model({"pack/body", "pack/paint"}))).to.equal(1)
			end
		},
		{
			name = "Pattern and Match rules match, and Match sees the 0-based index and the entity",
			func = function()
				rule("pattern", {Pattern = "/livery_%d+$"})
				expect(Photon.GetLiverySubMaterial(model({"pack/glass", "pack/livery_02"}))).to.equal(1)
				list.Set(Photon.LiverySlots.ListName, RULE_PREFIX .. "pattern", nil)

				local ent = model({"pack/glass", "pack/shell"})
				local seen
				rule("match", {Match = function(name, index, matchEnt)
					if name == "pack/shell" then seen = {index, matchEnt} return true end
					return false
				end})
				expect(Photon.GetLiverySubMaterial(ent)).to.equal(1)
				expect(seen[1]).to.equal(1)
				expect(seen[2]).to.equal(ent)
			end
		},
		{
			name = "A malformed rule and a Match that errors are skipped, and later rules still run",
			func = function()
				rule("a_bad", {Priority = 10})
				rule("b_errors", {Priority = 5, Match = function() error("broken rule") end})
				rule("c_good", {Suffixes = {"/paint"}})
				expect(Photon.LiverySlots.ValidateRule({Priority = 10})).to.beFalse()
				expect(Photon.LiverySlots.ValidateRule({Pattern = "%"})).to.beFalse()
				expect(Photon.GetLiverySubMaterial(model({"pack/glass", "pack/paint"}))).to.equal(1)
			end
		},
		{
			name = "EMV.LiverySubMaterial wins over rules, and a suffix that matches nothing falls back",
			func = function()
				rule("l2", {Suffixes = {"/skin_l2"}})
				local ent = model({"pack/skin_l2", "pack/stripes", "pack/skin"})

				EMVU.LiverySlots[VEHICLE] = Photon.LiverySlots.NormalizeOverride(VEHICLE, 2)
				expect(Photon.GetLiverySubMaterial(ent, VEHICLE)).to.equal(2)

				EMVU.LiverySlots[VEHICLE] = Photon.LiverySlots.NormalizeOverride(VEHICLE, "/stripes")
				expect(Photon.GetLiverySubMaterial(ent, VEHICLE)).to.equal(1)

				EMVU.LiverySlots[VEHICLE] = Photon.LiverySlots.NormalizeOverride(VEHICLE, {"/nothing"})
				expect(Photon.GetLiverySubMaterial(ent, VEHICLE)).to.equal(0)

				-- A sub-prop is resolved without the vehicle's override.
				EMVU.LiverySlots[VEHICLE] = Photon.LiverySlots.NormalizeOverride(VEHICLE, 2)
				expect(Photon.GetLiverySubMaterial(ent)).to.equal(0)

				expect(Photon.LiverySlots.NormalizeOverride(VEHICLE, -1)).to.beNil()
				expect(Photon.LiverySlots.NormalizeOverride(VEHICLE, {"/ok", 3})).to.beNil()
			end
		},
		{
			name = "A vehicle file's override is stored with the vehicle and cleared when it is dropped",
			func = function()
				EMVU:OverwriteIndex(VEHICLE, {LiverySubMaterial = "/stripes"})
				expect(Photon.GetLiverySubMaterial(model({"pack/skin", "pack/stripes"}), VEHICLE)).to.equal(1)

				EMVU:OverwriteIndex(VEHICLE, {})
				expect(EMVU.LiverySlots[VEHICLE]).to.beNil()
				expect(Photon.GetLiverySubMaterial(model({"pack/skin", "pack/stripes"}), VEHICLE)).to.equal(0)
			end
		},
	},

	afterEach = function()
		local rules = list.GetForEdit(Photon.LiverySlots.ListName)
		for key in pairs(rules) do
			if isstring(key) and string.StartWith(key, RULE_PREFIX) then
				rules[key] = nil
			end
		end
		for _, tableName in ipairs({"Attributes", "LightMeta", "Patterns", "Sections", "Positions", "LiverySlots", "PresetIndex"}) do
			if istable(EMVU[tableName]) then EMVU[tableName][VEHICLE] = nil end
		end
	end
}
