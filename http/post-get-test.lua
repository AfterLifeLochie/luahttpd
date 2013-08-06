-- Lazy and wrote this all in Lua
print("<html>")
print("<body>")

for _, mode in pairs({ "GET", "POST" }) do
	print("<h1>" .. mode .. " Test</h1>")
	print("<form method='" .. mode .. "' action='/post-get-test.lua'>")
	print("<input type='text' name='textblob'><br />")
	print("<input type='submit' name='buttonobject' value='do eet'>")
	print("</form>");
end

if (request.postdata) then
	print("<br />You POST'ed:<pre>")
	for k, v in pairs(request.postdata) do
		print(k .. " => " .. v)
	end
	print("</pre>")
end

if (request.getdata) then
	print("<br />You GET'ed:<pre>")
	for k, v in pairs(request.getdata) do
		print(k .. " => " .. v)
	end
	print("</pre>")
end