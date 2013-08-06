--[[ 
--   Lua Executor Module
--      :call(self, request, response)
--      Called from the server when the module should parse the given
--      request and put any data or results in the response table. The
--      call-block should return the updated response.
--   
--    There are no other required methods.
]]--
return {
	call = function(self, request, response)
		-- Make a local sandbox
		local sandbox = table.copy(_G)
		sandbox.WebServer = nil -- nope.avi
		
		-- Running state
		local run = true
		
		-- Generic-ish-not-really error handler
		sandbox.error = function(...)
			local args = {...}
			-- Give the webdev some helpful data
			WebServer:formatStatusTemplate(response, {
				["statusnum"] = 500, ["filename"] = "Lua Executor",
				["errordata"] = "<h2>Lua Executor Error: " .. (args and args[1] or 'undefined') .. "</h2><pre>" .. 
					debug.traceback("Unhandled error caught by pre-processor", ((args and args[2] and (args[2] + 2)) or 2)) .. "</pre>"
			})
			run = false
			-- Throw back to the subrunner (here) that the callee has error()'d
			coroutine.yield("application_has_crashed")
		end
		
		-- Put response and request fields
		sandbox.response = response
		sandbox.request = request
		
		if (response.handlerName == "lua-script") then -- 100% Lua script
			local fx, ex = loadstring(response.data, "chunk")
			if not fx then
				WebServer:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = "Lua Parser Error",
					["errordata"] = "Lua Exception: " .. ex	})
			else
				-- Clear all data
				response.data = ""
				sandbox.print = function(arg) response.data = response.data .. arg .. "\n" end
				-- Sandbox
				setfenv(fx, sandbox)
				-- Coroutine
				local co = coroutine.create(fx)
				
				-- Resource limiting
				local starttime = os.time()
				local timelimit = 5
				sandbox.setTimeLimit = function(t) assert(type(t) == "number", "Number expected") timelimit = t end
				debug.sethook(co, function()
						if (timelimit > 0) and ((os.time() - 5) > starttime) then sandbox.error("Ran out of execution time!", 1) end
					end, "crl")
				
				while coroutine.status(co) ~= "dead" and run do
					local val = {coroutine.resume(co)}
					if (val[1] == "application_has_crashed") then break end -- My break-all is win
				end
				return response
			end
		else
			-- Back up the old data
			local olddata = response.data
			-- Find all Lua chunks (hasty)
			for chunk in string.gmatch(olddata, "%<%?lua[.%a%c%d%l%p%s%u%w%x%z\r\n]-%?%>") do
				-- Strip garbage
				local pchunk = string.sub(chunk, 6, string.len(chunk) - 2)
				local fx, ex = loadstring(pchunk, "sub-document chunk")
				if not fx then
					WebServer:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = "Lua Parser Error",
						["errordata"] = "Lua Exception: " .. ex })
				else
					-- Holder for script result
					local result = ""
					
					-- Proxy glue
					sandbox.print = function(arg) result = result .. arg .. "\n" end
					
					-- Sandbox
					setfenv(fx, sandbox)
					-- Coroutine
					local co = coroutine.create(fx)
					
					-- Resource limiting
					local starttime = os.time()
					local timelimit = 5
					sandbox.setTimeLimit = function(t) assert(type(t) == "number", "Number expected") timelimit = t end
					debug.sethook(co, function()
						if (timelimit > 0) and ((os.time() - 5) > starttime) then sandbox.error("Ran out of execution time!", 1) end
					end, "crl")
					
					while coroutine.status(co) ~= "dead" and run do
						local val = {coroutine.resume(co)}
						if (val[1] == "application_has_crashed") then break end -- My break-all is win
					end
					-- Replace the codechunk with the result if anything
					response.data = string.gsub(response.data, patterns.sanitize(chunk), result)
				end
			end
		end
		-- Return the new response data
		return response
	end
}