---
title: Livery Slots
description: Which of a model's materials a livery replaces, and how to tell Photon when it can't guess.
---

# Livery Slots

A livery is a material swapped onto one submaterial of a vehicle: its paint. Photon needs to know
which submaterial that is wherever it puts a material on the paint:

- `EMV.Skin` set to a material path, applied when the vehicle spawns.
- A livery picked from the Photon menu, from `EMV.Liveries`.
- An autoskin, including one restored from a saved configuration.
- Generated unit-number liveries, and the skin a configuration export records.

All of them ask `Photon.GetLiverySubMaterial(ent, vehicleName)`, which returns the 0-based index
`SetSubMaterial` takes, or `false` when nothing matches. Sub-props (`prop_dynamic_ornament` children)
are looked up on their own material lists.

## Photon's own rule

With nothing else configured, the paint is the first material, in model order, whose name ends
`/skin`, `/skin0` or `/carpaint`. Most Photon-era vehicle packs name their paint that way.

## Registering a rule

A pack whose models name their paint differently registers a rule in the `PhotonLiverySlots` list:

```lua
list.Set("PhotonLiverySlots", "my_pack", {
	Suffixes = {"/paint_main", "/paint_main0"},
})
```

Use `list.Set`, not a Photon function. Photon reads the list when it looks a slot up, so the rule
works however the autorun files are ordered, including when your file runs before Photon's.
Register it on both realms: the client resolves the slot for generated liveries and exports.

| Field | Type | Matches a material when |
| :--- | :--- | :--- |
| `Suffixes` | `string[]` | its name ends with one of these, compared exactly as `GetMaterials` returns it |
| `Pattern` | `string` | the Lua pattern finds a match in its name |
| `Match` | `function(name, index, ent) -> boolean` | the function returns true; `index` is 0-based |
| `Priority` | `number` | Not a matcher. Higher runs first; defaults to 0 |

A rule needs at least one matcher, and matches a material if any of its matchers does. Prefer
`Suffixes`. A suffix that starts with `/` cannot catch a longer name by accident: `/skin_l2` does not
match `windowskin_l2`, nor a skin-family variant such as `skin1_l2`.

A rule that is malformed, or whose `Match` errors, is skipped with a warning naming it, once. It
never stops another rule, or the livery, from working.

## Per-vehicle override

A vehicle file can name its paint slot outright:

```lua
EMV.LiverySubMaterial = 3                -- the 0-based submaterial index
EMV.LiverySubMaterial = "/stripes"       -- the first material ending with this
EMV.LiverySubMaterial = {"/a", "/b"}     -- the first material ending with either
```

It applies to the vehicle itself, not to its sub-props. A suffix override that matches nothing on the
model is reported and falls back to the rules below.

`EMV.SkinMaterialIndex`, together with `EMV.SkinIndex`, still sets the slot for `EMV.Skin` at spawn, as
before. It does not reach liveries picked later; `EMV.LiverySubMaterial` does.

## Order

1. The vehicle's `EMV.LiverySubMaterial`.
2. Registered rules, highest `Priority` first, ties broken by key. Each rule scans the whole material
   list before the next is tried.
3. Photon's own `/skin`, `/skin0`, `/carpaint`, exactly as before.

With no rules and no override, the result is the same as before this API existed.
