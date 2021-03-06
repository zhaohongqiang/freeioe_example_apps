local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local map_inputs = {}
	local calc_inputs = {}
	local alarms = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.manufacturer = v[2]
				meta.name = v[3]
				meta.desc = v[4]
				meta.series = v[5]
			end
			if v[1] == 'INPUT' then
				local input = {
					name = v[2],
					desc = v[3],
					vt = v[4],
					ns = tonumber(v[5]) or 0,
				}
				if string.len(v[6]) > 0 then
					input.i = tonumber(v[6]) or v[6]
				end
				assert(input.i, "ID index missing")
				if string.len(input.desc) == 0 then
					input.desc = nil -- will auto load the display name for description
				end
				inputs[#inputs + 1] = input
			end
			if v[1] == 'MAP_INPUT' then
				local mi = map_inputs[v[2]] or {
					name = v[2],
					desc = v[3],
					vt = v[4],
					values = {}
				}

				local input = {
					ns = tonumber(v[5]) or 0,
					value = tonumber(v[7]) or -1,
					desc = v[8],
				}
				if string.len(v[6]) > 0 then
					input.i = tonumber(v[6]) or v[6]
				end
				assert(input.i, "ID index missing")

				table.insert(mi.values, input)
				map_inputs[mi.name] = mi
			end
			if v[1] == 'CALC_INPUT' then
				table.insert(calc_inputs, {
					name = v[2],
					desc = v[3],
					vt = v[4],
					func = v[5],
				})
			end
			if v[1] == 'ALARM' then
				local alm = {
					desc = v[2],
					vt = v[3],
					ns = tonumber(v[4]) or -1,
					is_error = tonumber(v[6]) == 1,
					errno = tonumber(v[7]) or -1,
				}
				if string.len(v[5]) > 0 then
					alm.i = tonumber(v[5]) or v[5]
				end
				assert(alm.i, "ID index missing")

				table.insert(alarms, alm)
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
		map_inputs = map_inputs,
		calc_inputs = calc_inputs,
		alarms = alarms,
	}
end

--[[
--local cjson = require 'cjson.safe'
local tpl = load_tpl('bms')
print(cjson.encode(tpl))
]]--

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
