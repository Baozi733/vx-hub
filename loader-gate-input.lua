--[[
	VX Hub 卡密输入版
	用法（执行器里执行，不需要在命令里带卡密）：

	    loadstring(game:HttpGet("https://gh-proxy.com/https://raw.githubusercontent.com/Baozi733/vx-hub/refs/heads/main/loader-gate-input.lua"))()

	会弹出一个输入框，让用户自己打卡密，点「进入」才加载主程序。
	卡密错/到期/换设备都会在框里直接提示原因。

	如果已经在命令里传了卡密（...）("VX-...."），就直接用，不再弹框。
]]

local ARGS = { ... }
local PRESET = tostring(ARGS[1] or "")
local GATE = "https://vxhub-auth.guangdong-77.workers.dev/vx"
local KEY_FILE = "VX_key.txt"

-- ============ 设备标识 ============
local function getHwid()
	if type(gethwid) == "function" then
		local ok, v = pcall(gethwid)
		if ok and v and v ~= "" then return tostring(v) end
	end
	local ok2, v2 = pcall(function()
		return game:GetService("RbxAnalyticsService"):GetClientId()
	end)
	if ok2 and v2 and v2 ~= "" then return tostring(v2) end
	local execName = "unknown"
	if type(identifyexecutor) == "function" then
		local ok3, a = pcall(identifyexecutor)
		if ok3 and a then execName = tostring(a) end
	end
	local lp = game:GetService("Players").LocalPlayer
	return tostring(lp and lp.UserId or 0) .. ":" .. execName
end

local function urlEncode(s)
	return (tostring(s):gsub("[^%w%-%._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function httpGet(url)
	local ok, body = pcall(function() return game:HttpGet(url, true) end)
	if ok and type(body) == "string" and #body > 0 then return body end
	if type(syn) == "table" and type(syn.request) == "function" then
		local ok2, res = pcall(syn.request, { Url = url, Method = "GET" })
		if ok2 and res and res.Body then return res.Body end
	end
	if type(request) == "function" then
		local ok3, res = pcall(request, { Url = url, Method = "GET" })
		if ok3 and res and res.Body then return res.Body end
	end
	return nil
end

local function rememberKey(key)
	pcall(function() writefile(KEY_FILE, key) end)
end

local function recallKey()
	local ok, data = pcall(function() return readfile(KEY_FILE) end)
	if ok and type(data) == "string" then
		return (data:gsub("%s+", ""))
	end
	return ""
end

-- ============ 主程序加载 ============
local function runScript(body, key)
	local chunk, err = loadstring(body)
	if not chunk then
		return false, "编译失败：" .. tostring(err)
	end
	local ok, runErr = pcall(chunk, key)
	if not ok then
		return false, "运行异常：" .. tostring(runErr)
	end
	return true
end

local Friendly = {
	invalid = "卡密不存在，检查有没有打错",
	expired = "这张卡已经到期了",
	banned = "这张卡被封禁了",
	device_mismatch = "这张卡已经绑定其他设备，找卖家解绑",
	no_hwid = "取不到设备标识，换个执行器试试",
	upstream = "服务器拉取脚本失败，稍后再试",
	server = "服务器异常，稍后再试",
	notfound = "网关地址不对",
}

-- 去服务器换脚本
local function exchange(key, callback)
	task.spawn(function()
		local url = GATE .. "?key=" .. urlEncode(key) .. "&hwid=" .. urlEncode(getHwid())
		local body = httpGet(url)
		if not body then
			callback(false, "网络不通，检查手机网络后重试")
			return
		end
		local code, msg = body:match("^%-%-%[%[VXERR:([^|]+)|(.-)%]%]")
		if code then
			callback(false, Friendly[code] or msg or code)
			return
		end
		callback(true, body)
	end)
end

-- ============ 界面 ============
local function buildLogin(onDone)
	local parent = game:GetService("CoreGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "VXLogin"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10000
	local okParent = pcall(function() gui.Parent = parent end)
	if not okParent then
		gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.9, 0, 0, 240)
	panel.Position = UDim2.new(0.05, 0, 0.5, -120)
	panel.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(110, 190, 255)
	stroke.Parent = panel

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("FF1493")),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex("00FFAA")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("00BFFF")),
	})
	gradient.Parent = stroke

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -32, 0, 42)
	title.Position = UDim2.new(0, 16, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(235, 240, 250)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "VX Hub 验证"
	title.Parent = panel

	local tip = Instance.new("TextLabel")
	tip.Size = UDim2.new(1, -32, 0, 22)
	tip.Position = UDim2.new(0, 16, 0, 50)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.Gotham
	tip.TextSize = 13
	tip.TextColor3 = Color3.fromRGB(150, 150, 170)
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.Text = "输入你的卡密（形如 VX-XXXX-XXXX-XXXX-XXXX）"
	tip.Parent = panel

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -32, 0, 46)
	box.Position = UDim2.new(0, 16, 0, 78)
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Code
	box.TextSize = 18
	box.TextColor3 = Color3.fromRGB(235, 240, 250)
	box.PlaceholderText = "VX-XXXX-XXXX-XXXX-XXXX"
	box.PlaceholderColor3 = Color3.fromRGB(90, 90, 110)
	box.ClearTextOnFocus = false
	box.Text = PRESET ~= "" and PRESET or recallKey()
	box.Parent = panel

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 8)
	boxCorner.Parent = box

	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 10)
	boxPad.PaddingRight = UDim.new(0, 10)
	boxPad.Parent = box

	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -32, 0, 24)
	status.Position = UDim2.new(0, 16, 0, 132)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextColor3 = Color3.fromRGB(255, 150, 150)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = panel

	local confirm = Instance.new("TextButton")
	confirm.Size = UDim2.new(1, -32, 0, 46)
	confirm.Position = UDim2.new(0, 16, 0, 168)
	confirm.BackgroundColor3 = Color3.fromRGB(60, 130, 255)
	confirm.BorderSizePixel = 0
	confirm.Font = Enum.Font.GothamBold
	confirm.TextSize = 15
	confirm.TextColor3 = Color3.new(1, 1, 1)
	confirm.Text = "进 入"
	confirm.Parent = panel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = confirm

	local busy = false

	local function submit()
		if busy then return end
		local key = (box.Text or ""):gsub("%s+", ""):upper()
		if #key < 8 then
			status.TextColor3 = Color3.fromRGB(255, 150, 150)
			status.Text = "卡密格式不对，检查一下"
			return
		end
		busy = true
		confirm.Text = "验证中..."
		status.TextColor3 = Color3.fromRGB(180, 200, 220)
		status.Text = "正在连接服务器..."

		exchange(key, function(ok, data)
			if not ok then
				busy = false
				confirm.Text = "进 入"
				status.TextColor3 = Color3.fromRGB(255, 130, 130)
				status.Text = data
				return
			end
			status.TextColor3 = Color3.fromRGB(120, 220, 150)
			status.Text = "验证通过，正在加载..."
			rememberKey(key)
			task.wait(0.2)
			gui:Destroy()
			local ran, err = runScript(data, key)
			if not ran then
				warn("[VX] " .. tostring(err))
			end
			onDone(ran)
		end)
	end

	confirm.MouseButton1Click:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	-- 手机点输入框自动弹键盘
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > 40 then
			box.Text = box.Text:sub(1, 40)
		end
	end)

	return gui
end

-- ============ 启动 ============
if PRESET ~= "" then
	-- 命令里已经给了卡密，直接验证，不弹框
	exchange(PRESET, function(ok, data)
		if not ok then
			warn("[VX] " .. tostring(data))
			return
		end
		local ran, err = runScript(data, PRESET)
		if not ran then warn("[VX] " .. tostring(err)) end
	end)
else
	buildLogin(function() end)
end
