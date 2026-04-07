local VERSION  = "1.0.0"
local AUTHOR   = "vhxLUA"
local TARGET   = 130
local TIMEOUT  = 12
local LOG_FILE = "unc_progress.txt"
local REPORT_API_URL = "https://67unc.vercel.app/api/results"

local _rawequal = rawequal
local _type     = type
local _pcall    = pcall
local _tostring = tostring
local _pairs    = pairs
local _ipairs   = ipairs
local _floor    = math.floor
local _random   = math.random
local _clock    = os.clock
local _fmt      = string.format
local _rep      = string.rep
local _byte     = string.byte
local _char     = string.char
local _sub      = string.sub
local _gmatch   = string.gmatch
local _insert   = table.insert
local _sort     = table.sort
local _min      = math.min

local function _resolveEnv(tbl, path)
	if _type(tbl) ~= "table" and _type(tbl) ~= "userdata" then return nil end
	local cur = tbl
	for seg in _gmatch(path, "[^%.]+") do
		if _type(cur) ~= "table" and _type(cur) ~= "userdata" then return nil end
		local ok, v = _pcall(function() return cur[seg] end)
		if not ok or v == nil then return nil end
		cur = v
	end
	return cur
end

local _canLog = _type(writefile) == "function"
local function _log(msg)
	if _canLog then _pcall(writefile, LOG_FILE, msg) end
end
local function _safe(fn, ...)
	local ok, r = _pcall(fn, ...)
	return ok, r
end
local function _copyToClipboard(value)
	if _type(value) ~= "string" or value == "" then return false end
	local fns = {setclipboard, toclipboard, setrbxclipboard}
	for _, fn in _ipairs(fns) do
		if _type(fn) == "function" then
			local ok = _pcall(fn, value)
			if ok then return true end
		end
	end
	return false
end
local function _uid()
	return _fmt("u%x%x", _random(0, 0xFFFFFF), _random(0, 0xFFFFFF))
end

local passes   = 0
local fails    = 0
local skipped  = 0
local failLog  = {}
local missingAl= {}
local testResults = {}
local startTime= _clock()
local testQueue= {}

local IFLAGS = {}
local ICOUNT = 0
local function _flag(r) ICOUNT = ICOUNT + 1; _insert(IFLAGS, r) end
local function _aP() passes = passes + 1 end

local function _resolve(path)
	if _type(path) ~= "string" or path == "" then return nil end
	local v = _resolveEnv(getfenv(0), path)
	if v ~= nil then return v end
	if _type(_G) == "table" then v = _resolveEnv(_G, path); if v ~= nil then return v end end
	local ok, renv = _safe(getrenv)
	if ok and _type(renv) == "table" then v = _resolveEnv(renv, path); if v ~= nil then return v end end
	return nil
end

local function _collectMissingAliases(primary, aliases)
	local missing = {}
	for _, alias in _ipairs(aliases or {}) do
		if not _resolve(alias) then
			_insert(missingAl, {primary=primary, alias=alias})
			_insert(missing, alias)
		end
	end
	return missing
end

local _animCache = nil
local function _animate()
	if _animCache and _animCache.Parent then return _animCache end
	local ok, P = _safe(game.GetService, game, "Players")
	if not ok or not P then return nil end
	local lp = P.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	local anim = char:FindFirstChild("Animate")
	_animCache = anim
	return anim
end

local _v0 = (function(s) local r=0; for i=1,#s do r=r+_byte(s,i)*i end; return r end)(VERSION)
local _a0 = (function(s) local r=0; for i=1,#s do r=r+_byte(s,i) end; return r end)(AUTHOR)
local _vk = _v0 * 7 + 3
local _ak = _a0 * 13 + 5

local function _integrityCheck()
	local _vc = (function(s) local r=0; for i=1,#s do r=r+_byte(s,i)*i end; return r end)(VERSION)
	local _ac = (function(s) local r=0; for i=1,#s do r=r+_byte(s,i) end; return r end)(AUTHOR)
	if (_vc * 7 + 3) ~= _vk then ICOUNT = ICOUNT + 1; _insert(IFLAGS, "v:mut") end
	if (_ac * 13 + 5) ~= _ak then ICOUNT = ICOUNT + 1; _insert(IFLAGS, "a:mut") end

	local function ic(fn, ...) local ok, r = _pcall(fn, ...); return ok and r end
	if _type(iscclosure) == "function" then
		if ic(iscclosure, function() end) ~= false then _flag("icc:lua->t") end
		if ic(iscclosure, print) ~= true            then _flag("icc:p->f")  end
	end
	if _type(islclosure) == "function" then
		if ic(islclosure, print) ~= false        then _flag("ilc:p->t")  end
		if ic(islclosure, function() end) ~= true then _flag("ilc:lua->f") end
	end
	if _type(checkcaller) == "function" then
		if ic(checkcaller) ~= true then _flag("cc:f") end
	end
	if _type(crypt) == "table" and _type(crypt.base64encode) == "function" then
		if ic(crypt.base64encode, "test") ~= "dGVzdA==" then _flag("b64:bad") end
	end
end

local function test(name, aliases, callback)
	_insert(testQueue, {name=name, aliases=aliases or {}, callback=callback})
end

local function _runOne(entry, index, total, done)
	local name     = entry.name
	local aliases  = entry.aliases
	local callback = entry.callback
	_log(_fmt("[%d/%d] RUNNING: %s", index, total, name))
	if not _resolve(name) then
		fails = fails + 1
		local reason = "not defined"
		local missing = _collectMissingAliases(name, aliases)
		_insert(failLog, {name=name, reason=reason})
		_insert(testResults, {name=name, status="fail", reason=reason, missingAliases=missing})
		warn(_fmt("[UNC] x  %-38s not defined", name))
		_log(_fmt("[%d/%d] DONE: %s => FAIL (not defined)", index, total, name))
		done(); return
	end
	if callback == nil then
		skipped = skipped + 1
		local reason = "exists (no deep callback)"
		local missing = _collectMissingAliases(name, aliases)
		_insert(testResults, {name=name, status="skip", reason=reason, missingAliases=missing})
		print(_fmt("[UNC] -  %-38s exists", name))
		_log(_fmt("[%d/%d] DONE: %s => SKIP", index, total, name))
		done(); return
	end
	local t0 = _clock(); local finished = false; local timedOut = false
	task.delay(TIMEOUT, function()
		if not finished then
			timedOut = true; finished = true
			fails = fails + 1
			local reason = "timeout"
			local missing = _collectMissingAliases(name, aliases)
			_insert(failLog, {name=name, reason=reason})
			_insert(testResults, {name=name, status="fail", reason=reason, missingAliases=missing})
			warn(_fmt("[UNC] x  %-38s TIMEOUT (>%ds)", name, TIMEOUT))
			_log(_fmt("[%d/%d] DONE: %s => TIMEOUT", index, total, name))
			done()
		end
	end)
	task.spawn(function()
		local ok, result = _pcall(callback)
		if timedOut then return end
		finished = true
		local ms = _fmt("%.0fms", (_clock() - t0) * 1000)
		if ok then
			_aP()
			local note = (_type(result) == "string" and #result > 0) and " (" .. result .. ")" or ""
			local reason = (_type(result) == "string" and #result > 0) and result or "Passed all checks"
			local missing = _collectMissingAliases(name, aliases)
			_insert(testResults, {name=name, status="pass", reason=reason, missingAliases=missing})
			print(_fmt("[UNC] +  %s%s [%s]", name, note, ms))
			_log(_fmt("[%d/%d] DONE: %s => PASS [%s]", index, total, name, ms))
		else
			fails = fails + 1
			local raw    = _tostring(result or "")
			local reason = raw:match(":%d+: (.+)") or raw
			local missing = _collectMissingAliases(name, aliases)
			_insert(failLog, {name=name, reason=reason})
			_insert(testResults, {name=name, status="fail", reason=reason, missingAliases=missing})
			warn(_fmt("[UNC] x  %-38s %s", name, reason))
			_log(_fmt("[%d/%d] DONE: %s => FAIL (%s)", index, total, name, reason))
		end
		done()
	end)
end

local function _printSummary()
	_safe(function()
		if _type(isfolder) == "function" and isfolder(".tests") then _safe(delfolder, ".tests") end
	end)
	local tested  = passes + fails
	local rate    = tested > 0 and math.round(passes / tested * 100) or 0
	local elapsed = _fmt("%.2fs", _clock() - startTime)
	local execName= "unknown"
	_safe(function()
		if _type(identifyexecutor) == "function" then
			local n, v = identifyexecutor()
			execName = _tostring(n or "?")
			if v ~= nil then execName = execName .. " v" .. _tostring(v) end
		elseif _type(getexecutorname) == "function" then
			execName = _tostring(getexecutorname() or "?")
		end
	end)
	local bar  = _rep("=", 60)
	local thin = _rep("-", 60)
	print(bar)
	print(_fmt("[UNC] UNC Tester v%s by vhxLUA", VERSION))
	print(_fmt("[UNC] Executor  : %s", execName))
	print(thin)
	print(_fmt("[UNC] Passed    : %d", passes))
	print(_fmt("[UNC] Failed    : %d", fails))
	print(_fmt("[UNC] Skipped   : %d", skipped))
	print(_fmt("[UNC] Tested    : %d  /  Target: %d", tested + skipped, TARGET))
	print(_fmt("[UNC] Score     : %d%%   Time: %s", rate, elapsed))
	print(thin)
	if #missingAl > 0 then
		warn(_fmt("[UNC] Missing aliases : %d", #missingAl))
		for _, e in _ipairs(missingAl) do warn(_fmt("[UNC]   ? %-30s (for %s)", e.alias, e.primary)) end
	else
		print("[UNC] Aliases   : all present")
	end
	if #failLog > 0 then
		print(thin)
		warn(_fmt("[UNC] Failures  : %d", #failLog))
		for _, e in _ipairs(failLog) do warn(_fmt("[UNC]   x %-30s %s", e.name, e.reason)) end
	end
	print(thin)
	if ICOUNT > 0 then
		warn(_fmt("[UNC] INTEGRITY : %d flag(s) — %s", ICOUNT, table.concat(IFLAGS, ",")))
	else
		print("[UNC] INTEGRITY : OK")
	end
	local httpSvc = game:GetService("HttpService")
	local reqFn = (_type(request) == "function" and request)
		or (_type(http_request) == "function" and http_request)
		or (_type(http) == "table" and _type(http.request) == "function" and http.request)
	if _type(reqFn) == "function" then
		local payload = {
			version = VERSION,
			author = AUTHOR,
			executor = execName,
			elapsed = elapsed,
			summary = {
				passed = passes,
				failed = fails,
				skipped = skipped,
				tested = tested,
				target = TARGET,
				score = rate
			},
			integrityFlags = IFLAGS,
			tests = testResults
		}
		local okReq, res = _safe(reqFn, {
			Url = REPORT_API_URL,
			Method = "POST",
			Headers = {["Content-Type"] = "application/json"},
			Body = httpSvc:JSONEncode(payload)
		})
		local status = okReq and _type(res) == "table" and tonumber(res.StatusCode or res.Status or res.status) or nil
		local rawBody = okReq and _type(res) == "table" and (res.Body or res.body or "") or ""
		if status and status >= 200 and status < 300 then
			local okDecode, body = _safe(httpSvc.JSONDecode, httpSvc, rawBody ~= "" and rawBody or "{}")
			if okDecode and _type(body) == "table" and _type(body.url) == "string" then
				print(_fmt("[UNC] Report URL: %s", body.url))
				if _copyToClipboard(body.url) then
					print("[UNC] Copied report URL to clipboard")
				else
					warn("[UNC] Could not copy report URL to clipboard")
				end
			else
				warn("[UNC] Backend response did not include a valid report URL")
			end
		else
			local bodyPreview = _tostring(rawBody or "")
			if #bodyPreview > 180 then bodyPreview = _sub(bodyPreview, 1, 180) .. "..." end
			if status then
				warn(_fmt("[UNC] Failed to upload report to backend (status %s)", _tostring(status)))
				if bodyPreview ~= "" then warn(_fmt("[UNC] Backend response: %s", bodyPreview)) end
			else
				warn("[UNC] Failed to upload report to backend")
			end
		end
	else
		warn("[UNC] No HTTP request function found for report upload")
	end
	print(bar)
	_log("=== COMPLETED ===")
end

local function _scheduler()
	local total = #testQueue
	_log(_fmt("=== UNC v%s | %d tests ===", VERSION, total))
	local idx = 0
	local function _next()
		idx = idx + 1
		if idx > total then _printSummary(); return end
		_runOne(testQueue[idx], idx, total, function() task.defer(_next) end)
	end
	_next()
end

_safe(function()
	if _type(isfolder)=="function" and _type(makefolder)=="function" and _type(writefile)=="function" then
		if isfolder(".tests") then _safe(delfolder, ".tests") end
		_safe(makefolder, ".tests")
	end
end)

test("request",{"http.request","http_request"},function()
	local reqFn=(_type(request)=="function" and request)
		or(_type(http_request)=="function" and http_request)
		or(_type(http)=="table" and _type(http.request)=="function" and http.request)
	assert(_type(reqFn)=="function","no http request function found")
	local ok,res=_safe(reqFn,{
		Url="https://httpbin.org/user-agent",
		Method="POST",
		Headers={["Content-Type"]="application/json"},
		Body="{}"
	})
	assert(ok,"request threw: ".._tostring(res))
	assert(_type(res)=="table","response should be a table, got ".._type(res))
	assert(_type(res.StatusCode)=="number","response missing StatusCode")
	assert(res.StatusCode>=200 and res.StatusCode<300,
		"expected 2xx status, got ".._tostring(res.StatusCode))
	assert(_type(res.Body)=="string","response missing Body string")
	assert(#res.Body>0,"response Body should not be empty")
end)

test("cache.invalidate",{},function()
	local f=Instance.new("Folder")
	local p=Instance.new("Part",f)
	local r1=f:FindFirstChild("Part")
	assert(_rawequal(r1,p),"r1 should equal p before invalidate")
	cache.invalidate(r1)
	local r2=f:FindFirstChild("Part")
	assert(r2~=nil and not _rawequal(r1,r2) and typeof(r2)=="Instance")
	r2.Name=_uid()
	assert(p.Name==r2.Name,"p and r2 should alias same instance")
	f:Destroy()
end)

test("cache.iscached",{},function()
	local p=Instance.new("Part")
	assert(cache.iscached(p)==true)
	cache.invalidate(p)
	assert(cache.iscached(p)==false)
	p:Destroy()
end)

test("cache.replace",{},function()
	local a=Instance.new("Part")
	local b=Instance.new("Fire")
	cache.replace(a,b)
	assert(cache.iscached(b)==true)
	a:Destroy()
end)

test("cloneref",{},function()
	local p=Instance.new("Part")
	local c=cloneref(p)
	assert(not _rawequal(p,c) and typeof(c)=="Instance")
	local m=_uid();c.Name=m
	assert(p.Name==m,"cloneref should alias same underlying instance")
	p:Destroy()
end)

test("compareinstances",{},function()
	local a=Instance.new("Part")
	local c=cloneref(a)
	local b=Instance.new("Part")
	assert(compareinstances(a,c)==true,"same instance -> true")
	assert(compareinstances(a,b)==false,"different instances -> false")
	a:Destroy();b:Destroy()
end)

test("checkcaller",{},function()
	assert(checkcaller()==true,"executor thread should be caller")
	local result
	local be=Instance.new("BindableEvent")
	be.Event:Connect(function()result=checkcaller()end)
	be:Fire()
	task.wait(0.05)
	be:Destroy()
	assert(result==false,"game callback should not be caller")
end)

test("clonefunction",{},function()
	local s={}
	local function orig()return s end
	local copy=clonefunction(orig)
	assert(not _rawequal(orig,copy) and _type(copy)=="function")
	assert(_rawequal(orig(),copy()),"both should return same upvalue")
	local s2={}
	_safe(debug.setupvalue,copy,1,s2)
	assert(_rawequal(orig(),s),"orig upvalue unchanged")
	assert(_rawequal(copy(),s2),"copy upvalue changed")
end)

test("getcallingscript",{})

test("getscriptclosure",{"getscriptfunction"},function()
	local fn_get=getscriptclosure or getscriptfunction
	assert(_type(fn_get)=="function")
	local ok,mods=_safe(getloadedmodules)
	if not ok or _type(mods)~="table" or #mods==0 then return "no modules" end
	local mod
	for i=1,_min(#mods,50) do
		local v=mods[i]
		if typeof(v)=="Instance" and v:IsA("ModuleScript") then mod=v;break end
	end
	if not mod then return "no ModuleScript found" end
	local ok2,fn=_safe(fn_get,mod)
	assert(ok2 and _type(fn)=="function","expected function back")
end)

test("hookfunction",{"replaceclosure"},function()
	local hit,origRan=false,false
	local function tgt(x,y)origRan=true;return x+y end
	assert(tgt(2,3)==5);origRan=false
	local origFn=hookfunction(tgt,function(x,y)hit=true;return x*y end)
	assert(tgt(2,3)==6,"hook should multiply")
	assert(hit==true,"hook flag should be set")
	assert(origRan==false,"original should not have run")
	assert(origFn(2,3)==5,"original reference should still add")
	origRan=false
	hookfunction(tgt,origFn)
	assert(tgt(2,3)==5 and origRan==true,"restored function should add again")
end)

test("iscclosure",{},function()
	assert(iscclosure(print)==true,"print is C")
	assert(iscclosure(math.random)==true,"math.random is C")
	assert(iscclosure(function()end)==false,"lua closure is not C")
	assert(iscclosure(newcclosure(function()end))==true,"newcclosure wraps as C")
end)

test("islclosure",{},function()
	assert(islclosure(print)==false,"print is not Lua")
	assert(islclosure(function()end)==true,"lua closure is Lua")
	assert(islclosure(newcclosure(function()end))==false,"newcclosure is not Lua")
	local lf=function()end
	assert(iscclosure(lf)~=islclosure(lf),"iscclosure and islclosure must differ")
end)

test("isexecutorclosure",{"checkclosure","isourclosure"},function()
	local fn=isexecutorclosure or checkclosure or isourclosure
	assert(fn(fn)==true,"executor fn -> true")
	assert(fn(newcclosure(function()end))==true,"newcclosure -> true")
	assert(fn(function()end)==true,"lua fn in executor -> true")
	assert(fn(print)==false,"game C fn -> false")
	assert(fn(math.random)==false,"game C fn -> false")
	local ok,renv=_safe(getrenv)
	if ok and _type(renv)=="table" and _type(renv.require)=="function" then
		assert(fn(renv.require)==false,"renv fn -> false")
	end
end)

test("loadstring",{},function()
	local fn,err=loadstring("return ... + 1")
	assert(_type(fn)=="function" and err==nil,"valid source should load")
	assert(fn(1)==2 and fn(9)==10)
	local bad,berr=loadstring("@@invalid@@")
	assert(bad==nil and _type(berr)=="string" and #berr>0,"invalid source should error")
	local anim=_animate()
	if anim then
		local ok,bc=_safe(getscriptbytecode,anim)
		if ok and _type(bc)=="string" and #bc>0 then
			local loaded=loadstring(bc)
			assert(loaded==nil or _type(loaded)=="function","bytecode loadstring should return nil or function")
		end
	end
end)

test("newcclosure",{},function()
	local log={}
	local function orig(a,b)_insert(log,a+b);return a+b end
	local cc=newcclosure(orig)
	assert(iscclosure(cc)==true,"should be C closure")
	assert(islclosure(cc)==false,"should not be Lua closure")
	assert(not _rawequal(cc,orig),"should be a different function")
	assert(cc(3,4)==7 and cc(1,2)==3 and #log==2)
	local function mr()return 10,20,30 end
	local a,b,c=newcclosure(mr)()
	assert(a==10 and b==20 and c==30,"multiple returns should pass through")
end)

test("restorefunction",{"restoreclosure"},function()
	local restore=(_type(restorefunction)=="function" and restorefunction)
		or(_type(restoreclosure)=="function" and restoreclosure)
	assert(_type(restore)=="function","restorefunction/restoreclosure must exist")
	assert(_type(hookfunction)=="function","hookfunction required for this test")
	local function tgt(x)return x*2 end
	local origFn=hookfunction(tgt,function(x)return x*99 end)
	assert(tgt(5)==495,"hook should be active")
	restore(tgt)
	assert(tgt(5)==10,"tgt should be restored")
end)

test("rconsoleclear",{"consoleclear"})
test("rconsolecreate",{"consolecreate"})
test("rconsoledestroy",{"consoledestroy"})
test("rconsoleinput",{"consoleinput"})
test("rconsoleprint",{"consoleprint"})
test("rconsolesettitle",{"rconsolename","consolesettitle"})

test("crypt.base64encode",{"crypt.base64.encode","crypt.base64_encode","base64.encode","base64_encode"},function()
	local enc=crypt.base64encode
	local r0=enc("")
	assert(r0=="" or r0==nil,"empty string: expected '' or nil")
	assert(enc("M")=="TQ==")
	assert(enc("Ma")=="TWE=")
	assert(enc("Man")=="TWFu")
	assert(enc("test")=="dGVzdA==")
	assert(enc("Hello, World!")=="SGVsbG8sIFdvcmxkIQ==")
	local all="";for i=0,255 do all=all.._char(i)end
	local encoded=enc(all)
	assert(_type(encoded)=="string" and #encoded==344,"256 bytes -> 344 base64 chars")
end)

test("crypt.base64decode",{"crypt.base64.decode","crypt.base64_decode","base64.decode","base64_decode"},function()
	local dec=crypt.base64decode
	local r0=dec("")
	assert(r0=="" or r0==nil,"empty decode: expected '' or nil")
	assert(dec("TQ==")=="M")
	assert(dec("TWFu")=="Man")
	assert(dec("dGVzdA==")=="test")
	assert(dec("SGVsbG8sIFdvcmxkIQ==")=="Hello, World!")
	local all="";for i=0,255 do all=all.._char(i)end
	assert(dec(crypt.base64encode(all))==all,"roundtrip must be lossless")
end)

test("crypt.generatekey",{},function()
	local seen={}
	for i=1,6 do
		local k=crypt.generatekey()
		assert(_type(k)=="string" and #k>0,"key must be non-empty string")
		local ok,decoded=_safe(crypt.base64decode,k)
		local keyLen=(ok and _type(decoded)=="string") and #decoded or #k
		assert(keyLen==32,_fmt("key length should be 32, got %d (iter %d)",keyLen,i))
		assert(not seen[k],"duplicate key at iter "..i)
		seen[k]=true
	end
end)

test("crypt.generatebytes",{},function()
	for _,sz in _ipairs({1,8,16,32}) do
		local b=crypt.generatebytes(sz)
		assert(_type(b)=="string" and #b>0,"generatebytes must return string")
		local ok,decoded=_safe(crypt.base64decode,b)
		local byteLen=(ok and _type(decoded)=="string") and #decoded or #b
		assert(byteLen==sz,_fmt("expected %d bytes, got %d",sz,byteLen))
	end
	local seen={}
	for _=1,6 do
		local v=crypt.generatebytes(16)
		assert(not seen[v],"duplicate random bytes");seen[v]=true
	end
end)

test("crypt.encrypt",{},function()
	local key=crypt.generatekey()
	local ok,enc,iv=_safe(function()
		local e,i=crypt.encrypt("hello",key,nil,"CBC")
		return e,i
	end)
	if not ok then
		local iv2=crypt.generatekey()
		enc=crypt.encrypt("hello",key,iv2,"CBC")
		iv=iv2
	end
	assert(_type(enc)=="string" and enc~="hello","ciphertext must differ from plaintext")
	assert(_type(iv)=="string","IV must be a string")
	local plain=crypt.decrypt(enc,key,iv,"CBC")
	assert(plain=="hello","decrypt must recover plaintext")
	local enc2,iv2=crypt.encrypt("hello",key,nil,"CBC")
	if enc2 and iv2 then assert(iv~=iv2,"IVs should differ between encryptions")end
end)

test("crypt.decrypt",{},function()
	local key=crypt.generatekey()
	local iv=crypt.generatekey()
	local plain="secret_".._uid()
	local enc=crypt.encrypt(plain,key,iv,"CBC")
	assert(_type(enc)=="string","encrypt must return string")
	local result=crypt.decrypt(enc,key,iv,"CBC")
	assert(result==plain,"decrypt must recover original plaintext")
end)

test("crypt.hash",{},function()
	local algos={"sha1","sha256","sha384","sha512","md5","sha3-224","sha3-256","sha3-512"}
	local seen={}
	for _,algo in _ipairs(algos) do
		local ok1,h1=_safe(crypt.hash,"test",algo)
		if ok1 and _type(h1)=="string" and #h1>0 then
			local _,h2=_safe(crypt.hash,"test",algo)
			local _,h3=_safe(crypt.hash,_uid(),algo)
			assert(h1==h2,algo.." same input must give same hash")
			assert(h1~=h3,algo.." different input must give different hash")
			assert(not seen[h1],"hash collision: "..algo)
			seen[h1]=algo
		end
	end
end)

test("crypt.random",{},function()
	if _type(crypt)~="table" or _type(crypt.random)~="function" then return "not present" end
	for i=1,10 do
		local n=crypt.random(1,100)
		assert(_type(n)=="number" and n>=1 and n<=100 and n==_floor(n),"out of range at iter "..i)
	end
	local s={};for _=1,30 do s[crypt.random(1,2)]=true end
	assert(s[1] and s[2],"crypt.random should produce both 1 and 2 in 30 tries")
end)

test("debug.getconstant",{},function()
	local MARK="kc_".._uid()
	local function f()print(MARK)end
	local found=false
	local ok,consts=_safe(debug.getconstants,f)
	if ok and _type(consts)=="table" then
		for _,v in _pairs(consts) do if v==MARK then found=true;break end end
	end
	if not found then
		for i=0,255 do
			local ok2,v=_safe(debug.getconstant,f,i)
			if ok2 and v==MARK then found=true;break end
		end
	end
	assert(found,"constant '"..MARK.."' not found in function")
end)

test("debug.getconstants",{},function()
	local STR="sc_".._uid()
	local NUM=7654321
	local function f()local _=NUM;print(STR)end
	local c=debug.getconstants(f)
	assert(_type(c)=="table","getconstants must return table")
	local gs,gn,gp=false,false,false
	for _,v in _pairs(c) do
		if v==STR then gs=true end
		if v==NUM then gn=true end
		if v=="print" then gp=true end
	end
	assert(gs,"string constant not found")
	assert(gn,"number constant not found")
	assert(gp,"print constant not found")
end)

test("debug.getinfo",{},function()
	local function vfn(...)print(...)end
	local function ffn(a,b)return a+b end
	local info=debug.getinfo(vfn)
	assert(_type(info)=="table","getinfo must return table")
	assert(_rawequal(info.func,vfn),"info.func must match function")
	assert(info.is_vararg==1,"vfn should be vararg")
	assert(info.numparams==0,"vfn should have 0 params")
	local i2=debug.getinfo(ffn)
	assert(i2.numparams==2,"ffn should have 2 params")
	assert(i2.is_vararg==0,"ffn should not be vararg")
	local ok,ic=_safe(debug.getinfo,print)
	assert(ok and _type(ic)=="table","getinfo on C function should succeed")
end)

test("debug.getproto",{},function()
	local function outer()
		local function inner()return 99 end
	end
	local ok,act=_safe(debug.getproto,outer,1,true)
	assert(ok and _type(act)=="table" and #act>=1,"should return table of instances")
	assert(_type(act[1])=="function" and act[1]()==99,"proto instance should be callable")
end)

test("debug.getprotos",{},function()
	local function outer()
		local function _a()return "a" end
		local function _b()return "b" end
		local function _c()return "c" end
	end
	local protos=debug.getprotos(outer)
	assert(_type(protos)=="table" and #protos==3,"should have 3 protos")
	local vals={}
	for i=1,3 do
		local ok,act=_safe(debug.getproto,outer,i,true)
		if ok and act and _type(act[1])=="function" then _insert(vals,act[1]())end
	end
	_sort(vals)
	assert(vals[1]=="a" and vals[2]=="b" and vals[3]=="c","proto values mismatch")
end)

test("debug.getstack",{},function()
	local MARK=_uid()
	local passed=false
	local function inner()
		local _=MARK
		local ok,stk=_safe(debug.getstack,1)
		if not ok or _type(stk)~="table" then passed=true;return end
		local found=false
		for _,v in _pairs(stk) do if v==MARK then found=true;break end end
		assert(found,"MARK not found in stack")
		passed=true
	end
	inner()
	assert(passed,"inner() did not complete")
end)

test("debug.getupvalue",{},function()
	local s={}
	local function f()return s end
	local ok,v=_safe(debug.getupvalue,f,1)
	assert(ok and _rawequal(v,s),"upvalue 1 should be s")
end)

test("debug.getupvalues",{},function()
	local a,b,c={},{},{}
	local function f()return a,b,c end
	local ups=debug.getupvalues(f)
	assert(_type(ups)=="table","getupvalues must return table")
	assert(_rawequal(ups[1],a),"upvalue 1 should be a")
	assert(_rawequal(ups[2],b),"upvalue 2 should be b")
	assert(_rawequal(ups[3],c),"upvalue 3 should be c")
end)

test("debug.setconstant",{},function()
	local ORIG="orig_".._uid()
	local MOD="mod_".._uid()
	local function f()return ORIG end
	local idx
	local ok,consts=_safe(debug.getconstants,f)
	if ok and _type(consts)=="table" then
		for i,v in _pairs(consts) do if v==ORIG then idx=i;break end end
	end
	if not idx then
		for i=0,255 do
			local ok2,v=_safe(debug.getconstant,f,i)
			if ok2 and v==ORIG then idx=i;break end
		end
	end
	assert(idx~=nil,"could not find constant index for ORIG")
	_safe(debug.setconstant,f,idx,MOD)
	assert(f()==MOD,"setconstant should change output to MOD")
	_safe(debug.setconstant,f,idx,ORIG)
	assert(f()==ORIG,"restoring constant should return ORIG")
end)

test("debug.setstack",{},function()
	local ok,result=_safe(function()
		local function f()
			local slot="before"
			debug.setstack(1,1,"after")
			return slot
		end
		return f()
	end)
	if not ok then return "not supported" end
	assert(result=="after","setstack should modify local slot")
end)

test("debug.setupvalue",{},function()
	local orig="A_".._uid()
	local repl="B_".._uid()
	local function f()return orig end
	_safe(debug.setupvalue,f,1,repl)
	assert(f()==repl,"upvalue should be replaced")
	_safe(debug.setupvalue,f,1,orig)
	assert(f()==orig,"upvalue should be restored")
end)

test("debug.traceback",{},function()
	local ok,tb=_safe(debug.traceback,"lbl",1)
	if not ok or _type(tb)~="string" then ok,tb=_safe(debug.traceback)end
	assert(_type(tb)=="string" and #tb>0,"traceback must return non-empty string")
end)

test("debug.profilebegin",{},function()
	if _type(debug.profilebegin)~="function" then return "not present" end
	_safe(debug.profilebegin,"unc")
	if _type(debug.profileend)=="function" then _safe(debug.profileend)end
end)

test("debug.profileend",{},function()
	if _type(debug.profileend)~="function" then return "not present" end
	if _type(debug.profilebegin)=="function" then _safe(debug.profilebegin,"unc")end
	_safe(debug.profileend)
end)

test("readfile",{},function()
	local content="rf_".._uid()
	writefile(".tests/rf.txt",content)
	local result=readfile(".tests/rf.txt")
	assert(result==content,_fmt("expected %q got %q",content,tostring(result)))
end)

test("writefile",{},function()
	writefile(".tests/wf.txt","first")
	assert(readfile(".tests/wf.txt")=="first","first write failed")
	writefile(".tests/wf.txt","second")
	assert(readfile(".tests/wf.txt")=="second","overwrite failed")
	local bin="";for i=0,255 do bin=bin.._char(i)end
	writefile(".tests/wf.bin",bin)
	assert(readfile(".tests/wf.bin")==bin,"binary roundtrip failed")
end)

test("appendfile",{},function()
	writefile(".tests/af.txt","abc")
	appendfile(".tests/af.txt","def")
	appendfile(".tests/af.txt","ghi")
	assert(readfile(".tests/af.txt")=="abcdefghi","appended content mismatch")
end)

test("makefolder",{},function()
	local p=".tests/mk_".._uid()
	makefolder(p)
	assert(isfolder(p)==true,"folder should exist after makefolder")
	_safe(makefolder,p)
	assert(isfolder(p)==true,"calling makefolder again should not error")
end)

test("listfiles",{},function()
	local dir=".tests/ls_".._uid()
	makefolder(dir)
	writefile(dir.."/a.txt","a")
	writefile(dir.."/b.txt","b")
	local files=listfiles(dir)
	assert(_type(files)=="table" and #files==2,"should list 2 files")
	for _,p in _ipairs(files) do
		local ok=isfile(p)
		if not ok then ok=isfile(p:gsub("\\","/"))end
		assert(ok,"listed path should be a file: "..tostring(p))
	end
end)

test("isfile",{},function()
	local p=".tests/if_".._uid()..".txt"
	writefile(p,"x")
	assert(isfile(p)==true,"written file should exist")
	assert(isfile(".tests")==false,"folder should not be file")
	assert(isfile(".tests/no_".._uid())==false,"nonexistent should be false")
end)

test("isfolder",{},function()
	assert(isfolder(".tests")==true,".tests should be a folder")
	assert(isfolder(".tests/no_".._uid())==false,"nonexistent should be false")
	assert(isfolder(".tests/isf_".._uid()..".txt")==false,"file should not be folder")
end)

test("delfolder",{},function()
	local p=".tests/df_".._uid()
	makefolder(p)
	assert(isfolder(p)==true,"folder should exist before delete")
	delfolder(p)
	assert(isfolder(p)==false,"folder should not exist after delete")
end)

test("delfile",{},function()
	local p=".tests/del_".._uid()..".txt"
	writefile(p,"bye")
	assert(isfile(p)==true,"file should exist before delete")
	delfile(p)
	assert(isfile(p)==false,"file should not exist after delete")
end)

test("loadfile",{},function()
	local p=".tests/lf_".._uid()..".lua"
	writefile(p,"return ... + 1")
	local fn,err=loadfile(p)
	assert(_type(fn)=="function" and err==nil,"valid file should load cleanly")
	assert(fn(4)==5,"loaded function should work")
	local bp=".tests/bf_".._uid()..".lua"
	writefile(bp,"!invalid!")
	local bad,berr=loadfile(bp)
	assert(bad==nil and _type(berr)=="string","invalid file should return nil + error")
end)

test("dofile",{})

test("getcustomasset",{},function()
	local p=".tests/ca_".._uid()..".png"
	writefile(p,"fake")
	local id=getcustomasset(p)
	assert(_type(id)=="string" and #id>0,"should return asset string")
	assert(_sub(id,1,12)=="rbxasset://","should start with rbxasset://")
	assert(getcustomasset(p)==id,"same file should return same id")
	local p2=".tests/ca2_".._uid()..".png"
	writefile(p2,"other")
	assert(getcustomasset(p2)~=id,"different files should return different ids")
end)

test("isrbxactive",{"isgameactive"},function()
	local ok,r=_safe(isrbxactive)
	assert(ok and _type(r)=="boolean","should return boolean")
end)

test("mouse1click",{})
test("mouse1press",{})
test("mouse1release",{})
test("mouse2click",{})
test("mouse2press",{})
test("mouse2release",{})
test("mousemoveabs",{})
test("mousemoverel",{})
test("mousescroll",{})
test("keypress",{})
test("keyrelease",{})

test("fireclickdetector",{},function()
	local model=Instance.new("Model")
	local part=Instance.new("Part",model)
	local detector=Instance.new("ClickDetector",part)
	model.Parent=workspace
	local fired=false
	local conn=detector.MouseClick:Connect(function()fired=true end)
	_safe(fireclickdetector,detector,0)
	task.wait(0.2)
	_safe(function()conn:Disconnect();model:Destroy()end)
	assert(fired,"MouseClick should have fired")
end)

test("fireproximityprompt",{},function()
	if _type(fireproximityprompt)~="function" then return "not present" end
	local part=Instance.new("Part")
	local prompt=Instance.new("ProximityPrompt",part)
	part.Parent=workspace
	local hit=false
	local conn=prompt.Triggered:Connect(function()hit=true end)
	_safe(fireproximityprompt,prompt)
	task.wait(0.2)
	_safe(function()conn:Disconnect();part:Destroy()end)
	assert(hit,"Triggered should have fired")
end)

test("getcallbackvalue",{},function()
	local bf=Instance.new("BindableFunction")
	local function cb(x)return x*3 end
	bf.OnInvoke=cb
	local ret=getcallbackvalue(bf,"OnInvoke")
	assert(_rawequal(ret,cb),"should return the exact callback")
	assert(ret(4)==12,"callback should still work")
	bf:Destroy()
end)

test("getconnections",{},function()
	local be=Instance.new("BindableEvent")
	local log={}
	be.Event:Connect(function(v)_insert(log,v)end)
	local conns=getconnections(be.Event)
	assert(_type(conns)=="table" and #conns>=1,"should return at least 1 connection")
	local c=conns[1]
	assert(_type(c.Function)=="function","Function field missing")
	assert(_type(c.Disconnect)=="function","Disconnect field missing")
	assert(_type(c.Fire)=="function","Fire field missing")
	if _type(c.Disable)=="function" and _type(c.Enable)=="function" then
		_safe(function()c.Disable();c.Enable()end)
	end
	_safe(c.Fire,"ping")
	task.wait(0.1)
	assert(log[#log]=="ping","Fire should have triggered handler")
	local before=#log
	_safe(function()c.Disconnect()end)
	_safe(function()be:Fire("x")end)
	task.wait(0.1)
	assert(#log==before,"disconnected handler should not fire")
	be:Destroy()
end)

test("gethiddenproperty",{},function()
	local fire=Instance.new("Fire")
	local ok,val,hidden=_safe(function()
		local v,h=gethiddenproperty(fire,"size_xml")
		return v,h
	end)
	assert(ok,"gethiddenproperty should not throw")
	assert(val==5,"size_xml default should be 5")
	assert(hidden==true,"size_xml should be hidden")
	fire:Destroy()
end)

test("sethiddenproperty",{},function()
	local fire=Instance.new("Fire")
	sethiddenproperty(fire,"size_xml",10)
	assert(gethiddenproperty(fire,"size_xml")==10,"should be 10 after set")
	sethiddenproperty(fire,"size_xml",5)
	assert(gethiddenproperty(fire,"size_xml")==5,"should be 5 after restore")
	fire:Destroy()
end)

test("gethui",{},function()
	local hui=gethui()
	assert(typeof(hui)=="Instance","gethui should return Instance")
	local sg=Instance.new("ScreenGui")
	sg.Parent=hui
	assert(sg.Parent==hui,"parenting to hUI should work")
	sg:Destroy()
end)

test("getinstances",{},function()
	local inst=getinstances()
	assert(_type(inst)=="table" and #inst>0,"should return non-empty table")
	local hasGame=false
	for i=1,_min(#inst,300) do
		local v=inst[i]
		if typeof(v)=="Instance" and _rawequal(v,game) then hasGame=true;break end
	end
	assert(hasGame,"game should be in instance list")
end)

test("getnilinstances",{},function()
	local name="UNCnil_".._uid()
	local part=Instance.new("Part");part.Name=name
	local ref=part
	part.Parent=nil
	task.wait(0.05)
	local nilInst=getnilinstances()
	assert(_type(nilInst)=="table","should return table")
	local found=false
	for i=1,_min(#nilInst,300) do
		local v=nilInst[i]
		if typeof(v)=="Instance" and _rawequal(v,ref) then found=true;break end
	end
	assert(found,"nil parented part should appear in getnilinstances")
end)

test("isscriptable",{},function()
	local fire=Instance.new("Fire")
	assert(isscriptable(fire,"size_xml")==false,"size_xml should be non-scriptable")
	assert(isscriptable(fire,"Size")==true,"Size should be scriptable")
	fire:Destroy()
end)

test("setscriptable",{},function()
	local fire=Instance.new("Fire")
	setscriptable(fire,"size_xml",true)
	assert(isscriptable(fire,"size_xml")==true,"should be scriptable after set")
	setscriptable(fire,"size_xml",false)
	assert(isscriptable(fire,"size_xml")==false,"should be non-scriptable after restore")
	fire:Destroy()
end)

test("setrbxclipboard",{})

test("getrawmetatable",{},function()
	local mt={__metatable="Locked!",__index=function(_,k)return k.."_v" end}
	local obj=setmetatable({},mt)
	assert(getmetatable(obj)=="Locked!","protected metatable should return guard string")
	local raw=getrawmetatable(obj)
	assert(_rawequal(raw,mt),"should return actual metatable")
	assert(_type(raw.__index)=="function","__index should be function")
end)

test("hookmetamethod",{},function()
	local log={}
	local obj=setmetatable({},{
		__index=newcclosure(function(_,k)return k.."_orig" end),
		__metatable="Locked!",
	})
	local origIdx=hookmetamethod(obj,"__index",newcclosure(function(_,k)
		_insert(log,k);return k.."_hook"
	end))
	assert(obj.foo=="foo_hook","hook should be active")
	assert(#log>=1 and log[#log]=="foo","hook should have logged 'foo'")
	assert(origIdx(obj,"x")=="x_orig","original should still work")
	hookmetamethod(obj,"__index",origIdx)
	assert(obj.test=="test_orig","restored index should work")
end)

test("getnamecallmethod",{},function()
	local cap={}
	local origNC=nil
	local ok1=_safe(function()
		origNC=hookmetamethod(game,"__namecall",newcclosure(function(self,...)
			_insert(cap,getnamecallmethod())
			return origNC(self,...)
		end))
	end)
	if not ok1 then return "hookmetamethod failed" end
	_safe(function()game:GetService("Lighting")end)
	_safe(function()game:GetService("Workspace")end)
	_safe(function()hookmetamethod(game,"__namecall",origNC)end)
	task.wait(0.05)
	local foundGetService=false
	for _,v in _ipairs(cap) do
		if v=="GetService" then foundGetService=true;break end
	end
	assert(foundGetService,"GetService should appear in captured namecall methods")
end)

test("isreadonly",{},function()
	local t={v=1}
	assert(isreadonly(t)==false,"unfrozen table should not be readonly")
	table.freeze(t)
	assert(isreadonly(t)==true,"frozen table should be readonly")
end)

test("setrawmetatable",{},function()
	local obj=setmetatable({},{
		__index=function()return "old" end,
		__metatable="Locked!",
	})
	assert(_safe(setmetatable,obj,{})==false,"protected setmetatable should fail")
	setrawmetatable(obj,{__index=function()return "new" end})
	assert(obj.any=="new","new __index should take effect")
end)

test("setreadonly",{},function()
	local t={v=1};table.freeze(t)
	assert(isreadonly(t)==true,"should be readonly after freeze")
	assert(_safe(function()t.v=2 end)==false,"write to frozen should fail")
	setreadonly(t,false)
	t.v=9
	assert(t.v==9,"write after setreadonly(false) should work")
	setreadonly(t,true)
	assert(_safe(function()t.v=0 end)==false,"re-frozen write should fail")
end)

test("identifyexecutor",{"getexecutorname"},function()
	local ok,n,v=_safe(function()
		local a,b=identifyexecutor();return a,b
	end)
	if not ok then
		local ok2,name=_safe(identifyexecutor)
		assert(ok2 and _type(name)=="string" and #name>0)
		return name
	end
	assert(_type(n)=="string" and #n>0,"executor name should be non-empty string")
	return v~=nil and "v".._tostring(v) or "no version"
end)

test("lz4compress",{},function()
	local raw=string.rep("abcdef",100)
	local comp=lz4compress(raw)
	assert(_type(comp)=="string" and comp~=raw,"compressed should differ from raw")
	assert(lz4decompress(comp,#raw)==raw,"decompressed should match original")
end)

test("lz4decompress",{},function()
	for _,s in _ipairs({"Hello!",string.rep("xyz",50),"a"}) do
		local comp=lz4compress(s)
		assert(lz4decompress(comp,#s)==s,"roundtrip failed for: "..s)
	end
end)

test("messagebox",{})
test("queue_on_teleport",{"queueonteleport"})

test("request",{"http.request","http_request"},function()
	local fn=(_type(request)=="function" and request)
		or(_type(http_request)=="function" and http_request)
		or(_type(http)=="table" and _type(http.request)=="function" and http.request)
	assert(_type(fn)=="function","no http request function found")
	local ok,res=_safe(fn,{Url="https://httpbin.org/get",Method="GET"})
	if not ok then return "network unavailable" end
	assert(_type(res)=="table","response must be table")
	assert(_type(res.StatusCode)=="number" and res.StatusCode>=200 and res.StatusCode<400,
		"expected 2xx/3xx, got "..tostring(res.StatusCode))
	assert(_type(res.Body)=="string" and #res.Body>0,"body should be non-empty")
	return "HTTP "..res.StatusCode
end)

test("setclipboard",{"toclipboard"})

test("setfpscap",{},function()
	local rs=game:GetService("RunService").RenderStepped
	rs:Wait()
	local function measure(n)
		local s=0
		for _=1,n do s=s+1/rs:Wait()end
		return s/n
	end
	setfpscap(30);task.wait(0.1)
	local capped=measure(4)
	setfpscap(0);task.wait(0.1)
	local free=measure(4)
	setfpscap(0)
	assert(capped<=55,"capped FPS too high: "..math.round(capped))
	assert(free>capped,"free FPS should exceed capped FPS")
	return math.round(capped).."@30cap / "..math.round(free).."@uncapped"
end)

test("getgc",{},function()
	local marker={__unc_marker=_uid()}
	local _keep=marker
	local ok,gc=_safe(getgc,true)
	if not ok then ok,gc=_safe(getgc,false)end
	if not ok or _type(gc)~="table" then return "getgc unavailable" end
	assert(#gc>0,"GC table should not be empty")
	local hf,ht,found=false,false,false
	local limit=_min(#gc,2000)
	for i=1,limit do
		local v=gc[i]; local t=_type(v)
		if t=="function" then hf=true end
		if t=="table" then ht=true end
		if t=="table" and _rawequal(v,marker) then found=true end
		if hf and ht and found then break end
	end
	assert(hf,"no functions found in GC")
	assert(ht,"no tables found in GC")
	assert(found,"marker table not found in GC")
end)

test("getgenv",{},function()
	local key="__unc_".._uid()
	local genv=getgenv()
	assert(_type(genv)=="table","getgenv must return table")
	genv[key]=42
	assert(getfenv(0)[key]==42,"genv write should be visible in fenv")
	genv[key]=nil
end)

test("getfenv",{},function()
	local env=getfenv(0)
	assert(_type(env)=="table","getfenv(0) must return table")
	assert(_rawequal(env.game,game),"env.game should be game")
	assert(_type(env.print)=="function","env.print should be function")
	local function f()end
	assert(_type(getfenv(f))=="table","getfenv(fn) must return table")
end)

test("setfenv",{},function()
	local key="__sf_".._uid()
	local custom=setmetatable({[key]=true},{__index=getfenv(0)})
	local function f()return _G[key]end
	setfenv(f,custom)
	local ok,result=_safe(f)
	if not ok then return "sandboxed" end
	assert(result==true,"setfenv should expose custom key")
end)

test("getloadedmodules",{},function()
	local mods=getloadedmodules()
	assert(_type(mods)=="table" and #mods>0,"should return non-empty table")
	for i=1,_min(#mods,100) do
		local m=mods[i]
		assert(typeof(m)=="Instance" and m:IsA("ModuleScript"),"entry "..i.." should be ModuleScript")
	end
end)

test("getrenv",{},function()
	local renv=getrenv()
	assert(_type(renv)=="table","getrenv must return table")
	assert(_rawequal(renv.game,game),"renv.game should be game")
	assert(_rawequal(renv.workspace,workspace),"renv.workspace should be workspace")
	assert(_type(renv.print)=="function","renv.print should be function")
end)

test("getrunningscripts",{},function()
	local scripts=getrunningscripts()
	assert(_type(scripts)=="table" and #scripts>0,"should return non-empty table")
	for i=1,_min(#scripts,100) do
		local s=scripts[i]
		assert(typeof(s)=="Instance","entry "..i.." should be Instance")
		assert(s:IsA("ModuleScript") or s:IsA("LocalScript"),"entry "..i.." should be ModuleScript or LocalScript")
	end
end)

test("getscriptbytecode",{"dumpstring"},function()
	local anim=_animate()
	if not anim then return "no Animate script" end
	local ok,bc=_safe(getscriptbytecode,anim)
	assert(ok and _type(bc)=="string" and #bc>0,"should return bytecode string")
	local hasNP=false
	for i=1,_min(#bc,32) do
		if _byte(bc,i)<32 or _byte(bc,i)>126 then hasNP=true;break end
	end
	assert(hasNP,"bytecode should contain non-printable bytes")
end)

test("getscripthash",{},function()
	local anim=_animate()
	if not anim then return "no Animate script" end
	local ok,clone=_safe(function()return anim:Clone()end)
	if not ok then return "clone failed" end
	local h1=getscripthash(clone)
	assert(_type(h1)=="string" and #h1>0,"hash must be non-empty string")
	assert(h1==getscripthash(clone),"same script should give same hash")
	local canWrite=_safe(function()clone.Source=clone.Source end)
	if canWrite then
		local orig=clone.Source
		clone.Source="--".._uid()
		assert(getscripthash(clone)~=h1,"modified source should give different hash")
		clone.Source=orig
		assert(getscripthash(clone)==h1,"restored source should give original hash")
	else
		return "source write restricted"
	end
end)

test("getscripts",{},function()
	local scripts=getscripts()
	assert(_type(scripts)=="table" and #scripts>0,"should return non-empty table")
	for i=1,_min(#scripts,100) do
		local s=scripts[i]
		assert(typeof(s)=="Instance","entry should be Instance")
		assert(s:IsA("ModuleScript") or s:IsA("LocalScript"),"entry "..i.." should be script type")
	end
end)

test("getsenv",{},function()
	local anim=_animate()
	if not anim then return "no Animate script" end
	local ok,env=_safe(getsenv,anim)
	assert(ok and _type(env)=="table","getsenv should return table")
	assert(_rawequal(env.game,game),"env.game should be game")
	assert(_rawequal(env.script,anim),"env.script should be Animate")
end)

test("getthreadidentity",{"getidentity","getthreadcontext"},function()
	local id=getthreadidentity()
	assert(_type(id)=="number","identity should be number")
	assert(id==_floor(id),"identity should be integer")
	assert(id>=0 and id<=8,"identity should be 0-8")
end)

test("setthreadidentity",{"setidentity","setthreadcontext"},function()
	local orig=getthreadidentity()
	for _,id in _ipairs({2,3,6,7}) do
		setthreadidentity(id)
		assert(getthreadidentity()==id,"identity should be "..id)
	end
	setthreadidentity(orig)
	assert(getthreadidentity()==orig,"identity should be restored")
end)

test("Drawing",{})

test("Drawing.new",{},function()
	local types={"Line","Text","Circle","Square","Image","Quad","Triangle"}
	local objs={}
	for _,dtype in _ipairs(types) do
		local ok,d=_safe(Drawing.new,dtype)
		assert(ok and d~=nil,"Drawing.new('"..dtype.."') should succeed")
		local vok=_safe(function()return d.Visible end)
		assert(vok,dtype.." should have Visible property")
		_insert(objs,d)
	end
	for i,d in _ipairs(objs) do
		local method=(i%2==0) and "Destroy" or "Remove"
		_safe(function()d[method](d)end)
	end
end)

test("Drawing.Fonts",{},function()
	assert(_type(Drawing.Fonts)=="table","Fonts should be table")
	assert(Drawing.Fonts.UI==0,"UI font should be 0")
	assert(Drawing.Fonts.System==1,"System font should be 1")
	assert(Drawing.Fonts.Plex==2,"Plex font should be 2")
	assert(Drawing.Fonts.Monospace==3,"Monospace font should be 3")
end)

test("isrenderobj",{},function()
	local d=Drawing.new("Square")
	assert(isrenderobj(d)==true,"Drawing object should be render obj")
	assert(isrenderobj(newproxy())==false,"proxy should not be render obj")
	assert(isrenderobj({})==false,"table should not be render obj")
	assert(isrenderobj(nil)==false,"nil should not be render obj")
	d:Remove()
end)

test("getrenderproperty",{},function()
	local d=Drawing.new("Square")
	d.Visible=true
	assert(getrenderproperty(d,"Visible")==true,"should read true")
	d.Visible=false
	assert(getrenderproperty(d,"Visible")==false,"should read false")
	d:Remove()
end)

test("setrenderproperty",{},function()
	local d=Drawing.new("Square")
	setrenderproperty(d,"Visible",true)
	assert(d.Visible==true,"should be true after set")
	setrenderproperty(d,"Visible",false)
	assert(d.Visible==false,"should be false after set")
	d:Remove()
end)

test("cleardrawcache",{},function()
	local objs={}
	for _=1,3 do
		local d=Drawing.new("Square");d.Visible=false;_insert(objs,d)
	end
	local ok,err=_safe(cleardrawcache)
	assert(ok,"cleardrawcache should not throw: "..tostring(err))
end)

test("getmenv",{},function()
	if _type(getmenv)~="function" then return "not present" end
	local ok,env=_safe(getmenv)
	if not ok then return "threw" end
	assert(_type(env)=="table","should return table")
	assert(_rawequal(env.game,game) or _rawequal(env.workspace,workspace),"env should contain game globals")
end)

test("getobjects",{},function()
	if _type(getobjects)~="function" then return "not present" end
	local ok,r=_safe(getobjects,"rbxasset://textures/face.png")
	if not ok then return "threw" end
	assert(_type(r)=="table","should return table")
end)

test("isnetworkowner",{},function()
	if _type(isnetworkowner)~="function" then return "not present" end
	local part=Instance.new("Part");part.Parent=workspace
	local ok,r=_safe(isnetworkowner,part)
	_safe(function()part:Destroy()end)
	if not ok then return "threw" end
	assert(_type(r)=="boolean","should return boolean")
end)

test("getspecialinfo",{},function()
	if _type(getspecialinfo)~="function" then return "not present" end
	local part=Instance.new("Part")
	local ok,r=_safe(getspecialinfo,part)
	_safe(function()part:Destroy()end)
	if not ok then return "threw" end
	assert(_type(r)=="table","should return table")
end)

test("decompile",{},function()
	if _type(decompile)~="function" then return "not present" end
	local anim=_animate()
	if not anim then return "no Animate script" end
	local ok,result=_safe(decompile,anim)
	if not ok then return "threw" end
	assert(_type(result)=="string","should return string")
end)

test("getsynasset",{"getCustomAsset"},function()
	if _type(getsynasset)~="function" then return "not present" end
	local p=".tests/gsa_".._uid()..".png"
	_safe(writefile,p,"data")
	local ok,id=_safe(getsynasset,p)
	if not ok then return "threw" end
	assert(_type(id)=="string" and #id>0,"should return asset id string")
end)

test("saveinstance",{},function()
	if _type(saveinstance)~="function" then return "not present" end
	return "present (skipped)"
end)

test("getproperties",{})

test("firetouchinterest",{},function()
	if _type(firetouchinterest)~="function" then return "not present" end
	local a=Instance.new("Part");a.Parent=workspace
	local b=Instance.new("Part");b.Parent=workspace
	local hit=false
	local conn=a.Touched:Connect(function()hit=true end)
	_safe(firetouchinterest,a,b,0)
	task.wait(0.2)
	_safe(function()conn:Disconnect();a:Destroy();b:Destroy()end)
	assert(hit,"Touched should have fired")
end)

test("getscriptfromthread",{},function()
	if _type(getscriptfromthread)~="function" then return "not present" end
	local ok,r=_safe(getscriptfromthread,coroutine.running())
	if not ok then return "threw" end
	if r~=nil then assert(typeof(r)=="Instance","should return Instance or nil")end
end)

test("getthreads",{},function()
	if _type(getthreads)~="function" then return "not present" end
	local ok,r=_safe(getthreads)
	if not ok then return "threw" end
	assert(_type(r)=="table","should return table")
	for i=1,_min(#r,20) do assert(_type(r[i])=="thread","entry "..i.." should be thread")end
end)

test("isparallel",{},function()
	if _type(isparallel)~="function" then return "not present" end
	local ok,r=_safe(isparallel)
	if not ok then return "threw" end
	assert(_type(r)=="boolean","should return boolean")
end)

test("setsimulationradius",{},function()
	if _type(setsimulationradius)~="function" then return "not present" end
	local ok=_safe(setsimulationradius,1000)
	if not ok then return "threw" end
end)

test("getconnection",{},function()
	if _type(getconnection)~="function" then return "not present" end
	local be=Instance.new("BindableEvent")
	local conn=be.Event:Connect(function()end)
	local ok=_safe(getconnection,conn)
	_safe(function()conn:Disconnect();be:Destroy()end)
	if not ok then return "threw" end
end)

test("WebSocket",{})

test("WebSocket.connect",{},function()
	if _type(WebSocket)~="table" and _type(WebSocket)~="userdata" then return "not present" end
	if _type(WebSocket.connect)~="function" then return "not present" end
	local ok,ws=_safe(WebSocket.connect,"wss://echo.websocket.events")
	if not ok or ws==nil then
		ok,ws=_safe(WebSocket.connect,"ws://echo.websocket.events")
		if not ok or ws==nil then return "connect failed (network)" end
	end
	local wsType=_type(ws)
	if wsType~="table" and wsType~="userdata" then return "unexpected ws type" end
	if _type(ws.Send)~="function" or _type(ws.Close)~="function" then
		_safe(function()ws:Close()end);return "missing Send or Close"
	end
	if ws.OnMessage==nil then _safe(function()ws:Close()end);return "missing OnMessage" end
	local received={}
	local connOk,conn=_safe(function()
		return ws.OnMessage:Connect(function(msg)_insert(received,msg)end)
	end)
	if not connOk then _safe(function()ws:Close()end);return "OnMessage:Connect failed" end
	local payload="unc_".._uid()
	_safe(function()ws:Send(payload)end)
	local t=_clock()
	repeat task.wait(0.1) until #received>0 or (_clock()-t)>=6
	_safe(function()conn:Disconnect()end)
	_safe(function()ws:Close()end)
	if #received==0 then return "echo server unreachable (network)" end
	assert(received[1]==payload,"echoed message should match sent payload")
end)

task.defer(function()
	task.wait()
	_integrityCheck()
	_scheduler()
end)