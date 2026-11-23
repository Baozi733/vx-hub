--[[
	VX Hub v1.0 —— 通用 Roblox 执行器脚本框架
	对标 PYHub 的结构：兼容层 / 工具 / 游戏适配 / 自绘 UI / 功能 / 上报

	入口（远端加载）：
	    loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/refs/heads/main/dist/vxhub.lua"))("卡密")

	目录结构：
	    0  参数
	    1  执行器兼容层
	    2  工具函数
	    3  配置与持久化
	    4  游戏适配层（全部 pcall 保护，缺模块自动降级）
	    5  迷你 UI 库（自绘，无外部依赖）
	    6  ESP
	    7  自瞄
	    8  Ragebot
	    9  范围（Hitbox）
	   10  角色移动
	   11  游戏功能（体力/子弹/反摔/隐身等）
	   12  悬浮开关
	   13  上报（可关）
	   14  菜单装配
	   15  启动
]]

-- ============================================================
-- 0. 参数
-- ============================================================
local ARGS = {...}
local SCRIPT_KEY = tostring(ARGS[1] or "")

local TAG = "[VX] "

-- ============================================================
-- 1. 执行器兼容层
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")

local cloneref   = cloneref or function(o) return o end
local newcclosure = (type(newcclosure) == "function") and newcclosure or function(f) return f end
local hookfunction = (type(hookfunction) == "function" and hookfunction)
	or (type(hookfunc) == "function" and hookfunc)
	or nil
local getrawmetatable = (type(getrawmetatable) == "function") and getrawmetatable or nil
local setreadonly     = (type(setreadonly) == "function") and setreadonly or nil
local getnamecallmethod = (type(getnamecallmethod) == "function") and getnamecallmethod or function() return "" end
local fireproximityprompt = (type(fireproximityprompt) == "function") and fireproximityprompt or nil
local getgc = (type(getgc) == "function") and getgc or function() return {} end
local DrawingLib = Drawing   -- 没有 Drawing 库时自动降级（FOV 圈/追踪线不可用，其余功能照常）

local hasIO = (type(writefile) == "function") and (type(readfile) == "function")

local function getEnv()
	if type(getgenv) == "function" then
		local ok, e = pcall(getgenv)
		if ok and type(e) == "table" then return e end
	end
	return _G
end
local ENV = getEnv()

local function waitLocalPlayer()
	local waited = 0
	while not Players.LocalPlayer and waited < 20 do
		task.wait(0.25)
		waited = waited + 0.25
	end
	return Players.LocalPlayer
end
local LP = waitLocalPlayer()
if not LP then
	warn(TAG .. "未取到 LocalPlayer，退出")
	return
end

local function resolveGuiParent()
	local parent
	pcall(function()
		if type(gethui) == "function" then parent = gethui() end
	end)
	if parent then return parent end
	pcall(function() parent = game:GetService("CoreGui") end)
	if parent then return parent end
	pcall(function() parent = LP:WaitForChild("PlayerGui", 5) end)
	return parent
end
local UI_PARENT = resolveGuiParent()

-- ============================================================
-- 2. 工具函数
-- ============================================================
local function getChar(player)
	player = player or LP
	local char = player.Character
	if not char then return nil end
	local hum  = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("UpperTorso")
	if not hum or not root then return nil end
	return char, hum, root
end

local function isAlive(player)
	local _, hum = getChar(player)
	return hum ~= nil and hum.Health > 0
end

local function teamName(player)
	return (player and player.Team and player.Team.Name) or "Neutral"
end

local Palette = {
	["红"] = Color3.fromRGB(255, 70, 70),
	["橙"] = Color3.fromRGB(255, 150, 40),
	["黄"] = Color3.fromRGB(255, 235, 60),
	["绿"] = Color3.fromRGB(70, 235, 110),
	["青"] = Color3.fromRGB(60, 235, 235),
	["蓝"] = Color3.fromRGB(70, 150, 255),
	["紫"] = Color3.fromRGB(170, 90, 255),
	["粉"] = Color3.fromRGB(255, 130, 200),
	["白"] = Color3.fromRGB(255, 255, 255),
}

local function rainbow(period)
	period = period or 5
	return Color3.fromHSV((tick() % period) / period, 0.85, 1)
end

local function colorOf(name)
	if name == "彩虹" then return rainbow() end
	return Palette[name] or Palette["红"]
end

local ColorNames = { "红", "橙", "黄", "绿", "青", "蓝", "紫", "粉", "白", "彩虹" }

local function notify(text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "VX Hub",
			Text = tostring(text),
			Duration = 3,
		})
	end)
	warn(TAG .. tostring(text))
end

-- ============================================================
-- 3. 配置与持久化
-- ============================================================
local CONFIG_FILE = "VXHub_config.json"

local Defaults = {
	esp = {
		enabled = false, name = true, dist = true, health = true,
		highlight = true, tracer = false, teamCheck = false, maxDist = 800,
	},
	aim = {
		enabled = false, fov = 110, smooth = 0.35, part = "Head",
		prediction = false, wallCheck = false, teamCheck = true,
		showFov = true, showCrosshair = true, showTracer = false,
		color = "红", holdKey = true,
	},
	rage = {
		enabled = false, range = 120, interval = 0.08, damage = 3,
		part = "Head", teamCheck = true, wallCheck = false, beam = false,
	},
	hitbox = {
		enabled = false, size = 10, transparency = 0.7, color = "红",
		glow = false, pulse = false, teamCheck = true, collision = false,
	},
	player = {
		speedOn = false, speed = 32, jumpOn = false, jump = 70,
		infJump = false, flyOn = false, flySpeed = 70, flyMode = "传送",
		noclip = false,
	},
	game = {
		stamina = false, hunger = false, combatBlock = false, noRagdoll = false,
		noFallDamage = false, infiniteAmmo = false, rapidFire = false,
		autoPickup = false, autoMission = false, autoCuff = false,
		cuffRange = 200,
	},
	ui = {
		openKey = "RightShift", autoReport = false, showOpenButton = true,
	},
	meta = {
		borderRainbow = true, borderEnabled = true, borderColor = "青",
	},
	-- 安全模式：让行为更像真人，降低被服务端记录的概率
	safe = {
		enabled = true,      -- 默认开
		level = "标准",      -- 标准 / 极限（极限会强制压低一切可疑参数）
		maxSpeed = 32,       -- 速度上限（服务端一般容忍 30~40）
		teleportStep = 12,   -- 每次移动多少 stud
		teleportGap = 0.05,  -- 每步间隔
		rageJitter = 0.35,   -- 攻击间隔随机浮动比例
		rageSkipRate = 0.12, -- 随机漏打的概率
		noGcScan = true,     -- 禁用 getgc 扫描类功能
		ammoCap = 9999,      -- 子弹上限（替代 math.huge）
		maxFov = 90,         -- 极限模式下自瞄 FOV 上限
		tpBudget = 220,      -- 传送令牌桶：每 tpWindow 秒最多走这么多 stud
		tpWindow = 2,
		burstOn = 3.0,       -- 连打多少秒后强制休息
		burstOff = 1.5,      -- 休息多久
		panicKey = "P",      -- 急停键：一键关掉全部功能
	},
}

local function deepCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and deepCopy(v) or v
	end
	return out
end

local C = deepCopy(Defaults)

local function saveConfig()
	if not hasIO then return end
	pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(C))
	end)
end

local function loadConfig()
	if not hasIO then return end
	local ok, data = pcall(readfile, CONFIG_FILE)
	if not ok or type(data) ~= "string" or data == "" then return end
	local ok2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
	if not ok2 or type(decoded) ~= "table" then return end
	for section, values in pairs(decoded) do
		if type(C[section]) == "table" and type(values) == "table" then
			for k, v in pairs(values) do
				if C[section][k] ~= nil then
					C[section][k] = v
				end
			end
		end
	end
end
loadConfig()

-- ============================================================
-- 启动强制策略：所有功能一律关闭，只保留安全模式
--   配置文件会记住上次状态；不强制清掉的话，上次开了透视/飞行，
--   下次一进游戏就是开着的，容易出事。子选项（颜色/距离等）保留。
-- ============================================================
local ForceOff = {
	esp = { "enabled" },
	aim = { "enabled" },
	rage = { "enabled" },
	hitbox = { "enabled" },
	player = { "speedOn", "jumpOn", "infJump", "flyOn", "noclip" },
	game = {
		"stamina", "hunger", "combatBlock", "noRagdoll", "noFallDamage",
		"infiniteAmmo", "rapidFire", "autoPickup", "autoMission", "autoCuff",
	},
}
for section, keys in pairs(ForceOff) do
	if type(C[section]) == "table" then
		for _, key in ipairs(keys) do
			if C[section][key] ~= nil then
				C[section][key] = false
			end
		end
	end
end

-- 安全模式始终默认开启（想关就在菜单里点，本次会话有效）
C.safe.enabled = true

-- ============================================================
-- 「极限防封」策略
--   把所有能触发服务端/行为检测的参数压到人类范围：
--   限速更低、传送更碎、攻击更慢更随机、关掉所有自动化和 GC 扫描
-- ============================================================
local function isExtreme()
	return C.safe.level == "极限"
end

local function applyProtectionLevel()
	if not isExtreme() then return end
	C.safe.maxSpeed = math.min(C.safe.maxSpeed or 32, 28)
	C.safe.teleportStep = math.min(C.safe.teleportStep or 12, 8)
	C.safe.teleportGap = math.max(C.safe.teleportGap or 0.05, 0.08)
	C.safe.rageJitter = math.max(C.safe.rageJitter or 0.35, 0.4)
	C.safe.rageSkipRate = math.max(C.safe.rageSkipRate or 0.12, 0.2)
	C.safe.noGcScan = true
	C.safe.ammoCap = math.min(C.safe.ammoCap or 9999, 300)

	-- 关掉最容易被抓的功能
	C.game.rapidFire = false
	C.game.autoMission = false
	C.game.autoCuff = false
	C.game.autoPickup = false
	C.hitbox.enabled = false

	-- 战斗参数压到"像人"
	C.aim.fov = math.min(C.aim.fov or 110, C.safe.maxFov or 90)
	C.aim.prediction = false
	C.rage.damage = 1
	C.rage.interval = math.max(C.rage.interval or 0.08, 0.16)
end

-- ============================================================
-- 4. 游戏适配层
--    这里是与具体游戏耦合的部分。换游戏只改这一块。
--    默认按 "Remote/PlayerEvent + PlayerScripts/Framework" 结构探测。
-- ============================================================
local Game = {
	event = nil,      -- RemoteEvent：PlayerEvent
	func = nil,       -- RemoteFunction：PlayerFunc
	character = nil,  -- Framework/Character 模块
	core = nil,       -- Framework/Core 模块
	algorithms = nil, -- ReplicatedStorage/Modules/Algorithms
	ragdoll = nil,    -- ReplicatedStorage/Modules/Ragdoll
}

pcall(function()
	local folder = ReplicatedStorage:WaitForChild("Remote", 10)
	if folder then
		Game.event = folder:WaitForChild("PlayerEvent", 10)
		Game.func  = folder:WaitForChild("PlayerFunc", 10)
	end
end)

pcall(function()
	local framework = LP:WaitForChild("PlayerScripts", 10):WaitForChild("Framework", 10)
	Game.character = require(framework:WaitForChild("Character", 10))
	if framework:FindFirstChild("Core") then
		Game.core = require(framework:FindFirstChild("Core"))
	end
end)

pcall(function()
	Game.algorithms = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Algorithms"))
end)

pcall(function()
	Game.ragdoll = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Ragdoll"))
end)

local unpackFn = table.unpack or unpack

local function fireEvent(...)
	if not Game.event then return end
	-- 注意：'...' 不能直接写进内层普通函数里，先收集再传
	local args = { ... }
	local count = select("#", ...)
	pcall(function()
		Game.event:FireServer(unpackFn(args, 1, count))
	end)
end

local function invokeFunc(...)
	if not Game.func then return nil end
	local args = { ... }
	local count = select("#", ...)
	local ok, res = pcall(function()
		return Game.func:InvokeServer(unpackFn(args, 1, count))
	end)
	if ok then return res end
	return nil
end

-- 传送令牌桶：极限模式下限制"单位时间能走多远"
local TP = { budget = 0 }
RunService.Heartbeat:Connect(function(dt)
	local cap = C.safe.tpBudget or 220
	local win = math.max(0.5, C.safe.tpWindow or 2)
	TP.budget = math.min(cap, (TP.budget or 0) + cap * dt / win)
end)

-- 客户端传送：本地 PivotTo + 可选向服务端同步（不同游戏字段不同，改这里）
-- 安全模式下改成"分几步走过去"，避免服务端看到瞬移
local function teleportTo(position)
	local char, _, root = getChar(LP)
	if not char or not root or not position then return end
	local target = position + Vector3.new(0, 3, 0)

	-- 极限模式：令牌桶限速，短时间能走的距离有上限，避免"连续瞬移"被抓
	if isExtreme() then
		local from = root.Position
		local delta = target - from
		local distance = delta.Magnitude
		local budget = TP.budget or 0
		if budget < 2 then
			return   -- 配额用光，这帧不动
		end
		if distance > budget then
			target = from + delta.Unit * budget
		end
		TP.budget = math.max(0, budget - math.min(distance, budget))
	end

	if C.safe.enabled and C.safe.teleportStep and C.safe.teleportStep > 0 then
		local from = root.Position
		local distance = (target - from).Magnitude
		local stepSize = math.max(4, C.safe.teleportStep)
		local steps = math.clamp(math.ceil(distance / stepSize), 1, 80)
		for i = 1, steps do
			local point = from:Lerp(target, i / steps)
			pcall(function() root.CFrame = CFrame.new(point) end)
			if i < steps then
				local gap = C.safe.teleportGap or 0.05
				if isExtreme() then
					gap = gap * (0.8 + math.random() * 0.6)   -- 随机化，别做成等间隔
				end
				task.wait(gap)
			end
		end
		return
	end

	local cf = CFrame.new(target)
	pcall(function() char:PivotTo(cf) end)
	pcall(function()
		local id = ((char:GetAttribute("PivotId") or 0) + 1) % 100
		-- TODO: 换成你的游戏的传送事件名
		fireEvent("charPivotTo", cf, char, id)
	end)
end

-- 伤害事件：默认按 bodyParts / shotCode / damageFactor 结构发
-- TODO: 换成你的游戏实际的伤害 Remote 与字段
local function sendDamage(target, part, damage)
	local _, _, myRoot = getChar(LP)
	local _, _, tRoot = getChar(target)
	if not myRoot or not tRoot then return end
	local myPos = myRoot.Position
	fireEvent("damage", {
		bodyParts = { { part or "Head", 1 } },
		shotCode = { myPos, (tRoot.Position - myPos).Unit },
		pos = tRoot.Position,
		target = target,
		damageFactor = damage or 1,
		bulletProofTool = false,
	})
end

-- 探测是否被墙挡住
local function visibleBetween(fromPos, toPos, ignoreList)
	if not fromPos or not toPos then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, v in ipairs(ignoreList or {}) do
		if v then table.insert(ignore, v) end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(fromPos, toPos - fromPos, params)
	return hit == nil
end

-- ============================================================
-- 5. 迷你 UI 库（自绘，无外部依赖）
-- ============================================================
local UI = {
	tabs = {},
	accent = Color3.fromRGB(110, 190, 255),
	bg = Color3.fromRGB(17, 17, 21),
	panel = Color3.fromRGB(27, 27, 33),
	text = Color3.fromRGB(235, 235, 240),
	dim = Color3.fromRGB(150, 150, 165),
	rainbowStroke = nil,
	toggleSync = {},   -- 同名开关联动：key -> { 推送函数 }
}

local function new(class, props, parent)
	local obj = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			obj[k] = v
		end
	end
	if parent then obj.Parent = parent end
	return obj
end

local gui, mainFrame, sidebar, contentHolder, openButton

local function setPageVisible(entry)
	for _, e in ipairs(UI.tabs) do
		e.page.Visible = (e == entry)
		e.button.BackgroundColor3 = (e == entry) and Color3.fromRGB(45, 45, 56) or Color3.fromRGB(27, 27, 33)
		e.button.TextColor3 = (e == entry) and UI.accent or UI.dim
	end
end

function UI.tab(title)
	local button = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = UI.panel,
		BorderSizePixel = 0,
		Text = title,
		TextColor3 = UI.dim,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sidebar,
	}, nil)
	button.TextXAlignment = Enum.TextXAlignment.Left
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = button }, nil)

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = UI.accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
		Parent = contentHolder,
	}, nil)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y

	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = page,
	}, nil)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 6),
		Parent = page,
	}, nil)

	local entry = { button = button, page = page }
	table.insert(UI.tabs, entry)
	button.MouseButton1Click:Connect(function()
		setPageVisible(entry)
	end)
	if #UI.tabs == 1 then
		setPageVisible(entry)
	end
	return page
end

local function rowFrame(parent, height)
	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = UI.panel,
		BorderSizePixel = 0,
		Parent = parent,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = frame }, nil)
	return frame
end

function UI.toggle(parent, text, get, set, syncKey)
	local frame = rowFrame(parent, 34)
	new("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UI.text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, nil)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.new(1, -46, 0.5, -9),
		BackgroundColor3 = Color3.fromRGB(60, 60, 72),
		BorderSizePixel = 0,
		Parent = frame,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob }, nil)

	local dot = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(2, 2),
		BackgroundColor3 = Color3.fromRGB(240, 240, 245),
		BorderSizePixel = 0,
		Parent = knob,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot }, nil)

	local state = (get() and true) or false
	local function render()
		knob.BackgroundColor3 = state and UI.accent or Color3.fromRGB(60, 60, 72)
		dot.Position = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
	end
	render()

	-- 同名开关联动：主页和设置页各放一个，改哪个另一个都跟着动
	local function push(v)
		state = v and true or false
		render()
	end
	if syncKey then
		UI.toggleSync[syncKey] = UI.toggleSync[syncKey] or {}
		table.insert(UI.toggleSync[syncKey], push)
	end

	local click = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = frame,
	}, nil)
	click.MouseButton1Click:Connect(function()
		state = not state
		render()
		local ok, err = pcall(set, state)
		if not ok then warn(TAG .. "toggle 回调异常: " .. tostring(err)) end
		if syncKey then
			for _, other in ipairs(UI.toggleSync[syncKey] or {}) do
				if other ~= push then
					pcall(other, state)
				end
			end
		end
		saveConfig()
	end)
	return frame
end

-- 供外部推送状态（比如主页开关要顺带点亮设置页那个）
function UI.syncToggle(key, value)
	for _, other in ipairs(UI.toggleSync[key] or {}) do
		pcall(other, value)
	end
end

function UI.slider(parent, text, min, max, step, get, set)
	local frame = rowFrame(parent, 46)
	local label = new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 2),
		BackgroundTransparency = 1,
		Text = text .. ": " .. tostring(get()),
		TextColor3 = UI.text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, nil)

	local track = new("Frame", {
		Size = UDim2.new(1, -20, 0, 4),
		Position = UDim2.new(0, 10, 0, 32),
		BackgroundColor3 = Color3.fromRGB(50, 50, 62),
		BorderSizePixel = 0,
		Parent = frame,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track }, nil)

	local function ratioOf(value)
		if max == min then return 0 end
		return math.clamp((value - min) / (max - min), 0, 1)
	end

	local fill = new("Frame", {
		Size = UDim2.new(ratioOf(get()), 0, 1, 0),
		BackgroundColor3 = UI.accent,
		BorderSizePixel = 0,
		Parent = track,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill }, nil)

	local hit = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0.5, -9),
		BackgroundTransparency = 1,
		Text = "",
		Parent = track,
	}, nil)

	local dragging = false
	local function applyFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local value = min + (max - min) * rel
		value = math.floor(value / step + 0.5) * step
		value = math.clamp(value, min, max)
		value = math.floor(value * 1000 + 0.5) / 1000
		fill.Size = UDim2.new(ratioOf(value), 0, 1, 0)
		label.Text = text .. ": " .. tostring(value)
		pcall(set, value)
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			applyFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			applyFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				saveConfig()
			end
		end
	end)
	return frame
end

function UI.button(parent, text, callback)
	local frame = rowFrame(parent, 32)
	local btn = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UI.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		Parent = frame,
	}, nil)
	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(callback)
		if not ok then
			notify("按钮异常: " .. tostring(err))
		end
	end)
	return frame
end

function UI.dropdown(parent, text, options, get, set)
	local frame = rowFrame(parent, 34)
	local index = 1
	for i, value in ipairs(options) do
		if value == get() then index = i end
	end
	local label = new("TextLabel", {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = text .. ": " .. tostring(options[index]),
		TextColor3 = UI.text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, nil)
	local click = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = frame,
	}, nil)
	click.MouseButton1Click:Connect(function()
		index = (index % #options) + 1
		label.Text = text .. ": " .. tostring(options[index])
		pcall(set, options[index])
		saveConfig()
	end)
	return frame
end

function UI.label(parent, text, height)
	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, height or 28),
		BackgroundTransparency = 1,
		Parent = parent,
	}, nil)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UI.dim,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, nil)
	return frame
end

-- 边框外观统一入口：主页 / 设置 / 安全 各处开关都调它，避免样式不一致
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FF1493")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("FFD700")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("00FFAA")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("00BFFF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("FF1493")),
})

local function applyBorder()
	local s = UI.rainbowStroke
	if not s or not s.stroke then return end
	s.stroke.Enabled = C.meta.borderEnabled and true or false
	if C.meta.borderRainbow then
		s.gradient.Color = RAINBOW_SEQ
	else
		s.gradient.Color = ColorSequence.new(colorOf(C.meta.borderColor))
	end
	s.stroke.Thickness = C.meta.borderEnabled and 2 or 0
end

local function buildWindow()
	-- 重复执行/二次构建时先清掉旧 UI，避免叠加
	if gui then
		pcall(function() gui:Destroy() end)
		gui = nil
	end
	UI.tabs = {}
	UI.rainbowStroke = nil

	gui = new("ScreenGui", {
		Name = "VXHub",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		Parent = UI_PARENT,
	}, nil)

	-- 按屏幕大小自适应：手机竖屏窄，窗口不能写死 620x430
	local vp = Vector2.new(1280, 720)
	pcall(function()
		if Workspace.CurrentCamera then vp = Workspace.CurrentCamera.ViewportSize end
	end)
	if vp.X <= 0 or vp.Y <= 0 then vp = Vector2.new(1280, 720) end
	local winW = math.clamp(vp.X - 40, 300, 620)
	local winH = math.clamp(vp.Y - 70, 260, 430)
	local sidebarW = math.clamp(math.floor(winW * 0.30), 104, 154)

	mainFrame = new("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(winW, winH),
		Position = UDim2.new(0.5, -math.floor(winW / 2), 0.5, -math.floor(winH / 2)),
		BackgroundColor3 = UI.bg,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = mainFrame }, nil)

	local stroke = new("UIStroke", {
		Name = "Border",
		Thickness = 2,
		Color = Color3.fromRGB(90, 170, 255),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = mainFrame,
	}, nil)
	local gradient = new("UIGradient", { Name = "BorderGradient", Parent = stroke }, nil)
	UI.rainbowStroke = { stroke = stroke, gradient = gradient }

	-- 边框旋转动画一直开着，颜色是否彩虹由 applyBorder 决定（关掉也没开销）
	RunService.Heartbeat:Connect(function()
		if gradient.Parent and C.meta.borderEnabled and C.meta.borderRainbow then
			gradient.Rotation = (gradient.Rotation + 1.2) % 360
		end
	end)

	applyBorder()

	local titleBar = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color3.fromRGB(22, 22, 28),
		BorderSizePixel = 0,
		Parent = mainFrame,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = titleBar }, nil)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 1, -12),
		BackgroundColor3 = Color3.fromRGB(22, 22, 28),
		BorderSizePixel = 0,
		Parent = titleBar,
	}, nil)

	new("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Text = "VX Hub  v1.0",
		TextColor3 = UI.text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = titleBar,
	}, nil)

	local closeBtn = new("TextButton", {
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -34, 0.5, -13),
		BackgroundColor3 = Color3.fromRGB(60, 40, 45),
		BorderSizePixel = 0,
		Text = "×",
		TextColor3 = Color3.fromRGB(255, 200, 200),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Parent = titleBar,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeBtn }, nil)
	closeBtn.MouseButton1Click:Connect(function()
		mainFrame.Visible = false
	end)

	-- 侧边栏
	sidebar = new("Frame", {
		Size = UDim2.new(0, sidebarW, 1, -52),
		Position = UDim2.fromOffset(10, 44),
		BackgroundTransparency = 1,
		Parent = mainFrame,
	}, nil)
	new("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sidebar,
	}, nil)

	contentHolder = new("Frame", {
		Size = UDim2.new(1, -(sidebarW + 32), 1, -52),
		Position = UDim2.fromOffset(sidebarW + 22, 44),
		BackgroundTransparency = 1,
		Parent = mainFrame,
	}, nil)

	-- 拖动
	local dragging, dragStart, startPos = false, nil, nil
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- 展开按钮
	openButton = new("TextButton", {
		Name = "OpenButton",
		Size = UDim2.fromOffset(112, 44),
		Position = UDim2.new(0, 16, 0.5, -22),
		BackgroundColor3 = Color3.fromRGB(25, 25, 32),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Text = "VX HUB",
		TextColor3 = UI.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Active = true,
		Visible = C.ui.showOpenButton,
		Parent = gui,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = openButton }, nil)
	local openStroke = new("UIStroke", {
		Thickness = 1.5,
		Color = UI.accent,
		Parent = openButton,
	}, nil)
	openButton.MouseButton1Click:Connect(function()
		mainFrame.Visible = not mainFrame.Visible
	end)
	RunService.RenderStepped:Connect(function()
		if openStroke.Parent then
			openStroke.Color = rainbow(6)
		end
	end)

	-- 展开按钮拖动（手指和鼠标都要支持）
	local obDragging, obStart, obPos, obMoved = false, nil, nil, false
	openButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			obDragging = true
			obMoved = false
			obStart = input.Position
			obPos = openButton.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if obDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - obStart
			if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
				obMoved = true
			end
			openButton.Position = UDim2.new(
				obPos.X.Scale, obPos.X.Offset + delta.X,
				obPos.Y.Scale, obPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			obDragging = false
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local key = C.ui.openKey
		if input.KeyCode == Enum.KeyCode[key] then
			mainFrame.Visible = not mainFrame.Visible
		end
	end)
end

-- ============================================================
-- 6. ESP
-- ============================================================
local EspTrack = {}

local function dropEsp(player)
	local t = EspTrack[player]
	if not t then return end
	for _, obj in pairs(t) do
		pcall(function()
			if typeof(obj) == "RBXScriptConnection" then
				obj:Disconnect()
			elseif typeof(obj) == "Instance" then
				obj:Destroy()
			elseif obj and obj.Remove then
				obj:Remove()
			end
		end)
	end
	EspTrack[player] = nil
end

local function espAllowed(player)
	if not C.esp.enabled then return false end
	if player == LP or not player.Character then return false end
	if C.esp.teamCheck and player.Team and LP.Team and player.Team == LP.Team then
		return false
	end
	return true
end

local function buildEsp(player)
	dropEsp(player)
	if not espAllowed(player) then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local parent = UI_PARENT or resolveGuiParent()
	if not parent then return end

	local billboard = new("BillboardGui", {
		Name = "VX_ESP_" .. player.Name,
		AlwaysOnTop = true,
		Size = UDim2.new(4, 0, 4, 0),
		StudsOffset = Vector3.new(0, 3, 0),
		Adornee = root,
		Parent = parent,
	}, nil)

	local holder = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = billboard,
	}, nil)

	local nameLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextStrokeTransparency = 0.4,
		Text = player.Name,
		Parent = holder,
	}, nil)

	local infoLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = holder,
	}, nil)

	local highlight = new("Highlight", {
		Name = "VX_ESP_HL",
		Adornee = char,
		FillTransparency = 0.72,
		OutlineTransparency = 0,
		Parent = parent,
	}, nil)

	local tracerLine = nil
	if DrawingLib then
		tracerLine = tryDrawing("Line")
		if tracerLine then
			pcall(function()
				tracerLine.Thickness = 1
				tracerLine.Transparency = 0.4
				tracerLine.Visible = false
			end)
		end
	end

	local update = RunService.Heartbeat:Connect(function()
		if not espAllowed(player) or not player.Character or not root.Parent then
			billboard.Enabled = false
			if tracerLine then tracerLine.Visible = false end
			if highlight.Parent then highlight.Enabled = false end
			return
		end
		billboard.Enabled = true
		highlight.Enabled = C.esp.highlight

		local _, hum, myRoot = getChar(LP)
		local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0
		if C.esp.maxDist and dist > C.esp.maxDist then
			billboard.Enabled = false
			if tracerLine then tracerLine.Visible = false end
			return
		end

		local color = (player.Team and player.Team.TeamColor and player.Team.TeamColor.Color) or Color3.fromRGB(0, 255, 140)
		local team = teamName(player)

		nameLabel.Text = "[" .. team .. "] " .. player.Name
		nameLabel.TextColor3 = color
		nameLabel.Visible = C.esp.name

		highlight.FillColor = color
		highlight.OutlineColor = color

		local parts = {}
		if C.esp.dist then
			table.insert(parts, string.format("%d", math.floor(dist)))
		end
		if C.esp.health and hum then
			table.insert(parts, string.format("%d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth)))
		end
		infoLabel.Text = #parts > 0 and ("[" .. table.concat(parts, " | ") .. "]") or ""
		infoLabel.TextColor3 = color
		infoLabel.Visible = C.esp.dist or C.esp.health

		local camera = Workspace.CurrentCamera
		if tracerLine and camera then
			if C.esp.tracer then
				local screen, onScreen = camera:WorldToViewportPoint(root.Position)
				if onScreen then
					local vp = camera.ViewportSize
					tracerLine.From = Vector2.new(vp.X / 2, vp.Y)
					tracerLine.To = Vector2.new(screen.X, screen.Y)
					tracerLine.Color = color
					tracerLine.Visible = true
				else
					tracerLine.Visible = false
				end
			else
				tracerLine.Visible = false
			end
		end
	end)

	EspTrack[player] = {
		billboard = billboard,
		highlight = highlight,
		update = update,
		tracer = tracerLine,
	}
end

local function refreshEsp()
	if not C.esp.enabled then
		for player in pairs(EspTrack) do
			dropEsp(player)
		end
		return
	end
	for player in pairs(EspTrack) do
		if not espAllowed(player) then
			dropEsp(player)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP and espAllowed(player) and not EspTrack[player] then
			buildEsp(player)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		if C.esp.enabled then buildEsp(player) end
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	dropEsp(player)
end)

-- ============================================================
-- 7. 自瞄
-- ============================================================
local AimVisual = { circle = nil, lines = nil, tracer = nil }

-- 手机执行器的 Drawing 库经常只支持部分类型，逐个试，失败就当没有
local function tryDrawing(class)
	if not DrawingLib then return nil end
	local ok, obj = pcall(function() return DrawingLib.new(class) end)
	if ok then return obj end
	return nil
end

local function buildAimVisuals()
	AimVisual.circle = tryDrawing("Circle")
	if AimVisual.circle then
		pcall(function()
			AimVisual.circle.Filled = false
			AimVisual.circle.NumSides = 60
			AimVisual.circle.Thickness = 1.5
			AimVisual.circle.Visible = false
		end)
	end

	AimVisual.tracer = tryDrawing("Line")
	if AimVisual.tracer then
		pcall(function()
			AimVisual.tracer.Thickness = 1.5
			AimVisual.tracer.Transparency = 0.4
			AimVisual.tracer.Visible = false
		end)
	end

	AimVisual.lines = {}
	for _, name in ipairs({ "Top", "Bottom", "Left", "Right" }) do
		local line = tryDrawing("Line")
		if line then
			pcall(function()
				line.Thickness = 2
				line.Visible = false
			end)
			AimVisual.lines[name] = line
		end
	end
end
pcall(buildAimVisuals)

local PartAliases = {
	["Head"] = { "Head" },
	["Torso"] = { "UpperTorso", "Torso" },
	["LeftArm"] = { "LeftHand", "Left Arm", "LeftUpperArm" },
	["RightArm"] = { "RightHand", "Right Arm", "RightUpperArm" },
	["LeftLeg"] = { "LeftFoot", "Left Leg", "LeftUpperLeg" },
	["RightLeg"] = { "RightFoot", "Right Leg", "RightUpperLeg" },
}
local PartNames = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local function findBodyPart(char, partName)
	for _, alias in ipairs(PartAliases[partName] or { "Head" }) do
		local part = char:FindFirstChild(alias)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function aimTargetAllowed(player)
	if player == LP or not isAlive(player) then return false end
	if C.aim.teamCheck and player.Team and LP.Team and player.Team == LP.Team then
		return false
	end
	return true
end

local function bestAimTarget()
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local best, bestScore = nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if aimTargetAllowed(player) then
			local char = player.Character
			if char then
				local part = findBodyPart(char, C.aim.part)
				if part then
					local screen, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local fov = (Vector2.new(screen.X, screen.Y) - center).Magnitude
						if fov <= C.aim.fov then
							local ok = true
							if C.aim.wallCheck then
								ok = visibleBetween(camera.CFrame.Position, part.Position, { LP.Character, camera })
							end
							if ok and fov < bestScore then
								bestScore = fov
								best = { player = player, part = part, screen = screen }
							end
						end
					end
				end
			end
		end
	end
	return best
end

RunService.RenderStepped:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local color = colorOf(C.aim.color)

	if AimVisual.circle then
		AimVisual.circle.Position = center
		AimVisual.circle.Radius = C.aim.fov
		AimVisual.circle.Color = color
		AimVisual.circle.Visible = C.aim.enabled and C.aim.showFov
	end
	if AimVisual.lines then
		local gap, size = 6, 12
		local top = AimVisual.lines.Top
		top.From = Vector2.new(center.X, center.Y - gap)
		top.To = Vector2.new(center.X, center.Y - gap - size)
		local bottom = AimVisual.lines.Bottom
		bottom.From = Vector2.new(center.X, center.Y + gap)
		bottom.To = Vector2.new(center.X, center.Y + gap + size)
		local left = AimVisual.lines.Left
		left.From = Vector2.new(center.X - gap, center.Y)
		left.To = Vector2.new(center.X - gap - size, center.Y)
		local right = AimVisual.lines.Right
		right.From = Vector2.new(center.X + gap, center.Y)
		right.To = Vector2.new(center.X + gap + size, center.Y)
		for _, line in pairs(AimVisual.lines) do
			line.Color = color
			line.Visible = C.aim.enabled and C.aim.showCrosshair
		end
	end
	if AimVisual.tracer then
		AimVisual.tracer.Visible = false
	end

	if not C.aim.enabled then return end

	-- 手机没有右键，触屏设备上忽略「按住触发」，开了就一直生效
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if C.aim.holdKey and not touchOnly then
		local mouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		local keyDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if not (mouseDown or keyDown) then return end
	end

	local target = bestAimTarget()
	if not target then return end

	if AimVisual.tracer and C.aim.showTracer then
		AimVisual.tracer.From = center
		AimVisual.tracer.To = Vector2.new(target.screen.X, target.screen.Y)
		AimVisual.tracer.Color = color
		AimVisual.tracer.Visible = true
	end

	local aimPos = target.part.Position
	if C.aim.prediction then
		aimPos = aimPos + target.part.AssemblyLinearVelocity * dt * 1.4
	end
	local goal = CFrame.new(camera.CFrame.Position, aimPos)
	local factor = math.clamp(1 - C.aim.smooth, 0.08, 0.95)
	camera.CFrame = camera.CFrame:Lerp(goal, factor)
end)

-- ============================================================
-- 8. Ragebot
-- ============================================================
local function makeBeam(fromPos, toPos, color)
	local p1 = new("Part", {
		Anchored = true, CanCollide = false, Transparency = 1,
		Size = Vector3.new(0.1, 0.1, 0.1), Parent = Workspace,
	}, nil)
	local p2 = new("Part", {
		Anchored = true, CanCollide = false, Transparency = 1,
		Size = Vector3.new(0.1, 0.1, 0.1), Parent = Workspace,
	}, nil)
	p1.Position = fromPos
	p2.Position = toPos
	local a1 = new("Attachment", { Parent = p1 }, nil)
	local a2 = new("Attachment", { Parent = p2 }, nil)
	local beam = new("Beam", {
		Attachment0 = a1, Attachment1 = a2,
		Width0 = 0.16, Width1 = 0.16,
		Color = ColorSequence.new(color or Color3.fromRGB(180, 210, 255)),
		FaceCamera = true, Parent = p1,
	}, nil)
	task.delay(0.7, function()
		pcall(function()
			beam:Destroy()
			p1:Destroy()
			p2:Destroy()
		end)
	end)
end

task.spawn(function()
	local burstStart = os.clock()
	while true do
		-- 极限模式：连打一段时间后强制休息，避免"持续稳定输出"这种机器特征
		if isExtreme() and C.rage.enabled then
			local onTime = C.safe.burstOn or 3.0
			if os.clock() - burstStart > onTime then
				task.wait((C.safe.burstOff or 1.5) + math.random() * 0.8)
				burstStart = os.clock()
			end
		elseif not C.rage.enabled then
			burstStart = os.clock()
		end

		if C.rage.enabled and Game.event then
			-- 安全模式：随机漏打 + 间隔浮动，别做成"每 80ms 精准一次"
			local skip = C.safe.enabled and math.random() < (C.safe.rageSkipRate or 0.12)
			local _, _, myRoot = getChar(LP)
			if myRoot and not skip then
				local myPos = myRoot.Position
				for _, player in ipairs(Players:GetPlayers()) do
					local ok = player ~= LP and isAlive(player)
					if ok and C.rage.teamCheck and player.Team and LP.Team and player.Team == LP.Team then
						ok = false
					end
					if ok then
						local char, hum, root = getChar(player)
						if char and hum and root then
							if (root.Position - myPos).Magnitude <= C.rage.range then
								local pass = true
								if C.rage.wallCheck then
									pass = visibleBetween(myPos, root.Position, { LP.Character })
								end
								if pass then
									-- 极限模式：命中部位随机化，别每一枪都打头
									local partName = PartAliases[C.rage.part] and PartAliases[C.rage.part][1] or "Head"
									if isExtreme() then
										local roll = math.random()
										if roll < 0.45 then
											partName = "Head"
										elseif roll < 0.85 then
											partName = "UpperTorso"
										else
											partName = "LeftUpperArm"
										end
									end
									pcall(function()
										sendDamage(player, partName, C.rage.damage)
									end)
									if C.rage.beam and not isExtreme() then
										makeBeam(myPos, root.Position)
									end
								end
							end
						end
					end
				end
			end
		end
		-- 等待时间：安全模式下随机浮动，看起来像人在打
		local baseInterval = C.rage.interval or 0.1
		local waitTime = baseInterval
		if C.safe.enabled then
			local jitter = C.safe.rageJitter or 0.35
			waitTime = baseInterval * (1 - jitter + math.random() * jitter * 2)
			if math.random() < 0.1 then
				waitTime = waitTime + 0.25
			end
			waitTime = math.max(waitTime, 0.06)
		end
		task.wait(waitTime)
	end
end)

-- ============================================================
-- 9. 范围（Hitbox）
-- ============================================================
local HitboxBackup = {}

local function resetHitbox(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local backup = HitboxBackup[root]
	if backup then
		root.Size = backup.size
		root.Transparency = backup.transparency
		root.Material = backup.material
		root.CanCollide = backup.collide
		root.Color = backup.color
		HitboxBackup[root] = nil
	end
	local hl = root:FindFirstChild("VX_HitboxHL")
	if hl then hl:Destroy() end
	local light = root:FindFirstChild("VX_HitboxLight")
	if light then light:Destroy() end
end

local function applyHitbox(char)
	if not C.hitbox.enabled then return end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if not HitboxBackup[root] then
		HitboxBackup[root] = {
			size = root.Size,
			transparency = root.Transparency,
			material = root.Material,
			collide = root.CanCollide,
			color = root.Color,
		}
	end
	local size = C.hitbox.size
	if C.hitbox.pulse then
		size = size * (1 + math.sin(tick() * 2.5) * 0.2)
	end
	root.Size = Vector3.new(size, size, size)
	root.Transparency = C.hitbox.transparency
	root.Material = Enum.Material.Neon
	root.CanCollide = C.hitbox.collision
	root.Color = C.hitbox.color == "彩虹" and rainbow(5) or colorOf(C.hitbox.color)

	if C.hitbox.glow then
		local light = root:FindFirstChild("VX_HitboxLight")
		if not light then
			light = new("PointLight", { Name = "VX_HitboxLight", Parent = root }, nil)
		end
		light.Brightness = 4
		light.Range = 16
		light.Color = root.Color
	else
		local light = root:FindFirstChild("VX_HitboxLight")
		if light then light:Destroy() end
	end
end

-- 统一重置入口
local function clearAllHitbox()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then resetHitbox(player.Character) end
	end
end

local hitboxDirty = false

RunService.Heartbeat:Connect(function()
	if C.hitbox.enabled then
		hitboxDirty = true
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LP and player.Character then
				local sameTeam = C.hitbox.teamCheck and player.Team and LP.Team and player.Team == LP.Team
				if sameTeam then
					resetHitbox(player.Character)
				else
					applyHitbox(player.Character)
				end
			end
		end
	elseif hitboxDirty then
		hitboxDirty = false
		clearAllHitbox()
	end
end)

-- ============================================================
-- 10. 角色移动
-- ============================================================
local Move = {
	speedConn = nil,
	jumpConn = nil,
	flyConn = nil,
	noclipConn = nil,
	bv = nil,
	bg = nil,
	collisionCache = {},
}

local function stopSpeed()
	if Move.speedConn then
		Move.speedConn:Disconnect()
		Move.speedConn = nil
	end
end

local function startSpeed()
	stopSpeed()
	if not C.player.speedOn then return end
	Move.speedConn = RunService.Heartbeat:Connect(function()
		local _, hum = getChar(LP)
		if hum and C.player.speedOn then
			-- 安全模式：不要超过服务端容忍阈值，否则会被拉回/记录
			local limit = C.player.speed
			if C.safe.enabled then
				limit = math.min(limit, C.safe.maxSpeed or 32)
			end
			hum.WalkSpeed = limit
		end
	end)
end

local function stopFly()
	if Move.flyConn then
		Move.flyConn:Disconnect()
		Move.flyConn = nil
	end
	if Move.bv then
		Move.bv:Destroy()
		Move.bv = nil
	end
	if Move.bg then
		Move.bg:Destroy()
		Move.bg = nil
	end
	local _, hum = getChar(LP)
	if hum then
		hum.PlatformStand = false
		hum.AutoRotate = true
	end
end

local controls
pcall(function()
	controls = require(LP.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
end)

local function startFly()
	stopFly()
	if not C.player.flyOn then return end
	local _, hum, root = getChar(LP)
	if not root or not hum then return end

	if C.player.flyMode == "物理" then
		Move.bv = new("BodyVelocity", {
			Name = "VX_FlyVelocity",
			MaxForce = Vector3.new(9e9, 9e9, 9e9),
			Velocity = Vector3.zero,
			Parent = root,
		}, nil)
		Move.bg = new("BodyGyro", {
			Name = "VX_FlyGyro",
			MaxTorque = Vector3.new(9e9, 9e9, 9e9),
			P = 9e4,
			Parent = root,
		}, nil)
		hum.PlatformStand = true
		hum.AutoRotate = false

		Move.flyConn = RunService.RenderStepped:Connect(function()
			if not C.player.flyOn then return end
			local _, curHum, curRoot = getChar(LP)
			local camera = Workspace.CurrentCamera
			if not curRoot or not camera or not (Move.bv and Move.bg) then return end
			local moveVector = controls and controls:GetMoveVector() or Vector3.zero
			local dir = camera.CFrame.LookVector * -moveVector.Z + camera.CFrame.RightVector * moveVector.X
			local vertical = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) or (curHum and curHum.Jump) then vertical = 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vertical = -1 end
			Move.bv.Velocity = (dir + Vector3.new(0, vertical, 0)) * C.player.flySpeed
			Move.bg.CFrame = camera.CFrame
			if curHum then curHum.PlatformStand = true end
		end)
	else
		hum.AutoRotate = false
		Move.flyConn = RunService.RenderStepped:Connect(function(dt)
			if not C.player.flyOn then return end
			local _, curHum, curRoot = getChar(LP)
			local camera = Workspace.CurrentCamera
			if not curRoot or not camera then return end
			local moveVector = controls and controls:GetMoveVector() or Vector3.zero
			local dir = camera.CFrame.LookVector * -moveVector.Z + camera.CFrame.RightVector * moveVector.X
			local vertical = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) or (curHum and curHum.Jump) then vertical = 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vertical = -1 end
			local delta = (dir + Vector3.new(0, vertical, 0)) * C.player.flySpeed * dt
			curRoot.CFrame = curRoot.CFrame + delta
			curRoot.AssemblyLinearVelocity = Vector3.zero
			curRoot.AssemblyAngularVelocity = Vector3.zero
		end)
	end
end

local function stopNoclip()
	if Move.noclipConn then
		Move.noclipConn:Disconnect()
		Move.noclipConn = nil
	end
	for part, old in pairs(Move.collisionCache) do
		if part and part.Parent then
			pcall(function() part.CanCollide = old end)
		end
	end
	Move.collisionCache = {}
end

local function startNoclip()
	stopNoclip()
	if not C.player.noclip then return end
	Move.noclipConn = RunService.Stepped:Connect(function()
		if not C.player.noclip then return end
		local char = LP.Character
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				if Move.collisionCache[part] == nil then
					Move.collisionCache[part] = part.CanCollide
				end
				part.CanCollide = false
			end
		end
	end)
end

local function stopJump()
	if Move.jumpConn then
		Move.jumpConn:Disconnect()
		Move.jumpConn = nil
	end
end

local function startJump()
	stopJump()
	if not C.player.jumpOn then return end
	Move.jumpConn = UserInputService.JumpRequest:Connect(function()
		if not C.player.jumpOn then return end
		local _, hum, root = getChar(LP)
		if not hum or not root or hum.Health <= 0 then return end
		local state = hum:GetState()
		local grounded = state == Enum.HumanoidStateType.Landed
			or state == Enum.HumanoidStateType.Running
			or state == Enum.HumanoidStateType.RunningNoPhysics
		if not C.player.infJump and not grounded then return end
		root.CFrame = root.CFrame + Vector3.new(0, C.player.jump * 0.1, 0)
	end)
end

LP.CharacterAdded:Connect(function()
	task.wait(0.6)
	Move.collisionCache = {}
	if C.player.speedOn then startSpeed() end
	if C.player.jumpOn then startJump() end
	if C.player.noclip then startNoclip() end
	if C.player.flyOn then startFly() end
end)

-- ============================================================
-- 11. 游戏功能
-- ============================================================
local GameBlocked = {
	combatNamecallOld = nil,
	damageNamecallOld = nil,
	ragdollOld = nil,
	ragdollServerOld = nil,
}

-- 无限体力 / 饥饿（依赖 Framework/Core）
RunService.Heartbeat:Connect(function()
	if not Game.core then return end
	if C.game.stamina then
		pcall(function() Game.core.stamina = 100 end)
	end
	if C.game.hunger then
		pcall(function() Game.core.food = 100 end)
	end
end)

-- 无限子弹（按 Characters/<名字>/工具/Config/Ammo 结构）
RunService.Heartbeat:Connect(function()
	if not C.game.infiniteAmmo then return end
	local folder = Workspace:FindFirstChild("Characters")
	folder = folder and folder:FindFirstChild(LP.Name)
	if not folder then return end
	-- 安全模式下不用 math.huge（这种值最容易在日志里露馅）
	local cap = C.safe.enabled and (C.safe.ammoCap or 9999) or math.huge
	for _, gun in ipairs(folder:GetChildren()) do
		local cfg = gun:FindFirstChild("Config")
		if cfg then
			local ammo = cfg:FindFirstChild("Ammo")
			local total = cfg:FindFirstChild("TotalAmmo")
			if ammo then pcall(function() ammo.Value = cap end) end
			if total then pcall(function() total.Value = cap end) end
		end
	end
end)

-- 快速射击（扫描 GC 中的武器配置表）
-- 安全模式下默认不跑：getgc 全量扫描在手机上既卡又容易被行为检测盯上
local function applyRapidFire()
	if not C.game.rapidFire then return end
	if C.safe.enabled and C.safe.noGcScan then return end
	if type(getgc) ~= "function" then return end
	local ok = pcall(function()
		for _, tbl in pairs(getgc(true)) do
			if type(tbl) == "table" then
				if rawget(tbl, "RPM") ~= nil then
					rawset(tbl, "RPM", C.safe.enabled and 900 or math.huge)
				end
				if rawget(tbl, "SHOOT_MODE") ~= nil then
					rawset(tbl, "SHOOT_MODE", 2)
				end
			end
		end
	end)
	return ok
end

task.spawn(function()
	while true do
		if C.game.rapidFire then applyRapidFire() end
		task.wait(0.5)
	end
end)

-- 战斗拦截 / 防摔伤：namecall 拦截
local function installNamecallHooks()
	if not (getrawmetatable and setreadonly) then return end
	local ok = pcall(function()
		local mt = getrawmetatable(game)
		setreadonly(mt, false)
		local old = mt.__namecall
		GameBlocked.damageNamecallOld = old
		mt.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer" then
				local args = { ... }
				local first = args[1]
				if C.game.combatBlock and first == "combatMode" then
					return nil
				end
				if C.game.noFallDamage and first == "takeDamage" and tostring(self) == "PlayerEvent" then
					return nil
				end
			end
			return old(self, ...)
		end)
		setreadonly(mt, true)
	end)
	if not ok then
		warn(TAG .. "namecall hook 安装失败（执行器不支持）")
	end
end
installNamecallHooks()

-- 防布娃娃：包装 Ragdoll 模块
pcall(function()
	if Game.ragdoll and Game.ragdoll.activate then
		local old = Game.ragdoll.activate
		GameBlocked.ragdollOld = old
		Game.ragdoll.activate = function(character, enable, duration, ...)
			if C.game.noRagdoll and enable then return nil end
			return old(character, enable, duration, ...)
		end
	end
	if Game.ragdoll and Game.ragdoll.activateServer then
		local oldSrv = Game.ragdoll.activateServer
		GameBlocked.ragdollServerOld = oldSrv
		Game.ragdoll.activateServer = function(character, enable, duration, ...)
			if C.game.noRagdoll and enable then return nil end
			return oldSrv(character, enable, duration, ...)
		end
	end
end)

-- 取 ProximityPrompt 世界坐标
local function promptPosition(prompt)
	if not prompt or not prompt.Parent then return nil end
	local parent = prompt.Parent
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	if parent:IsA("Model") then
		local part = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
		if part then return part.Position end
	end
	return nil
end

local function firePrompt(prompt)
	if not prompt then return end
	pcall(function()
		if fireproximityprompt then
			fireproximityprompt(prompt, 0)
		else
			prompt.HoldDuration = 0
			prompt:InputHoldBegin()
			task.wait(0.05)
			prompt:InputHoldEnd()
		end
	end)
end

-- 自动拾取 / 自动捡钱
task.spawn(function()
	while true do
		if C.game.autoPickup then
			local _, _, root = getChar(LP)
			if root then
				local best, bestDist
				for _, obj in ipairs(Workspace:GetDescendants()) do
					if obj:IsA("ProximityPrompt") then
						local pos = promptPosition(obj)
						if pos then
							local dist = (root.Position - pos).Magnitude
							if dist < 55 and (not bestDist or dist < bestDist) then
								bestDist, best = dist, obj
							end
						end
					end
				end
				if best then
					if bestDist > 8 then
						teleportTo(promptPosition(best))
						task.wait(0.25)
					end
					firePrompt(best)
				end
			end
		end
		task.wait(0.35)
	end
end)

-- 自动接任务（需要 RPC 名字对得上）
task.spawn(function()
	while true do
		if C.game.autoMission and Game.func then
			pcall(function()
				local jobs
				for _, tbl in pairs(getgc(true)) do
					if type(tbl) == "table" and rawget(tbl, "teamJobs") then
						jobs = tbl.teamJobs
						break
					end
				end
				if jobs then
					for id, job in pairs(jobs) do
						if type(job) == "table" and not job.joined then
							invokeFunc("talkToMission", tostring(id) .. "join")
							break
						end
					end
				end
			end)
		end
		task.wait(2)
	end
end)

-- 自动铐（限警用剧本，RPC 名字按游戏改）
task.spawn(function()
	while true do
		if C.game.autoCuff and Game.func then
			local _, _, myRoot = getChar(LP)
			if myRoot then
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LP and isAlive(player) then
						local _, _, root = getChar(player)
						if root and (root.Position - myRoot.Position).Magnitude <= C.game.cuffRange then
							invokeFunc("handcuff", player, false)
						end
					end
				end
			end
		end
		task.wait(0.5)
	end
end)

-- ============================================================
-- 12. 悬浮开关工厂
-- ============================================================
local function quickSwitch(config)
	local holder = new("ScreenGui", {
		Name = "VX_" .. config.name,
		ResetOnSpawn = false,
		DisplayOrder = 998,
		Parent = UI_PARENT,
	}, nil)

	local button = new("TextButton", {
		Size = UDim2.fromOffset(104, 40),
		Position = config.position or UDim2.new(0, 20, 0.5, 40),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Text = config.text or config.name,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Active = true,
		Parent = holder,
	}, nil)
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = button }, nil)
	local stroke = new("UIStroke", { Thickness = 1.5, Color = UI.accent, Parent = button }, nil)
	RunService.RenderStepped:Connect(function()
		if stroke.Parent then
			stroke.Color = rainbow(6)
		end
	end)

	local api = {}
	function api:setActive(active)
		button.TextColor3 = active and Color3.fromRGB(90, 255, 130) or Color3.fromRGB(255, 90, 90)
		button.Text = (config.text or config.name) .. (active and ": 开" or ": 关")
	end
	api:setActive(config.get())

	button.MouseButton1Click:Connect(function()
		local nextState = not config.get()
		pcall(config.set, nextState)
		api:setActive(nextState)
	end)

	-- 拖动（手机手指 + 鼠标）
	local dragging, startPos, dragStart = false, nil, nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = button.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			button.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return api
end

-- ============================================================
-- 13. 上报（默认关闭，C.ui.autoReport 打开才发）
-- ============================================================
local REPORT_URL = "https://YOUR-API.example.com/api/report"

local function buildRequester()
	if type(request) == "function" then return request end
	if type(http_request) == "function" then return http_request end
	if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
	if type(http) == "table" and type(http.request) == "function" then return http.request end
	return nil
end

local function executorName()
	local fns = { identifyexecutor, getexecutorname }
	for _, fn in ipairs(fns) do
		if type(fn) == "function" then
			local ok, a, b = pcall(fn)
			if ok and a then
				return tostring(a) .. (b and (" " .. tostring(b)) or "")
			end
		end
	end
	if ENV.EXECUTOR_NAME then return tostring(ENV.EXECUTOR_NAME) end
	return "unknown"
end

local function report()
	if not C.ui.autoReport then return end
	local requester = buildRequester()
	if not requester then return end
	local payload = HttpService:JSONEncode({
		card_key = SCRIPT_KEY,
		user_id = tostring(LP.UserId),
		username = LP.Name,
		display_name = LP.DisplayName,
		place_id = tostring(game.PlaceId),
		job_id = game.JobId or "",
		executor = executorName(),
		client_time = os.time(),
	})
	task.spawn(function()
		pcall(function()
			requester({
				Url = REPORT_URL,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = payload,
			})
		end)
	end)
end

-- ============================================================
-- 14. 菜单装配
-- ============================================================
-- 急停：一键关掉全部功能（默认按 P）
local function panicKill()
	C.esp.enabled = false
	C.aim.enabled = false
	C.rage.enabled = false
	C.hitbox.enabled = false
	C.player.speedOn = false
	C.player.jumpOn = false
	C.player.infJump = false
	C.player.flyOn = false
	C.player.noclip = false
	C.game.infiniteAmmo = false
	C.game.rapidFire = false
	C.game.autoPickup = false
	C.game.autoMission = false
	C.game.autoCuff = false
	pcall(stopSpeed)
	pcall(stopJump)
	pcall(stopFly)
	pcall(stopNoclip)
	pcall(clearAllHitbox)
	pcall(refreshEsp)
	if mainFrame then mainFrame.Visible = false end
	notify("急停：全部功能已关闭")
end

local function buildMenu()
	buildWindow()

	-- ---- 主页 ----
	local page = UI.tab("主页")
	UI.label(page, "VX Hub v1.0 — 通用框架版", 24)
	UI.label(page, "PlaceId: " .. tostring(game.PlaceId), 18)
	UI.label(page, "执行器: " .. executorName(), 18)
	UI.label(page, "卡密: " .. (SCRIPT_KEY ~= "" and SCRIPT_KEY or "未传入"), 18)
	UI.button(page, "刷新 ESP 列表", function()
		refreshEsp()
	end)
	UI.button(page, "重置全部功能", function()
		C.esp.enabled = false
		C.aim.enabled = false
		C.rage.enabled = false
		C.hitbox.enabled = false
		C.player.speedOn = false
		C.player.flyOn = false
		C.player.noclip = false
		stopSpeed(); stopFly(); stopNoclip()
		clearAllHitbox()
		refreshEsp()
		saveConfig()
		notify("已重置（需重开菜单刷新控件状态）")
	end)

	-- 主页快捷开关：彩虹边框
	UI.toggle(page, "彩虹边框（菜单描边）", function()
		return C.meta.borderEnabled and C.meta.borderRainbow
	end, function(v)
		C.meta.borderEnabled = v
		C.meta.borderRainbow = v
		applyBorder()
		-- 设置页那两个开关也跟着变
		UI.syncToggle("borderEnabled", v)
		UI.syncToggle("borderRainbow", v)
		notify(v and "彩虹边框已开启" or "彩虹边框已关闭")
	end, "borderRainbowQuick")

	-- 主页快捷开关：安全模式
	UI.toggle(page, "安全模式（防封）", function()
		return C.safe.enabled
	end, function(v)
		C.safe.enabled = v
		UI.syncToggle("safeMode", v)
		notify(v and ("安全模式已开启，速度上限 " .. tostring(C.safe.maxSpeed)) or "安全模式已关闭，注意风险")
	end, "safeModeQuick")

	-- ---- ESP ----
	page = UI.tab("透视")
	UI.toggle(page, "ESP 总开关", function() return C.esp.enabled end, function(v)
		C.esp.enabled = v
		refreshEsp()
	end)
	UI.toggle(page, "显示名字", function() return C.esp.name end, function(v) C.esp.name = v end)
	UI.toggle(page, "显示距离", function() return C.esp.dist end, function(v) C.esp.dist = v end)
	UI.toggle(page, "显示血量", function() return C.esp.health end, function(v) C.esp.health = v end)
	UI.toggle(page, "显示高亮", function() return C.esp.highlight end, function(v) C.esp.highlight = v end)
	UI.toggle(page, "显示追踪线", function() return C.esp.tracer end, function(v) C.esp.tracer = v end)
	UI.toggle(page, "过滤队友", function() return C.esp.teamCheck end, function(v)
		C.esp.teamCheck = v
		refreshEsp()
	end)
	UI.slider(page, "最大显示距离", 100, 3000, 50, function() return C.esp.maxDist end, function(v)
		C.esp.maxDist = v
	end)

	-- ---- 自瞄 ----
	page = UI.tab("自瞄")
	UI.toggle(page, "自瞄开关", function() return C.aim.enabled end, function(v) C.aim.enabled = v end)
	UI.toggle(page, "按住右键/E 触发", function() return C.aim.holdKey end, function(v) C.aim.holdKey = v end)
	UI.toggle(page, "显示 FOV 圈", function() return C.aim.showFov end, function(v) C.aim.showFov = v end)
	UI.toggle(page, "显示准心", function() return C.aim.showCrosshair end, function(v) C.aim.showCrosshair = v end)
	UI.toggle(page, "显示追踪线", function() return C.aim.showTracer end, function(v) C.aim.showTracer = v end)
	UI.toggle(page, "预判", function() return C.aim.prediction end, function(v) C.aim.prediction = v end)
	UI.toggle(page, "墙壁检测", function() return C.aim.wallCheck end, function(v) C.aim.wallCheck = v end)
	UI.toggle(page, "队伍检测", function() return C.aim.teamCheck end, function(v) C.aim.teamCheck = v end)
	UI.slider(page, "FOV 半径", 10, 600, 5, function() return C.aim.fov end, function(v) C.aim.fov = v end)
	UI.slider(page, "平滑度(越小越跟手)", 0.05, 1, 0.05, function() return C.aim.smooth end, function(v) C.aim.smooth = v end)
	UI.dropdown(page, "瞄准部位", PartNames, function() return C.aim.part end, function(v) C.aim.part = v end)
	UI.dropdown(page, "颜色", ColorNames, function() return C.aim.color end, function(v) C.aim.color = v end)

	-- ---- Ragebot ----
	page = UI.tab("Rage")
	UI.toggle(page, "Ragebot 开关", function() return C.rage.enabled end, function(v) C.rage.enabled = v end)
	UI.toggle(page, "队伍检测", function() return C.rage.teamCheck end, function(v) C.rage.teamCheck = v end)
	UI.toggle(page, "墙壁检测", function() return C.rage.wallCheck end, function(v) C.rage.wallCheck = v end)
	UI.toggle(page, "弹道显示", function() return C.rage.beam end, function(v) C.rage.beam = v end)
	UI.slider(page, "攻击距离", 5, 600, 5, function() return C.rage.range end, function(v) C.rage.range = v end)
	UI.slider(page, "间隔(秒)", 0.02, 1, 0.02, function() return C.rage.interval end, function(v) C.rage.interval = v end)
	UI.slider(page, "伤害倍率", 1, 50, 1, function() return C.rage.damage end, function(v) C.rage.damage = v end)
	UI.dropdown(page, "攻击部位", PartNames, function() return C.rage.part end, function(v) C.rage.part = v end)

	-- ---- 范围 ----
	page = UI.tab("范围")
	UI.toggle(page, "范围开关", function() return C.hitbox.enabled end, function(v)
		C.hitbox.enabled = v
		if not v then clearAllHitbox() end
	end)
	UI.toggle(page, "队伍检测", function() return C.hitbox.teamCheck end, function(v) C.hitbox.teamCheck = v end)
	UI.toggle(page, "发光", function() return C.hitbox.glow end, function(v) C.hitbox.glow = v end)
	UI.toggle(page, "脉动", function() return C.hitbox.pulse end, function(v) C.hitbox.pulse = v end)
	UI.toggle(page, "允许碰撞", function() return C.hitbox.collision end, function(v) C.hitbox.collision = v end)
	UI.slider(page, "范围大小", 2, 60, 1, function() return C.hitbox.size end, function(v) C.hitbox.size = v end)
	UI.slider(page, "透明度", 0, 1, 0.05, function() return C.hitbox.transparency end, function(v)
		C.hitbox.transparency = v
	end)
	UI.dropdown(page, "颜色", ColorNames, function() return C.hitbox.color end, function(v) C.hitbox.color = v end)

	-- ---- 玩家 ----
	page = UI.tab("玩家")
	UI.toggle(page, "速度修改", function() return C.player.speedOn end, function(v)
		C.player.speedOn = v
		startSpeed()
	end)
	UI.slider(page, "速度值", 16, 300, 1, function() return C.player.speed end, function(v) C.player.speed = v end)
	UI.toggle(page, "跳跃修改", function() return C.player.jumpOn end, function(v)
		C.player.jumpOn = v
		startJump()
	end)
	UI.slider(page, "跳跃高度", 50, 500, 5, function() return C.player.jump end, function(v) C.player.jump = v end)
	UI.toggle(page, "无限跳跃", function() return C.player.infJump end, function(v) C.player.infJump = v end)
	UI.toggle(page, "飞行", function() return C.player.flyOn end, function(v)
		C.player.flyOn = v
		if v then startFly() else stopFly() end
	end)
	UI.dropdown(page, "飞行模式", { "传送", "物理" }, function() return C.player.flyMode end, function(v)
		C.player.flyMode = v
		if C.player.flyOn then startFly() end
	end)
	UI.slider(page, "飞行速度", 20, 400, 5, function() return C.player.flySpeed end, function(v)
		C.player.flySpeed = v
	end)
	UI.toggle(page, "穿墙", function() return C.player.noclip end, function(v)
		C.player.noclip = v
		if v then startNoclip() else stopNoclip() end
	end)

	-- ---- 游戏 ----
	page = UI.tab("游戏")
	UI.label(page, "以下功能依赖游戏内模块，换游戏需改第 4 节的适配层", 34)
	UI.toggle(page, "无限体力", function() return C.game.stamina end, function(v) C.game.stamina = v end)
	UI.toggle(page, "无限饥饿", function() return C.game.hunger end, function(v) C.game.hunger = v end)
	UI.toggle(page, "战斗拦截", function() return C.game.combatBlock end, function(v) C.game.combatBlock = v end)
	UI.toggle(page, "防布娃娃", function() return C.game.noRagdoll end, function(v) C.game.noRagdoll = v end)
	UI.toggle(page, "防摔伤", function() return C.game.noFallDamage end, function(v) C.game.noFallDamage = v end)
	UI.toggle(page, "无限子弹", function() return C.game.infiniteAmmo end, function(v) C.game.infiniteAmmo = v end)
	UI.toggle(page, "快速射击", function() return C.game.rapidFire end, function(v) C.game.rapidFire = v end)
	UI.toggle(page, "自动拾取", function() return C.game.autoPickup end, function(v) C.game.autoPickup = v end)
	UI.toggle(page, "自动接任务", function() return C.game.autoMission end, function(v) C.game.autoMission = v end)
	UI.toggle(page, "自动铐人", function() return C.game.autoCuff end, function(v) C.game.autoCuff = v end)
	UI.slider(page, "铐人范围", 20, 600, 10, function() return C.game.cuffRange end, function(v)
		C.game.cuffRange = v
	end)

	-- ---- 设置 ----
	page = UI.tab("设置")
	UI.toggle(page, "显示悬浮开关按钮", function() return C.ui.showOpenButton end, function(v)
		C.ui.showOpenButton = v
		if openButton then openButton.Visible = v end
	end)
	UI.toggle(page, "启用边框", function() return C.meta.borderEnabled end, function(v)
		C.meta.borderEnabled = v
		applyBorder()
		UI.syncToggle("borderEnabled", v)
	end, "borderEnabled")
	UI.toggle(page, "彩虹边框", function() return C.meta.borderRainbow end, function(v)
		C.meta.borderRainbow = v
		applyBorder()
		UI.syncToggle("borderRainbow", v)
	end, "borderRainbow")
	UI.dropdown(page, "边框颜色", ColorNames, function() return C.meta.borderColor end, function(v)
		C.meta.borderColor = v
		applyBorder()
	end)
	UI.dropdown(page, "开关按键", { "RightShift", "LeftShift", "K", "Insert", "F1" },
		function() return C.ui.openKey end, function(v) C.ui.openKey = v end)
	UI.toggle(page, "发送使用上报（需自建接口）", function() return C.ui.autoReport end, function(v)
		C.ui.autoReport = v
	end)
	UI.button(page, "立即上报", function()
		report()
		notify("已按配置尝试上报")
	end)
	UI.button(page, "保存配置", function()
		saveConfig()
		notify("配置已保存")
	end)

	-- ---- 安全 ----
	page = UI.tab("安全")
	UI.label(page, "「极限」会把速度压到 28、传送切成 8 格一步、攻击变慢变随机、\n关掉自动化和 GC 扫描。它挡得住行为检测，挡不住客户端注入检测。", 54)
	UI.dropdown(page, "防护强度", { "标准", "极限" }, function() return C.safe.level end, function(v)
		C.safe.level = v
		applyProtectionLevel()
		saveConfig()
		if v == "极限" then
			notify("已切到极限：速度≤28，传送分段，攻击加随机，自动化全关")
		else
			notify("已切回标准模式")
		end
	end)
	UI.button(page, "急停：一键关闭全部功能（P 键）", function()
		panicKill()
	end)
	UI.label(page, "连打自动休息：" .. tostring(C.safe.burstOn) .. " 秒后停 1.5~2 秒，避免机器特征", 20)
	UI.toggle(page, "安全模式总开关", function() return C.safe.enabled end, function(v)
		C.safe.enabled = v
		UI.syncToggle("safeMode", v)
		if v then
			notify("安全模式开启：速度上限 " .. tostring(C.safe.maxSpeed) .. "，传送改为分段")
		else
			notify("安全模式关闭：功能全开，被封风险上升")
		end
	end, "safeMode")
	UI.slider(page, "速度上限", 16, 80, 1, function() return C.safe.maxSpeed end, function(v)
		C.safe.maxSpeed = v
	end)
	UI.slider(page, "传送每步距离", 4, 60, 2, function() return C.safe.teleportStep end, function(v)
		C.safe.teleportStep = v
	end)
	UI.slider(page, "传送步间隔(秒)", 0.01, 0.3, 0.01, function() return C.safe.teleportGap end, function(v)
		C.safe.teleportGap = v
	end)
	UI.slider(page, "攻击间隔抖动", 0, 0.8, 0.05, function() return C.safe.rageJitter end, function(v)
		C.safe.rageJitter = v
	end)
	UI.slider(page, "随机漏打比例", 0, 0.5, 0.02, function() return C.safe.rageSkipRate end, function(v)
		C.safe.rageSkipRate = v
	end)
	UI.toggle(page, "禁用 GC 扫描功能", function() return C.safe.noGcScan end, function(v)
		C.safe.noGcScan = v
	end)
	UI.slider(page, "子弹上限", 100, 99999, 100, function() return C.safe.ammoCap end, function(v)
		C.safe.ammoCap = v
	end)
	UI.button(page, "恢复安全默认值", function()
		C.safe.enabled = true
		C.safe.maxSpeed = 32
		C.safe.teleportStep = 12
		C.safe.teleportGap = 0.05
		C.safe.rageJitter = 0.35
		C.safe.rageSkipRate = 0.12
		C.safe.noGcScan = true
		C.safe.ammoCap = 9999
		saveConfig()
		notify("已恢复默认（重开菜单生效）")
	end)
	UI.label(page, "建议：平时只开透视；打架时开自瞄不开 Rage；速度别过 40；不要连续瞬移。", 40)
end

-- ============================================================
-- 15. 启动
-- ============================================================
local ok, err = pcall(buildMenu)
if not ok then
	warn(TAG .. "菜单构建失败（CoreGui 可能不可写），回退到 PlayerGui: " .. tostring(err))
	pcall(function()
		UI_PARENT = LP:WaitForChild("PlayerGui", 5)
	end)
	if UI_PARENT then
		ok, err = pcall(buildMenu)
	end
	if not ok then
		warn(TAG .. "二次构建仍失败: " .. tostring(err))
		return
	end
end

quickSwitch({
	name = "Fly",
	text = "飞行",
	position = UDim2.new(0, 20, 0.5, 60),
	get = function() return C.player.flyOn end,
	set = function(v)
		C.player.flyOn = v
		if v then startFly() else stopFly() end
	end,
})

quickSwitch({
	name = "Aim",
	text = "自瞄",
	position = UDim2.new(0, 20, 0.5, 100),
	get = function() return C.aim.enabled end,
	set = function(v) C.aim.enabled = v end,
})

if mainFrame then
	mainFrame.Visible = true
end

-- 若上次保存的是「极限」，启动时立刻把参数压一遍
pcall(applyProtectionLevel)

-- 急停键：任何时候按一下立刻全关
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local key = C.safe.panicKey or "P"
	if input.KeyCode == Enum.KeyCode[key] then
		pcall(panicKill)
	end
end)

if C.ui.autoReport then
	report()
end

notify("加载完成 | " .. C.ui.openKey .. " 菜单 · " .. (C.safe.panicKey or "P") .. " 急停 · 防护=" .. tostring(C.safe.level))
