-- Don't even ask.

thread = {
	new = function(...) local result = {} setmetatable(result, { __index = thread }) return result end,
	
	resume = function(self)
		if (self.cothread) and not (coroutine.status(self.cothread) == "dead") then
			if (self.isBlocked) then if (self.blockingCallback) then self.blockingCallback() end
			else
				local ok, result = coroutine.resume(self.cothread)
				if not (ok) then error("Unexpected thread error: " .. (result or 'failed to report')) end
				if (self.cothread == nil) or (coroutine.status(self.cothread) == "dead") then
					self.alive = false self.finished = true
				end
				return result
			end
		else error("Cannot resume dead thread.") end
	end,
	
	start = function(self) self.cothread = coroutine.create(self.run) self.alive = true end,
	interrupt = function(self) self.alive = false self.finished = true self.cothread = nil end,
	stop = function(self) self.cothread = nil error("Forced thread stop!") end,
	
	block = function(self, callback) self.isBlocked = true self.blockingCallback = callback end,
	getIsBlocked = function(self) return self.isBlocked end,
	notify = function(self) self.isBlocked = nil end,
	
	getIsBlocking = function(self) return self.isBlocking end,
	setIsBlocking = function(self, callback) self.isBlocking = true self.blockingCallback = callback end,
	clearIsBlocking = function(self) self.isBlocking = nil self.blockingCallback = nil end,

	join = function(self, foreignThread, maxTime)
		assert(not foreignThread:getIsBlocking(), "Invalid foreign thread state for :join(), foreign thread is already blocking.")
		assert(not self:getIsBlocked(), "Invalid local thread state for :join(), local thread is already blocked (huh?).")
		self.blockingStart = os.time()
		self:block(function() if ((self.blockingStart + maxTime) < os.time()) then self:notify() end end)
		foreignThread:setIsBlocking(function() self:notify() end)
		local __ignore = coroutine.yield()
	end,	
}

notify = {
	new = function() local result = {} setmetatable(result, { __index = notify }) return result end,
	
	wait = function(self, thread, ...)
		assert(thread ~= nil, "Invalid local thread.")
		assert(not thread:getIsBlocked(), "Invalid local thread state for :join(), local thread is already blocked (huh?).")
		self.notifyAllItems = false
		thread.blockingStart = os.time()	
		thread:block(function() if (self.notifyAllItems) then thread:notify() end end)
		local __ignore = coroutine.yield()
	end,
	
	notifyAll = function(self) self.notifyAllItems = true end,
}

threadRunner = {
	threads = {}, abort = false,
	run = function(self)		
		local __m_cleanup = {}
		while not (abort) do
			if (#self.threads == 0) then self.abort = true break end
			for i, threadData in pairs(self.threads) do
				if (threadData.thread.alive) and (not threadData.thread.finished) then
					threadData.result = threadData.thread:resume()
				end
				if (threadData.thread.finished) then table.insert(__m_cleanup, i) end
			end
			
			if (#__m_cleanup ~= 0) then
				for i = #__m_cleanup, 1, -1 do
					local item = __m_cleanup[i]
					assert(self.threads[item] ~= nil, "Exception: cannot remove thread index at `" .. i .. "`: already removed(?)")
					if (self.threads[item].thread.isBlocking) then self.threads[item].thread.blockingCallback() end
					table.remove(self.threads, item)
				end
				__m_cleanup = {}
			end
			assert(#self.threads ~= 0, "Out of threads (stop).")
		end
	end,
	
	offer = function(self, t) table.insert(self.threads, { ["thread"] = t }) end
}