-- If you're using different system paths, change this.
LUA_PATH="lua/?.lua;?.lua;?"

-- Imports
dofile("helper.lua")
dofile("thread.lua")
assert(thread ~= nil, "Threading library missing!")

local lfs = require("lfs")
assert(lfs ~= nil, "LFS library missing!")

local socket = require("socket")
assert(socket ~= nil, "Socket library missing!")


-- Webserver configuration
WebServer = {
	-- Listening port
	port = 8080,
	
	-- Format of all dates
	dateFormat = "!%a, %d %b %Y %H:%M:%S %Z",
	
	-- Server name. Go on, be witty.
	serverName = "LOLLOOOOL " .. _VERSION .. " httpd",
	
	-- HTTP status code values.
	http = {
		-- 2xx Standard
		["200"] = { "200 OK" },
		
		-- 3xx Content
		["301"] = { "301 Moved Permanently" },
		["302"] = { "302 Found" },
		
		-- 4xx Client Issue
		["400"] = { "400 Bad Request" },
		["401"] = { "401 Unauthorized" },
		["403"] = { "403 Forbidden" },
		["404"] = { "404 Not Found" },
		
		-- 5xx Server Issue
		["500"] = { "500 Internal Server Error" },
		["501"] = { "501 Not Implemented" },
	},

	-- Mime handlers.
	-- Argument 1 is a table of all extensions this mime-type matches.
	-- Argument 2 is the HTML-value mime-type text (sent in headers).
	--	Arguments 3 and 4 are 'handler' modules for each type. Currently, only
	--   one handler type can be assigned. No handler? No handler :call() will
	--   be invoked.
	mime = {
		-- generic html documents, feed through `lua-embedded`
		["html"] = { { "html", "htm", "hta" }, "text/html", 
					"lua-embedded", getModule("lua-preproc") },
					
		-- generic text, does nothing
		["plain"] = { { "txt" }, "text/plain" },
		
		-- lua code, feed through `lua-script`
		["lua"] = { { "lua" }, "text/html", 
					"lua-script", getModule("lua-preproc") },
		
		-- images
		["png"] = { { "png" }, "image/png" },
		["jpg"] = { { "jpeg", "jpg" }, "image/jpeg" },
		["gif"] = { { "gif" }, "image/gif" },
		
		-- other web-y-stuff
		["css"] = { { "css" }, "text/css" },
		["js"] = { { "js" }, "application/javascript" },
		
		-- plain fallback
		-- DO NOT SET A PROCESSOR ON THIS VALUE
		["default"] = { {}, "text/plain" },
	},
	
	-- Client storage cache.
	clients = {}
}


-- ** Nothing more configurable beyond here ** --

-- Starts the webserver
function WebServer:run()
	self.server = socket.bind("localhost", self.port)
	self.server:settimeout(0.01)
	self:mainLoop()
end

-- Accepts all clients
function WebServer:mainLoop()
	while true do
		local client = self.server:accept()
		if client then
			-- Register the client
			table.insert(self.clients, client)
			
			-- Hastily dipatch a coroutine-thread (set, start, offer)
			local t = thread:new()
			t.run = function() return WebServer:handleClient(client) end
			t:start()
			threadRunner:offer(t)
		end
		-- Yield;;
		coroutine.yield()
	end
	-- We shouldn't get here
	self.server:close()
end

-- Called to handle a new client
function WebServer:handleClient(client)
	-- The formed request
	local request = {}
	-- The raw request data
	local data = {}
	while true do
		local line, ex = client:receive()
		if (line == nil) or (line == "") or (#line == 0) then break
		else table.insert(data, line) end
	end			
	
	-- The formed response (some initial values)
	local response = {}
	response["status"] = ""
	response["data"] = ""
	response["handler"] = nil
	response["mime"] = "text/plain"
	response["connection"] = "close"
	
	if (#data == 0) then -- Okay, random sockets, go away.
		response.status = self.http["400"][1]
		local data = self:makeRequest(response, nil)
		WebServer:dispatch(client, data, true)
	else
		-- Handle only GET and POST (for now!)
		if (split(data[1], " ")[1] ~= "GET") and (split(data[1], " ")[1] ~= "POST") then	
			self:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = request.path,
				["errordata"] = "Unknown HTTP method!" })
			local data = self:makeRequest(response, nil) .. response.data
			WebServer:dispatch(client, data, true)
		end
		
		if (split(data[1], " ")[1] == "POST") then -- POST detected
			-- Obtain POST data size
			local len = -1
			for _, line in pairs(data) do
				if (split(line, " ")[1] == "Content-Length:") then len = tonumber(split(line, " ")[2]) break end
			end
			if (len == -1) then -- Weird post?
				self:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = "HTTP Processor",
					["errordata"] = "The POST Content-Length field was an invalid size." })
			end
			-- Get the POST data
			local line, ex = client:receive(len)
			request.postdata = {}
			-- Parse some stuff
			if (line ~= nil) then url.parse(line, request.postdata) end
		elseif (split(data[1], " ")[1] == "GET") then -- GET detected
			-- Split the data to " ", get the 2nd item (URL), split URL on /
			local parts = split(split(data[1], " ")[2], "/")				
			-- Split the last chunk of the URL on ? (file.ext?<getdata>)
			local query = split(parts[#parts], "?")[2] or nil
			-- If we has get, parse
			if (query) then request.getdata = {} url.parse(query, request.getdata) end
		end
		
		-- Try and isolate just the filepath, remove other garbage
		local parts = split(split(data[1], " ")[2], "/")
		local confparts = {}
		-- Remove all inserted ? crap
		for _, part in pairs(parts) do local subparts = split(part, "?") table.insert(confparts, subparts[1]) end
		-- Formalize the path
		request.path = table.concat(parsePath(table.concat(confparts, "/")), "/")		
		-- Produce the real-world filepath
		local filepath = table.concat(parsePath("http/" .. request.path), "/")
		if not (lfs.attributes(filepath, "mode")) then -- Not a file or folder
			self:formatStatusTemplate(response, { ["statusnum"] = 404, ["filename"] = request.path })
		elseif (lfs.attributes(filepath, "mode") == "file") then -- A file
			-- Open
			local handle, ex = io.open(filepath, "r")
			if not handle then 
				-- Can't handle the things? Okay.
				self:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = request.path, ["errordata"] = ex })
			else
				-- Read all the data!
				local fdata = {}
				for line in handle:lines() do table.insert(fdata, line) end
				handle:close()
				-- Indicate a 200 when we send
				response.status = self.http["200"][1]
				response.data = table.concat(fdata, "\n")
				
				-- Try and locate a MIME for this
				local fileparts = split(filepath, ".")
				for groupName, groupData in pairs(self.mime) do
					for _, extension in pairs(groupData[1]) do
						if (extension == fileparts[#fileparts]) then
							response.mime = groupData[2]
							response.handlerName = groupData[3]
							response.handler = groupData[4]
							break
						end
					end
				end
				-- No MIME -> fallback to `default`
				if (response.mime == "") then response.mime = self.mime["default"][2] end
			end
		else
			if (lfs.attributes(filepath, "mode") == "directory") then -- Directory index
				-- Indicate we're `text/html`
				response.mime = "text/html"
				-- Indicate a 200 when we send
				response.status = self.http["200"][1]
				local http_dir = string.gsub(filepath, "http", "") -- Strip out HTTP garbage (again)
				-- Make a pretty heading
				response.data = "Directory index for " .. http_dir .. "<br /><br />\n\n<pre>"
				for filename in lfs.dir(filepath) do -- iter: items in dir;
					local subfile = filepath .. "/" .. filename
					if (subfile ~= "") then -- File isn't a ghost?
						local http_path = string.gsub(subfile, "http", "") -- Strip out HTTP garbage (hurr)
						-- Write padded mode
						response.data = response.data .. string.pad(lfs.attributes(subfile, "mode"), 24, " ", true)
						-- Write padded link -> text
						response.data = response.data .. "<a href='" .. http_path .. "'>" .. filename .. "</a>" .. "\n"
					end
				end
				-- Wrap up
				response.data = response.data .. "</pre><hr><pre>" .. WebServer.serverName .. ".\nIt is now " .. os.date(WebServer.dateFormat) .. ".</pre>"
			else -- Probably a symlink or ghost or something funky
				self:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = request.path,
					["errordata"] = ("Unknown file type: " .. ((lfs.attributes(filepath, "mode")) or 'nil') .. " for " .. filepath) })
			end
		end
		
		-- Is there a registered handler?
		if (response.handler) then
			-- "Don't be a fool; wrap your tool."
			local ok, err = pcall(function() response = response.handler:call(request, response) end)
			if not ok then 
				-- Report we failed
				self:formatStatusTemplate(response, { ["statusnum"] = 500, ["filename"] = request.path,
					["errordata"] = err })
			end
		end
		
		-- Finalize the data to send
		local data = self:makeRequest(response, nil) .. response.data
		-- Send everything!
		WebServer:dispatch(client, data, true)
	end
end

-- Called to dispatch data to a client, and if set, close the socket
function WebServer:dispatch(client, data, close)
	local ok, result = client:send(data)
	if not ok then print("Unexpected non-fatal socket error:\n\t" .. result) end
	if (close) then
		client:close()
		-- Unregister the client
		local pos = -1
		for index, value in pairs(self.clients) do if (value == client) then pos = index break end end
		if (pos ~= -1) then table.remove(self.clients, pos) end
	end
	return true
end

-- Format a template document and return the resulting response object
function WebServer:formatStatusTemplate(object, args) 
	local fh, ex = io.open("templates/error-" .. args.statusnum .. ".tpl", "r")
	if not fh then return error(ex) end
	local fdata = fh:read("*a")
	fh:close()
	args.VERSION = WebServer.serverName
	
	for repl, val in pairs(args) do fdata = string.gsub(fdata, "%%" .. repl .. "%%", val) end
	object.data = fdata
	object.mime = "text/html"
	object.status = ((WebServer.http[tostring(args.statusnum)] and
		WebServer.http[tostring(args.statusnum)][1])
			or "500 Internal Server Error")
	return object
end

-- Make headers
function WebServer:makeRequest(tProperties, tAnyAdditionalHeaders)
	local result = ""
	result = result .. "HTTP/1.1 " .. (tProperties.status or '500 Internal Server Error') .. "\n"
	result = result .. "Date: " .. os.date(self.dateFormat) .. "\n"
	result = result .. "Server: " .. WebServer.serverName .. "\n"
	result = result .. "Cache-Control: max-age=1" .. "\n"
	result = result .. "Expires: " .. os.date(self.dateFormat, os.time() + 1) .. "\n"
	result = result .. "Last-Modified: " .. os.date(self.dateFormat) .. "\n"
	result = result .. "Accept-Ranges: bytes" .. "\n"
	result = result .. "Connection: " .. (tProperties.connection or 'close') .. "\n"
	result = result .. "Content-Length: " .. ((tProperties.data and #tProperties.data) or 0) .. "\n"
	result = result .. "Content-Type: " .. (tProperties.mime or 'text/plain') .. "\n"
	if (tAnyAdditionalHeaders) then
		assert(type(tAnyAdditionalHeaders) == "table", "not a table: " .. tostring(tAnyAdditionalHeaders))
		for _, header in pairs(tAnyAdditionalHeaders) do result = result .. header .. "\n" end
	end
	result = result .. "\n"
	return result
end


-- Start
local sandbox = table.copy(_G)
for k, v in pairs(WebServer) do if (type(v) == "function") then setfenv(v, sandbox) end end
-- Give real access
sandbox.WebServer = WebServer
sandbox.thread = thread
sandbox.threadRunner = threadRunner

print("`" .. WebServer.serverName .. "` starting:")
print("  > port: " .. WebServer.port)
print("  > date: " .. os.date(WebServer.dateFormat))
print("Use CTRL+C or Cmd+C to really stop the server.")

-- Error handler to perform a 'safe shutdown'
sandbox.error = function(...)
	local ok, err = pcall(function() WebServer.server:close() end)
	if not ok then print("Exception in WebServer.server:close():: " .. err) end
	for i, v in pairs(WebServer.clients) do if (v ~= nil) then v:close() end end
	error(..., 2)
end

-- Spawn new main thread
local mainThread = thread:new()
mainThread.run = function() return WebServer:run() end
mainThread:start()
threadRunner:offer(mainThread)

-- Deploy the main thread runner
threadRunner:run()