local class = require 'middleclass'
local sum = require 'summation'
local netinfo = require 'netinfo'
local gcom = require 'utils.gcom'
local cjson = require 'cjson.safe'

local lte_wan = class("FREEIOE_WAN_SUM_CLASS")

function lte_wan:initialize(app, sys)
	self._app = app
	self._sys = sys
	self._3ginfo = false
	self._gcom = false
	self._lte_wan_freq = app._conf.lte_wan_freq

	self._wan_sum = sum:new({
		file = true,
		save_span = 60 * 5, -- five minutes
		key = 'wan',
		span = 'month',
		path = '/root', -- Q102's data/cache partition
	})
end

function lte_wan:inputs()
	local sys_id = self._sys:hw_id()
	local id = self._sys:id()
	if string.sub(sys_id, 1, 8) == '2-30002-' or string.sub(sys_id, 1, 8) == '2-30102-' then
		self._gcom = true
		return {
			{
				name = 'ccid',
				desc = 'SIM card ID',
				vt = "string",
			},
			{
				name = 'csq',
				desc = 'GPRS/LTE sginal strength',
				vt = "int",
			},
			{
				name = 'cpsi',
				desc = 'GPRS/LTE work mode',
				vt = "string",
			},
			{
				name = 'wan_s',
				desc = 'GPRS/LET send this month',
				vt = 'int',
				unit = 'KB'
			},
			{
				name = 'wan_r',
				desc = 'GPRS/LET receive this month',
				vt = 'int',
				unit = 'KB'
			},
		}
	end
	if lfs.attributes("/tmp/sysinfo/3ginfo", "mode") == 'file' then
		self._3ginfo = true
		-- TODO: 3Ginfo export
		return {
			{
				name = 'ccid',
				desc = 'SIM card ID',
				vt = "string",
			},
			{
				name = 'csq',
				desc = 'GPRS/LTE sginal strength',
				vt = "int",
			},
			{
				name = 'lte_info',
				desc = 'GPRS/LTE work information',
				vt = "string",
			},
			{
				name = 'wan_s',
				desc = 'GPRS/LET send this month',
				vt = 'int',
				unit = 'KB'
			},
			{
				name = 'wan_r',
				desc = 'GPRS/LET receive this month',
				vt = 'int',
				unit = 'KB'
			},
		}
	end

	return {}
end

--- For wan statistics
function lte_wan:read_wan_sr()
	if self._gcom then
		local info, err = netinfo.proc_net_dev('3g-wan')
		if info and #info == 16 then
			self._wan_sum:set('recv', math.floor(info[1] / 1000))
			self._wan_sum:set('send', math.floor(info[9] / 1000))
		end
	end
	if self._3ginfo then
		local info, err = netinfo.proc_net_dev('wwan0')
		if info and #info == 16 then
			self._wan_sum:set('recv', math.floor(info[1] / 1000))
			self._wan_sum:set('send', math.floor(info[9] / 1000))
		end
	end
end

function lte_wan:start(dev, lte_strength_cb)
	self._dev = dev
	self:read_wan_sr()
	local calc_lte_wan = nil
	local lte_wan_freq = self._lte_wan_freq or (1000 * 60)

	if self._gcom then
		calc_lte_wan = function()
			-- Reset timer
			self._lte_wan_cancel_timer = self._sys:cancelable_timeout(lte_wan_freq, calc_lte_wan)

			local ccid, err = gcom.get_ccid()
			if ccid then
				self._dev:set_input_prop('ccid', "value", ccid)
			end
			local csq, err = gcom.get_csq()
			if csq then
				self._dev:set_input_prop('csq', "value", csq)
				if lte_strength_cb then
					lte_strength_cb(csq)
				end
			end
			local cpsi, err = gcom.get_cpsi()
			if cpsi then
				self._dev:set_input_prop('cpsi', "value", cpsi)
			end

			self._dev:set_input_prop('wan_r', "value", self._wan_sum:get('recv'))
			self._dev:set_input_prop('wan_s', "value", self._wan_sum:get('send'))
			--- GCOM core dump file removal hacks
			os.execute("rm -rf /tmp/gcom*.core")
		end
	end
	if self._3ginfo then
		calc_lte_wan = function()
			self._lte_wan_cancel_timer = self._sys:cancelable_timeout(lte_wan_freq, calc_lte_wan)
			local f, err = io.open('/tmp/sysinfo/3ginfo', 'r')
			if f then
				local str, err = f:read('*a')
				f:close()

				if str then
					local info = cjson.decode(str)
					local ccid = info.ccid
					if ccid then
						self._dev:set_input_prop('ccid', "value", ccid)
					end
					local csq = tonumber(info.csq)
					if csq then
						self._dev:set_input_prop('csq', "value", csq)
						if lte_strength_cb then
							lte_strength_cb(csq)
						end
					end

					for k, v in pairs(info) do
						if string.len(v) == 0 or v == '-' then
							info[k] = nil
						end
					end
					self._dev:set_input_prop('lte_info', "value", cjson.encode(info))

					self._dev:set_input_prop('wan_r', "value", self._wan_sum:get('recv'))
					self._dev:set_input_prop('wan_s', "value", self._wan_sum:get('send'))
				end
			end
		end
	end

	--- GCOM takes too much time which may blocks the first run too long
	self._sys:timeout(1000, function() calc_lte_wan() end)
end

function lte_wan:run()
	self:read_wan_sr()
end

function lte_wan:stop()
	if self._lte_wan_cancel_timer then
		self._lte_wan_cancel_timer()
		self._lte_wan_cancel_timer = nil
	end
end

return lte_wan
